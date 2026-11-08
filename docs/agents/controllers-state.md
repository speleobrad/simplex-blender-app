# Controllers and app state

Scope: the three `ChangeNotifier` controllers in `lib/src/controllers/`, their wiring, and the invariants they enforce. Storage formats and settings validation are in [persistence-settings.md](./persistence-settings.md). Features and build are in `README.md`.

## Ownership and wiring

| Controller | Owns | Persists via |
|---|---|---|
| `AppController` (`app_controller.dart`) | banks, settings, theme, onboarding, navigation, failure flags, analytics gate | `lib/src/data/` adapters |
| `BlendController` (`blend_controller.dart`) | inputs, `lastResult`, interim readings, bank price suggestions | none; bank price writes go through `updateBank` |
| `WhatIfController` (`what_if_controller.dart`) | scenario, rows, last run, status | none |

- `lib/main.dart` builds one `AppController`, then passes its `banks`, `settings`, `updateBank`, and `analytics` into `BlendController` and `WhatIfController`.
- Controllers do not import each other. Blend and what-if import only `lib/src/analytics/` and `lib/src/domain/`. `AppController` imports no controller.
- Blend and what-if hold copies of shared inputs. They refresh them only through `updateSharedInputs({banks, settings})`.
- `lib/src/ui/shell/app_shell.dart` calls `updateSharedInputs` on both controllers from `initState` and from `_onAppChanged`, the listener on `AppController`. A new shared input MUST be forwarded there too.
- `BlendController` writes inventory only through the `updateBank` callback. It never mutates `AppController` state directly.

## Analytics

- `AppController` wraps the injected backend in `GatedAnalytics`. Controllers receive `app.analytics` (the gated one), so the user's opt-out applies to every event.
- Events go through `safeTrack` (`lib/src/analytics/analytics.dart`), which swallows sink errors. A sink failure MUST NOT change calculation or UI results.
- Event helpers live in `lib/src/analytics/analytics_events.dart`: `trackAppStarted`, `trackScreenView`, `trackBlendCalculated`, `trackPresetImported`, `trackFactoryReset`.
- `startup()` sends `app_started` once per launch (guarded by `_startupTracked`).
- `setPrimaryScreen` sends `screen_view` only when the screen changes.
- `setAnalyticsEnabled` keeps the choice in memory for the launch even when the save fails.
- `factoryReset` sets `enabled = true` on the gate after the reset succeeds.
- Analytics is disabled unless `APTABASE_APP_KEY` is passed via `--dart-define` (see `README.md`). `lib/src/analytics/analytics.dart` header mentions `js/analytics.js`; that file is not in this repo.

## Reactivity

- Widgets rebuild with `ListenableBuilder` on `Listenable.merge([controller, app])` (for example `lib/src/ui/blending/recipe_pane.dart`, `ternary_pane.dart`). Some use `AnimatedBuilder` (`blending_result_panel.dart`).
- `transfer_conditions.dart` and `mixing_steps.dart` attach `addListener`/`removeListener` by hand.
- Every state change MUST call `notifyListeners()`. Failure paths that change visible state do too (for example `rejectBankEdit`).

## AppController

Loading:
- The constructor loads banks, settings, theme, and onboarding. Each loader's `onFallback` sets its failure flag, which `storageWarning` reports. Defaults are used only after the flag is set.
- When `loadSettings` reports migrated cylinder dimensions (`onCylinderDimensionsMigrated`), the constructor saves the migrated settings immediately. A save failure is swallowed: the migrated settings stay in memory and the notice repeats on the next start. This is not a warning flag. The notice is exposed as `cylinderMigrationNotice`, and `dismissCylinderMigrationNotice()` clears it.
- The analytics gate is read from storage before any event is sent.

Inventory (`banks`):
- Ids come from `_newBankId()`: `bank-<ms>`, with a `-N` suffix on collision. Ids of removed banks stay in `_issuedBankIds`, so a new bank in the same millisecond cannot reattach a removed bank's what-if row.
- `addBank()` appends `New Mix`: 50 L, 200 bar, max 200 bar, 32% O2, 0% He, enabled.
- `updateBank(bank)`:
  - Unknown id: ignored.
  - Oxygen 21% with helium 0%: rejected as `Air is supplied by the compressor and cannot be a finite supply bank.` Compressor air is a `topUp` with no gas line in `computeFillCost`.
  - Other invalid input: first error from `validateSupplyBankInput` goes to `rejectBankEdit`, which stores `'<name>: <message>'` in `bankInputFailure` and does not change `banks`.
  - Valid edit: `clearBankInputFailure` for that id, then replace.
- `setBankEnabled` is never rejected. `removeBank` clears that bank's input failure.
- `_persistBanks()` keeps the in-memory edit when the save fails, sets `bankSaveFailure`, and clears it on the next successful save.

Settings:
- `applySettings(settings)`: validation errors are returned with settings unchanged.
- Save throws: `settingsSaveFailure` is set, previous settings are kept, and the return is `[settingsSaveFailureMessage]`.
- Success: both settings flags clear and the return is `[]`.
- `settingsSaveFailureMessage`: `Settings were not saved. Check that browser storage is enabled and has space, then try again.`
- `applyPresetImport`: empty selection is a no-op. `mergeSelectedPresets` runs, then `saveSettings`. A save error is rethrown with settings unchanged. Success clears settings flags and calls `trackPresetImported`.

Theme, onboarding, navigation:
- `setThemePreference`: unknown value returns `false`. The in-memory theme is kept when the save fails; the return is `false`.
- `markTourSeen`: a failed save still dismisses the tour for the session.
- `setPrimaryScreen(id)`: unknown id returns `false`. Known ids: `blending`, `what-if`, `inventory`, `settings`, `about`.
- `setSettingsCategory`: unknown or unchanged category is ignored.
- `navigate({screen, settingsCategory})`: the category is applied only when known.

Factory reset:
- `factoryReset(confirm)` returns `FactoryResetOutcome`:
  - `cancelled`: confirm returned false. Nothing changes.
  - `failed`: the reset threw. State is unchanged.
  - `reset`: all failure flags and `bankInputFailure` clear, `trackFactoryReset` fires, then the analytics gate is re-enabled.
- The reset itself is `resetApplicationState` (`lib/src/domain/factory_reset.dart`) over `resetApplicationData` (`lib/src/data/factory_reset_storage.dart`). Storage details are in [persistence-settings.md](./persistence-settings.md).

## BlendController

Shared inputs (`updateSharedInputs`):
- Re-resolves the selected cylinder preset by name from `settings.cylinderPresets` first, so edits made in Settings reach Blending without re-picking the preset. A name that no longer exists (deleted or renamed in Settings) keeps the previous copy in `_inputs`, but Blending refuses to calculate from it: see the refusal below. Re-adding a preset with that name, or re-selecting a preset in the dropdown, recovers.
- Drops bank price suggestions for banks whose `enabled` flipped.
- If `calculatorInputSignature` changed from the previous input, clears interim readings and `interimMeasurementSignature`.
- Prunes suggestions that are no longer fresh, then recalculates.

Signature rules (`lib/src/domain/interim_measurements.dart`, `calculatorInputSignature`):
- Excluded: `thermal.interimMeasurements`, `settings.costs`, `settings.units`, and each bank's `pricePerLitre`.
- So editing a price or display unit keeps the interim readings. Editing anything else in the signature clears them.

Interim readings (`applyInterimMeasurement`, `clearInterimMeasurement`):
- Readings are a list indexed by step. Only the latest reading can be changed or cleared (`interimMeasurementLockMessage`). A new reading MUST be at or after the latest index. Earlier steps are locked.
- `applyInterimMeasurement(index, reading)`:
  - Returns the lock message when locked.
  - Builds a candidate input and runs `verifyInterimMeasurement` (`lib/src/domain/interim_check.dart`). The check plans from the readings before `index` and compares the measured pressure with the planned one using `settings.interimPressureTolerancePercent`.
  - Rejection returns the error text and changes nothing.
  - Success stores the reading, sets `interimMeasurementSignature` from the candidate, then recalculates. Returns `null`.
- A measured temperature below ambient is rejected unless the gas state came from a pressure-lowering step. Those steps are `draining-rate`, `salvage-decant`, and `salvage-booster` (`gasCanBeBelowAmbient`).
- `clearInterimMeasurement(index)`: lock check with action `clear`, then `signatureAfterClearingMeasurement`. The signature is `null` when no reading remains. Then recalculates.
- `recalculate()` drops all readings when they exist and `interimMeasurementSignature` no longer matches the input. This is the guard against readings that no longer describe the recipe.

Results:
- Invalid input yields `_invalidInputResult`: `feasible: false`, `error: 'Invalid input: ...'`.
- An incomplete cylinder preset (no diameter or length) is refused before any physics runs. The validation message is `incompleteCylinderMessage(name)`.
- A selected preset whose name matches no preset in the current `settings.cylinderPresets` is refused before any physics runs, with `selectCylinderPresetMessage` ('Select an available cylinder preset.'), the same message What-if uses. This check comes first, so no incomplete-preset message is added for it.
- Both paths pass through `_withPressureLimitWarnings`.
- `blend_calculated` is tracked once per run with the `optimize` mode and outcome `invalidInput`, `feasible`, or `infeasible`.

Costs (`blendingCost`, `blendingSavings`):
- `blendingCostSource()` is `null` unless there is a result with input and `feasible` is not `false`.
- Cost is computed live from the current `banks` and `settings.costs` (`computeFillCost`). Price edits update cost without re-planning.
- Each source bank gets one gas line. Source banks with no price are listed in `unpricedSources`, and the total is marked `incomplete`.
- Operation fees count distinct `costOperationId`s per operation.
- Savings come from `computeSavings` (`lib/src/domain/savings.dart`).

Bank price suggestions (`calculateBankPrice`, `applyBankPrice`, `clearBankSuggestion`, `bankSuggestionFor`):
- `calculateBankPrice(id)` runs `priceBankByRecipe` (`lib/src/domain/bank_pricing.dart`), which is side-effect free. The result is stored with `bankPricingSignature(bank)`.
- The signature covers volume, pressure, O2 and He percent, costs, booster, pressure-limit mode, physics model, ambient temperature, pure-gas prices, and inventory temperature.
- `bankSuggestionFor(id)` drops the entry and returns `null` when the signature is stale or the bank is gone.
- `applyBankPrice(id)` applies only a fresh `BankPriceOk`, through `updateBank` with the new `pricePerLitre`. It then removes the suggestion and recalculates.
- Recipe pricing refuses:
  - Pure O2 or pure He banks (enter the price manually).
  - Banks below 10 bar.
  - Recipes needing more than 6 virtual sources of one pure gas.
- A needed pure gas with no weighted price returns `BankPriceFailure` with `missingGas` set to `oxygen` or `helium`.
- Pure-gas prices are volume-weighted over enabled pure banks that hold free gas (`pureGasPrices`, `lib/src/domain/pure_prices.dart`).

Factory reset: `resetForFactoryReset()` clears suggestions and readings, then recalculates.

## WhatIfController

Invariants (also in the class doc comment):
- A failed run keeps the last valid `result` and `warnings`, and still sets `hasRun`. This covers the validation branch (`_rejectRun`) and the simulation-error branch (`_rejectSimulation`).
- `isStale` is derived: `sharedInputChanged || draftChanged`. A result is stale once the draft revision or the shared-input signature differs from the run that produced it. This holds after a successful run or a failed one.
- Bank prices are excluded from the shared-input signature (`whatIfSharedInputSignature`, `lib/src/domain/what_if_scenario.dart`), so a price-only change never marks the projection stale.

Other rules:
- `updateSharedInputs` stores new shared inputs. `isStale` recomputes the current signature on each read.
- `copyFromBlending` copies blend start values into the scenario and runs it. Every run sets `hasRun`.
- `resetForFactoryReset()` restores the default scenario, clears field errors and `hasRun`, and keeps the stored result, as the JS app does.

## Tests

- Controller tests live in `test/controllers/`. Use `MemoryStorage` (`test/support/memory_storage.dart`) for storage-backed controllers.
- `test/controllers/blend_controller_test.dart` header names the JS functions these Dart controllers mirror.

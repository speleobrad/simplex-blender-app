# Persistence and settings

Scope: browser-storage adapters in `lib/src/data/`, the pure domain code they call in `lib/src/domain/`, and the rules for loading, saving, and migrating each stored value. Controller behavior on storage failures is in [controllers-state.md](./controllers-state.md).

## Storage keys

Key strings are exact. Changing one orphans user data.

| Constant | Key | Owner |
|---|---|---|
| `SETTINGS_STORAGE_KEY` | `simplex-gas-remixer-settings` | `lib/src/data/settings_storage.dart` |
| `STORAGE_KEY` (banks) | `simplex-gas-remixer-banks` | `lib/src/data/bank_storage.dart` |
| `THEME_STORAGE_KEY` | `simplex-gas-remixer-theme` | `lib/src/domain/theme.dart` |
| `ONBOARDING_STORAGE_KEY` | `simplex-gas-remixer-onboarding` | `lib/src/domain/onboarding.dart` |
| `analyticsStorageKey` | `simplex-gas-remixer-analytics` | `lib/src/data/analytics_storage.dart` |

No other `simplex-*` keys exist in `lib/`. Tests use the same constants.

## Adapter contract

- `KeyValueStorage` (`lib/src/data/key_value_storage.dart`): `getItem` returns `null` when absent. `clear` removes every key, as `localStorage.clear()` does.
- `PreferencesKeyValueStorage.open({onWriteError})` (`lib/src/data/preferences_storage.dart`) preloads string entries. Non-string entries are invisible to `getItem`.
- `setItem` and `clear` update memory immediately and queue the platform write in call order. Write methods never throw synchronously.
- A failed write (false return or thrown error) goes to `onWriteError`, is not rethrown, and the in-memory value serves the rest of the session.
- `onWriteError` MUST NOT throw. `lib/main.dart` passes a `debugPrint` logger.
- `pendingWrites` completes when queued writes finish. The preferences test helper calls `reload()` to re-read the platform store, bypassing the cache (`test/data/preferences_storage_test.dart`).

## Load and save rules

- Loaders never throw. A bad stored value yields defaults and calls `onFallback`, which sets the matching failure flag in `AppController`.
- Loaders do not write back. Defaults stay in storage until the next save.
- Savers validate first. Invalid data throws before any write, so storage keeps the last good value.
- Absent key (`null`) returns defaults without `onFallback`. Only corrupt data is reported.

## Settings

Files: `settings_storage.dart`, `settings_json.dart`, `settings_migrations.dart`.

Load (`loadSettings`):
- `getItem` throws: `onFallback`, defaults.
- `null`: defaults, no `onFallback`.
- `jsonDecode` throws `FormatException`: `onFallback`, defaults.
- Decoded JSON runs through `normalizeSettingsJson`, then `validateSettingsJson`. Any errors: `onFallback` with `RangeError(errors.join(' '))`, defaults.
- Valid: `settingsFromJson`.

Save (`saveSettings`):
- Normalize, validate. Invalid: throws `RangeError(errors.join(' '))`, no write.
- Valid: `setItem(SETTINGS_STORAGE_KEY, jsonEncode(stored))`.
- `settingsToJson` key order follows the JS `copySettings` shape.

Shape:
- There is no version field. Shape is enforced only by `validateSettingsJson` (`settings_json.dart`).
- Checked: `gasPresets` and `cylinderPresets` are lists; `units` is `metric` or `imperial`; `pressureLimitMode` is `hard-stop` or `warning`; `pressureWarningUnlocked` is bool; `warning` mode requires the unlock; `interimPressureTolerancePercent` is in 0.5–10; `physics.model` is `ideal` or `vdw`; booster scalars; compressor, booster, gas, and cylinder preset validators; preset names unique; `validateCostSettings`.
- `settingsFromJson` assumes validated input. Do not call it on raw JSON.

Migrations (`normalizeSettingsJson`), in order:
1. `addDefaultBooster`
2. `addDefaultUnits`: anything other than `imperial` becomes `metric`.
3. `addDefaultPressureLimitPolicy`
4. `addDefaultPhysics`
5. `addDefaultCylinderPresets`: legacy `volumePresets` convert via `legacyVolumePresetsToCylinders`. Each becomes `'<n> L Steel 232 bar'`, steel, 14 kg, 232 bar working pressure. `hotOverfillPercent` is filled only when absent.
6. `addDefaultEquipmentPresets`: MUST run after `addDefaultBooster`.
7. `addDefaultInterimPressureTolerance`
8. `addDefaultCosts`: `copyCosts` treats non-object `costs` and `operationPrices` as absent. Legacy per-litre keys are ignored. `feeOrZero`: an absent fee is 0.

Migration rule: use `containsKey`. A present `null` is kept, and only absent keys take defaults.

## Inventory banks

File: `bank_storage.dart`.

Load (`loadSupplyBanks`):
- `getItem` throws or `FormatException`: `onFallback`, defaults.
- `null`: copy of `DEFAULT_BANKS`, no `onFallback`.
- `normalizeSavedBanks` failure: `onFallback`, defaults.

Normalization order:
1. Drop legacy Air records.
2. Replace the exact legacy default set with `DEFAULT_BANKS`.
3. Fill missing `maxPressureBar` with `max(200, pressureBar)`.
4. Validate with `validateSupplyBankInput`.

Save (`saveSupplyBanks`): validates, throws `DomainError(errors.join(' '))` before writing. Writes a JSON list of `bankToRecord`.

## Theme

Files: `theme_storage.dart`, `lib/src/domain/theme.dart`.
- Load: any throw or unknown value returns `DEFAULT_THEME` (`'light'`). Not reported.
- Save: `themeToStore` throws `RangeError('Theme must be light or dark.')` before writing. Valid values: `light`, `dark`.

## Onboarding

Files: `onboarding_storage.dart`, `lib/src/domain/onboarding.dart`.
- Load: `getItem` throws, unparsable JSON, or missing or non-bool `wizardSeen`: `DEFAULT_ONBOARDING_STATE` (`wizardSeen: false`) and `onFallback`. `null`: default, no `onFallback`.
- Extra keys are ignored. Legacy `consentAccepted` is dropped on the next save.
- Save writes `{"wizardSeen": <bool>}` only.

## Analytics opt-out

File: `analytics_storage.dart`.
- Load: `null` is enabled. `{"enabled": bool}` returns that value. Anything else, or a throw, is enabled. This path is silent: there is no `onFallback` and no warning.
- Save writes `{"enabled": <bool>}`.

## Storage warnings

`getStorageWarningMessages` (`lib/src/domain/storage_warning.dart`) returns lines in this order:
1. `Saved presets could not be loaded; built-in defaults are active.` (settings load)
2. `Saved Inventory could not be loaded; default inventory is active.` (banks load)
3. `Inventory changes could not be saved to browser storage.` (banks save)
4. `Saved guided-tour preference could not be loaded; the guided tour will be shown again.` (onboarding load)
5. `Inventory edit rejected: <message>` (when a bank edit was rejected)

A settings save failure is not a warning line. `AppController.applySettings` returns `settingsSaveFailureMessage` and keeps the previous settings in memory.

## Factory reset

- `resetApplicationState` (`lib/src/domain/factory_reset.dart`): confirm returns false, so no change. Otherwise `resetData()` runs and its result is copied into state. If `resetData` throws, the error propagates and state is unchanged.
- `resetApplicationData` (`lib/src/data/factory_reset_storage.dart`): calls `storage.clear()` first, then runs each loader. Every key is absent afterward, so every loader returns defaults with no `onFallback`. Onboarding returns to `wizardSeen: false`; consent is not kept.

## Tests

- `test/support/memory_storage.dart`: `MemoryStorage(Map<String, String> initial)` implements `KeyValueStorage` synchronously. It has no failure injection. `values` returns an unmodifiable snapshot.
- Storage tests: `test/data/` (`factory_reset_storage_test.dart`, `preferences_storage_test.dart`, `onboarding_storage_test.dart`, `theme_storage_test.dart`).
- Key-level assertions use the constants, e.g. `analyticsStorageKey` (`test/controllers/analytics_gate_test.dart`) and `STORAGE_KEY` (`test/controllers/app_controller_test.dart`).

# Optimizer and physics

Blend optimizer (`lib/src/domain/optimizer.dart` and `lib/src/domain/optimizer/`), gas physics, and the domain files they call. Ported from `js/optimizer.js` and related JS; the JS files are not in this repo and are cited in comments as provenance only.

## 1. Public entry points

| Symbol | File | Use |
|---|---|---|
| `optimizeBlend(Map<String, Object?>)` | `optimizer/blend_entry.dart` | Main entry. Validates, then calls `solveThermalWithSalvageFallback(input, optimizeBlendWithoutThermal)`. |
| `solveThermalWithSalvageFallback` | `optimizer/blend_entry.dart` | Salvage and thermal orchestration. Takes the static solver as a parameter. |
| `optimizeBlendWithoutThermal` | `optimizer/salvage_search.dart` | Static (non-thermal) solver. Replays salvage receiver ids when set. |
| `searchSalvageVariant` | `optimizer/salvage_search.dart` | Returns chosen salvage receiver ids (`List<String>?`). |

- Input is the JS-shaped map. `_parseBlendInput` (`optimizer/blend_input.dart`) converts it to typed records. Callers never pass typed objects.
- Output is a JS-shaped `Map<String, Object?>`. `optimizeBlendWithoutThermal` removes `lpCost` from its output.

## 2. Pipeline

Files in the order a request flows through them. Helper files are called from the entry files.

1. `optimizer/blend_input.dart`: parse into `PhysicsInput`, `List<Bank>`, `BlendSettings`, `ThermalInput`. Missing numeric fields parse to `null` and fall back per field. The header comment's fallback numbers (232, 200, 20 bar) do not match the `settings.dart` defaults (booster output 230 bar), so check the consumer, not the comment.
2. `optimizer/values.dart`: typed readers for the untyped cylinder map (`_numberOrNull`, `_numberOrNan`).
3. `optimizer/blend_metrics.dart`: `_validateBlendInput`, `_invalidBlendInputResult`, `_failedResult`, diagnostics, shortfalls, summary.
4. `optimizer/blend_entry.dart`: validation gate, thermal or static dispatch, salvage fallback.
5. `optimizer/salvage_search.dart`: static solve. Runs the vent-only solve, then ranks receivers and builds candidate variants for selection.
6. `optimizer/blend_no_salvage.dart`: vent-only solve (`_solveBlendWithoutSalvage`). Accepts `_salvagePlan` from step 8.
7. `optimizer/blend_no_salvage_search.dart`: pressure search (`_BlendSearch`: `solveAtPressure`, `safetyFor`, `safeAtPressure`, `tryPairShare`).
8. `optimizer/salvage_cascade.dart`: salvage decant then boost (`_runSalvageCascade`), receiver ranking (`_rankSalvageReceivers`), variant build (`_buildSalvageVariant`).
9. `optimizer/linear_program.dart`: composition LP (`_solveLinearProgram`, `_solveTargetBlendAtMoles`) on `solveTwoPhaseSimplex`.
10. `optimizer/blend_plan.dart`: compressor air, boost ordering, pressure-transfer staging.
11. `optimizer/blend_safety.dart`: equipment safety, feasible oxygen-share ranges, maximum outside-oxygen search.
12. `optimizer/thermal_blend.dart`: thermal candidate search (`_optimizeThermalBlend`, `_evaluateThermalCandidate`, `_thermalResult`). Requires thermal input.
13. `optimizer/schedule.dart`: `scheduleSafeThermalProtocol`. Returns `protocolSteps`, `automaticWaits`, `simulation`, `unsafe`.
14. `optimizer/safety.dart`: thermal safety checks, safe transfer splits, automatic waits.

## 3. Supporting domain files

- `lib/src/domain/physics.dart`: gas law. See section 4.
- `lib/src/domain/thermodynamics.dart`: thermal model and typed records (`PhysicsInput`, `ThermalInput`, `ProtocolStep`, `ThermalStep`, `ThermalProtocolResult`). Simulations: `simulateThermalProtocol`, `simulateCompareProtocol`, `calculateBoosterFillRate`, `estimateTransferTemperature`, `coolingTimeConstantMinutes`.
- `lib/src/domain/salvage.dart`: salvage economics and selection. `selectSalvageVariant`, `salvageTransferMoles`, `applyDrawToBank`, `isSalvageReceiver`, `SalvageVariant`, `SalvageBaseline`, `ReceiverCandidate`.
- `lib/src/domain/simplex.dart`: `solveTwoPhaseSimplex`, port of `js/simplex.js`.
- `lib/src/domain/leftover_attractiveness.dart`: `leftoverAttractiveness`, `leftoverReachability`, `standardTargets`.
- `lib/src/domain/compare_recipe.dart`: compare-recipe model, row types, methods, validation.
- `lib/src/domain/pressure_limits.dart`: `getCylinderPressureLimit`, pressure warnings. Port of `js/pressure-limits.js`.
- `lib/src/domain/js_number.dart`: `jsNumberString` (mirrors JS `String(n)`), `parseJsNumber` (mirrors JS `Number(text)`).

## 4. Physics

- Gas model is `PhysicsInput.model`. `PhysicsInput.useVdw` is `model == 'vdw'`, so any other value runs ideal gas. Settings accept only `ideal` or `vdw` (`lib/src/domain/settings.dart` `PhysicsSettings`, `_gasModelValues`). Default `vdw`. Serialized as `physics.model` by `physicsFromJson` and `physicsToJson` in `lib/src/domain/settings_json.dart`.
- `gasConstant = 0.083144626`. Pressure in bar, volume in litres, temperature in °C.
- `getMixParams`: van der Waals mixing. N2 fraction = 1 − O2 − He, clamped at 0. Per-gas parameters are private `_GasParameters` (He, O2, N2).
- `calcPressure`: returns `9999` when the denominator is ≤ 0.001. Ideal gas when `useVdw` is false.
- `calcMolarDensity`: Newton iteration, at most 40 steps. Stops when `|derivative| < 1e-9` or `|delta| < 1e-6`. Clamps density to `0.95 × maxDensity` and floors at `1e-4`. Ideal gas when `useVdw` is false.
- `calcZ` and `calcZFromDensity` return 1 when `useVdw` is false.
- `thermodynamics.dart` constants: `atmosphericPressureBar = 1.01325`, `gaugePressureOffsetBar = 1`, `clearanceRatio = 0.05`, `gamma = 1.4`, `oxygenRichThreshold = 40`, `thermalIntegrationStepSeconds = 0.5`, `heatTransferAirWPerM2K = 12`, `heatTransferWaterWPerM2K = 250`, `defaultWaterSubmersionPercent = 60`.
- Hot-endpoint solve in `simulateThermalProtocol`: up to 8 iterations; stops when the transfer end pressure moves less than `1e-7` bar.
- `simplex.dart`: pivot tolerance `1e-12`; entering threshold `-1e-6`; ratio test skips coefficients `≤ 1e-8`; at most 80 iterations per phase; phase-1 feasibility tolerance `max(1e-12, scale × 1e-9)`.

## 5. Gotchas

- Cylinder data is an untyped `Map<String, Object?>` with JS key names. A missing key is an absent map key. Read it through `_numberOrNull` (non-number → null) or `_numberOrNan` (non-number → NaN).
- `_SafetyContext` fields are read with `!` in places where the JS dereferences them only on guarded paths. A new unguarded read can throw.
- `_failedResult` infers `reasonCode` from the error text and component shortfalls. Passing `reasonCode` explicitly overrides this, including an explicit `null`.
- Values that reach JS-visible keys or messages use `jsNumberString`, not `toString()`. Example: `_cascadeCompositionKey` in `linear_program.dart`.
- `solveThermalWithSalvageFallback` checks `_salvage == false` before any salvage search. The order decides whether `searchSalvageVariant` runs.
- For thermal input, if the salvage result is infeasible, the solver falls back to the baseline with `_salvage: false` when that baseline is feasible.
- `INTERNAL_THERMAL_TARGET` (`'__internalThermalTarget'`, `linear_program.dart`) is an internal LP target name. `_validateBlendInput` takes an `internalThermalTarget` flag for it.
- Two separate constants are both 1440 minutes: `MAX_AUTOMATIC_WAIT_MINUTES` (`safety.dart`) and `MAX_WAIT_MINUTES` (`compare_recipe.dart`).
- Salvage: `SALVAGE_MOLE_TOLERANCE = 1e-9` (`salvage_cascade.dart`); `_tolerance = 1e-9` and `_bisectionSteps = 100` (`salvage.dart`). Gate: no bank may lose more than `|salvageAttractivenessGate|` (2) points; net value kept must be ≥ `salvageMinValue` (1.0). Prices: `salvageHePricePerLitre = 0.075`, `salvageO2PricePerLitre = 0.007`.
- Target-pressure bounds in `salvage_search.dart`: `MINIMUM_TARGET_PRESSURE_BAR = 10`, `MAXIMUM_TARGET_PRESSURE_BAR = 350`. Thermal target tolerance: `THERMAL_TARGET_TOLERANCE_BAR = 1e-5`. Thermal safety tolerance: `THERMAL_SAFETY_TOLERANCE_BAR = 1e-9` (`safety.dart`).
- `leftoverAttractiveness` returns 0 for invalid input. A null `physics` means ideal gas at the given temperature.

## 6. Tests

Tests are under `test/domain/`.

| Area | Test file |
|---|---|
| Static blend, validation, default example | `optimizer_test.dart` |
| Salvage variants and cascade | `optimizer_salvage_test.dart` |
| Thermal protocol, pressure caps, fallbacks | `optimizer_thermal_test.dart` |
| Shared JS-shaped fixtures (`defaultOptimizerInput`, `cloneOptimizerInput`) | `optimizer_fixtures.dart` |
| Salvage selection and constants | `salvage_test.dart` |
| Simplex | `simplex_test.dart` |
| Gas physics | `physics_test.dart` |
| Thermodynamics | `thermodynamics_test.dart` |
| Compare recipe | `compare_recipe_test.dart` |
| Pressure limits | `pressure_limits_test.dart` |
| Leftover attractiveness | `leftover_attractiveness_test.dart` |
| `js_number.dart` | none found under `test/` |

- `defaultOptimizerInput()` returns a fresh map each call. Use `cloneOptimizerInput` to copy a shared input before editing it.

## 7. Change rules

- Keep JS-port comments and their provenance references. Do not add JS line numbers.
- This is a port: keep the gas-law and simplex arithmetic as written.
- Keep the branch order in `solveThermalWithSalvageFallback` and `optimizeBlendWithoutThermal`.
- Read cylinder fields through the typed readers in `optimizer/values.dart`. Do not add direct raw-map reads.
- The gas-model list lives in three places that must agree: `_gasModelValues` (`settings.dart`), `physicsFromJson`, and `physicsToJson` (`settings_json.dart`).
- Add optimizer tests to the matching `optimizer_*_test.dart` file. Shared inputs go in `optimizer_fixtures.dart`.
- Build, test, and CI conventions are in `README.md`.

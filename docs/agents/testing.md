# Testing

Test layout, shared helpers, and the JS-parity conventions for Dart tests. For how to run tests and CI checks, see `README.md`.

## Layout

| Folder | Covers |
|---|---|
| `test/domain/` | pure logic, one `*_test.dart` per module (`optimizer_*`, `cost_test.dart`, `physics_test.dart`, `salvage_test.dart`, …) |
| `test/data/` | storage adapters and migrations (`*_storage_test.dart`) |
| `test/controllers/` | `AppController`, `BlendController`, `WhatIfController`, analytics gate |
| `test/ui/` | widget tests mirroring `lib/src/ui/`: `app_screens/`, `blending/`, `what_if/`, `shell/`, `results/` |
| `test/widget/` | `preset_import_test.dart`, the only file here; drives the settings preset import flow |
| `test/analytics/` | `analytics_test.dart`, event helpers and `safeTrack` |
| `test/support/` | `memory_storage.dart`, the shared in-memory `KeyValueStorage` |
| `test/fixtures/` | `valid-gases.json`, `invalid.json`; used only by `preset_import_test.dart` |

- `test/domain/optimizer_fixtures.dart` is a helper, not a test. `defaultOptimizerInput()` returns a fresh map; `cloneOptimizerInput(input)` deep-copies a map before mutation.
- `materials_test.dart` and `preset_import_test.dart` read the real `assets/presets/{gas,cylinders,equipment}.json` through relative paths. Run tests from the repo root.

## Conventions

- File names: snake_case, suffix `_test.dart`, named after the module under test.
- Domain and data files: `void main()` with `group('<subject>', …)` and `test('<sentence>', …)`. `cost_test.dart` has no `group`.
- Widget files use `testWidgets('<sentence>', …)`. Controller files use `test`.
- Fakes are declared inside the test file that needs them. No fake is shared through `test/support/`.
- Analytics fakes: `_RecordingAnalytics` (records `{event, props}` in `calls`), `_ThrowingAnalytics`, and `_NoopAnalytics` in UI tests. For new analytics tests, see `./analytics.md`.
- Storage fakes: `_UnreadableStorage` (`getItem` throws), `_FailingWriteStorage` (`setItem` throws), `_ClearFailsStorage` (`clear` throws). Other storage tests use `MemoryStorage`.
- `MemoryStorage(<String, String>{KEY: jsonEncode(json)})` seeds raw stored records. Its `values` getter returns a snapshot for assertions.
- Controllers are built directly: `AppController(storage: MemoryStorage(), analytics: …)` and a local `_controller(…)` in `blend_controller_test.dart`.
- Widget files each define their own pump helper (`_pump`, `_pumpShell`, `_pumpScreen`, `pumpEditor`) that calls `tester.pumpWidget(MaterialApp(…))`. No shared pump helper exists.
- Screens that read onboarding anchors are pumped with `TourTargets()` or `TourTargetsScope`, for example `blending_form_test.dart` and `settings_screen_test.dart`.
- `app_shell_test.dart` sets `tester.view.physicalSize` and resets it with `addTearDown`.
- Preset import seams: `preset_import_test.dart` injects a file picker through `filePicker:` and mocks HTTP with `MockClient`. Fixtures load with `File(path).readAsStringSync()`.

## JS parity

- The Dart code is a port. Expected values come from the JS app's behavior, not from Dart output. `calculator_input_test.dart` header: "Expected shapes are taken from the JS source, not from the Dart output".
- Header comments cite JS sources for provenance. These are NOT in this repo (`js/` and `tests/` are absent). Do not try to open them. Cited examples:
  - `js/main.js`: `blend_controller_test.dart`, `pressure_warnings_test.dart`.
  - `js/bank-storage.js`: `calculator_input_test.dart`.
  - `js/preset-validation.js`: `preset_validation_test.dart`. Messages are verbatim; the same file pins user-visible text instead of JS `RangeError` cases.
  - `js/ui/results.js` (`renderProtocol`) and `index.html`: `mixing_steps_test.dart`. `index.html` tour anchors: `blending_screen_test.dart`.
  - `tests/browser/persistence.spec.js`: `preset_import_test.dart`. Its fixture files come from the same JS repo.
  - `tests/supply-banks-ui.test.js`: `supply_banks_section_test.dart`.
- Structure tests assert JS key order (`calculator_input_test.dart`).
- `JS undefined and null both map to Dart null` (`bank_price_format_test.dart`).
- Error tests match the message regex, case-insensitive. Helper: `_rangeErrorWith(pattern)` in `settings_storage_test.dart`.
- Storage read failures must reach `onFallback`, not be swallowed (`onboarding_storage_test.dart`).

## Gotchas

- Optimizer thermal tests: pass the full default settings map (`_defaultSettingsMap()` in `optimizer_thermal_test.dart`), not `{}`. An empty map falls back to 200 bar booster output, not 230.
- Optimizer input: start from `defaultOptimizerInput()`, then `cloneOptimizerInput` before mutating.
- `analysis_options.yaml` applies to `test/` too: `strict-casts`, `strict-inference`, and `strict-raw-types` are on. Write explicit types (`<String, Object?>{…}`) and cast with `as`. `optimizer_salvage_test.dart` uses `_m(Object? value) => value! as Map<String, Object?>`.
- Expected values for new cases must be checked against the JS source or the documented behavior, never copied from current Dart output.

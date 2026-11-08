# Architecture

Layering, import direction, UI feature map, and porting conventions for `lib/`.

## Layers

| Layer | Path | Role | May import |
|---|---|---|---|
| domain | `lib/src/domain/` | Pure Dart: physics, thermodynamics, optimizer, validation, settings JSON shape, cylinder geometry (`cylinder_geometry.dart`) and preset display text (`cylinder_preset_text.dart`) | `domain` only. No `package:flutter`. |
| data | `lib/src/data/` | `KeyValueStorage` adapters, settings/bank/theme/onboarding persistence, settings migrations, `preset_source.dart` (file picker and HTTP) | `data`, `domain`, `package:shared_preferences` (`preferences_storage.dart` only), `package:file_picker` and `package:http` (`preset_source.dart` only) |
| analytics | `lib/src/analytics/` | `Analytics` interface, event enums, `NoopAnalytics`, `GatedAnalytics`, `AptabaseAnalytics` | `analytics`, `package:aptabase_flutter` |
| controllers | `lib/src/controllers/` | `ChangeNotifier` state: `AppController`, `BlendController`, `WhatIfController` | `domain`, `data`, `analytics`, `package:flutter/foundation.dart` |
| ui | `lib/src/ui/` | Widgets, grouped by feature. Reads controllers and domain value types | `controllers`, `domain`, `ui`, `package:flutter`, `package:url_launcher` (`about/about_screen.dart` only), `package:http` (`settings/settings_screen.dart` only). `data` and `analytics` only in `ui/settings/settings_screen.dart` |

## Wiring point

`lib/main.dart` is the composition root. `main()` does:

1. `PreferencesKeyValueStorage.open(onWriteError: ...)` builds the storage.
2. `_aptabaseAppKey` (from `String.fromEnvironment('APTABASE_APP_KEY')`) selects `NoopAnalytics` or `AptabaseAnalytics.init(...)`.
3. `AppController(storage:, analytics:)` is constructed. It owns settings, banks, theme, onboarding, and the analytics gate.
4. `BlendController` gets `app.banks`, `app.settings`, `app.analytics`, and `app.updateBank`. `WhatIfController` gets `app.banks`, `app.settings`, and `app.analytics`. Controllers never import each other.
5. `runApp(SimplexBlenderApp(app:, blend:, whatIf:))`, defined in `lib/src/ui/shell/app_shell.dart`.

Add new long-lived services here and pass them down through constructors. Do not reach for globals.

## Import rules

Verified by grep of `import` lines in each layer:

- `domain` imports no `package:flutter`, `controllers`, `data`, `analytics`, or `ui`.
- `controllers` import no other controller. `BlendController` gets bank writes through the `updateBank` callback rather than importing `AppController`.
- `controllers` import `data` only in `app_controller.dart`. `BlendController` and `WhatIfController` do not import `data` or access storage.
- `ui` imports `controllers` and `domain`. Only `settings_screen.dart` imports `data` and `analytics`.
- `data` imports `domain` and `data`. It does not import `controllers`, `analytics`, or `ui`.
- `analytics` is the only layer that imports `package:aptabase_flutter`.

Known exceptions: `lib/main.dart` (composition root) imports every layer. `ui/settings/settings_screen.dart` imports `data/preset_source.dart` and `analytics/analytics_events.dart`. Some files use relative imports (`what_if_controller.dart`, `settings_screen.dart`). New imports use the package form: `package:simplex_blender/src/...`.

## UI feature map

Folders under `lib/src/ui/`:

| Folder | Purpose |
|---|---|
| `shell/` | `SimplexBlenderApp` (root widget and navigation), `app_theme.dart` palette, `TourTargets` for the guided tour |
| `blending/` | Blending screen: form, transfer conditions, recipe, ternary and thermal panes, tanks and costs |
| `what_if/` | What-if screen: scenario rows, start fields, results, number and select fields, formatting |
| `inventory/` | Inventory screen: supply bank list and equipment summary |
| `results/` | Shared result widgets: `ternary_diagram.dart`, `thermal_charts.dart`, `water_pressure_pane.dart` |
| `shared/` | `compare_recipe_editor.dart`, used by Blending and What-if. `number_input.dart`: `signedDecimalKeyboard`. `focus_loss_node.dart`: `FocusLossNode`, a `FocusNode` that calls back when focus is lost |
| `settings/` | `settings_screen.dart`: settings editor, save/cancel, factory reset. `sections/*.dart` are `part` files of it: one per category (general, costs, gas presets, cylinder presets, equipment) as extensions on the state, and preset import as a mixin that owns the import state |
| `about/` | `about_screen.dart`: app info, links, license page |
| `onboarding/` | `onboarding_tour.dart`: eight-step spotlight tour |

## Porting conventions

- Ported code cites its JS origin in doc comments as `Port of JS <name>` (for example `Port of JS loadSettings` in `lib/src/data/settings_storage.dart`). The `js/*.js` files named in comments are not in this repo.
- Formulas, constants, tolerances, iteration limits, and branch order match the JS. Do not refactor the math. Preserve evaluation order in ported branches.
- `lib/src/domain/domain_error.dart` defines `DomainError`. Its message text is kept identical to the web app because it is user-visible.
- Other user-visible strings are constants next to their owner, kept identical to the web app:
  - `settingsSaveFailureMessage` in `lib/src/controllers/app_controller.dart`
  - `_factoryResetPrompt`, `_factoryResetFailedMessage`, `_factoryResetDoneMessage` in `lib/src/ui/settings/settings_screen.dart`
  - `PRESSURE_WARNING_UNLOCK_PHRASE` in `lib/src/domain/settings.dart`
- Storage keys and the settings JSON shape follow the web app's localStorage layout. Migrations in `lib/src/data/settings_migrations.dart` are ports of the JS settings migration chain. Keep them in the same order.
- Validation returns message lists (for example `validateSettingsJson` in `lib/src/domain/settings_json.dart`). Storage writes throw `RangeError` on invalid data before anything is persisted (`saveSettings`, `saveThemePreference`).

## Pointers

- Controller state, notifications, and error flow: `./controllers-state.md`
- Storage adapters, keys, migrations, and factory reset: `./persistence-settings.md`
- Analytics gate, events, and privacy rules: `./analytics.md`
- Test layout, fixtures, and fakes: `./testing.md`
- Optimizer and physics ports: `./optimizer-physics.md`

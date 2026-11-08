# simplex_blender: agent guide

Flutter port of a breathing-gas blending calculator. Features, build, and CI are in `README.md`. This file points to topic docs; read only the ones your task needs.

## Checks

Run before finishing a change (CI runs the first three):

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test                                  # one file: flutter test test/domain/optimizer_test.dart
```

## Hard rules

- Ported logic: formulas, constants, tolerances, iteration limits, and branch order match the JS app. Do not refactor the math. Exception: the heat-transfer surface comes from cylinder dimensions (see `docs/superpowers/specs/2026-11-08-cylinder-dimensions-design.md`). See `docs/agents/architecture.md`.
- `lib/src/domain/` never imports `package:flutter`.
- Controllers do not import each other. `AppController` owns shared state. See `docs/agents/controllers-state.md`.
- Analytics sends only events defined in `lib/src/analytics/analytics_events.dart`, with closed values. Never send bank names, gas values, pressures, prices, or free text. See `docs/agents/analytics.md`.
- Storage keys and the settings JSON shape match the web app's localStorage layout. Cylinder presets also store `diameterMm` and `lengthMm` (number or `null`), an addition beyond the web app's shape. See `docs/agents/persistence-settings.md`.
- Never commit generated files: `build/`, `.dart_tool/`, `coverage/`, `android/local.properties`, plugin registrants.

## Topics

| Read when | File |
|---|---|
| Layers, import rules, UI feature map, porting conventions | `docs/agents/architecture.md` |
| Controllers, state ownership, invariants | `docs/agents/controllers-state.md` |
| Storage keys, settings load/save, migrations, storage warnings | `docs/agents/persistence-settings.md` |
| Analytics interface, events, privacy rules | `docs/agents/analytics.md` |
| Test layout, fixtures, test support, conventions | `docs/agents/testing.md` |
| Blend optimizer pipeline, physics models | `docs/agents/optimizer-physics.md` |

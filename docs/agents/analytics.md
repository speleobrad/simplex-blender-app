# Analytics

Analytics sink, closed event set, user opt-out, and how to add events. For supplying the Aptabase key, see the Analytics section of `README.md`.

## Components (`lib/src/analytics/analytics.dart`)

- `Analytics`: interface, `track(String event, [Map<String, Object> props])`.
- `NoopAnalytics`: drops every event; no network.
- `GatedAnalytics(inner, {required enabled})`: forwards only while its mutable `enabled` is true. Disabled events are dropped, not queued.
- `AptabaseAnalytics.init(appKey)`: async, returns `Future<Analytics>`. Asserts a non-empty key. If `Aptabase.init` throws, returns `NoopAnalytics`.
- `AptabaseAnalytics.track`: calls `Aptabase.instance.trackEvent` and consumes its async error.
- `safeTrack(analytics, event, props)`: calls `track` and swallows synchronous errors. Every `track…` helper goes through it.

## Wiring

- `lib/main.dart` reads `_aptabaseAppKey` from `String.fromEnvironment('APTABASE_APP_KEY')`.
  - Empty: `NoopAnalytics`. No SDK start, no network.
  - Non-empty: `AptabaseAnalytics.init(key)`.
- `AppController` constructor wraps the injected backend: `_analytics = GatedAnalytics(analytics, enabled: loadAnalyticsEnabled(storage))`. Exposed through the `AppController.analytics` getter.
- `lib/main.dart` passes `app.analytics` to `BlendController` and `WhatIfController`. Controllers never receive the raw backend.

## User setting

- Storage: key `analyticsStorageKey` (`simplex-gas-remixer-analytics`), value `{"enabled":bool}`. Defined in `lib/src/data/analytics_storage.dart` as `loadAnalyticsEnabled` and `saveAnalyticsEnabled`.
- Default is on. A missing, unreadable, or malformed value loads as `true`.
- User-controlled. The switch "Send anonymous usage analytics" in `lib/src/ui/settings/sections/general.dart` calls `AppController.setAnalyticsEnabled(enabled:)`, which sets the gate's `enabled` and saves the choice.
- `AppController.factoryReset` calls `resetApplicationData(_storage)`, which clears all stored keys, then tracks `factory_reset` and sets the gate to `enabled = true` in memory. The event is tracked before re-enable, so a reset made while opted out sends no `factory_reset`.
- Tests: `test/controllers/analytics_gate_test.dart`.

## Closed event set (`lib/src/analytics/analytics_events.dart`)

Event names are private `_event…` constants. Each event has one public `track…` helper. Controllers call helpers; `Analytics.track` is called directly only inside `analytics.dart`. The `Analytics` interface accepts any string, so the closed set is enforced by this file, not by the type system.

| Event | Helper | Properties |
|---|---|---|
| `app_started` | `trackAppStarted` | none |
| `screen_view` | `trackScreenView` | `name` |
| `blend_calculated` | `trackBlendCalculated` | `mode`, `outcome` |
| `preset_imported` | `trackPresetImported` | `category`, `source`, `count` |
| `factory_reset` | `trackFactoryReset` | none |

Property values (Dart enum → sent string):

| Property | Enum → sent value |
|---|---|
| `name` | `AnalyticsScreen`: `blending`→`Blending`, `whatIf`→`What-if`, `inventory`→`Inventory`, `settings`→`Settings`, `about`→`About` |
| `mode` | `AnalyticsBlendMode`: `optimize`→`optimize`, `compare`→`compare`, `whatIf`→`what_if` |
| `outcome` | `AnalyticsOutcome`: `feasible`→`feasible`, `infeasible`→`infeasible`, `invalidInput`→`invalid_input` |
| `category` | `AnalyticsPresetCategory`: `gas`, `cylinder`, `equipment` |
| `source` | `AnalyticsPresetSource`: `file`, `url` |
| `count` | `int`, number of selected presets (`selected.length`) |

Call sites:

- `app_started`: `trackAppStarted` is reached only through `AppController.startup()`. No caller of `startup()` exists in `lib/` or `test/` on this branch, so the running app does not send this event.
- `screen_view`: `AppController.setPrimaryScreen`, only when the screen changes. Screen ids map via `AppController._analyticsScreen`.
- `blend_calculated`: `BlendController._trackCalculation`, mode `optimize`, outcomes `invalidInput`, `feasible`, `infeasible`. `WhatIfController._track`, mode `whatIf`, outcomes `feasible`, `invalidInput`, `infeasible`.
- `AnalyticsBlendMode.compare` is defined, but no code in `lib/` sends it.
- `preset_imported`: `AppController.applyPresetImport`, which takes `category` and `source` from `lib/src/ui/settings/sections/preset_import.dart` (`_importAnalyticsCategory`, `_importSource`).
- `factory_reset`: `AppController.factoryReset`, after a confirmed reset.

## Privacy rule

README, Conventions section, quoted verbatim:

> - **Analytics.** Only the events defined in `lib/src/analytics/analytics_events.dart` are sent. Their properties are closed string values and counts. Bank names, gas values, pressures, prices, and free text are never sent. Analytics failures are caught and never reach the calculator.

## Add or change an event

1. Add `const String _eventX = 'x';` in `analytics_events.dart`.
2. For each closed property, add an enum with a `wire` string, following `AnalyticsOutcome`. Counts are `int`. Do not send free text or values from the privacy rule above.
3. Add `void trackX(Analytics analytics, …)` with a doc comment. Build the props map and call `safeTrack`.
4. Call `trackX` from the controller with the injected `Analytics` it already holds. Do not call `track` directly.
5. Add tests in `test/analytics/analytics_test.dart`. Use its fake to assert the event name and exact props.
6. For controller call sites, assert through a recording fake, as `test/controllers/app_controller_test.dart` does.
7. Update the tables in this file.
8. Changing an existing wire value changes the data sent. Update the matching assertion in `analytics_test.dart`.

## Gotchas

- `GatedAnalytics.enabled` is set only through `AppController` (`setAnalyticsEnabled`, `factoryReset`).
- Opt-out is checked at send time, so an event tracked while opted out is lost, not deferred.

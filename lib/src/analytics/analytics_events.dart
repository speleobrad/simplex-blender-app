/// The complete set of analytics events and their properties.
///
/// Only these events are sent. Properties are limited to closed string values
/// and counts. Bank names, gas values, pressures, prices, and free text are
/// never sent.
library;

import 'analytics.dart';

const String _eventAppStarted = 'app_started';
const String _eventScreenView = 'screen_view';
const String _eventBlendCalculated = 'blend_calculated';
const String _eventPresetImported = 'preset_imported';
const String _eventFactoryReset = 'factory_reset';

/// Primary navigation destinations, as shown in the web app.
enum AnalyticsScreen {
  blending('Blending'),
  whatIf('What-if'),
  inventory('Inventory'),
  settings('Settings'),
  about('About');

  const AnalyticsScreen(this.wire);

  /// Value sent as the `name` property.
  final String wire;
}

/// Calculation mode for `blend_calculated`.
enum AnalyticsBlendMode {
  optimize('optimize'),
  compare('compare'),
  whatIf('what_if');

  const AnalyticsBlendMode(this.wire);

  /// Value sent as the `mode` property.
  final String wire;
}

/// Calculation outcome for `blend_calculated`.
enum AnalyticsOutcome {
  feasible('feasible'),
  infeasible('infeasible'),
  invalidInput('invalid_input');

  const AnalyticsOutcome(this.wire);

  /// Value sent as the `outcome` property.
  final String wire;
}

/// Preset category for `preset_imported`.
enum AnalyticsPresetCategory {
  gas('gas'),
  cylinder('cylinder'),
  equipment('equipment');

  const AnalyticsPresetCategory(this.wire);

  /// Value sent as the `category` property.
  final String wire;
}

/// Where an imported preset came from, for `preset_imported`.
enum AnalyticsPresetSource {
  file('file'),
  url('url');

  const AnalyticsPresetSource(this.wire);

  /// Value sent as the `source` property.
  final String wire;
}

/// Sent once per launch.
void trackAppStarted(Analytics analytics) {
  safeTrack(analytics, _eventAppStarted);
}

/// Sent when primary navigation changes to [screen].
void trackScreenView(Analytics analytics, AnalyticsScreen screen) {
  safeTrack(analytics, _eventScreenView, <String, Object>{'name': screen.wire});
}

/// Sent after a blend calculation finishes with [outcome].
void trackBlendCalculated(
  Analytics analytics, {
  required AnalyticsBlendMode mode,
  required AnalyticsOutcome outcome,
}) {
  safeTrack(analytics, _eventBlendCalculated, <String, Object>{
    'mode': mode.wire,
    'outcome': outcome.wire,
  });
}

/// Sent after a preset import is confirmed; [count] is the number of presets
/// written.
void trackPresetImported(
  Analytics analytics, {
  required AnalyticsPresetCategory category,
  required AnalyticsPresetSource source,
  required int count,
}) {
  safeTrack(analytics, _eventPresetImported, <String, Object>{
    'category': category.wire,
    'source': source.wire,
    'count': count,
  });
}

/// Sent when the user runs a factory reset.
void trackFactoryReset(Analytics analytics) {
  safeTrack(analytics, _eventFactoryReset);
}

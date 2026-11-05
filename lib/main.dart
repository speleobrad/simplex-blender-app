import 'package:flutter/widgets.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/controllers/what_if_controller.dart';
import 'package:simplex_blender/src/data/preferences_storage.dart';
import 'package:simplex_blender/src/domain/blend_defaults.dart';
import 'package:simplex_blender/src/ui/shell/app_shell.dart';

/// Aptabase App Key, supplied at build time with `--dart-define`. Empty means
/// analytics stays off: no SDK start and no network.
const String _aptabaseAppKey = String.fromEnvironment('APTABASE_APP_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await PreferencesKeyValueStorage.open(
    // Storage writes are asynchronous; the in-memory value stays current for
    // this session. Surface the failure in the debug log.
    onWriteError: (error) => debugPrint('Preferences write failed: $error'),
  );
  final Analytics analytics = _aptabaseAppKey.isEmpty
      ? const NoopAnalytics()
      : await AptabaseAnalytics.init(_aptabaseAppKey);

  final app = AppController(storage: storage, analytics: analytics);
  final blend = BlendController(
    inputs: BlendInputs.fromDefaults(
      defaultBlendInputs(cylinderPresets: app.settings.cylinderPresets),
    ),
    banks: app.banks,
    settings: app.settings,
    updateBank: app.updateBank,
    analytics: app.analytics,
  );
  final whatIf = WhatIfController(
    analytics: app.analytics,
    banks: app.banks,
    settings: app.settings,
  );

  runApp(SimplexBlenderApp(app: app, blend: blend, whatIf: whatIf));
}

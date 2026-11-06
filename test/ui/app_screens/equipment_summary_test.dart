import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/ui/inventory/equipment_summary.dart';

import '../../support/memory_storage.dart';

class _NoopAnalytics implements Analytics {
  @override
  void track(
    String event, [
    Map<String, Object> props = const <String, Object>{},
  ]) {}
}

const _bauer = CompressorPreset(
  name: 'Bauer Junior',
  inletFlowLPerMin: 100,
  maxPressureBar: 232,
  temperatureModifierC: 5,
);

const _maximator = BoosterPreset(
  name: 'Maximator ROB 22',
  minimumSourcePressureBar: 50,
  cylinderVolumeCm3: 4.6,
  oxygenBoostBpm: 30,
  otherBoostBpm: 50,
  oxygenDecantRateBarPerMin: 5,
  otherDecantRateBarPerMin: 10,
  maxOutputPressureBar: 280,
  temperatureModifierC: 0,
  drainingRateBarPerMin: 15,
);

const _matchingBooster = SettingsBooster(
  minimumSourcePressureBar: 50,
  cylinderVolumeCm3: 4.6,
  oxygenBoostBpm: 30,
  otherBoostBpm: 50,
  oxygenDecantRateBarPerMin: 5,
  otherDecantRateBarPerMin: 10,
  drainingRateBarPerMin: 15,
  compressorInletFlowLPerMin: 100,
  maxCompressorPressureBar: 232,
  maxBoosterOutputPressureBar: 280,
  boosterTemperatureModifierC: 0,
  compressorTemperatureModifierC: 5,
);

/// Storage whose writes fail on demand, to simulate a full or disabled store.
class _WriteSwitchStorage extends MemoryStorage {
  bool failWrites = false;

  @override
  void setItem(String key, String value) {
    if (failWrites) {
      throw StateError('storage is full');
    }
    super.setItem(key, value);
  }
}

Settings _settings({SettingsBooster booster = _matchingBooster}) =>
    DEFAULT_SETTINGS.copyWith(
      compressorPresets: const [_bauer],
      boosterPresets: const [_maximator],
      booster: booster,
    );

AppController _app(Settings settings) {
  final app = AppController(
    storage: MemoryStorage(),
    analytics: _NoopAnalytics(),
  );
  final errors = app.applySettings(settings);
  expect(errors, isEmpty, reason: 'fixture settings must be valid');
  return app;
}

Future<void> _pump(
  WidgetTester tester,
  AppController app, {
  VoidCallback? onEquipmentChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EquipmentSummary(
            app: app,
            onEquipmentChanged: onEquipmentChanged,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'renders named compressor and booster parameters in the compact summary',
    (tester) async {
      await _pump(tester, _app(_settings()));

      expect(find.textContaining('Bauer Junior'), findsWidgets);
      expect(find.textContaining('100 L/min'), findsOneWidget);
      expect(find.textContaining('232 bar'), findsOneWidget);
      expect(find.textContaining('Maximator ROB 22'), findsWidgets);
      expect(find.textContaining('boost 30/50 BPM'), findsOneWidget);
      expect(find.textContaining('decant 5/10 bar/min'), findsOneWidget);
      expect(find.textContaining('280 bar'), findsOneWidget);
    },
  );

  testWidgets('imperial units convert the equipment and decant values', (
    tester,
  ) async {
    final app = _app(
      DEFAULT_SETTINGS.copyWith(
        units: 'imperial',
        compressorPresets: const [_bauer],
        boosterPresets: const [_maximator],
        booster: _matchingBooster,
      ),
    );
    await _pump(tester, app);

    expect(find.textContaining('3.5 cu ft/min'), findsOneWidget);
    expect(find.textContaining('3364.9 psi'), findsOneWidget);
    expect(find.textContaining('decant 72.5/145.0 psi/min'), findsOneWidget);
    expect(find.textContaining('4061.1 psi'), findsOneWidget);
  });

  testWidgets(
    'labels equipment as custom when active fields do not match named presets',
    (tester) async {
      await _pump(
        tester,
        _app(
          _settings(
            booster: _matchingBooster.copyWith(compressorInletFlowLPerMin: 125),
          ),
        ),
      );

      expect(find.textContaining('Custom compressor'), findsWidgets);
      expect(find.textContaining('125 L/min'), findsOneWidget);
      expect(find.textContaining('Maximator ROB 22'), findsWidgets);
    },
  );

  testWidgets('adds a note directing users to Settings for equipment changes', (
    tester,
  ) async {
    await _pump(tester, _app(_settings()));

    expect(
      find.textContaining(
        'equipment lists and properties can also be changed in Settings',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'selecting a named compressor preset applies it and notifies once',
    (tester) async {
      final app = _app(
        _settings(
          booster: _matchingBooster.copyWith(compressorInletFlowLPerMin: 125),
        ),
      );
      var notified = 0;
      await _pump(tester, app, onEquipmentChanged: () => notified++);

      expect(app.settings.booster.compressorInletFlowLPerMin, 125);
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bauer Junior').last);
      await tester.pumpAndSettle();

      expect(app.settings.booster.compressorInletFlowLPerMin, 100);
      expect(app.settings.booster.maxCompressorPressureBar, 232);
      expect(notified, 1);
    },
  );

  testWidgets(
    'a selection that fails to save shows the error and does not notify',
    (tester) async {
      final storage = _WriteSwitchStorage();
      final app = AppController(storage: storage, analytics: _NoopAnalytics());
      expect(
        app.applySettings(
          _settings(
            booster: _matchingBooster.copyWith(compressorInletFlowLPerMin: 125),
          ),
        ),
        isEmpty,
      );
      storage.failWrites = true;
      var notified = 0;
      await _pump(tester, app, onEquipmentChanged: () => notified++);

      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bauer Junior').last);
      await tester.pumpAndSettle();

      expect(app.settings.booster.compressorInletFlowLPerMin, 125);
      expect(notified, 0);
      expect(find.text(settingsSaveFailureMessage), findsOneWidget);
    },
  );

  testWidgets(
    'a later selection that saves clears the error and notifies once',
    (tester) async {
      final storage = _WriteSwitchStorage();
      final app = AppController(storage: storage, analytics: _NoopAnalytics());
      expect(
        app.applySettings(
          _settings(
            booster: _matchingBooster.copyWith(compressorInletFlowLPerMin: 125),
          ),
        ),
        isEmpty,
      );
      storage.failWrites = true;
      var notified = 0;
      await _pump(tester, app, onEquipmentChanged: () => notified++);

      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bauer Junior').last);
      await tester.pumpAndSettle();
      expect(find.text(settingsSaveFailureMessage), findsOneWidget);

      storage.failWrites = false;
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bauer Junior').last);
      await tester.pumpAndSettle();

      expect(find.text(settingsSaveFailureMessage), findsNothing);
      expect(notified, 1);
    },
  );
}

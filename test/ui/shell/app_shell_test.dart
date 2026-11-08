import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/controllers/what_if_controller.dart';
import 'package:simplex_blender/src/data/key_value_storage.dart';
import 'package:simplex_blender/src/data/settings_storage.dart';
import 'package:simplex_blender/src/domain/blend_defaults.dart';
import 'package:simplex_blender/src/domain/interim_check.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/ui/settings/settings_screen.dart';
import 'package:simplex_blender/src/ui/shell/app_shell.dart';

import '../../support/legacy_cylinder_settings.dart';
import '../../support/memory_storage.dart';

class _FailingWrites extends MemoryStorage {
  @override
  void setItem(String key, String value) => throw StateError('quota');
}

class _UnreadableStorage extends MemoryStorage {
  @override
  String? getItem(String key) => throw StateError('storage unavailable');
}

typedef _Wired = ({
  AppController app,
  BlendController blend,
  WhatIfController whatIf,
});

_Wired _wire(KeyValueStorage storage) {
  final app = AppController(storage: storage, analytics: const NoopAnalytics());
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
  return (app: app, blend: blend, whatIf: whatIf);
}

Future<void> _pumpShell(WidgetTester tester, _Wired wired) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    SimplexBlenderApp(app: wired.app, blend: wired.blend, whatIf: wired.whatIf),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// A reading the plan accepts: the planned start state of the measured step.
InterimReading _plannedReading(BlendController controller, int index) {
  final steps = controller.lastResult!['protocolSteps']! as List<ProtocolStep>;
  final step = steps.firstWhere((step) => step.measurementIndex == index);
  final thermal = step.thermal!;
  return (
    pressureBar: thermal.pressureStartBar,
    temperatureC: thermal.temperatureStartC,
  );
}

Future<void> _openRailDestination(WidgetTester tester, String label) async {
  final rail = find.byType(NavigationRail);
  await tester.tap(find.descendant(of: rail, matching: find.text(label)));
  await tester.pump(const Duration(milliseconds: 300));
}

const String _themeNotSaved =
    'Theme changed for this session only; preference could not be saved.';

void main() {
  testWidgets(
    'first launch shows the tour; Skip persists and a relaunch hides it',
    (tester) async {
      final storage = MemoryStorage();

      await _pumpShell(tester, _wire(storage));
      expect(find.text('Skip'), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Skip'), findsNothing);

      // A new app instance over the same storage is a relaunch.
      await _pumpShell(tester, _wire(storage));
      expect(find.text('Skip'), findsNothing);
    },
  );

  testWidgets('the default inventory shows the recipe steps on Blending', (
    tester,
  ) async {
    final wired = _wire(MemoryStorage());
    await _pumpShell(tester, wired);
    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(milliseconds: 300));

    final steps =
        wired.blend.lastResult!['protocolSteps']! as List<ProtocolStep>;
    expect(steps, isNotEmpty);
    expect(find.text('Mixing steps'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('step-0')), findsOneWidget);
  });

  testWidgets('a failed theme save shows the session-only message', (
    tester,
  ) async {
    final wired = _wire(_FailingWrites());
    await _pumpShell(tester, wired);
    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Dark'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(_themeNotSaved), findsOneWidget);
  });

  testWidgets('a successful theme save shows no failure message', (
    tester,
  ) async {
    final wired = _wire(MemoryStorage());
    await _pumpShell(tester, wired);
    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Dark'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(wired.app.themePreference, 'dark');
    expect(find.text(_themeNotSaved), findsNothing);
  });

  testWidgets('unreadable storage shows the storage warning banner', (
    tester,
  ) async {
    final wired = _wire(_UnreadableStorage());
    expect(wired.app.storageWarning, isNotEmpty);

    await _pumpShell(tester, wired);

    expect(find.textContaining(wired.app.storageWarning.first), findsOneWidget);
  });

  testWidgets(
    'factory reset from Settings clears the What-if run and Blend readings',
    (tester) async {
      final wired = _wire(MemoryStorage());
      await _pumpShell(tester, wired);
      await tester.tap(find.text('Skip'));
      await tester.pump(const Duration(milliseconds: 300));

      // Entering What-if runs the scenario; that is the state reset must clear.
      await _openRailDestination(tester, 'What-if');
      expect(wired.whatIf.hasRun, isTrue);

      expect(
        wired.blend.applyInterimMeasurement(0, _plannedReading(wired.blend, 0)),
        isNull,
      );
      expect(
        wired.blend.interimMeasurements.whereType<InterimMeasurement>(),
        isNotEmpty,
      );

      await _openRailDestination(tester, 'Settings');
      final settings = find.byType(SettingsScreen);
      await tester.tap(
        find.descendant(of: settings, matching: find.text('Preset management')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final resetButton = find.descendant(
        of: settings,
        matching: find.text('Reset to factory settings'),
      );
      await tester.dragUntilVisible(
        resetButton,
        find.descendant(of: settings, matching: find.byType(ListView)),
        const Offset(0, -200),
      );
      await tester.tap(resetButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      expect(wired.whatIf.hasRun, isFalse);
      expect(
        wired.blend.interimMeasurements.whereType<InterimMeasurement>(),
        isEmpty,
      );
      expect(wired.blend.interimMeasurementSignature, isNull);
    },
  );

  testWidgets('migration notice is shown and can be dismissed', (tester) async {
    final wired = _wire(
      MemoryStorage(<String, String>{
        SETTINGS_STORAGE_KEY: legacyCylinderSettingsJson(),
      }),
    );
    await _pumpShell(tester, wired);
    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('nearest standard cylinder'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('cylinder-migration-dismiss')),
    );
    await tester.pump();
    expect(find.textContaining('nearest standard cylinder'), findsNothing);
  });
}

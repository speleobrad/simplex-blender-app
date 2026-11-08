import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/controllers/what_if_controller.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/what_if_scenario.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_screen.dart';

import '../../support/memory_storage.dart';

const WhatIfStart _start = WhatIfStart(
  pressureBar: 200,
  oxygenPercent: 21,
  heliumPercent: 0,
  ambientTemperatureC: 25,
  coolingMedium: 'air',
  inWaterTemperatureC: 20,
  cylinderPresetName: 'Catalina S80',
);

class _Harness {
  _Harness._({
    required this.app,
    required this.blend,
    required this.controller,
  });

  final AppController app;
  final BlendController blend;
  final WhatIfController controller;

  static Future<_Harness> create() async {
    const analytics = NoopAnalytics();
    final app = AppController(storage: MemoryStorage(), analytics: analytics);
    app.applySettings(DEFAULT_SETTINGS.copyWith(units: 'imperial'));
    final preset = app.settings.cylinderPresets.firstWhere(
      (candidate) => candidate.name == 'Catalina S80',
    );
    final blend = BlendController(
      inputs: BlendInputs(
        cylinderPreset: preset,
        initialPressureBar: 50,
        initialOxygenPercent: 21,
        initialHeliumPercent: 0,
        targetPressureBar: 200,
        targetOxygenPercent: 21,
        targetHeliumPercent: 0,
        ambientTemperatureC: 25,
        targetInWaterTemperatureC: 20,
        waitTargetTemperatureC: 25,
        inletTemperatureC: 25,
        coolingMedium: 'air',
        waterSubmersionPercent: 60,
        waitMode: 'minutes',
        waitMinutes: 0,
      ),
      banks: app.banks,
      settings: app.settings,
      updateBank: (_) {},
      analytics: analytics,
    );
    final controller = WhatIfController(
      analytics: analytics,
      banks: app.banks,
      settings: app.settings,
    );
    controller.initializeScenario(
      initialPressureBar: _start.pressureBar,
      initialOxygenPercent: _start.oxygenPercent,
      initialHeliumPercent: _start.heliumPercent,
      cylinderPresetName: _start.cylinderPresetName,
      ambientTemperatureC: _start.ambientTemperatureC,
      coolingMedium: _start.coolingMedium,
      waterSubmersionPercent: 60,
      targetInWaterTemperatureC: _start.inWaterTemperatureC,
    );
    return _Harness._(app: app, blend: blend, controller: controller);
  }
}

Future<void> _pumpScreen(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WhatIfScreen(
          controller: harness.controller,
          blend: harness.blend,
          app: harness.app,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders What-if controls without a manual run button', (
    tester,
  ) async {
    final harness = await _Harness.create();
    await _pumpScreen(tester, harness);

    for (final field in <String>[
      'pressureBar',
      'oxygenPercent',
      'heliumPercent',
      'cylinderPresetName',
      'ambientTemperatureC',
      'coolingMedium',
      'inWaterTemperatureC',
    ]) {
      expect(find.byKey(Key('what-if-field-$field')), findsOneWidget);
    }
    expect(find.textContaining('psi'), findsWidgets);
    expect(find.text('Copy from Blending'), findsOneWidget);
    expect(find.text('Run scenario'), findsNothing);
  });

  testWidgets('an incomplete cylinder is labelled in the what-if selector', (
    tester,
  ) async {
    const analytics = NoopAnalytics();
    final app = AppController(storage: MemoryStorage(), analytics: analytics);
    final legacy = CylinderPreset(
      name: 'Legacy 5L',
      volumeL: 5,
      material: 'aluminum',
      massKg: 4,
      workingPressureBar: 207,
      hotOverfillPercent: 0,
    );
    app.applySettings(
      copySettings(DEFAULT_SETTINGS).copyWith(
        units: 'imperial',
        cylinderPresets: <CylinderPreset>[
          ...DEFAULT_SETTINGS.cylinderPresets,
          legacy,
        ],
      ),
    );
    final blend = BlendController(
      inputs: BlendInputs(
        cylinderPreset: legacy,
        initialPressureBar: 50,
        initialOxygenPercent: 21,
        initialHeliumPercent: 0,
        targetPressureBar: 200,
        targetOxygenPercent: 21,
        targetHeliumPercent: 0,
        ambientTemperatureC: 25,
        targetInWaterTemperatureC: 20,
        waitTargetTemperatureC: 25,
        inletTemperatureC: 25,
        coolingMedium: 'air',
        waterSubmersionPercent: 60,
        waitMode: 'minutes',
        waitMinutes: 0,
      ),
      banks: app.banks,
      settings: app.settings,
      updateBank: (_) {},
      analytics: analytics,
    );
    final controller = WhatIfController(
      analytics: analytics,
      banks: app.banks,
      settings: app.settings,
    );
    controller.initializeScenario(
      initialPressureBar: 200,
      initialOxygenPercent: 21,
      initialHeliumPercent: 0,
      cylinderPresetName: 'Legacy 5L',
      ambientTemperatureC: 25,
      coolingMedium: 'air',
      waterSubmersionPercent: 60,
      targetInWaterTemperatureC: 20,
    );
    await _pumpScreen(
      tester,
      _Harness._(app: app, blend: blend, controller: controller),
    );

    expect(find.textContaining('Legacy 5L (needs dimensions)'), findsWidgets);
    expect(find.byKey(const Key('what-if-cylinder-hint')), findsOneWidget);
    expect(find.textContaining('· needs diameter and length'), findsOneWidget);
  });

  testWidgets('shows the empty state before any run', (tester) async {
    final harness = await _Harness.create();
    await _pumpScreen(tester, harness);

    expect(find.byKey(const Key('what-if-empty-state')), findsOneWidget);
    expect(find.text('Add step'), findsOneWidget);
  });

  testWidgets('copying from Blending reports the copied starting state', (
    tester,
  ) async {
    final harness = await _Harness.create();
    await _pumpScreen(tester, harness);

    await tester.tap(find.text('Copy from Blending'));
    await tester.pump();

    expect(
      find.text('Starting state copied from Blending; edits are independent.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed run shows its errors', (tester) async {
    final harness = await _Harness.create();
    await _pumpScreen(tester, harness);
    harness.controller.applyStartPatch(
      const WhatIfStart(cylinderPresetName: 'Missing'),
    );
    await tester.pump();

    expect(harness.controller.errors, isNotEmpty);
    for (final error in harness.controller.errors) {
      expect(find.text(error), findsOneWidget);
    }
  });

  testWidgets('places a field-keyed error under its control', (tester) async {
    final harness = await _Harness.create();
    await _pumpScreen(tester, harness);

    harness.controller.applyStartPatch(
      const WhatIfStart(cylinderPresetName: 'Missing'),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('what-if-cylinderPresetName-error')),
      findsOneWidget,
    );
  });

  testWidgets('places a row-scoped error only on its own row', (tester) async {
    final harness = await _Harness.create();
    await _pumpScreen(tester, harness);
    harness.controller.addDrainRow();
    await tester.pump();
    final rows = harness.controller.scenario.rows;
    final firstId = rows.first.id;
    final lastId = rows.last.id;
    expect(firstId, isNot(lastId));

    harness.controller.setRowTargetPressureBar(firstId, 250);
    await tester.pump();

    expect(
      find.byKey(Key('compare-$firstId-targetPressureBar-error')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('compare-$lastId-targetPressureBar-error')),
      findsNothing,
    );
    final invalid = tester
        .widgetList<TextField>(find.byType(TextField))
        .where((field) => field.decoration?.errorText != null)
        .toList();
    expect(invalid, hasLength(1));
    expect(
      invalid.single.decoration!.errorText,
      'Add target pressure cannot exceed the cylinder working pressure of 207 bar.',
    );
  });

  testWidgets('a failed rerun keeps the last result and marks it stale', (
    tester,
  ) async {
    final harness = await _Harness.create();
    await _pumpScreen(tester, harness);
    harness.controller.setRowTargetPressureBar(
      harness.controller.scenario.rows.first.id,
      180,
    );

    harness.controller.applyStartPatch(const WhatIfStart(pressureBar: 150));
    await tester.pump();
    expect(harness.controller.lastRun, isNotNull);

    harness.controller.applyStartPatch(
      const WhatIfStart(cylinderPresetName: 'Missing'),
    );
    await tester.pump();

    expect(harness.controller.lastRun, isNotNull);
    expect(
      find.text('Scenario result is out of date. Update the scenario inputs.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('what-if-stale-status')), findsOneWidget);
  });

  testWidgets('a successful run shows the scenario summary and recipe', (
    tester,
  ) async {
    final harness = await _Harness.create();
    await _pumpScreen(tester, harness);
    harness.controller.setRowTargetPressureBar(
      harness.controller.scenario.rows.first.id,
      180,
    );

    harness.controller.applyStartPatch(const WhatIfStart(pressureBar: 150));
    await tester.pump();

    expect(find.text('Scenario summary'), findsOneWidget);
    expect(find.text('Recipe'), findsOneWidget);
    expect(find.byKey(const Key('what-if-scenario-start')), findsOneWidget);
  });
}

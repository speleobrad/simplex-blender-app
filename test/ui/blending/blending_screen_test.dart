import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/ui/blending/blending_screen.dart';
import 'package:simplex_blender/src/ui/shell/tour_targets.dart';

import '../../support/memory_storage.dart';

// Source of truth: index.html. The tour anchors are the element ids that the
// onboarding steps point at (index.html 353, 379, 415, 492, 601). Transfer
// conditions follow the Blending markup (index.html 829-835). Compare is not
// part of this port, so no Compare text may appear.

CylinderPreset _catalinaS80() => DEFAULT_SETTINGS.cylinderPresets.firstWhere(
  (preset) => preset.name == 'Catalina S80',
);

BlendInputs _inputs() => BlendInputs(
  cylinderPreset: _catalinaS80(),
  initialPressureBar: 50,
  initialOxygenPercent: 21,
  initialHeliumPercent: 0,
  targetPressureBar: 195,
  targetOxygenPercent: 18,
  targetHeliumPercent: 45,
  ambientTemperatureC: 21,
  targetInWaterTemperatureC: 10,
  waitTargetTemperatureC: 25,
  inletTemperatureC: 21,
  coolingMedium: 'air',
  waterSubmersionPercent: 60,
  waitMode: 'minutes',
  waitMinutes: 5,
);

Future<({AppController app, BlendController blend, TourTargets targets})> _pump(
  WidgetTester tester,
) async {
  const analytics = NoopAnalytics();
  final app = AppController(storage: MemoryStorage(), analytics: analytics);
  final blend = BlendController(
    inputs: _inputs(),
    banks: app.banks,
    settings: app.settings,
    updateBank: (_) {},
    analytics: analytics,
  );
  final targets = TourTargets();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TourTargetsScope(
          targets: targets,
          child: BlendingScreen(controller: blend, app: app),
        ),
      ),
    ),
  );
  await tester.pump();
  return (app: app, blend: blend, targets: targets);
}

void main() {
  testWidgets('shows the form anchors, transfer conditions, and result tabs', (
    tester,
  ) async {
    final harness = await _pump(tester);
    final targets = harness.targets;

    expect(find.byKey(targets.keyFor('working-tank-section')), findsOneWidget);
    expect(find.byKey(targets.keyFor('ambient-temperature')), findsOneWidget);
    expect(find.byKey(targets.keyFor('dive-site-temperature')), findsOneWidget);
    expect(find.text('Transfer conditions'), findsOneWidget);
    expect(find.text('Same as ambient'), findsOneWidget);
    expect(harness.blend.lastResult, isNotNull);
    expect(find.byKey(targets.keyFor('results-tablist')), findsOneWidget);
    for (final label in <String>[
      'Recipe',
      'Thermal Graph',
      'In-water pressure',
      'Tanks and costs',
      'Simplex diagram',
    ]) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('has no Compare control and no in-water projection', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.textContaining('Compare'), findsNothing);
    expect(find.text('Scenario in-water projection'), findsNothing);
  });
}

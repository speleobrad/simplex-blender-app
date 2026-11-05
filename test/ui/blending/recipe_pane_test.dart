import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/ui/blending/recipe_pane.dart';
import 'package:simplex_blender/src/ui/shell/tour_targets.dart';

import '../../support/memory_storage.dart';

CylinderPreset _catalinaS80() => DEFAULT_SETTINGS.cylinderPresets.firstWhere(
  (preset) => preset.name == 'Catalina S80',
);

BlendInputs _inputs({required double targetPressureBar}) => BlendInputs(
  cylinderPreset: _catalinaS80(),
  initialPressureBar: 50,
  initialOxygenPercent: 21,
  initialHeliumPercent: 0,
  targetPressureBar: targetPressureBar,
  targetOxygenPercent: 18,
  targetHeliumPercent: 45,
  ambientTemperatureC: 21,
  targetInWaterTemperatureC: 10,
  waitTargetTemperatureC: 25,
  inletTemperatureC: 21,
  coolingMedium: 'water',
  waterSubmersionPercent: 40,
  waitMode: 'minutes',
  waitMinutes: 5,
);

({AppController app, BlendController blend}) _harness({
  required double targetPressureBar,
}) {
  const analytics = NoopAnalytics();
  final app = AppController(storage: MemoryStorage(), analytics: analytics);
  final blend = BlendController(
    inputs: _inputs(targetPressureBar: targetPressureBar),
    banks: app.banks,
    settings: app.settings,
    updateBank: (_) {},
    analytics: analytics,
  );
  return (app: app, blend: blend);
}

Future<void> _pump(WidgetTester tester, {required Widget child}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TourTargetsScope(
          targets: TourTargets(),
          child: SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('feasible blend shows retained, vented, and achieved mix cards', (
    tester,
  ) async {
    final h = _harness(targetPressureBar: 195);
    h.blend.recalculate();
    final result = h.blend.lastResult!;
    expect(result['feasible'], isTrue);
    final blend = result['blend']! as Map<String, Object?>;

    await _pump(
      tester,
      child: RecipePane(controller: h.blend, app: h.app),
    );

    expect(find.text('Retained gas'), findsOneWidget);
    expect(find.text('Helium vented'), findsOneWidget);
    expect(find.text('Achieved mix'), findsOneWidget);
    final oxygen = (blend['finalOxygenPercent']! as double).toStringAsFixed(1);
    final helium = (blend['finalHeliumPercent']! as double).toStringAsFixed(1);
    expect(find.text('$oxygen/$helium'), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('infeasible target shows an infeasible heading and no NaN', (
    tester,
  ) async {
    final h = _harness(targetPressureBar: 400);
    h.blend.recalculate();
    expect(h.blend.lastResult!['feasible'], isFalse);

    await _pump(
      tester,
      child: Column(
        children: <Widget>[
          BlendStatusBox(controller: h.blend, app: h.app),
          RecipePane(controller: h.blend, app: h.app),
        ],
      ),
    );

    final headingFound =
        find.text('Requested Mix Is Unavailable').evaluate().isNotEmpty ||
        find.text('No Feasible Blend').evaluate().isNotEmpty;
    expect(headingFound, isTrue);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('status box shows the feasible message for a feasible blend', (
    tester,
  ) async {
    final h = _harness(targetPressureBar: 195);
    h.blend.recalculate();

    await _pump(
      tester,
      child: BlendStatusBox(controller: h.blend, app: h.app),
    );

    expect(
      find.text(
        'Feasible blend · target pressure is achievable with the current supply.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('panes render the recipe once the controller has a result', (
    tester,
  ) async {
    // BlendController recalculates in its constructor, so a result exists
    // before the first pump; the screen never shows an empty recipe here.
    final h = _harness(targetPressureBar: 195);
    expect(h.blend.lastResult, isNotNull);

    await _pump(
      tester,
      child: Column(
        children: <Widget>[
          BlendStatusBox(controller: h.blend, app: h.app),
          RecipePane(controller: h.blend, app: h.app),
        ],
      ),
    );

    expect(find.text('Retained gas'), findsOneWidget);
  });
}

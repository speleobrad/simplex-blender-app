import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/ui/blending/ternary_data.dart';
import 'package:simplex_blender/src/ui/blending/ternary_pane.dart';
import 'package:simplex_blender/src/ui/results/ternary_diagram.dart';

import '../../support/memory_storage.dart';

// Source of truth: js/main.js 1397-1406 (renderTernary draws only when data
// exists) and js/ui/ternary.js 492-511 (diagram drawn for a feasible result).

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

void main() {
  testWidgets('draws the simplex diagram for a run with valid data', (
    tester,
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
    final inputs = blendingTernaryInputsOf(blend, app);
    expect(inputs, isNotNull);
    expect(inputs!.valid, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TernaryPane(controller: blend, app: app),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TernaryDiagram), findsOneWidget);
    expect(find.text(invalidTernaryDataText), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/ui/blending/thermal_pane.dart';

import '../../support/memory_storage.dart';

// Source of truth: js/ui/results.js 1089-1110 (feasible thermal summary) and
// js/ui/thermal-charts.js 757-841 (`renderThermalCharts`).

BlendInputs _inputs() => BlendInputs(
  cylinderPreset: DEFAULT_SETTINGS.cylinderPresets.firstWhere(
    (preset) => preset.name == 'Catalina S80',
  ),
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
  coolingMedium: 'water',
  waterSubmersionPercent: 40,
  waitMode: 'minutes',
  waitMinutes: 5,
);

({AppController app, BlendController blend}) _harness() {
  const analytics = NoopAnalytics();
  final app = AppController(storage: MemoryStorage(), analytics: analytics);
  final blend = BlendController(
    inputs: _inputs(),
    banks: app.banks,
    settings: app.settings,
    updateBank: (_) {},
    analytics: analytics,
  );
  return (app: app, blend: blend);
}

Future<void> _pump(
  WidgetTester tester,
  AppController app,
  BlendController blend,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ThermalPane(controller: blend, app: app),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders nothing without a result', (tester) async {
    final harness = _harness();
    harness.blend.lastResult = null;
    harness.blend.lastInput = null;
    await _pump(tester, harness.app, harness.blend);

    expect(find.text('Blending thermal history'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the thermal history once a result exists', (
    tester,
  ) async {
    final harness = _harness();
    harness.blend.lastInput = <String, Object?>{
      'cylinder': <String, Object?>{'initialPressureBar': 50.0},
      'physics': <String, Object?>{'temperatureC': 21.0},
      'thermal': <String, Object?>{'ambientTemperatureC': 21.0},
    };
    harness.blend.lastResult = <String, Object?>{
      'feasible': true,
      'protocolSteps': <Object?>[],
      'thermal': <String, Object?>{
        'finalAmbientPressureBar': 200.0,
        'finalAmbientTemperatureC': 21.0,
        'finalAmbientCoolOffMinutes': 0.0,
      },
    };
    await _pump(tester, harness.app, harness.blend);
    expect(find.text('Blending thermal history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

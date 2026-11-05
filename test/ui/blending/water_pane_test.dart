import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/ui/blending/water_pane.dart';

import '../../support/memory_storage.dart';

// Source of truth: js/ui/results.js 994-1048 (infeasible: thermal falls back to
// maximumPressure, blend from maximumPressure) and 1089-1110 (feasible).

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
          child: WaterPane(controller: blend, app: app),
        ),
      ),
    ),
  );
}

Map<String, Object?> _input() => <String, Object?>{
  'cylinder': <String, Object?>{'volumeL': 12.0, 'workingPressureBar': 300.0},
  'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 21.0},
};

void main() {
  testWidgets('renders nothing without a result', (tester) async {
    final harness = _harness();
    harness.blend.lastResult = null;
    harness.blend.lastInput = null;
    await _pump(tester, harness.app, harness.blend);

    expect(find.text('In water pressure'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('feasible result renders the in-water pressure tables', (
    tester,
  ) async {
    final harness = _harness();
    harness.blend.lastInput = _input();
    harness.blend.lastResult = <String, Object?>{
      'feasible': true,
      'thermal': <String, Object?>{
        'finalAmbientPressureBar': 200.0,
        'finalAmbientTemperatureC': 21.0,
      },
      'blend': <String, Object?>{
        'finalOxygenPercent': 18.0,
        'finalHeliumPercent': 45.0,
      },
    };
    await _pump(tester, harness.app, harness.blend);

    expect(find.text('In water pressure'), findsOneWidget);
    expect(find.text('Water temperatures'), findsOneWidget);
    expect(find.text('Car temperatures'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('infeasible result falls back to the maximum-pressure data', (
    tester,
  ) async {
    final harness = _harness();
    harness.blend.lastInput = _input();
    harness.blend.lastResult = <String, Object?>{
      'feasible': false,
      'maximumPressure': <String, Object?>{
        'thermal': <String, Object?>{
          'finalAmbientPressureBar': 200.0,
          'finalAmbientTemperatureC': 21.0,
        },
        'blend': <String, Object?>{
          'finalOxygenPercent': 18.0,
          'finalHeliumPercent': 45.0,
        },
      },
    };
    await _pump(tester, harness.app, harness.blend);

    expect(find.text('Water temperatures'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

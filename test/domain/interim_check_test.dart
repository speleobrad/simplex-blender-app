import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/interim_check.dart';
import 'package:simplex_blender/src/domain/optimizer.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

import '../support/tank_area.dart';

Map<String, Object?> bank(
  String id,
  String name,
  int oxygenPercent,
  int heliumPercent,
) => {
  'id': id,
  'name': name,
  'enabled': true,
  'volumeL': 50,
  'pressureBar': 300,
  'maxPressureBar': 350,
  'oxygenPercent': oxygenPercent,
  'heliumPercent': heliumPercent,
};

// Default-like recipe: 50 bar Air at 21 °C to 195 bar 18/45, settled at 10 °C in water.
final defaultCylinder = <String, Object?>{
  'volumeL': 12,
  'initialPressureBar': 50,
  'targetPressureBar': 195,
  'initialOxygenPercent': 21,
  'initialHeliumPercent': 0,
  'targetOxygenPercent': 18,
  'targetHeliumPercent': 45,
  'workingPressureBar': 232,
  'hotOverfillPercent': 2,
};

final defaultScenario = <String, Object?>{
  'cylinder': defaultCylinder,
  'physics': {'model': 'vdw', 'temperatureC': 21},
  'banks': [bank('oxygen', 'Oxygen', 100, 0), bank('helium', 'Helium', 0, 100)],
  'thermal': {
    'tankMaterial': 'steel',
    'tankSurfaceAreaM2': steelTestAreaM2,
    'coolingMedium': 'air',
    'ambientTemperatureC': 21,
    'inletTemperatureC': 25,
    'targetMediumTemperatureC': 21,
    'targetInWaterTemperatureC': 10,
    'waitMode': 'minutes',
    'waitMinutes': 5,
    'interimMeasurements': <Object?>[],
  },
  'settings': {
    'booster': <String, Object?>{},
    'units': 'metric',
    'pressureLimitMode': 'hard-stop',
  },
};

// Drain scenario: 150 bar cylinder drained to 100 bar; gas cools below ambient after the drain.
final drainScenario = <String, Object?>{
  ...defaultScenario,
  'cylinder': {
    ...defaultCylinder,
    'initialPressureBar': 150,
    'targetPressureBar': 100,
  },
  'thermal': {
    ...(defaultScenario['thermal']! as Map<String, Object?>),
    'targetInWaterTemperatureC': 21,
  },
};

const tolerancePercent = 3.0;

// Salvage scenario: the drained 150 bar cylinder moves its surplus into Leftover N, then the
// recipe decants Pure Oxygen. The salvage cools the working tank below ambient.
final salvageScenario = <String, Object?>{
  'cylinder': {
    'volumeL': 12,
    'initialPressureBar': 150,
    'targetPressureBar': 100,
    'initialOxygenPercent': 32,
    'initialHeliumPercent': 0,
    'targetOxygenPercent': 21,
    'targetHeliumPercent': 35,
  },
  'physics': {'model': 'vdw', 'temperatureC': 20},
  'banks': [
    {
      'id': 'bank-he',
      'name': 'Pure Helium',
      'volumeL': 50,
      'pressureBar': 200,
      'maxPressureBar': 350,
      'minimumPressureBar': 15,
      'oxygenPercent': 0,
      'heliumPercent': 100,
      'enabled': true,
    },
    {
      'id': 'bank-o2',
      'name': 'Pure Oxygen',
      'volumeL': 40,
      'pressureBar': 180,
      'maxPressureBar': 350,
      'minimumPressureBar': 10,
      'oxygenPercent': 100,
      'heliumPercent': 0,
      'enabled': true,
    },
    {
      'id': 'bank-n',
      'name': 'Leftover N',
      'volumeL': 50,
      'pressureBar': 20,
      'maxPressureBar': 200,
      'minimumPressureBar': 10,
      'oxygenPercent': 32,
      'heliumPercent': 0,
      'enabled': true,
    },
  ],
  'thermal': {
    'tankMaterial': 'steel',
    'tankSurfaceAreaM2': steelTestAreaM2,
    'coolingMedium': 'air',
    'ambientTemperatureC': 20,
    'inletTemperatureC': 40,
    'targetMediumTemperatureC': 20,
    'targetInWaterTemperatureC': 20,
    'waitMode': 'minutes',
    'waitMinutes': 0,
    'interimMeasurements': <Object?>[],
  },
  'settings': {
    'booster': {
      'maxCompressorPressureBar': 350,
      'maxBoosterOutputPressureBar': 350,
    },
  },
};

List<ProtocolStep?> protocolStepsOf(Map<String, Object?> result) =>
    (result['protocolSteps']! as List<Object?>).cast<ProtocolStep?>();

void main() {
  test('a first reading at the planned state is accepted', () {
    expect(
      verifyInterimMeasurement(defaultScenario, 0, (
        pressureBar: 50,
        temperatureC: 21,
      ), tolerancePercent: tolerancePercent),
      equals(const InterimCheckResult.accepted()),
    );
  });

  test('a reading below ambient is rejected when no drain produced it', () {
    final result = verifyInterimMeasurement(defaultScenario, 0, (
      pressureBar: 30,
      temperatureC: 15,
    ), tolerancePercent: tolerancePercent);
    expect(result.ok, isFalse);
    expect(
      result.error,
      matches(RegExp(r'below ambient 21\.0 °C.*pressure-lowering drain')),
    );
    expect(
      result.error,
      matches(RegExp('salvage transfer out of the working tank')),
    );
  });

  test('a pressure outside the tolerance band for the measured temperature is rejected', () {
    final result = verifyInterimMeasurement(defaultScenario, 0, (
      pressureBar: 52,
      temperatureC: 21,
    ), tolerancePercent: tolerancePercent);
    expect(result.ok, isFalse);
    expect(
      result.error,
      matches(
        RegExp(r'outside ±3% of the planned 50\.0 bar for step 1 at 21\.0 °C'),
      ),
    );
  });

  test('a pressure inside a widened tolerance band is accepted', () {
    expect(
      verifyInterimMeasurement(defaultScenario, 0, (
        pressureBar: 52,
        temperatureC: 21,
      ), tolerancePercent: 5),
      equals(const InterimCheckResult.accepted()),
    );
  });

  test('mismatch messages use the selected display units', () {
    final result = verifyInterimMeasurement(
      defaultScenario,
      0,
      (pressureBar: 52, temperatureC: 21),
      tolerancePercent: tolerancePercent,
      units: 'imperial',
    );
    expect(result.ok, isFalse);
    expect(result.error, matches(RegExp(r'planned 725\.\d psi')));
    expect(result.error, matches(RegExp('69\\.8 °F')));
  });

  test(
    'a reading below ambient after a drain is accepted at the drained state',
    () {
      final result = verifyInterimMeasurement(drainScenario, 1, (
        pressureBar: 41.7,
        temperatureC: 11.8,
      ), tolerancePercent: tolerancePercent);
      expect(result, equals(const InterimCheckResult.accepted()));
    },
  );

  test('a reading below ambient after a salvage is accepted at the salvage-cooled state', () {
    final planned = protocolStepsOf(optimizeBlend(salvageScenario))
        .firstWhere((step) => step?.measurementIndex == 1)!
        .thermal!;
    expect(
      planned.temperatureStartC < 20,
      isTrue,
      reason: 'the salvage should cool the tank below ambient',
    );
    final result = verifyInterimMeasurement(salvageScenario, 1, (
      pressureBar: planned.pressureStartBar,
      temperatureC: planned.temperatureStartC,
    ), tolerancePercent: tolerancePercent);
    expect(result, equals(const InterimCheckResult.accepted()));
  });

  test('a pressure mismatch after a drain is rejected with the step number the results panel shows', () {
    final result = verifyInterimMeasurement(drainScenario, 1, (
      pressureBar: 30,
      temperatureC: 11.8,
    ), tolerancePercent: tolerancePercent);
    expect(result.ok, isFalse);
    final planTitle = protocolStepsOf(optimizeBlend(drainScenario))
        .firstWhere((step) => step?.measurementIndex == 1)!
        .title!;
    final shownNumber = RegExp(r'^Step (\d+)').firstMatch(planTitle)!.group(1)!;
    expect(
      result.error,
      matches(RegExp('planned 41\\.\\d bar for step $shownNumber ')),
    );
  });
}

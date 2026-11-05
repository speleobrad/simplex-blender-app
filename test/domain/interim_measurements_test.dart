import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/interim_measurements.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

ProtocolStep step(String type, String rateSource) => ProtocolStep(
  type: type,
  thermal: ThermalStep(
    rateSource: rateSource,
    rateBarPerMin: null,
    durationMinutes: 0,
    inletTemperatureC: 0,
    pressureStartBar: 0,
    temperatureStartC: 0,
    temperatureAtTransferEndC: 0,
    pressureReferenceTemperatureC: 0,
    pressureAtTransferEndReferenceBar: 0,
    pressureAtTransferEndAmbientBar: 0,
    waitMinutes: 0,
    temperatureAfterWaitC: 0,
    pressureAtTransferEndBar: 0,
    pressureAtTransferEndHotBar: 0,
    pressureAfterWaitBar: 0,
    samples: const [],
  ),
);

final input = <String, Object?>{
  'cylinder': {'initialPressureBar': 50, 'targetPressureBar': 200},
  'physics': {'model': 'vdw', 'temperatureC': 25},
  'thermal': {
    'ambientTemperatureC': 25,
    'waitMode': 'minutes',
    'waitMinutes': 7,
    'interimMeasurements': [
      null,
      {'pressureBar': 60.2, 'temperatureC': 25.7},
    ],
  },
  'banks': [
    {'id': 'oxygen', 'pressureBar': 200},
  ],
  'settings': {
    'booster': {'otherBoostBpm': 50},
  },
};

Map<String, Object?> withThermal(
  Map<String, Object?> base,
  Map<String, Object?> thermal,
) => {
  ...base,
  'thermal': {...(base['thermal']! as Map<String, Object?>), ...thermal},
};

Map<String, Object?> priced([Map<String, Object?> over = const {}]) => {
  ...input,
  'banks': [
    {'id': 'oxygen', 'pressureBar': 200, 'pricePerLitre': 0.02},
  ],
  'settings': {
    'booster': {'otherBoostBpm': 50},
    'costs': {
      'currencySymbol': '€',
      'leftoverDiscountPercent': 0,
      'operationPrices': {'boost': 1, 'decant': 2, 'topUp': 3},
    },
  },
  ...over,
};

void main() {
  test('calculator recipe signature ignores interim readings themselves', () {
    expect(
      calculatorInputSignature(input),
      equals(
        calculatorInputSignature(
          withThermal(input, {
            'interimMeasurements': [
              null,
              {'pressureBar': 61, 'temperatureC': 26},
            ],
          }),
        ),
      ),
    );
  });

  test('calculator recipe signature changes when a recipe input changes', () {
    expect(
      calculatorInputSignature(input),
      isNot(
        equals(
          calculatorInputSignature({
            ...input,
            'cylinder': {'initialPressureBar': 50, 'targetPressureBar': 210},
          }),
        ),
      ),
    );
  });

  test('calculator recipe signature ignores display units but tracks equipment settings', () {
    String withSettings(Map<String, Object?> overrides) =>
        calculatorInputSignature({
          ...input,
          'settings': {
            ...(input['settings']! as Map<String, Object?>),
            ...overrides,
          },
        });
    expect(
      withSettings({'units': 'metric'}),
      equals(withSettings({'units': 'imperial'})),
    );
    expect(
      withSettings({
        'booster': {'otherBoostBpm': 51},
      }),
      isNot(
        equals(
          withSettings({
            'booster': {'otherBoostBpm': 50},
          }),
        ),
      ),
    );
  });

  test(
    'clearing one reading keeps the recipe signature while others remain',
    () {
      final multiInput = withThermal(input, {
        'interimMeasurements': [
          null,
          {'pressureBar': 60.2, 'temperatureC': 25.7},
          {'pressureBar': 104.6, 'temperatureC': 26.9},
        ],
      });
      expect(
        signatureAfterClearingMeasurement(multiInput, 1),
        equals(calculatorInputSignature(multiInput)),
      );
    },
  );

  test('latest reading index ignores empty slots', () {
    expect(latestInterimMeasurementIndex(const []), equals(-1));
    expect(latestInterimMeasurementIndex(const [null, null]), equals(-1));
    expect(
      latestInterimMeasurementIndex(const [
        InterimMeasurement(pressureBar: 1, temperatureC: 1),
        null,
        null,
      ]),
      equals(0),
    );
    expect(
      latestInterimMeasurementIndex(const [
        null,
        InterimMeasurement(pressureBar: 1, temperatureC: 1),
        null,
      ]),
      equals(1),
    );
  });

  test(
    'earlier readings are locked; only the latest can be edited or cleared',
    () {
      const measurements = [
        InterimMeasurement(pressureBar: 50, temperatureC: 21),
        InterimMeasurement(pressureBar: 55, temperatureC: 25),
      ];
      expect(
        interimMeasurementLockMessage(measurements, 0, 'apply'),
        matches(RegExp('step 1 is locked', caseSensitive: false)),
      );
      expect(
        interimMeasurementLockMessage(measurements, 0, 'clear'),
        matches(RegExp('step 1 is locked', caseSensitive: false)),
      );
      expect(interimMeasurementLockMessage(measurements, 1, 'apply'), isNull);
      expect(interimMeasurementLockMessage(measurements, 1, 'clear'), isNull);
      expect(interimMeasurementLockMessage(measurements, 2, 'apply'), isNull);
      expect(
        interimMeasurementLockMessage(measurements, 2, 'clear'),
        matches(RegExp('step 3 is locked', caseSensitive: false)),
      );
    },
  );

  test('empty slots before the latest reading cannot be recorded', () {
    const measurements = [
      null,
      null,
      InterimMeasurement(pressureBar: 55, temperatureC: 25),
    ];
    expect(
      interimMeasurementLockMessage(measurements, 1, 'apply'),
      matches(RegExp('step 2 is locked', caseSensitive: false)),
    );
    expect(
      interimMeasurementLockMessage(const [null, null], 1, 'apply'),
      isNull,
    );
  });

  test('pressure tolerance is inclusive and relative to the plan', () {
    expect(
      interimPressureWithinTolerance(
        measuredBar: 103,
        plannedBar: 100,
        tolerancePercent: 3,
      ),
      isTrue,
    );
    expect(
      interimPressureWithinTolerance(
        measuredBar: 97,
        plannedBar: 100,
        tolerancePercent: 3,
      ),
      isTrue,
    );
    expect(
      interimPressureWithinTolerance(
        measuredBar: 103.1,
        plannedBar: 100,
        tolerancePercent: 3,
      ),
      isFalse,
    );
    expect(
      interimPressureWithinTolerance(
        measuredBar: 30,
        plannedBar: 55,
        tolerancePercent: 3,
      ),
      isFalse,
    );
  });

  test('zero planned pressure requires an exact zero measurement', () {
    expect(
      interimPressureWithinTolerance(
        measuredBar: 0,
        plannedBar: 0,
        tolerancePercent: 3,
      ),
      isTrue,
    );
    expect(
      interimPressureWithinTolerance(
        measuredBar: 0.1,
        plannedBar: 0,
        tolerancePercent: 3,
      ),
      isFalse,
    );
  });

  test(
    'gas below ambient needs a pressure-lowering drain before the reading',
    () {
      expect(gasCanBeBelowAmbient([step('boost', 'booster')], 1), isFalse);
      expect(gasCanBeBelowAmbient([step('drain', 'draining-rate')], 1), isTrue);
      expect(gasCanBeBelowAmbient(const [], 0), isFalse);
    },
  );

  test('waits and keeps carry drain provenance forward', () {
    expect(
      gasCanBeBelowAmbient([
        step('drain', 'draining-rate'),
        step('wait', 'none'),
      ], 2),
      isTrue,
    );
    expect(
      gasCanBeBelowAmbient([
        step('drain', 'draining-rate'),
        step('keep', 'none'),
      ], 2),
      isTrue,
    );
  });

  test('a boost, decant, or top-up after a drain removes drain provenance', () {
    expect(
      gasCanBeBelowAmbient([
        step('drain', 'draining-rate'),
        step('boost', 'booster'),
      ], 2),
      isFalse,
    );
    expect(
      gasCanBeBelowAmbient([
        step('drain', 'draining-rate'),
        step('decant', 'decant-rate'),
      ], 2),
      isFalse,
    );
    expect(
      gasCanBeBelowAmbient([
        step('drain', 'draining-rate'),
        step('boost', 'compressor'),
      ], 2),
      isFalse,
    );
    expect(
      gasCanBeBelowAmbient([
        step('drain', 'draining-rate'),
        step('equalize', 'none'),
      ], 2),
      isFalse,
    );
  });

  test('a salvage transfer out of the working tank cools it, so its gas can sit below ambient', () {
    expect(
      gasCanBeBelowAmbient([step('salvage', 'salvage-decant')], 1),
      isTrue,
    );
    expect(
      gasCanBeBelowAmbient([step('salvage', 'salvage-booster')], 1),
      isTrue,
    );
    expect(
      gasCanBeBelowAmbient([
        step('drain', 'draining-rate'),
        step('salvage', 'salvage-decant'),
      ], 2),
      isTrue,
    );
  });

  test('a drain after a boost establishes provenance again', () {
    expect(
      gasCanBeBelowAmbient([
        step('drain', 'draining-rate'),
        step('boost', 'booster'),
        step('drain', 'draining-rate'),
      ], 3),
      isTrue,
    );
  });

  test('a titled step shows its plan number and an untitled step falls back to index + 1', () {
    expect(
      protocolStepNumber(
        const ProtocolStep(title: 'Step 1: Decant Oxygen to 46.9 bar'),
        1,
      ),
      equals(1),
    );
    expect(
      protocolStepNumber(
        const ProtocolStep(title: 'step   7: Boost Helium'),
        2,
      ),
      equals(7),
    );
    expect(
      protocolStepNumber(
        const ProtocolStep(title: 'Preserve 100% of Cylinder Gas'),
        0,
      ),
      equals(1),
    );
    expect(protocolStepNumber(null, 3), equals(4));
  });

  test(
    'calculator recipe signature ignores cost prices in settings and banks',
    () {
      final base = priced();
      expect(
        calculatorInputSignature(base),
        equals(
          calculatorInputSignature({
            ...base,
            'settings': {
              ...(base['settings']! as Map<String, Object?>),
              'costs': {
                'currencySymbol': '€',
                'leftoverDiscountPercent': 50,
                'operationPrices': {'boost': 9, 'decant': 9, 'topUp': 9},
              },
            },
          }),
        ),
      );
      expect(
        calculatorInputSignature(base),
        equals(
          calculatorInputSignature({
            ...base,
            'banks': [
              {'id': 'oxygen', 'pressureBar': 200, 'pricePerLitre': 1.5},
            ],
          }),
        ),
      );
      expect(
        calculatorInputSignature(base),
        equals(
          calculatorInputSignature({
            ...base,
            'banks': [
              {'id': 'oxygen', 'pressureBar': 200, 'pricePerLitre': null},
            ],
          }),
        ),
      );
    },
  );

  test('calculator recipe signature still changes for non-price bank, booster, and physics edits', () {
    final base = priced();
    final signature = calculatorInputSignature(base);
    expect(
      signature,
      isNot(
        equals(
          calculatorInputSignature({
            ...base,
            'banks': [
              {'id': 'oxygen', 'pressureBar': 180, 'pricePerLitre': 0.02},
            ],
          }),
        ),
      ),
    );
    expect(
      signature,
      isNot(
        equals(
          calculatorInputSignature({
            ...base,
            'settings': {
              ...(base['settings']! as Map<String, Object?>),
              'booster': {'otherBoostBpm': 60},
            },
          }),
        ),
      ),
    );
    expect(
      signature,
      isNot(
        equals(
          calculatorInputSignature({
            ...base,
            'physics': {'model': 'ideal', 'temperatureC': 25},
          }),
        ),
      ),
    );
  });

  test('calculator recipe signature does not mutate its input', () {
    final base = priced();
    final snapshot = jsonEncode(base);
    calculatorInputSignature(base);
    expect(jsonEncode(base), equals(snapshot));
  });
}

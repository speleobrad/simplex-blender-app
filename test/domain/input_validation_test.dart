import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/input_validation.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

const defaultCylinder = CalculatorCylinder(
  volumeL: 12,
  initialPressureBar: 80,
  targetPressureBar: 210,
);
const defaultPhysics = CalculatorPhysics(temperatureC: 20);

Map<String, Object?> validCosts() => <String, Object?>{
  'currencySymbol': '€',
  'leftoverDiscountPercent': 20,
  'operationPrices': <String, Object?>{'boost': 0.5, 'decant': 0, 'topUp': 5},
};

Map<String, Object?> supplyBank() => <String, Object?>{
  'id': 'b',
  'name': 'B',
  'volumeL': 10,
  'pressureBar': 100,
  'maxPressureBar': 200,
  'oxygenPercent': 100,
  'heliumPercent': 0,
  'enabled': true,
};

const _thermalBase = CalculatorThermal(
  tankMaterial: 'steel',
  coolingMedium: 'air',
  ambientTemperatureC: 20,
  waitMode: 'minutes',
  waitMinutes: 10,
  targetTemperatureC: 25,
);

void main() {
  test('accepts supported cylinder-input boundaries', () {
    expect(
      validateCalculatorInputs(
        defaultCylinder.copyWith(
          volumeL: 0.1,
          initialPressureBar: 0,
          targetPressureBar: 10,
        ),
        const CalculatorPhysics(temperatureC: 5),
        null,
      ),
      isEmpty,
    );
    expect(
      validateCalculatorInputs(
        defaultCylinder.copyWith(
          initialPressureBar: 350,
          targetPressureBar: 350,
        ),
        const CalculatorPhysics(temperatureC: 40),
        null,
      ),
      isEmpty,
    );
  });

  test('rejects blank and out-of-range cylinder inputs', () {
    final invalidCases = <(CalculatorCylinder, CalculatorPhysics, String)>[
      (
        defaultCylinder.copyWith(volumeL: double.nan),
        defaultPhysics,
        'Cylinder capacity must be at least 0.1 L.',
      ),
      (
        defaultCylinder.copyWith(volumeL: 0.09),
        defaultPhysics,
        'Cylinder capacity must be at least 0.1 L.',
      ),
      (
        defaultCylinder.copyWith(initialPressureBar: 351),
        defaultPhysics,
        'Initial pressure must be between 0 and 350 bar.',
      ),
      (
        defaultCylinder.copyWith(targetPressureBar: 9),
        defaultPhysics,
        'Target pressure must be between 10 and 350 bar.',
      ),
      (
        defaultCylinder.copyWith(targetPressureBar: 351),
        defaultPhysics,
        'Target pressure must be between 10 and 350 bar.',
      ),
      (
        defaultCylinder,
        const CalculatorPhysics(temperatureC: double.nan),
        'Temperature must be between 5 and 40°C.',
      ),
      (
        defaultCylinder,
        const CalculatorPhysics(temperatureC: 50.1),
        'Temperature must be between 5 and 40°C.',
      ),
    ];

    for (final (cylinder, physics, expectedMessage) in invalidCases) {
      expect(
        validateCalculatorInputs(cylinder, physics, null),
        contains(expectedMessage),
      );
    }
  });

  test('enforces the selected cylinder working pressure', () {
    final ratedCylinder = defaultCylinder.copyWith(workingPressureBar: 232);
    const workingMessage =
        'cannot exceed the selected cylinder working pressure of 232 bar.';

    expect(
      validateCalculatorInputs(
        ratedCylinder.copyWith(targetPressureBar: 232),
        defaultPhysics,
        _thermalBase,
      ),
      isEmpty,
    );
    expect(
      validateCalculatorInputs(
        ratedCylinder.copyWith(targetPressureBar: 232.1),
        defaultPhysics,
        _thermalBase,
      ).join(' '),
      contains('Target pressure $workingMessage'),
    );
    expect(
      validateCalculatorInputs(
        ratedCylinder.copyWith(initialPressureBar: 232.1),
        defaultPhysics,
        _thermalBase,
      ).join(' '),
      contains('Initial pressure $workingMessage'),
    );
  });

  test('validates measured interim readings against supported tank limits', () {
    final rated = defaultCylinder.copyWith(workingPressureBar: 232);
    final thermal = _thermalBase.copyWith(
      interimMeasurements: <InterimMeasurement?>[
        null,
        const InterimMeasurement(pressureBar: 237, temperatureC: 25),
      ],
    );

    expect(
      validateCalculatorInputs(rated, defaultPhysics, thermal).join(' '),
      contains(
        'Measured pressure cannot exceed the selected cylinder hot overfill limit of',
      ),
    );
    expect(
      validateCalculatorInputs(
        rated,
        defaultPhysics,
        thermal.copyWith(
          interimMeasurements: <InterimMeasurement?>[
            null,
            const InterimMeasurement(pressureBar: 60.2, temperatureC: -20.1),
          ],
        ),
      ).join(' '),
      contains('Measured temperature must be between -20 and 100°C.'),
    );
  });

  test('rejects a temperature wait target at or below ambient', () {
    final errors = validateCalculatorInputs(
      const CalculatorCylinder(
        volumeL: 12,
        initialPressureBar: 80,
        targetPressureBar: 210,
      ),
      const CalculatorPhysics(temperatureC: 20),
      const CalculatorThermal(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 25,
        inletTemperatureC: 25,
        targetMediumTemperatureC: 24,
        targetInWaterTemperatureC: 1,
        waitMode: 'temperature',
        waitMinutes: 10,
      ),
    );
    expect(
      errors,
      contains(
        'Thermal target-medium temperature cannot be below ambient temperature.',
      ),
    );
  });

  test('rejects target-medium below ambient regardless of cooling medium', () {
    final errors = validateCalculatorInputs(
      const CalculatorCylinder(
        volumeL: 12,
        initialPressureBar: 50,
        targetPressureBar: 200,
      ),
      const CalculatorPhysics(temperatureC: 25),
      const CalculatorThermal(
        tankMaterial: 'steel',
        coolingMedium: 'water',
        ambientTemperatureC: 25,
        inletTemperatureC: 25,
        targetMediumTemperatureC: 15,
        targetInWaterTemperatureC: 15,
        waitMode: 'minutes',
        waitMinutes: 10,
      ),
    );
    expect(
      errors,
      contains(
        'Thermal target-medium temperature cannot be below ambient temperature.',
      ),
    );
  });

  test('accepts only 20% steps up to 80% for water submersion and ignores it for air', () {
    List<String> run(String coolingMedium, double? waterSubmersionPercent) {
      return validateCalculatorInputs(
        const CalculatorCylinder(
          volumeL: 12,
          initialPressureBar: 50,
          targetPressureBar: 200,
        ),
        const CalculatorPhysics(temperatureC: 25),
        CalculatorThermal(
          tankMaterial: 'steel',
          coolingMedium: coolingMedium,
          waterSubmersionPercent: waterSubmersionPercent,
          ambientTemperatureC: 25,
          inletTemperatureC: 25,
          targetMediumTemperatureC: 25,
          targetInWaterTemperatureC: 15,
          waitMode: 'minutes',
          waitMinutes: 10,
        ),
      );
    }

    // JS `undefined` maps to Dart null (absent), which is accepted.
    for (final percent in <double?>[20, 40, 60, 80, null]) {
      expect(run('water', percent), isEmpty);
    }
    // JS 'abc' and null submersion values cannot be represented in typed
    // Dart input and are dropped.
    for (final percent in <double>[0, 10, 50, 70, 100]) {
      expect(
        run('water', percent),
        contains('Thermal water submersion must be 20, 40, 60, or 80%.'),
      );
    }
    expect(run('air', 100), isEmpty);
    expect(run('air', null), isEmpty);
  });

  test('rejects a settled temperature below ambient for air cooling', () {
    final errors = validateCalculatorInputs(
      const CalculatorCylinder(
        volumeL: 12,
        initialPressureBar: 50,
        targetPressureBar: 200,
      ),
      const CalculatorPhysics(temperatureC: 25),
      const CalculatorThermal(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 25,
        targetMediumTemperatureC: 15,
        targetInWaterTemperatureC: 15,
        inletTemperatureC: 25,
        waitMode: 'minutes',
        waitMinutes: 10,
        targetTemperatureC: 15,
      ),
    );

    expect(
      errors,
      contains(
        'Thermal target-medium temperature cannot be below ambient temperature.',
      ),
    );
  });

  test('fixed-minute waits require a target-medium temperature at or above ambient', () {
    final errors = validateCalculatorInputs(
      const CalculatorCylinder(
        volumeL: 12,
        initialPressureBar: 80,
        targetPressureBar: 210,
      ),
      const CalculatorPhysics(temperatureC: 20),
      const CalculatorThermal(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 26,
        inletTemperatureC: 26,
        targetMediumTemperatureC: 26,
        targetInWaterTemperatureC: 25,
        waitMode: 'minutes',
        waitMinutes: 10,
      ),
    );
    expect(errors, isEmpty);
  });

  test('rejects unsupported thermal selectors and negative fixed waits', () {
    final errors = validateCalculatorInputs(
      const CalculatorCylinder(
        volumeL: 12,
        initialPressureBar: 80,
        targetPressureBar: 210,
      ),
      const CalculatorPhysics(temperatureC: 20),
      const CalculatorThermal(
        tankMaterial: 'carbon',
        coolingMedium: 'oil',
        ambientTemperatureC: 20,
        inletTemperatureC: 20,
        targetMediumTemperatureC: 25,
        targetInWaterTemperatureC: 20,
        waitMode: 'temperature',
        waitMinutes: -1,
        targetTemperatureC: 25,
      ),
    );
    expect(errors.length, greaterThanOrEqualTo(2));
  });

  test('rejects invalid fixed wait minutes and unknown wait modes', () {
    const cylinder = CalculatorCylinder(
      volumeL: 12,
      initialPressureBar: 80,
      targetPressureBar: 210,
    );
    const physics = CalculatorPhysics(temperatureC: 20);
    const thermal = CalculatorThermal(
      tankMaterial: 'steel',
      coolingMedium: 'air',
      ambientTemperatureC: 20,
      inletTemperatureC: 20,
      targetMediumTemperatureC: 25,
      targetInWaterTemperatureC: 20,
      waitMode: 'minutes',
      waitMinutes: 5,
    );
    const waitMessage = 'Thermal wait must be between 0 and 1440 minutes.';

    expect(validateCalculatorInputs(cylinder, physics, thermal), isEmpty);
    expect(
      validateCalculatorInputs(
        cylinder,
        physics,
        thermal.copyWith(waitMinutes: double.nan),
      ),
      contains(waitMessage),
    );
    expect(
      validateCalculatorInputs(
        cylinder,
        physics,
        thermal.copyWith(waitMinutes: -1),
      ),
      contains(waitMessage),
    );
    expect(
      validateCalculatorInputs(
        cylinder,
        physics,
        thermal.copyWith(waitMinutes: 1441),
      ),
      contains(waitMessage),
    );
    expect(
      validateCalculatorInputs(
        cylinder,
        physics,
        thermal.copyWith(waitMode: 'sometime'),
      ),
      contains('Thermal wait mode must be minutes or temperature.'),
    );
    expect(
      validateCalculatorInputs(
        cylinder,
        physics,
        thermal.copyWith(waitMode: 'temperature', waitMinutes: double.nan),
      ),
      isEmpty,
    );
  });

  test('rejects finite Air supply banks because Air is an implicit compressor source', () {
    final bank = supplyBank()
      ..['name'] = 'Air bank'
      ..['id'] = 'air-bank'
      ..['volumeL'] = 10
      ..['pressureBar'] = 200
      ..['oxygenPercent'] = 21
      ..['heliumPercent'] = 0;
    final errors = validateSupplyBankInput(bank);

    expect(
      errors,
      contains(
        'Air is supplied by the implicit compressor and cannot be a finite supply bank.',
      ),
    );
  });

  test('accepts thermal temperature boundaries and semantic combinations', () {
    const valid = CalculatorThermal(
      tankMaterial: 'steel',
      coolingMedium: 'air',
      ambientTemperatureC: 5,
      inletTemperatureC: 5,
      targetMediumTemperatureC: 5,
      targetInWaterTemperatureC: 1,
      waitMode: 'minutes',
      waitMinutes: 0,
    );
    for (final value in <double>[5, 40]) {
      expect(
        validateCalculatorInputs(
          defaultCylinder,
          defaultPhysics,
          valid.copyWith(
            ambientTemperatureC: value,
            targetMediumTemperatureC: value,
          ),
        ),
        isEmpty,
      );
      expect(
        validateCalculatorInputs(
          defaultCylinder,
          defaultPhysics,
          valid.copyWith(inletTemperatureC: value),
        ),
        isEmpty,
      );
      expect(
        validateCalculatorInputs(
          defaultCylinder,
          defaultPhysics,
          valid.copyWith(targetMediumTemperatureC: value),
        ),
        isEmpty,
      );
    }
    for (final value in <double>[1, 30]) {
      expect(
        validateCalculatorInputs(
          defaultCylinder,
          defaultPhysics,
          valid.copyWith(targetInWaterTemperatureC: value),
        ),
        isEmpty,
      );
    }
  });

  test('rejects values outside every thermal temperature range', () {
    const valid = CalculatorThermal(
      tankMaterial: 'steel',
      coolingMedium: 'air',
      ambientTemperatureC: 20,
      inletTemperatureC: 20,
      targetMediumTemperatureC: 20,
      targetInWaterTemperatureC: 15,
      waitMode: 'minutes',
      waitMinutes: 0,
    );
    final cases = <(CalculatorThermal, String)>[
      (
        valid.copyWith(ambientTemperatureC: 4),
        'Thermal ambient temperature must be between 5 and 40°C.',
      ),
      (
        valid.copyWith(ambientTemperatureC: 41),
        'Thermal ambient temperature must be between 5 and 40°C.',
      ),
      (
        valid.copyWith(inletTemperatureC: 4),
        'Thermal inlet gas temperature must be between 5 and 40°C.',
      ),
      (
        valid.copyWith(inletTemperatureC: 41),
        'Thermal inlet gas temperature must be between 5 and 40°C.',
      ),
      (
        valid.copyWith(targetMediumTemperatureC: 4),
        'Thermal target-medium temperature must be between 5 and 40°C.',
      ),
      (
        valid.copyWith(targetMediumTemperatureC: 41),
        'Thermal target-medium temperature must be between 5 and 40°C.',
      ),
      (
        valid.copyWith(targetInWaterTemperatureC: 0),
        'Thermal target in-water temperature must be between 1 and 30°C.',
      ),
      (
        valid.copyWith(targetInWaterTemperatureC: 31),
        'Thermal target in-water temperature must be between 1 and 30°C.',
      ),
    ];
    for (final (thermal, message) in cases) {
      expect(
        validateCalculatorInputs(defaultCylinder, defaultPhysics, thermal),
        contains(message),
      );
    }
  });

  test(
    'allows target in-water below ambient while target medium remains valid',
    () {
      expect(
        validateCalculatorInputs(
          defaultCylinder,
          defaultPhysics,
          const CalculatorThermal(
            tankMaterial: 'steel',
            coolingMedium: 'air',
            ambientTemperatureC: 25,
            inletTemperatureC: 25,
            targetMediumTemperatureC: 25,
            targetInWaterTemperatureC: 1,
            waitMode: 'minutes',
            waitMinutes: 0,
          ),
        ),
        isEmpty,
      );
    },
  );

  test('allows target medium equal to ambient in temperature mode', () {
    expect(
      validateCalculatorInputs(
        defaultCylinder,
        defaultPhysics,
        const CalculatorThermal(
          tankMaterial: 'steel',
          coolingMedium: 'air',
          ambientTemperatureC: 25,
          inletTemperatureC: 25,
          targetMediumTemperatureC: 25,
          targetInWaterTemperatureC: 10,
          waitMode: 'temperature',
          waitMinutes: 0,
        ),
      ),
      isEmpty,
    );
  });

  test('measured interim overfill is allowed only while hotter than ambient and within the allowance', () {
    const cylinder = CalculatorCylinder(
      volumeL: 12,
      initialPressureBar: 80,
      targetPressureBar: 100,
      workingPressureBar: 100,
      hotOverfillPercent: 2,
    );
    const thermal = CalculatorThermal(
      tankMaterial: 'steel',
      coolingMedium: 'air',
      ambientTemperatureC: 20,
      inletTemperatureC: 20,
      targetMediumTemperatureC: 20,
      targetInWaterTemperatureC: 10,
      waitMode: 'minutes',
      waitMinutes: 10,
      interimMeasurements: <InterimMeasurement?>[
        InterimMeasurement(pressureBar: 101.5, temperatureC: 40),
      ],
    );

    expect(
      validateCalculatorInputs(cylinder, defaultPhysics, thermal),
      isEmpty,
    );
    expect(
      validateCalculatorInputs(
        cylinder,
        defaultPhysics,
        thermal.copyWith(
          interimMeasurements: <InterimMeasurement?>[
            const InterimMeasurement(pressureBar: 102.1, temperatureC: 40),
          ],
        ),
      ).join(' '),
      contains(
        'Measured pressure cannot exceed the selected cylinder hot overfill limit of',
      ),
    );
    expect(
      validateCalculatorInputs(
        cylinder,
        defaultPhysics,
        thermal.copyWith(
          interimMeasurements: <InterimMeasurement?>[
            const InterimMeasurement(pressureBar: 101.5, temperatureC: 20),
          ],
        ),
      ).join(' '),
      contains(
        'Measured pressure cannot exceed the selected cylinder working pressure of 100 bar.',
      ),
    );
  });

  test('Warning mode bypasses only cylinder ceilings, not supported calculator inputs', () {
    const warning = 'warning';
    final rated = defaultCylinder.copyWith(
      workingPressureBar: 100,
      hotOverfillPercent: 2,
    );
    final thermal = const CalculatorThermal(
      tankMaterial: 'steel',
      coolingMedium: 'air',
      ambientTemperatureC: 20,
      inletTemperatureC: 20,
      targetMediumTemperatureC: 20,
      targetInWaterTemperatureC: 10,
      waitMode: 'minutes',
      waitMinutes: 0,
      interimMeasurements: <InterimMeasurement?>[null],
    );

    expect(
      validateCalculatorInputs(
        rated.copyWith(initialPressureBar: 101, targetPressureBar: 110),
        defaultPhysics,
        thermal,
        pressureLimitMode: warning,
      ),
      isEmpty,
    );
    expect(
      validateCalculatorInputs(
        rated.copyWith(targetPressureBar: 110),
        defaultPhysics,
        thermal,
      ).join(' '),
      contains('working pressure'),
    );
    expect(
      validateCalculatorInputs(
        rated.copyWith(initialPressureBar: 101),
        defaultPhysics,
        thermal,
      ).join(' '),
      contains('working pressure'),
    );
    expect(
      validateCalculatorInputs(
        rated.copyWith(targetPressureBar: 351),
        defaultPhysics,
        thermal,
        pressureLimitMode: warning,
      ),
      contains('Target pressure must be between 10 and 350 bar.'),
    );
    expect(
      validateCalculatorInputs(
        rated.copyWith(initialPressureBar: 351),
        defaultPhysics,
        thermal,
        pressureLimitMode: warning,
      ),
      contains('Initial pressure must be between 0 and 350 bar.'),
    );
    expect(
      validateCalculatorInputs(
        rated.copyWith(targetPressureBar: 100.0000000005),
        defaultPhysics,
        thermal,
      ).join(' '),
      contains('working pressure'),
    );
    expect(
      validateCalculatorInputs(
        rated,
        defaultPhysics,
        thermal.copyWith(
          interimMeasurements: <InterimMeasurement?>[
            const InterimMeasurement(pressureBar: 90, temperatureC: 100.1),
          ],
        ),
        pressureLimitMode: warning,
      ),
      contains('Measured temperature must be between -20 and 100°C.'),
    );
    expect(
      validateCalculatorInputs(
        rated,
        defaultPhysics,
        thermal.copyWith(
          interimMeasurements: <InterimMeasurement?>[
            const InterimMeasurement(pressureBar: 103, temperatureC: 40),
          ],
        ),
        pressureLimitMode: warning,
      ),
      isEmpty,
    );
    expect(
      validateCalculatorInputs(
        rated,
        defaultPhysics,
        thermal.copyWith(
          interimMeasurements: <InterimMeasurement?>[
            const InterimMeasurement(pressureBar: 351, temperatureC: 40),
          ],
        ),
        pressureLimitMode: warning,
      ),
      contains('Measured pressure must be between 0 and 350 bar.'),
    );
    expect(
      validateCalculatorInputs(
        rated.copyWith(hotOverfillPercent: 2.25),
        defaultPhysics,
        thermal,
        pressureLimitMode: warning,
      ),
      contains('Cylinder hot overfill must be between 0 and 5% in 0.5% steps.'),
    );

    final invalidHotCylinder = rated.copyWith(hotOverfillPercent: 2.25);
    final overLimitReading = thermal.copyWith(
      interimMeasurements: <InterimMeasurement?>[
        const InterimMeasurement(pressureBar: 103, temperatureC: 40),
      ],
    );
    final hardStopInvalidHotErrors = validateCalculatorInputs(
      invalidHotCylinder,
      defaultPhysics,
      overLimitReading,
    );
    expect(
      hardStopInvalidHotErrors,
      contains('Cylinder hot overfill must be between 0 and 5% in 0.5% steps.'),
    );
    expect(
      hardStopInvalidHotErrors.join(' '),
      contains(
        'Measured pressure cannot exceed the selected cylinder hot overfill limit of',
      ),
    );
    final warningInvalidHotErrors = validateCalculatorInputs(
      invalidHotCylinder,
      defaultPhysics,
      overLimitReading,
      pressureLimitMode: warning,
    );
    expect(
      warningInvalidHotErrors,
      contains('Cylinder hot overfill must be between 0 and 5% in 0.5% steps.'),
    );
    expect(
      warningInvalidHotErrors.join(' '),
      isNot(contains('Measured pressure cannot exceed')),
    );
  });

  test('valid cost settings pass', () {
    expect(validateCostSettings(validCosts()), isEmpty);
  });

  test('flat fees accept zero and the 1,000,000 ceiling', () {
    final c = validCosts();
    c['operationPrices'] = <String, Object?>{
      'boost': 0,
      'decant': 1000000,
      'topUp': 0.01,
    };
    expect(validateCostSettings(c), isEmpty);
  });

  test('cost settings reject negative, non-finite, missing, oversized fees and bad discount', () {
    final mutations = <void Function(Map<String, Object?>)>[
      (c) => _prices(c)['boost'] = -1,
      (c) => _prices(c)['decant'] = double.nan,
      (c) => _prices(c)['topUp'] = 1000001,
      (c) => _prices(c).remove('boost'),
      (c) => _prices(c)['topUp'] = '5',
      (c) => c['leftoverDiscountPercent'] = 101,
      (c) => c['currencySymbol'] = 'WAYTOOLONGSYMBOL',
      (c) => c['currencySymbol'] = 5,
    ];
    for (final mutate in mutations) {
      final c = validCosts();
      mutate(c);
      expect(validateCostSettings(c), isNotEmpty);
    }
  });

  test('supply bank price must be a non-negative finite number or null', () {
    final bank = supplyBank();
    expect(
      validateSupplyBankInput(<String, Object?>{...bank, 'pricePerLitre': 0.5}),
      isEmpty,
    );
    expect(
      validateSupplyBankInput(<String, Object?>{
        ...bank,
        'pricePerLitre': null,
      }),
      isEmpty,
    );
    expect(
      validateSupplyBankInput(<String, Object?>{...bank, 'pricePerLitre': -1}),
      isNotEmpty,
    );
    expect(
      validateSupplyBankInput(<String, Object?>{...bank, 'pricePerLitre': 'x'}),
      isNotEmpty,
    );
  });

  test('supply bank maximum pressure must be 1–350 bar and at least the current pressure', () {
    final bank = supplyBank()
      ..['id'] = 'bank-max'
      ..['name'] = 'Max'
      ..['pressureBar'] = 150
      ..['maxPressureBar'] = 200
      ..['oxygenPercent'] = 0
      ..['heliumPercent'] = 100;
    const message =
        'Supply bank maximum pressure must be 1–350 bar and at least the current pressure.';
    for (final maxPressureBar in <double>[
      0,
      351,
      double.nan,
      double.infinity,
      149,
    ]) {
      expect(
        validateSupplyBankInput(<String, Object?>{
          ...bank,
          'maxPressureBar': maxPressureBar,
        }),
        equals(<String>[message]),
      );
    }
    expect(
      validateSupplyBankInput(<String, Object?>{
        ...bank,
        'maxPressureBar': 150,
      }),
      isEmpty,
    );
    expect(
      validateSupplyBankInput(<String, Object?>{
        ...bank,
        'maxPressureBar': 350,
      }),
      isEmpty,
    );
  });
}

Map<String, Object?> _prices(Map<String, Object?> costs) =>
    costs['operationPrices']! as Map<String, Object?>;

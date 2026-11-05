import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/calculator_input.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

// Expected shapes are taken from the JS source, not from the Dart output:
// - `readInput()` in js/main.js (lines 1065-1100) builds
//   cylinder / physics / thermal / banks; callers add `settings`
//   (`{ ...readInput(), settings: state.settings }`).
// - `copyBanks()` in js/bank-storage.js gives the JS bank record keys.

const CylinderPreset cylinderPreset = CylinderPreset(
  name: 'Test 12 L',
  volumeL: 12,
  material: 'aluminium',
  massKg: 5.5,
  workingPressureBar: 200,
  hotOverfillPercent: 10,
);

const Bank bank = Bank(
  id: 'bank-1',
  name: 'Tx 18/45',
  volumeL: 50,
  pressureBar: 200,
  oxygenPercent: 18,
  heliumPercent: 45,
  enabled: true,
  pricePerLitre: 0.25,
  maxPressureBar: 350,
  isCompressor: false,
  minimumPressureBar: 20,
);

Settings settings() =>
    DEFAULT_SETTINGS.copyWith(physics: const PhysicsSettings(model: 'vdw'));

Map<String, Object?> fixedInput({
  List<InterimMeasurement?> interimMeasurements = const <InterimMeasurement?>[],
}) => buildCalculatorInput(
  cylinderPreset: cylinderPreset,
  initialPressureBar: 80,
  initialOxygenPercent: 21,
  initialHeliumPercent: 35,
  targetPressureBar: 210,
  targetOxygenPercent: 18,
  targetHeliumPercent: 45,
  ambientTemperatureC: 20,
  targetInWaterTemperatureC: 15,
  waitTargetTemperatureC: 25,
  inletTemperatureC: 18,
  coolingMedium: 'water',
  waterSubmersionPercent: 50,
  waitMode: 'minutes',
  waitMinutes: 30,
  banks: const <Bank>[bank],
  settings: settings(),
  interimMeasurements: interimMeasurements,
);

void main() {
  group('buildCalculatorInput', () {
    test('has the JS readInput keys plus settings, in JS order', () {
      final input = fixedInput();

      expect(input.keys.toList(), <String>[
        'cylinder',
        'physics',
        'thermal',
        'banks',
        'settings',
      ]);
      expect(
        (input['cylinder']! as Map<String, Object?>).keys.toList(),
        <String>[
          'presetName',
          'volumeL',
          'workingPressureBar',
          'hotOverfillPercent',
          'initialPressureBar',
          'initialOxygenPercent',
          'initialHeliumPercent',
          'targetPressureBar',
          'targetOxygenPercent',
          'targetHeliumPercent',
        ],
      );
      expect(
        (input['physics']! as Map<String, Object?>).keys.toList(),
        <String>['model', 'temperatureC'],
      );
      expect(
        (input['thermal']! as Map<String, Object?>).keys.toList(),
        <String>[
          'tankMaterial',
          'tankMassKg',
          'coolingMedium',
          'waterSubmersionPercent',
          'ambientTemperatureC',
          'targetInWaterTemperatureC',
          'targetMediumTemperatureC',
          'inletTemperatureC',
          'waitMode',
          'waitMinutes',
          'interimMeasurements',
          'targetTemperatureC',
        ],
      );
    });

    test('nested values match JS readInput for one fixed input', () {
      final input = fixedInput();

      expect(input['cylinder'], <String, Object?>{
        'presetName': 'Test 12 L',
        'volumeL': 12.0,
        'workingPressureBar': 200.0,
        'hotOverfillPercent': 10.0,
        'initialPressureBar': 80.0,
        'initialOxygenPercent': 21.0,
        'initialHeliumPercent': 35.0,
        'targetPressureBar': 210.0,
        'targetOxygenPercent': 18.0,
        'targetHeliumPercent': 45.0,
      });
      expect(input['physics'], <String, Object?>{
        'model': 'vdw',
        'temperatureC': 20.0,
      });
      expect(input['thermal'], <String, Object?>{
        'tankMaterial': 'aluminium',
        'tankMassKg': 5.5,
        'coolingMedium': 'water',
        'waterSubmersionPercent': 50.0,
        'ambientTemperatureC': 20.0,
        'targetInWaterTemperatureC': 15.0,
        'targetMediumTemperatureC': 25.0,
        'inletTemperatureC': 18.0,
        'waitMode': 'minutes',
        'waitMinutes': 30.0,
        'interimMeasurements': <Object?>[],
        'targetTemperatureC': 25.0,
      });
    });

    test(
      'settings key carries the JS copySettings physics and pressure mode',
      () {
        final settingsJson = fixedInput()['settings']! as Map<String, Object?>;

        expect(settingsJson['physics'], <String, Object?>{'model': 'vdw'});
        expect(
          settingsJson['pressureLimitMode'],
          DEFAULT_SETTINGS.pressureLimitMode,
        );
      },
    );

    test('interim readings are JS measurement objects with null gaps', () {
      final input = fixedInput(
        interimMeasurements: const <InterimMeasurement?>[
          null,
          InterimMeasurement(pressureBar: 120, temperatureC: 25),
        ],
      );
      final thermal = input['thermal']! as Map<String, Object?>;

      expect(thermal['interimMeasurements'], <Object?>[
        null,
        <String, Object?>{'pressureBar': 120.0, 'temperatureC': 25.0},
      ]);
    });

    test('banks are the optimizer bank records', () {
      final input = fixedInput();

      expect(input['banks'], <Object?>[optimizerBankJson(bank)]);
    });
  });

  group('optimizerBankJson', () {
    test('produces the JS bank record keys plus the optimizer-only keys', () {
      final record = optimizerBankJson(bank);

      // JS copyBanks keys (js/bank-storage.js) plus pricePerLitre (when set).
      const jsBankKeys = <String>[
        'id',
        'name',
        'volumeL',
        'pressureBar',
        'maxPressureBar',
        'oxygenPercent',
        'heliumPercent',
        'enabled',
        'pricePerLitre',
      ];
      expect(record.keys.toSet(), <String>{
        ...jsBankKeys,
        'minimumPressureBar',
        'isCompressor',
      });
      expect(record['id'], 'bank-1');
      expect(record['name'], 'Tx 18/45');
      expect(record['volumeL'], 50.0);
      expect(record['pressureBar'], 200.0);
      expect(record['maxPressureBar'], 350.0);
      expect(record['oxygenPercent'], 18.0);
      expect(record['heliumPercent'], 45.0);
      expect(record['enabled'], true);
      expect(record['pricePerLitre'], 0.25);
    });
  });
}

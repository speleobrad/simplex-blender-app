import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/domain_error.dart';
import 'package:simplex_blender/src/domain/input_validation.dart';
import 'package:simplex_blender/src/domain/materials.dart';
import 'package:simplex_blender/src/domain/optimizer.dart';
import 'package:simplex_blender/src/domain/preset_validation.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/domain/units.dart';

Map<String, Object?> withFields(
  Map<String, Object?> base,
  Map<String, Object?> changes,
) => <String, Object?>{...base, ...changes};

List<Map<String, Object?>> loadShippedCylinderPresets() {
  final decoded = jsonDecode(
    File('assets/presets/cylinders.json').readAsStringSync(),
  );
  return (decoded as List<Object?>)
      .map((preset) => preset! as Map<String, Object?>)
      .toList();
}

void main() {
  group('materials', () {
    test(
      'every accepted material has a complete, positive thermal parameter set',
      () {
        for (final value in materialValues) {
          final thermal = materials[value]!.thermal;
          for (final parameter in [
            thermal.defaultTankMassKg,
            thermal.specificHeatJPerKgK,
            thermal.areaM2,
            thermal.airTauMinutes,
            thermal.waterTauMinutes,
          ]) {
            expect(parameter.isFinite && parameter > 0, isTrue, reason: value);
          }
        }
      },
    );

    test(
      'unknown materials are rejected instead of inheriting steel behaviour',
      () {
        expect(
          () => materialThermal('carbon'),
          throwsA(
            isA<DomainError>().having(
              (error) => error.message,
              'message',
              contains('Unknown cylinder material'),
            ),
          ),
        );
        expect(
          () => coolingTimeConstantMinutes('carbon', 'air'),
          throwsA(
            isA<DomainError>().having(
              (error) => error.message,
              'message',
              contains('Unknown cylinder material'),
            ),
          ),
        );
        expect(materialThermal(null), materials['steel']!.thermal);
      },
    );

    test('carbon-wrapped steel is labelled Fero-carbon and borrows steel thermal parameters', () {
      expect(materialLabel('carbon-wrapped-steel', metricUnits), 'Fero-carbon');
      expect(materialLabel('aluminum', imperialUnits), 'Aluminum');
      expect(materialLabel('aluminum', metricUnits), 'Aluminium');
      expect(materialThermal('carbon-wrapped-steel'), materialThermal('steel'));
      expect(materialThermal('aluminum') == materialThermal('steel'), isFalse);
    });

    test('cylinder preset validation accepts carbon-wrapped steel and rejects other materials', () {
      final preset = <String, Object?>{
        'name': 'X',
        'volumeL': 12.0,
        'material': 'carbon-wrapped-steel',
        'massKg': 10.9,
        'workingPressureBar': 300.0,
        'hotOverfillPercent': 2.0,
      };
      expect(validateCylinderPreset(preset), <String>[]);
      expect(
        validateCylinderPreset(
          withFields(preset, <String, Object?>{'material': 'carbon-steel'}),
        ),
        hasLength(1),
      );
      expect(
        validateCylinderPreset(
          withFields(preset, <String, Object?>{'material': 'carbon'}),
        ),
        hasLength(1),
      );
    });

    test('every shipped cylinder preset validates', () {
      final presets = loadShippedCylinderPresets();
      for (final preset in presets) {
        expect(
          validateCylinderPreset(preset),
          <String>[],
          reason: '${preset['name']}',
        );
      }
      final carbon = presets
          .where((preset) => preset['material'] == 'carbon-wrapped-steel')
          .map(
            (preset) => <Object?>[
              preset['volumeL'],
              preset['massKg'],
              preset['workingPressureBar'],
            ],
          )
          .toList();
      expect(carbon, <List<Object?>>[
        <Object?>[6.8, 6.25, 300.0],
        <Object?>[12.0, 10.9, 300.0],
      ]);
    });

    test('a Carbondive 12 L preset runs through validation and the optimizer with thermal output', () {
      final presets = loadShippedCylinderPresets();
      final preset = presets.firstWhere(
        (item) => item['name'] == 'Worthington Carbondive 12L 300 bar',
      );
      final thermal = <String, Object?>{
        'tankMaterial': preset['material'],
        'tankMassKg': preset['massKg'],
        'coolingMedium': 'air',
        'ambientTemperatureC': 20.0,
        'inletTemperatureC': 20.0,
        'targetMediumTemperatureC': 20.0,
        'targetInWaterTemperatureC': 15.0,
        'waitMode': 'minutes',
        'waitMinutes': 10.0,
      };
      final cylinder = <String, Object?>{
        'volumeL': preset['volumeL'],
        'initialPressureBar': 50.0,
        'initialOxygenPercent': 21.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 200.0,
        'targetOxygenPercent': 21.0,
        'targetHeliumPercent': 0.0,
        'workingPressureBar': preset['workingPressureBar'],
        'hotOverfillPercent': preset['hotOverfillPercent'],
      };
      const physicsMap = <String, Object?>{
        'model': 'ideal',
        'temperatureC': 20.0,
      };
      // JS DEFAULT_SETTINGS (pressureLimitMode and booster), keyed as in JS.
      const settingsMap = <String, Object?>{
        'pressureLimitMode': 'hard-stop',
        'booster': <String, Object?>{
          'minimumSourcePressureBar': 5.0,
          'cylinderVolumeCm3': 9.0,
          'oxygenBoostBpm': 35.0,
          'otherBoostBpm': 50.0,
          'oxygenDecantRateBarPerMin': 5.0,
          'otherDecantRateBarPerMin': 10.0,
          'drainingRateBarPerMin': 15.0,
          'compressorInletFlowLPerMin': 100.0,
          'maxCompressorPressureBar': 232.0,
          'maxBoosterOutputPressureBar': 230.0,
          'boosterTemperatureModifierC': 10.0,
          'compressorTemperatureModifierC': 5.0,
        },
      };

      expect(
        validateCalculatorInputs(
          CalculatorCylinder(
            volumeL: (preset['volumeL']! as num).toDouble(),
            initialPressureBar: 50,
            targetPressureBar: 200,
            workingPressureBar: (preset['workingPressureBar']! as num)
                .toDouble(),
            hotOverfillPercent: (preset['hotOverfillPercent']! as num)
                .toDouble(),
          ),
          const CalculatorPhysics(temperatureC: 20),
          CalculatorThermal(
            ambientTemperatureC: 20,
            tankMaterial: preset['material']! as String,
            coolingMedium: 'air',
            inletTemperatureC: 20,
            targetMediumTemperatureC: 20,
            targetInWaterTemperatureC: 15,
            waitMode: 'minutes',
            waitMinutes: 10,
          ),
        ),
        <String>[],
      );
      final result = optimizeBlend(<String, Object?>{
        'cylinder': cylinder,
        'physics': physicsMap,
        'thermal': thermal,
        'settings': settingsMap,
        'banks': <Object?>[],
      });
      expect(result['feasible'], isTrue);
      final steps = result['protocolSteps']! as List<Object?>;
      expect(
        steps.any((step) => (step! as ProtocolStep).thermal != null),
        isTrue,
      );
    });

    test('isValidMaterial accepts only string material keys', () {
      expect(isValidMaterial('steel'), isTrue);
      expect(isValidMaterial(['steel']), isFalse);
      expect(isValidMaterial(Object()), isFalse);
    });
  });
}

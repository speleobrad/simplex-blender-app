import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/preset_validation.dart';

// Messages come verbatim from js/preset-validation.js. The JS rejection cases
// in tests/settings.test.js (lines 199 and 733) assert RangeError only, so
// these tests pin the user-visible text of the same validators.
void main() {
  test('gas preset validation reports composition and name errors', () {
    expect(
      validateGasPreset(<String, Object?>{
        'name': 'G',
        'oxygenPercent': 60,
        'heliumPercent': 50,
      }),
      ['Gas preset “G” must total at most 100% O₂ and He.'],
    );
    expect(
      validateGasPreset(<String, Object?>{
        'name': '  ',
        'oxygenPercent': 21,
        'heliumPercent': 0,
      }),
      ['Every gas preset needs a name.'],
    );
    expect(validateGasPreset(null), [
      'Every gas preset needs a name.',
      'Gas preset “” must total at most 100% O₂ and He.',
    ]);
    expect(
      validatePreset('gasPresets', <String, Object?>{
        'name': 'G',
        'oxygenPercent': 60,
        'heliumPercent': 20,
      }),
      isEmpty,
    );
  });

  test('compressor preset validation reports out-of-range fields', () {
    expect(
      validateCompressorPreset(<String, Object?>{
        'name': 'C',
        'inletFlowLPerMin': 0.05,
        'maxPressureBar': 400,
        'temperatureModifierC': 101,
      }),
      [
        'Compressor inlet flow must be between 0.1 and 10000 L/min.',
        'Maximum compressor pressure must be between 10 and 350 bar.',
        'Compressor temperature modifier must be between -100 and 100°C.',
      ],
    );
    expect(
      validateCompressorPreset(<String, Object?>{
        'name': 'C',
        'inletFlowLPerMin': 10000,
        'maxPressureBar': 350,
        'temperatureModifierC': -100,
      }),
      isEmpty,
    );
  });

  test('booster preset validation reports out-of-range fields', () {
    expect(
      validateBoosterPreset(<String, Object?>{
        'name': 'B',
        'cylinderVolumeCm3': 0.1,
        'minimumSourcePressureBar': 0,
        'oxygenBoostBpm': 1,
        'otherBoostBpm': 1000,
        'maxOutputPressureBar': 350,
        'temperatureModifierC': -100,
        'oxygenDecantRateBarPerMin': 0.01,
        'otherDecantRateBarPerMin': 1000,
        'drainingRateBarPerMin': 0.01,
      }),
      isEmpty,
    );
    expect(
      validateBoosterPreset(<String, Object?>{
        'name': 'B',
        'cylinderVolumeCm3': 0.05,
        'minimumSourcePressureBar': 0,
        'oxygenBoostBpm': 1,
        'otherBoostBpm': 1000,
        'maxOutputPressureBar': 9,
        'temperatureModifierC': 100,
        'oxygenDecantRateBarPerMin': 0.01,
        'otherDecantRateBarPerMin': 1000,
        'drainingRateBarPerMin': 0.001,
      }),
      [
        'Booster cylinder volume must be between 0.1 and 1000 cm³.',
        'Maximum booster output pressure must be between 10 and 350 bar.',
        'Draining rate must be between 0.01 and 1000 bar/min.',
      ],
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/equipment_presets.dart';
import 'package:simplex_blender/src/domain/settings.dart';

// Fixture from tests/equipment-summary.test.js equipmentSettings().
const _compressorPresets = <CompressorPreset>[
  CompressorPreset(
    name: 'Bauer Junior',
    inletFlowLPerMin: 100,
    maxPressureBar: 232,
    temperatureModifierC: 5,
  ),
];

const _boosterPresets = <BoosterPreset>[
  BoosterPreset(
    name: 'Maximator ROB 22',
    minimumSourcePressureBar: 50,
    cylinderVolumeCm3: 4.6,
    oxygenBoostBpm: 30,
    otherBoostBpm: 50,
    oxygenDecantRateBarPerMin: 5,
    otherDecantRateBarPerMin: 10,
    maxOutputPressureBar: 280,
    temperatureModifierC: 0,
    drainingRateBarPerMin: 15,
  ),
];

const _booster = SettingsBooster(
  minimumSourcePressureBar: 50,
  cylinderVolumeCm3: 4.6,
  oxygenBoostBpm: 30,
  otherBoostBpm: 50,
  oxygenDecantRateBarPerMin: 5,
  otherDecantRateBarPerMin: 10,
  drainingRateBarPerMin: 15,
  compressorInletFlowLPerMin: 100,
  maxCompressorPressureBar: 232,
  maxBoosterOutputPressureBar: 280,
  boosterTemperatureModifierC: 0,
  compressorTemperatureModifierC: 5,
);

void main() {
  test(
    'renders named compressor and booster parameters in the compact summary',
    () {
      expect(
        compressorDisplayName(_booster, _compressorPresets),
        'Bauer Junior',
      );
      expect(boosterDisplayName(_booster, _boosterPresets), 'Maximator ROB 22');
    },
  );

  test(
    'labels equipment as custom when active fields do not match named presets',
    () {
      final mismatched = _booster.copyWith(compressorInletFlowLPerMin: 125);

      expect(
        compressorDisplayName(mismatched, _compressorPresets),
        'Custom compressor',
      );
      expect(
        boosterDisplayName(mismatched, _boosterPresets),
        'Maximator ROB 22',
      );
    },
  );
}

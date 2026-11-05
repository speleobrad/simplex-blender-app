import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/data/settings_storage.dart';
import 'package:simplex_blender/src/domain/preset_import.dart';
import 'package:simplex_blender/src/domain/settings.dart';

import '../support/memory_storage.dart';

void main() {
  test('selected imports survive the existing settings storage round trip', () {
    final settings = copySettings(DEFAULT_SETTINGS);
    final sources = <PresetAnalysis>[
      analyzePresetSource('gas', <Object?>[
        <String, Object?>{
          'name': 'Imported gas',
          'oxygenPercent': 19,
          'heliumPercent': 41,
        },
      ], settings),
      analyzePresetSource('cylinders', <Object?>[
        <String, Object?>{
          'name': 'Imported cylinder',
          'volumeL': 12,
          'material': 'steel',
          'massKg': 14,
          'workingPressureBar': 232,
          'hotOverfillPercent': 3,
        },
      ], settings),
      analyzePresetSource('equipment', <String, Object?>{
        'compressorPresets': <Object?>[
          <String, Object?>{
            'name': 'Imported compressor',
            'inletFlowLPerMin': 160,
            'maxPressureBar': 250,
            'temperatureModifierC': 4,
          },
        ],
        'boosterPresets': <Object?>[
          <String, Object?>{
            'name': 'Imported booster',
            'minimumSourcePressureBar': 20,
            'cylinderVolumeCm3': 10,
            'oxygenBoostBpm': 40,
            'otherBoostBpm': 55,
            'oxygenDecantRateBarPerMin': 6,
            'otherDecantRateBarPerMin': 11,
            'maxOutputPressureBar': 240,
            'temperatureModifierC': 2,
            'drainingRateBarPerMin': 12,
          },
        ],
      }, settings),
    ];
    final candidates = sources.expand((result) => result.candidates).toList();
    final merged = mergeSelectedPresets(
      settings,
      candidates,
      candidates.map((candidate) => candidate.id),
    );
    final storage = MemoryStorage();

    saveSettings(merged, storage);

    final loaded = loadSettings(storage);
    expect(loaded.gasPresets.last.name, 'Imported gas');
    expect(loaded.cylinderPresets.last.name, 'Imported cylinder');
    expect(loaded.cylinderPresets.last.hotOverfillPercent, 3.0);
    expect(loaded.compressorPresets.last.name, 'Imported compressor');
    expect(loaded.boosterPresets.last.name, 'Imported booster');
  });
}

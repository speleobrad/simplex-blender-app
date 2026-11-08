import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/preset_import.dart';
import 'package:simplex_blender/src/domain/settings.dart';

Settings newSettings() => copySettings(DEFAULT_SETTINGS);

Map<String, Object?> withFields(
  Map<String, Object?> base,
  Map<String, Object?> changes,
) => <String, Object?>{...base, ...changes};

void main() {
  test('classifies gas candidates by content and validation', () {
    final settings = newSettings();
    final result = analyzePresetSource('gas', <Object?>[
      <String, Object?>{'name': 'AIR', 'oxygenPercent': 21, 'heliumPercent': 0},
      <String, Object?>{
        'name': 'New mix',
        'oxygenPercent': 19,
        'heliumPercent': 41,
      },
      <String, Object?>{
        'name': 'Same content, new name',
        'oxygenPercent': 19,
        'heliumPercent': 41,
      },
      <String, Object?>{
        'name': 'New mix',
        'oxygenPercent': 20,
        'heliumPercent': 30,
      },
      <String, Object?>{
        'name': 'Broken',
        'oxygenPercent': 101,
        'heliumPercent': 0,
      },
    ], settings);

    expect(result.errors, <String>[]);
    expect(result.candidates.map((c) => c.status).toList(), <String>[
      'duplicate',
      'new',
      'duplicate',
      'invalid',
      'invalid',
    ]);
    expect(result.candidates[0].selectable, false);
    expect(result.candidates[1].selectable, true);
    expect(
      result.candidates[0].reason,
      matches(RegExp('content', caseSensitive: false)),
    );
    expect(
      result.candidates[2].reason,
      matches(RegExp('content', caseSensitive: false)),
    );
    expect(result.candidates[3].selectable, false);
  });

  test('rejects gas candidates that reuse a name with different content', () {
    final settings = newSettings();
    final result = analyzePresetSource('gas', <Object?>[
      <String, Object?>{'name': 'Air', 'oxygenPercent': 22, 'heliumPercent': 0},
    ], settings);

    expect(result.candidates[0].status, 'invalid');
    expect(result.candidates[0].selectable, false);
    expect(
      result.candidates[0].reason,
      matches(RegExp('same name', caseSensitive: false)),
    );
  });

  test('classifies cylinder candidates by normalized name', () {
    final settings = newSettings();
    final base = settings.cylinderPresets[0].toJson();
    final contentDuplicate = withFields(base, <String, Object?>{
      'name': 'Another name',
    });
    final nameDuplicate = withFields(base, <String, Object?>{'volumeL': 4});
    final result = analyzePresetSource('cylinders', <Object?>[
      contentDuplicate,
      nameDuplicate,
      <String, Object?>{
        'name': 'New cylinder',
        'volumeL': 12,
        'material': 'steel',
        'massKg': 14,
        'workingPressureBar': 232,
      },
      <String, Object?>{
        'name': 'Invalid cylinder',
        'volumeL': 0,
        'material': 'wood',
        'massKg': -1,
        'workingPressureBar': 500,
      },
    ], settings);

    expect(result.errors, <String>[]);
    expect(result.candidates.map((c) => c.status).toList(), <String>[
      'new',
      'duplicate',
      'new',
      'invalid',
    ]);
    expect(result.candidates[0].selectable, true);
    expect(result.candidates[1].collection, 'cylinderPresets');
    expect(
      result.candidates[1].reason,
      matches(RegExp('same name', caseSensitive: false)),
    );
  });

  test('classifies compressor and booster candidates by normalized name', () {
    final settings = newSettings();
    final compressorBase = settings.compressorPresets[0].toJson();
    final boosterBase = settings.boosterPresets[0].toJson();
    final result = analyzePresetSource('equipment', <String, Object?>{
      'compressorPresets': <Object?>[
        withFields(compressorBase, <String, Object?>{'name': 'Different name'}),
        withFields(compressorBase, <String, Object?>{'maxPressureBar': 250}),
        <String, Object?>{
          'name': 'New compressor',
          'inletFlowLPerMin': 160,
          'maxPressureBar': 250,
          'temperatureModifierC': 4,
        },
      ],
      'boosterPresets': <Object?>[
        withFields(boosterBase, <String, Object?>{'name': 'Different name'}),
        withFields(boosterBase, <String, Object?>{'maxOutputPressureBar': 240}),
        <String, Object?>{
          'name': 'New booster',
          'minimumSourcePressureBar': 20,
          'cylinderVolumeCm3': 8,
          'oxygenBoostBpm': 40,
          'otherBoostBpm': 55,
          'oxygenDecantRateBarPerMin': 6,
          'otherDecantRateBarPerMin': 12,
          'maxOutputPressureBar': 240,
          'temperatureModifierC': 4,
          'drainingRateBarPerMin': 12,
        },
      ],
    }, settings);

    expect(result.errors, <String>[]);
    expect(
      result.candidates.map((c) => <String>[c.collection, c.status]).toList(),
      <List<String>>[
        <String>['compressorPresets', 'new'],
        <String>['compressorPresets', 'duplicate'],
        <String>['compressorPresets', 'new'],
        <String>['boosterPresets', 'new'],
        <String>['boosterPresets', 'duplicate'],
        <String>['boosterPresets', 'new'],
      ],
    );
  });

  test('rejects equipment files without a preset collection', () {
    final result = analyzePresetSource(
      'equipment',
      <String, Object?>{},
      newSettings(),
    );
    expect(result.candidates.length, 0);
    expect(
      result.errors[0],
      matches(RegExp('equipment', caseSensitive: false)),
    );
  });

  test(
    'rejects an equipment source when one provided collection is malformed',
    () {
      final result = analyzePresetSource('equipment', <String, Object?>{
        'compressorPresets': null,
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
      }, newSettings());

      expect(result.candidates, isEmpty);
      expect(result.errors[0], contains('compressorPresets'));
    },
  );

  test(
    'merges selected new candidates immutably into matching collections',
    () {
      final settings = newSettings();
      final result = analyzePresetSource('equipment', <String, Object?>{
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
      }, settings);
      final selectedIds = result.candidates.map((c) => c.id).toList();

      final merged = mergeSelectedPresets(
        settings,
        result.candidates,
        selectedIds,
      );

      expect(merged.compressorPresets.last.name, 'Imported compressor');
      expect(merged.boosterPresets.last.name, 'Imported booster');
      expect(
        settings.compressorPresets.any(
          (preset) => preset.name == 'Imported compressor',
        ),
        false,
      );
      expect(
        identical(merged.compressorPresets, settings.compressorPresets),
        false,
      );
    },
  );

  test('rejects attempts to merge duplicate or invalid candidates', () {
    final settings = newSettings();
    final result = analyzePresetSource('gas', <Object?>[
      <String, Object?>{'name': 'Air', 'oxygenPercent': 21, 'heliumPercent': 0},
    ], settings);
    expect(
      () => mergeSelectedPresets(settings, result.candidates, <String>[
        result.candidates[0].id,
      ]),
      throwsA(isA<RangeError>()),
    );
  });

  test('exposes repository raw preset URLs', () {
    expect(
      PRESET_IMPORT_DEFAULT_URLS['gas'],
      'https://raw.githubusercontent.com/speleobrad/simplex-blender/master/presets/gas.json',
    );
    expect(
      PRESET_IMPORT_DEFAULT_URLS['cylinders'],
      'https://raw.githubusercontent.com/speleobrad/simplex-blender/master/presets/cylinders.json',
    );
    expect(
      PRESET_IMPORT_DEFAULT_URLS['equipment'],
      'https://raw.githubusercontent.com/speleobrad/simplex-blender/master/presets/equipment.json',
    );
  });

  test('repository preset files contain only valid candidates', () {
    final settings = newSettings();
    for (final entry in <List<String>>[
      <String>['gas', 'gas.json'],
      <String>['cylinders', 'cylinders.json'],
      <String>['equipment', 'equipment.json'],
    ]) {
      final source = jsonDecode(
        File('assets/presets/${entry[1]}').readAsStringSync(),
      );
      final result = analyzePresetSource(entry[0], source, settings);
      expect(result.errors, <String>[]);
      expect(result.candidates.any((c) => c.status == 'invalid'), false);
    }
  });

  test('cylinder imports default missing hot overfill and preserve explicit values', () {
    final settings = newSettings();
    final result = analyzePresetSource('cylinders', <Object?>[
      <String, Object?>{
        'name': 'Legacy cylinder',
        'volumeL': 12,
        'material': 'steel',
        'massKg': 14,
        'workingPressureBar': 232,
      },
      <String, Object?>{
        'name': 'Custom cylinder',
        'volumeL': 12,
        'material': 'steel',
        'massKg': 14,
        'workingPressureBar': 232,
        'hotOverfillPercent': 3,
      },
    ], settings);

    expect(result.candidates.map((c) => c.status).toList(), <String>[
      'new',
      'new',
    ]);
    expect(
      result.candidates.map((c) => c.preset['hotOverfillPercent']).toList(),
      <Object?>[2, 3],
    );
  });

  test('cylinder import keeps dimensions and tolerates their absence', () {
    final settings = newSettings();
    final base = settings.cylinderPresets[0].toJson();
    final withDims = withFields(base, <String, Object?>{
      'name': 'Imported with dims',
      'diameterMm': 150.5,
      'lengthMm': 600,
    });
    final withoutDims = Map<String, Object?>.of(base)
      ..['name'] = 'Imported without dims'
      ..remove('diameterMm')
      ..remove('lengthMm');
    final analysis = analyzePresetSource('cylinders', <Object?>[
      withDims,
      withoutDims,
    ], settings);
    // Both entries are importable (absent dimensions are not an error).
    expect(analysis.errors, <String>[]);
    final candidates = analysis.candidates;
    expect(candidates.map((c) => c.status).toList(), <String>['new', 'new']);
    final merged = mergeSelectedPresets(
      settings,
      candidates,
      candidates.map((c) => c.id).toList(),
    );
    final byName = {for (final p in merged.cylinderPresets) p.name: p};
    expect(byName['Imported with dims']!.diameterMm, 150.5);
    expect(byName['Imported with dims']!.lengthMm, 600);
    expect(byName['Imported without dims']!.diameterMm, isNull);
    expect(byName['Imported without dims']!.isComplete, isFalse);
  });

  test('cylinder import rejects a non-positive dimension', () {
    final settings = newSettings();
    final base = settings.cylinderPresets[0].toJson();
    final bad = withFields(base, <String, Object?>{
      'name': 'Bad dims',
      'diameterMm': 0,
      'lengthMm': 500,
    });
    final analysis = analyzePresetSource('cylinders', <Object?>[bad], settings);
    // A rejected entry stays in the analysis as 'invalid' and is not selectable.
    expect(analysis.candidates.single.status, 'invalid');
    expect(analysis.candidates.single.selectable, isFalse);
  });
}

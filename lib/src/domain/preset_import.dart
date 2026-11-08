import 'dart:convert';

import 'preset_validation.dart';
import 'settings.dart';

// ignore: constant_identifier_names
const Map<String, String> PRESET_IMPORT_DEFAULT_URLS = <String, String>{
  'gas': 'https://raw.githubusercontent.com/speleobrad/simplex-blender/master/presets/gas.json',
  'cylinders': 'https://raw.githubusercontent.com/speleobrad/simplex-blender/master/presets/cylinders.json',
  'equipment': 'https://raw.githubusercontent.com/speleobrad/simplex-blender/master/presets/equipment.json',
};

class PresetCandidate {
  const PresetCandidate({
    required this.id,
    required this.category,
    required this.collection,
    required this.preset,
    required this.status,
    required this.reason,
    required this.selectable,
  });

  final String id;
  final String category;
  final String collection;
  final Map<String, Object?> preset;

  /// One of 'new', 'duplicate', 'invalid'.
  final String status;
  final String reason;
  final bool selectable;
}

class PresetAnalysis {
  const PresetAnalysis({required this.candidates, required this.errors});

  final List<PresetCandidate> candidates;
  final List<String> errors;
}

class _CollectionDefinition {
  const _CollectionDefinition({
    required this.sourceKey,
    required this.collection,
    required this.validator,
    required this.fields,
    required this.duplicateBy,
  });

  /// Key in an equipment file; null for single-collection categories.
  final String? sourceKey;
  final String collection;
  final PresetValidator validator;
  final List<String> fields;

  /// 'name' or 'content'.
  final String duplicateBy;
}

class _CategoryDefinition {
  const _CategoryDefinition(this.collections);

  final List<_CollectionDefinition> collections;
}

final Map<String, _CategoryDefinition> _categoryDefinitions =
    <String, _CategoryDefinition>{
      'gas': _CategoryDefinition(<_CollectionDefinition>[
        _CollectionDefinition(
          sourceKey: null,
          collection: 'gasPresets',
          validator: validateGasPreset,
          fields: <String>['name', 'oxygenPercent', 'heliumPercent'],
          duplicateBy: 'content',
        ),
      ]),
      'cylinders': _CategoryDefinition(<_CollectionDefinition>[
        _CollectionDefinition(
          sourceKey: null,
          collection: 'cylinderPresets',
          validator: validateCylinderPreset,
          fields: <String>[
            'name',
            'volumeL',
            'material',
            'massKg',
            'workingPressureBar',
            'hotOverfillPercent',
            'diameterMm',
            'lengthMm',
          ],
          duplicateBy: 'name',
        ),
      ]),
      'equipment': _CategoryDefinition(<_CollectionDefinition>[
        _CollectionDefinition(
          sourceKey: 'compressorPresets',
          collection: 'compressorPresets',
          validator: validateCompressorPreset,
          fields: <String>[
            'name',
            'inletFlowLPerMin',
            'maxPressureBar',
            'temperatureModifierC',
          ],
          duplicateBy: 'name',
        ),
        _CollectionDefinition(
          sourceKey: 'boosterPresets',
          collection: 'boosterPresets',
          validator: validateBoosterPreset,
          fields: <String>[
            'name',
            'minimumSourcePressureBar',
            'cylinderVolumeCm3',
            'oxygenBoostBpm',
            'otherBoostBpm',
            'oxygenDecantRateBarPerMin',
            'otherDecantRateBarPerMin',
            'maxOutputPressureBar',
            'temperatureModifierC',
            'drainingRateBarPerMin',
          ],
          duplicateBy: 'name',
        ),
      ]),
    };

class _Entry {
  const _Entry({
    required this.definition,
    required this.preset,
    required this.index,
  });

  final _CollectionDefinition definition;
  final Object? preset;
  final int index;
}

class _SourceEntries {
  const _SourceEntries(this.entries, this.errors);

  final List<_Entry> entries;
  final List<String> errors;
}

class _KeySets {
  final Set<String> duplicateKeys = <String>{};
  final Set<String> nameKeys = <String>{};
}

_CategoryDefinition _definitionFor(String category) {
  final definition = _categoryDefinitions[category];
  if (definition == null) {
    throw RangeError('Unknown preset import category: $category');
  }
  return definition;
}

Map<String, Object?> _copyPreset(Object? source, List<String> fields) =>
    <String, Object?>{
      for (final field in fields)
        field: source is Map<String, Object?> ? source[field] : null,
    };

/// JSON-safe value as JSON.stringify emits it: non-finite numbers become
/// null, and integral doubles print without a fraction (JS prints 21.0 as 21,
/// Dart's jsonEncode prints "21.0"). Values outside the exact-integer range
/// keep their double form.
Object? _jsonSafe(Object? value) {
  if (value is double) {
    if (!value.isFinite) {
      return null;
    }
    if (value == value.truncateToDouble() && value.abs() < 9e15) {
      return value.toInt();
    }
  }
  return value;
}

String _contentKey(Map<String, Object?> preset, List<String> fields) =>
    jsonEncode(<Object?>[
      for (final field in fields.skip(1)) _jsonSafe(preset[field]),
    ]);

String _nameOf(Map<String, Object?> preset) {
  final name = preset['name'];
  return name is String ? name : '';
}

String _duplicateKey(
  Map<String, Object?> preset,
  _CollectionDefinition definition,
) => definition.duplicateBy == 'name'
    ? normalizePresetName(_nameOf(preset))
    : _contentKey(preset, definition.fields);

List<Map<String, Object?>> _existingPresets(
  Settings settings,
  String collection,
) {
  switch (collection) {
    case 'gasPresets':
      return <Map<String, Object?>>[
        for (final preset in settings.gasPresets) preset.toJson(),
      ];
    case 'cylinderPresets':
      return <Map<String, Object?>>[
        for (final preset in settings.cylinderPresets) preset.toJson(),
      ];
    case 'compressorPresets':
      return <Map<String, Object?>>[
        for (final preset in settings.compressorPresets) preset.toJson(),
      ];
    case 'boosterPresets':
      return <Map<String, Object?>>[
        for (final preset in settings.boosterPresets) preset.toJson(),
      ];
    default:
      return const <Map<String, Object?>>[];
  }
}

void _addExistingIndexes(
  Settings settings,
  _CategoryDefinition definition,
  Map<String, _KeySets> keySetsByCollection,
) {
  for (final collectionDefinition in definition.collections) {
    final keySets = _KeySets();
    for (final preset in _existingPresets(
      settings,
      collectionDefinition.collection,
    )) {
      keySets.duplicateKeys.add(_duplicateKey(preset, collectionDefinition));
      keySets.nameKeys.add(normalizePresetName(_nameOf(preset)));
    }
    keySetsByCollection[collectionDefinition.collection] = keySets;
  }
}

_SourceEntries _sourceEntries(
  String category,
  Object? source,
  _CategoryDefinition definition,
) {
  if (category == 'equipment') {
    if (source is! Map<String, Object?>) {
      return const _SourceEntries(<_Entry>[], <String>[
        'Equipment presets must be an object containing preset lists.',
      ]);
    }
    final presentCollections = definition.collections
        .where((item) => source.containsKey(item.sourceKey))
        .toList();
    if (presentCollections.isEmpty) {
      return const _SourceEntries(<_Entry>[], <String>[
        'Equipment presets must contain compressorPresets or boosterPresets.',
      ]);
    }
    final errors = <String>[];
    final entries = <_Entry>[];
    for (final collectionDefinition in presentCollections) {
      final key = collectionDefinition.sourceKey!;
      final value = source[key];
      if (value is! List<Object?>) {
        errors.add('$key must be an array.');
        continue;
      }
      for (var index = 0; index < value.length; index++) {
        entries.add(
          _Entry(
            definition: collectionDefinition,
            preset: value[index],
            index: index,
          ),
        );
      }
    }
    return errors.isNotEmpty
        ? _SourceEntries(const <_Entry>[], errors)
        : _SourceEntries(entries, errors);
  }

  if (source is! List<Object?>) {
    final label = category == 'gas' ? 'Gas' : 'Cylinder';
    return _SourceEntries(const <_Entry>[], <String>[
      '$label presets must be an array.',
    ]);
  }
  final collectionDefinition = definition.collections.first;
  return _SourceEntries(<_Entry>[
    for (var index = 0; index < source.length; index++)
      _Entry(
        definition: collectionDefinition,
        preset: source[index],
        index: index,
      ),
  ], const <String>[]);
}

PresetAnalysis analyzePresetSource(
  String category,
  Object? source,
  Settings settings,
) {
  final definition = _definitionFor(category);
  final sourceResult = _sourceEntries(category, source, definition);
  final keySetsByCollection = <String, _KeySets>{};
  _addExistingIndexes(settings, definition, keySetsByCollection);
  final candidates = <PresetCandidate>[];

  for (final entry in sourceResult.entries) {
    final collectionDefinition = entry.definition;
    final preset = _copyPreset(entry.preset, collectionDefinition.fields);
    if (collectionDefinition.collection == 'cylinderPresets' &&
        preset['hotOverfillPercent'] == null) {
      preset['hotOverfillPercent'] = DEFAULT_HOT_OVERFILL_PERCENT;
    }
    final validationErrors = collectionDefinition.validator(preset);
    var status = 'invalid';
    var reason = validationErrors.join(' ');
    var selectable = false;
    if (validationErrors.isEmpty) {
      final keySets = keySetsByCollection[collectionDefinition.collection]!;
      final key = _duplicateKey(preset, collectionDefinition);
      final nameKey = normalizePresetName(_nameOf(preset));
      if (collectionDefinition.duplicateBy == 'content' &&
          keySets.nameKeys.contains(nameKey) &&
          !keySets.duplicateKeys.contains(key)) {
        reason =
            'An entry with the same name but different content already exists.';
      } else if (keySets.duplicateKeys.contains(key)) {
        status = 'duplicate';
        reason = collectionDefinition.duplicateBy == 'name'
            ? 'An entry with the same name already exists.'
            : 'An entry with the same content already exists.';
      } else {
        status = 'new';
        reason = 'Ready to import.';
        selectable = true;
        keySets.duplicateKeys.add(key);
      }
      keySets.nameKeys.add(nameKey);
    }
    candidates.add(
      PresetCandidate(
        id: '${collectionDefinition.collection}:${entry.index}',
        category: category,
        collection: collectionDefinition.collection,
        preset: preset,
        status: status,
        reason: reason,
        selectable: selectable,
      ),
    );
  }

  return PresetAnalysis(candidates: candidates, errors: sourceResult.errors);
}

double _numberField(Map<String, Object?> preset, String key) =>
    (preset[key]! as num).toDouble();

GasPreset _gasPresetFrom(Map<String, Object?> preset) => GasPreset(
  name: preset['name']! as String,
  oxygenPercent: _numberField(preset, 'oxygenPercent'),
  heliumPercent: _numberField(preset, 'heliumPercent'),
);

CylinderPreset _cylinderPresetFrom(Map<String, Object?> preset) =>
    CylinderPreset(
      name: preset['name']! as String,
      volumeL: _numberField(preset, 'volumeL'),
      material: preset['material']! as String,
      massKg: _numberField(preset, 'massKg'),
      workingPressureBar: _numberField(preset, 'workingPressureBar'),
      hotOverfillPercent: _numberField(preset, 'hotOverfillPercent'),
      diameterMm: (preset['diameterMm'] as num?)?.toDouble(),
      lengthMm: (preset['lengthMm'] as num?)?.toDouble(),
    );

CompressorPreset _compressorPresetFrom(Map<String, Object?> preset) =>
    CompressorPreset(
      name: preset['name']! as String,
      inletFlowLPerMin: _numberField(preset, 'inletFlowLPerMin'),
      maxPressureBar: _numberField(preset, 'maxPressureBar'),
      temperatureModifierC: _numberField(preset, 'temperatureModifierC'),
    );

BoosterPreset _boosterPresetFrom(Map<String, Object?> preset) => BoosterPreset(
  name: preset['name']! as String,
  minimumSourcePressureBar: _numberField(preset, 'minimumSourcePressureBar'),
  cylinderVolumeCm3: _numberField(preset, 'cylinderVolumeCm3'),
  oxygenBoostBpm: _numberField(preset, 'oxygenBoostBpm'),
  otherBoostBpm: _numberField(preset, 'otherBoostBpm'),
  oxygenDecantRateBarPerMin: _numberField(preset, 'oxygenDecantRateBarPerMin'),
  otherDecantRateBarPerMin: _numberField(preset, 'otherDecantRateBarPerMin'),
  maxOutputPressureBar: _numberField(preset, 'maxOutputPressureBar'),
  temperatureModifierC: _numberField(preset, 'temperatureModifierC'),
  drainingRateBarPerMin: _numberField(preset, 'drainingRateBarPerMin'),
);

/// Returns a new [Settings] with every selected candidate appended to its
/// collection. The input [settings] is never modified.
Settings mergeSelectedPresets(
  Settings settings,
  List<PresetCandidate> candidates,
  Iterable<String> selectedIds,
) {
  final selected = selectedIds.toSet();
  final byId = <String, PresetCandidate>{
    for (final candidate in candidates) candidate.id: candidate,
  };
  final gasPresets = List<GasPreset>.of(settings.gasPresets);
  final compressorPresets = List<CompressorPreset>.of(
    settings.compressorPresets,
  );
  final boosterPresets = List<BoosterPreset>.of(settings.boosterPresets);
  final cylinderPresets = List<CylinderPreset>.of(settings.cylinderPresets);
  for (final id in selected) {
    final candidate = byId[id];
    if (candidate == null ||
        candidate.status != 'new' ||
        !candidate.selectable) {
      throw RangeError('Only new valid presets can be imported.');
    }
    switch (candidate.collection) {
      case 'gasPresets':
        gasPresets.add(_gasPresetFrom(candidate.preset));
      case 'cylinderPresets':
        cylinderPresets.add(_cylinderPresetFrom(candidate.preset));
      case 'compressorPresets':
        compressorPresets.add(_compressorPresetFrom(candidate.preset));
      case 'boosterPresets':
        boosterPresets.add(_boosterPresetFrom(candidate.preset));
      default:
        throw RangeError('Unknown preset collection: ${candidate.collection}');
    }
  }
  final merged = settings.copyWith(
    gasPresets: gasPresets,
    compressorPresets: compressorPresets,
    boosterPresets: boosterPresets,
    cylinderPresets: cylinderPresets,
  );
  final errors = validateSettings(merged);
  if (errors.isNotEmpty) {
    throw RangeError(errors.join(' '));
  }
  return merged;
}

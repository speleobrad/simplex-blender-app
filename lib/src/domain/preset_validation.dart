/// Port of `js/preset-validation.js`.
///
/// Preset values arrive as decoded JSON, so every validator accepts `Object?`
/// and checks types at runtime exactly as the JS `Number.isFinite` and
/// `typeof` checks do.
library;

import 'package:simplex_blender/src/domain/gas_input.dart';
import 'package:simplex_blender/src/domain/materials.dart';

// ignore: constant_identifier_names
const double DEFAULT_HOT_OVERFILL_PERCENT = 2;

/// Lower-camel alias used by `pressure_limits.dart`.
const double defaultHotOverfillPercent = DEFAULT_HOT_OVERFILL_PERCENT;

typedef PresetValidator = List<String> Function(Object? preset);

bool isValidHotOverfillPercent(double? value) {
  if (value == null || !value.isFinite) return false;
  if (value < 0 || value > 5) return false;
  final doubled = value * 2;
  return doubled == doubled.truncateToDouble();
}

Map<String, Object?>? _asMap(Object? preset) {
  return preset is Map<String, Object?> ? preset : null;
}

/// Mirrors JS `preset?.name ?? ''` interpolation.
String _nameText(Map<String, Object?>? preset) {
  final name = preset?['name'];
  return name == null ? '' : name.toString();
}

/// Mirrors `Number.isFinite(x)` for decoded JSON values: only `num` qualifies.
double? _numField(Map<String, Object?>? preset, String key) {
  final value = preset?[key];
  if (value is num) return value.toDouble();
  return null;
}

/// True when the value is a finite number within `[minimum, maximum]`.
bool _inRange(double? value, num minimum, num maximum) {
  return value != null &&
      value.isFinite &&
      value >= minimum &&
      value <= maximum;
}

List<String> _validateNamedPreset(String category, Object? preset) {
  final map = _asMap(preset);
  final name = map?['name'];
  if (name is String && name.trim().isNotEmpty) return <String>[];
  return <String>['Every $category preset needs a name.'];
}

List<String> validateGasPreset(Object? preset) {
  final errors = _validateNamedPreset('gas', preset);
  final map = _asMap(preset);
  if (map == null ||
      !isValidGasComposition(
        _numField(map, 'oxygenPercent'),
        _numField(map, 'heliumPercent'),
      )) {
    errors.add(
      'Gas preset “${_nameText(map)}” must total at most 100% O₂ and He.',
    );
  }
  return errors;
}

List<String> validateCylinderPreset(Object? preset) {
  final errors = _validateNamedPreset('cylinder', preset);
  final map = _asMap(preset);
  final name = _nameText(map);
  final volume = _numField(map, 'volumeL');
  if (map == null || volume == null || !volume.isFinite || volume < 0.1) {
    errors.add('Cylinder preset “$name” volume must be at least 0.1 L.');
  }
  if (map == null || !isValidMaterial(map['material'])) {
    errors.add(
      'Cylinder preset “$name” material must be ${materialListText()}.',
    );
  }
  final mass = _numField(map, 'massKg');
  if (map == null || mass == null || !mass.isFinite || mass <= 0) {
    errors.add('Cylinder preset “$name” mass must be greater than 0 kg.');
  }
  if (!_inRange(_numField(map, 'workingPressureBar'), 10, 350)) {
    errors.add(
      'Cylinder preset “$name” working pressure must be between 10 and 350 bar.',
    );
  }
  if (map == null ||
      !isValidHotOverfillPercent(_numField(map, 'hotOverfillPercent'))) {
    errors.add(
      'Cylinder preset “$name” hot overfill must be between 0 and 5% in 0.5% steps.',
    );
  }
  return errors;
}

List<String> validateCompressorPreset(Object? preset) {
  final errors = _validateNamedPreset('compressor', preset);
  final map = _asMap(preset);
  if (!_inRange(_numField(map, 'inletFlowLPerMin'), 0.1, 10000)) {
    errors.add('Compressor inlet flow must be between 0.1 and 10000 L/min.');
  }
  if (!_inRange(_numField(map, 'maxPressureBar'), 10, 350)) {
    errors.add('Maximum compressor pressure must be between 10 and 350 bar.');
  }
  if (!_inRange(_numField(map, 'temperatureModifierC'), -100, 100)) {
    errors.add(
      'Compressor temperature modifier must be between -100 and 100°C.',
    );
  }
  return errors;
}

/// (field, minimum, maximum, label, unit) — same order as the JS table.
const List<(String, num, num, String, String)> _boosterRanges =
    <(String, num, num, String, String)>[
      ('cylinderVolumeCm3', 0.1, 1000, 'Booster cylinder volume', 'cm³'),
      (
        'minimumSourcePressureBar',
        0,
        100,
        'Booster minimum source pressure',
        'bar',
      ),
      ('oxygenBoostBpm', 1, 1000, 'Oxygen booster speed', 'BPM'),
      ('otherBoostBpm', 1, 1000, 'Other-gas booster speed', 'BPM'),
      (
        'maxOutputPressureBar',
        10,
        350,
        'Maximum booster output pressure',
        'bar',
      ),
      ('temperatureModifierC', -100, 100, 'Booster temperature modifier', '°C'),
      (
        'oxygenDecantRateBarPerMin',
        0.01,
        1000,
        'Oxygen manual decant rate',
        'bar/min',
      ),
      (
        'otherDecantRateBarPerMin',
        0.01,
        1000,
        'Other-gas manual decant rate',
        'bar/min',
      ),
      ('drainingRateBarPerMin', 0.01, 1000, 'Draining rate', 'bar/min'),
    ];

List<String> validateBoosterPreset(Object? preset) {
  final errors = _validateNamedPreset('booster', preset);
  final map = _asMap(preset);
  for (final (field, minimum, maximum, label, unit) in _boosterRanges) {
    if (!_inRange(_numField(map, field), minimum, maximum)) {
      errors.add('$label must be between $minimum and $maximum $unit.');
    }
  }
  return errors;
}

const Map<String, PresetValidator> categoryValidators =
    <String, PresetValidator>{
      'gasPresets': validateGasPreset,
      'cylinderPresets': validateCylinderPreset,
      'compressorPresets': validateCompressorPreset,
      'boosterPresets': validateBoosterPreset,
    };

/// Throws [RangeError] for an unknown category, like the JS `RangeError`.
List<String> validatePreset(String category, Object? preset) {
  final validator = categoryValidators[category];
  if (validator == null) {
    throw RangeError('Unknown preset category: $category');
  }
  return validator(preset);
}

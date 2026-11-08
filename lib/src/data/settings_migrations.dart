import 'package:simplex_blender/src/domain/js_number.dart';
import 'package:simplex_blender/src/domain/preset_validation.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/settings_json.dart';

// Ports of the migration helpers in JS `js/settings.js`. Each function takes a
// raw decoded settings object and returns a new one; the input is never
// mutated. Migrations use `containsKey` where JS uses `Object.hasOwn`, so a
// present `null` is kept as-is and only an absent key takes the default.

/// Text used for `${volume}` in JS template literals.
String _templateText(Object? value) =>
    value is num ? jsNumberString(value.toDouble()) : '$value';

/// Port of JS `legacyVolumePresetsToCylinders`.
List<Map<String, Object?>> legacyVolumePresetsToCylinders(
  List<Object?> volumePresets,
) {
  return volumePresets
      .map(
        (volume) => <String, Object?>{
          'name': '${_templateText(volume)} L Steel 232 bar',
          'volumeL': volume,
          'material': 'steel',
          'massKg': 14,
          'workingPressureBar': 232,
          'hotOverfillPercent': DEFAULT_HOT_OVERFILL_PERCENT,
        },
      )
      .toList();
}

/// Copies a cylinder preset (JS `{ ...preset }`) and fills `hotOverfillPercent`
/// only when the key is absent. A non-object preset becomes an object holding
/// only the default, which fails validation exactly as the JS spread does.
Map<String, Object?> _withHotOverfillDefault(Object? preset) {
  final copy = <String, Object?>{...?asJsonObject(preset)};
  if (!copy.containsKey('hotOverfillPercent')) {
    copy['hotOverfillPercent'] = DEFAULT_HOT_OVERFILL_PERCENT;
  }
  return copy;
}

/// Port of JS `addDefaultCylinderPresets`.
Map<String, Object?> addDefaultCylinderPresets(Map<String, Object?> settings) {
  final cylinders = settings['cylinderPresets'];
  final volumes = settings['volumePresets'];
  final Object? sourcePresets;
  if (cylinders is List<Object?>) {
    sourcePresets = cylinders;
  } else if (volumes is List<Object?>) {
    sourcePresets = legacyVolumePresetsToCylinders(volumes);
  } else {
    sourcePresets = null;
  }
  final cylinderPresets = sourcePresets is List<Object?>
      ? sourcePresets.map(_withHotOverfillDefault).toList()
      : sourcePresets;
  return <String, Object?>{...settings, 'cylinderPresets': cylinderPresets};
}

bool _hasDimensionKey(Map<String, Object?> preset) =>
    preset.containsKey('diameterMm') || preset.containsKey('lengthMm');

/// The built-in `Luxfer S80` entry as it was stored before its volume was
/// corrected from 10.6 L to 11.1 L (Luxfer LAL80 sheet).
bool _isUncorrectedLuxferS80(Map<String, Object?> preset) =>
    preset['name'] == 'Luxfer S80' &&
    preset['volumeL'] == 10.6 &&
    preset['material'] == 'aluminum' &&
    preset['massKg'] == 13.7 &&
    preset['workingPressureBar'] == 217 &&
    preset['hotOverfillPercent'] == DEFAULT_HOT_OVERFILL_PERCENT &&
    !_hasDimensionKey(preset);

/// Updates a stored, untouched built-in `Luxfer S80` from 10.6 L to 11.1 L.
/// A preset edited in any field, or under another name, is left alone.
/// Must run after [addDefaultCylinderPresets] and before
/// [addNearestCylinderDimensions].
Map<String, Object?> correctLuxferS80Volume(Map<String, Object?> settings) {
  final cylinders = settings['cylinderPresets'];
  if (cylinders is! List<Object?>) return settings;
  return <String, Object?>{
    ...settings,
    'cylinderPresets': <Object?>[
      for (final preset in cylinders)
        if (asJsonObject(preset) case final map?
            when _isUncorrectedLuxferS80(map))
          <String, Object?>{...map, 'volumeL': 11.1}
        else
          preset,
    ],
  };
}

/// Names of presets touched by [addNearestCylinderDimensions].
class CylinderDimensionMigration {
  const CylinderDimensionMigration({
    required this.matched,
    required this.incomplete,
  });

  /// Presets that received dimensions from the nearest standard cylinder.
  final List<String> matched;

  /// Presets that stay without dimensions and need user entry.
  final List<String> incomplete;
}

/// Closest built-in default for a legacy preset. Aluminium takes the nearest
/// volume with no cutoff. Every other material needs an exactly equal volume.
/// Ties go to the same name, then the smaller volume, then the earlier default.
CylinderPreset? _nearestStandard(
  Object? name,
  String material,
  double volumeL,
) {
  final exactOnly = material != 'aluminum';
  final candidates = <(double, int, double, int, CylinderPreset)>[];
  final defaults = DEFAULT_SETTINGS.cylinderPresets;
  for (var i = 0; i < defaults.length; i++) {
    final candidate = defaults[i];
    if (candidate.material != material) continue;
    final distance = (candidate.volumeL - volumeL).abs();
    if (exactOnly && distance != 0) continue;
    candidates.add((
      distance,
      candidate.name == name ? 0 : 1,
      candidate.volumeL,
      i,
      candidate,
    ));
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final byDistance = a.$1.compareTo(b.$1);
    if (byDistance != 0) return byDistance;
    final byName = a.$2.compareTo(b.$2);
    if (byName != 0) return byName;
    final byVolume = a.$3.compareTo(b.$3);
    if (byVolume != 0) return byVolume;
    return a.$4.compareTo(b.$4);
  });
  return candidates.first.$5;
}

/// Gives legacy presets (neither dimension key present) the dimensions of the
/// nearest standard cylinder, and reports which presets changed and which
/// remain without dimensions. A preset with either key present, including an
/// explicit `null`, is never changed.
({Map<String, Object?> settings, CylinderDimensionMigration report})
applyNearestCylinderDimensions(Map<String, Object?> settings) {
  final cylinders = settings['cylinderPresets'];
  final matched = <String>[];
  final incomplete = <String>[];
  if (cylinders is! List<Object?>) {
    return (
      settings: settings,
      report: const CylinderDimensionMigration(
        matched: <String>[],
        incomplete: <String>[],
      ),
    );
  }
  final migrated = <Object?>[];
  for (final preset in cylinders) {
    final map = asJsonObject(preset);
    final volume = map?['volumeL'];
    final material = map?['material'];
    if (map == null ||
        _hasDimensionKey(map) ||
        volume is! num ||
        !volume.isFinite ||
        material is! String) {
      migrated.add(preset);
      continue;
    }
    final name = map['name'];
    final standard = _nearestStandard(name, material, volume.toDouble());
    if (standard == null) {
      if (name is String) incomplete.add(name);
      migrated.add(preset);
      continue;
    }
    if (name is String) matched.add(name);
    migrated.add(<String, Object?>{
      ...map,
      'diameterMm': standard.diameterMm,
      'lengthMm': standard.lengthMm,
    });
  }
  return (
    settings: <String, Object?>{...settings, 'cylinderPresets': migrated},
    report: CylinderDimensionMigration(
      matched: matched,
      incomplete: incomplete,
    ),
  );
}

Map<String, Object?> addNearestCylinderDimensions(
  Map<String, Object?> settings,
) => applyNearestCylinderDimensions(settings).settings;

/// One-time notice text for a load that migrated dimensions.
String cylinderMigrationNoticeMessage(CylinderDimensionMigration report) {
  final count = report.matched.length;
  final noun = count == 1 ? 'preset' : 'presets';
  final buffer = StringBuffer(
    'Diameter and length were set for $count saved cylinder $noun from the '
    'nearest standard cylinder: ${report.matched.join(', ')}. Check them in '
    'Settings > Cylinder presets.',
  );
  final open = report.incomplete.length;
  if (open > 0) {
    final verb = open == 1 ? 'preset still needs' : 'presets still need';
    buffer.write(
      ' $open $verb a diameter and length: ${report.incomplete.join(', ')}.',
    );
  }
  return buffer.toString();
}

/// Port of JS `addDefaultBooster`. A non-object `booster` (including arrays)
/// is replaced by an empty object before merging with the defaults.
Map<String, Object?> addDefaultBooster(Map<String, Object?> settings) {
  final booster = asJsonObject(settings['booster']) ?? <String, Object?>{};
  return <String, Object?>{
    ...settings,
    'booster': <String, Object?>{
      ...settingsBoosterToJson(DEFAULT_SETTINGS.booster),
      ...booster,
    },
  };
}

/// Port of JS `addDefaultUnits`: any value other than `imperial` becomes
/// `metric`.
Map<String, Object?> addDefaultUnits(Map<String, Object?> settings) {
  return <String, Object?>{
    ...settings,
    'units': settings['units'] == 'imperial'
        ? 'imperial'
        : DEFAULT_SETTINGS.units,
  };
}

/// Port of JS `addDefaultPressureLimitPolicy`.
Map<String, Object?> addDefaultPressureLimitPolicy(
  Map<String, Object?> settings,
) {
  return <String, Object?>{
    ...settings,
    'pressureLimitMode': settings.containsKey('pressureLimitMode')
        ? settings['pressureLimitMode']
        : DEFAULT_SETTINGS.pressureLimitMode,
    'pressureWarningUnlocked': settings.containsKey('pressureWarningUnlocked')
        ? settings['pressureWarningUnlocked']
        : DEFAULT_SETTINGS.pressureWarningUnlocked,
  };
}

/// Port of JS `addDefaultInterimPressureTolerance`.
Map<String, Object?> addDefaultInterimPressureTolerance(
  Map<String, Object?> settings,
) {
  return <String, Object?>{
    ...settings,
    'interimPressureTolerancePercent':
        settings.containsKey('interimPressureTolerancePercent')
        ? settings['interimPressureTolerancePercent']
        : DEFAULT_SETTINGS.interimPressureTolerancePercent,
  };
}

/// Port of JS `addDefaultCosts`. A `null` or absent `costs` takes the default.
Map<String, Object?> addDefaultCosts(Map<String, Object?> settings) {
  return <String, Object?>{
    ...settings,
    'costs': copyCosts(
      settings['costs'] ?? costsToJson(DEFAULT_SETTINGS.costs),
    ),
  };
}

/// Port of JS `feeOrZero`: an absent fee loads as 0; a present value is kept
/// and validated later.
Object? _feeOrZero(Map<String, Object?> prices, String key) {
  return prices.containsKey(key) ? prices[key] : 0;
}

/// Port of JS `copyCosts`. Non-object `costs` or `operationPrices` are treated
/// as absent. Legacy per-litre keys are ignored.
Map<String, Object?> copyCosts(Object? costs) {
  final map = asJsonObject(costs) ?? const <String, Object?>{};
  final currencySymbol = map['currencySymbol'];
  final prices =
      asJsonObject(map['operationPrices']) ?? const <String, Object?>{};
  return <String, Object?>{
    'currencySymbol': currencySymbol is String
        ? currencySymbol.trim()
        : currencySymbol,
    'leftoverDiscountPercent': map['leftoverDiscountPercent'],
    'operationPrices': <String, Object?>{
      'boost': _feeOrZero(prices, 'boost'),
      'decant': _feeOrZero(prices, 'decant'),
      'topUp': _feeOrZero(prices, 'topUp'),
    },
  };
}

/// Port of JS `addDefaultPhysics`.
Map<String, Object?> addDefaultPhysics(Map<String, Object?> settings) {
  final physics = asJsonObject(settings['physics']) ?? <String, Object?>{};
  return <String, Object?>{
    ...settings,
    'physics': <String, Object?>{
      ...physicsToJson(DEFAULT_SETTINGS.physics),
      ...physics,
    },
  };
}

/// Port of JS `addDefaultEquipmentPresets`. Must run after
/// [addDefaultBooster], so `booster` is an object. A missing preset list is
/// seeded with one standard preset built from the booster values.
Map<String, Object?> addDefaultEquipmentPresets(Map<String, Object?> settings) {
  final booster = settings['booster'] as Map<String, Object?>;
  final compressorPresets = settings.containsKey('compressorPresets')
      ? settings['compressorPresets']
      : <Object?>[
          <String, Object?>{
            'name': 'Standard compressor',
            'inletFlowLPerMin': booster['compressorInletFlowLPerMin'],
            'maxPressureBar': booster['maxCompressorPressureBar'],
            'temperatureModifierC': booster['compressorTemperatureModifierC'],
          },
        ];
  final boosterPresets = settings.containsKey('boosterPresets')
      ? settings['boosterPresets']
      : <Object?>[
          <String, Object?>{
            'name': 'Standard booster',
            'minimumSourcePressureBar': booster['minimumSourcePressureBar'],
            'cylinderVolumeCm3': booster['cylinderVolumeCm3'],
            'oxygenBoostBpm': booster['oxygenBoostBpm'],
            'otherBoostBpm': booster['otherBoostBpm'],
            'oxygenDecantRateBarPerMin': booster['oxygenDecantRateBarPerMin'],
            'otherDecantRateBarPerMin': booster['otherDecantRateBarPerMin'],
            'maxOutputPressureBar': booster['maxBoosterOutputPressureBar'],
            'temperatureModifierC': booster['boosterTemperatureModifierC'],
            'drainingRateBarPerMin': booster['drainingRateBarPerMin'],
          },
        ];
  return <String, Object?>{
    ...settings,
    'compressorPresets': compressorPresets,
    'boosterPresets': boosterPresets,
  };
}

/// Applies every migration and also reports the cylinder dimension changes.
({Map<String, Object?> settings, CylinderDimensionMigration report})
normalizeSettingsJsonWithReport(Map<String, Object?> saved) {
  final withBooster = addDefaultBooster(saved);
  final withUnits = addDefaultUnits(withBooster);
  final withPressurePolicy = addDefaultPressureLimitPolicy(withUnits);
  final withPhysics = addDefaultPhysics(withPressurePolicy);
  final withCylinders = addDefaultCylinderPresets(withPhysics);
  final withLuxferVolume = correctLuxferS80Volume(withCylinders);
  final withDimensions = applyNearestCylinderDimensions(withLuxferVolume);
  final withEquipment = addDefaultEquipmentPresets(withDimensions.settings);
  final withTolerance = addDefaultInterimPressureTolerance(withEquipment);
  return (
    settings: addDefaultCosts(withTolerance),
    report: withDimensions.report,
  );
}

/// Applies every migration in the order JS `loadSettings` and `saveSettings`
/// use. The result still needs [validateSettingsJson] before it is parsed.
Map<String, Object?> normalizeSettingsJson(Map<String, Object?> saved) =>
    normalizeSettingsJsonWithReport(saved).settings;

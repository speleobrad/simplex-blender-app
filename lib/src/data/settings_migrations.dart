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

/// Applies every migration in the order JS `loadSettings` and `saveSettings`
/// use. The result still needs [validateSettingsJson] before it is parsed.
Map<String, Object?> normalizeSettingsJson(Map<String, Object?> saved) {
  final withBooster = addDefaultBooster(saved);
  final withUnits = addDefaultUnits(withBooster);
  final withPressurePolicy = addDefaultPressureLimitPolicy(withUnits);
  final withPhysics = addDefaultPhysics(withPressurePolicy);
  final withCylinders = addDefaultCylinderPresets(withPhysics);
  final withEquipment = addDefaultEquipmentPresets(withCylinders);
  final withTolerance = addDefaultInterimPressureTolerance(withEquipment);
  return addDefaultCosts(withTolerance);
}

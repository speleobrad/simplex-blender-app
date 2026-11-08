import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/input_validation.dart';
import 'package:simplex_blender/src/domain/preset_validation.dart';
import 'package:simplex_blender/src/domain/settings.dart';

/// Returns the map when [value] is a JSON object, otherwise null.
Map<String, Object?>? asJsonObject(Object? value) =>
    value is Map<String, Object?> ? value : null;

/// Mirrors `Number.isFinite(x)` on a decoded JSON value, then applies the
/// inclusive range check used by the JS validators.
bool _numberInRange(Object? value, num minimum, num maximum) {
  if (value is! num) return false;
  final number = value.toDouble();
  return number.isFinite && number >= minimum && number <= maximum;
}

/// Validates a settings object in its raw decoded JSON form. Port of JS
/// `validateSettings`: the input is the normalized object produced by the
/// migration chain, so every value is checked exactly as stored.
List<String> validateSettingsJson(Map<String, Object?> settings) {
  final gasPresets = settings['gasPresets'];
  final cylinderPresets = settings['cylinderPresets'];
  if (gasPresets is! List<Object?> || cylinderPresets is! List<Object?>) {
    return <String>['Settings must contain gas and cylinder preset lists.'];
  }
  final errors = <String>[];
  if (gasPresets.isEmpty) {
    errors.add('At least one gas preset is required.');
  }
  final units = settings['units'];
  if (units != 'metric' && units != 'imperial') {
    errors.add('Units must be either metric or imperial.');
  }
  final pressureLimitMode = settings['pressureLimitMode'];
  if (pressureLimitMode != 'hard-stop' && pressureLimitMode != 'warning') {
    errors.add('Pressure limit mode must be either hard-stop or warning.');
  }
  final pressureWarningUnlocked = settings['pressureWarningUnlocked'];
  if (pressureWarningUnlocked is! bool) {
    errors.add('Pressure warning unlock must be boolean.');
  }
  if (pressureLimitMode == 'warning' && pressureWarningUnlocked != true) {
    errors.add('Pressure warning mode requires an unlock.');
  }
  if (!_numberInRange(settings['interimPressureTolerancePercent'], 0.5, 10)) {
    errors.add('Interim pressure tolerance must be between 0.5 and 10%.');
  }
  if (cylinderPresets.isEmpty) {
    errors.add('At least one cylinder preset is required.');
  }
  final model = asJsonObject(settings['physics'])?['model'];
  if (model != 'ideal' && model != 'vdw') {
    errors.add('Gas model must be either ideal or vdw.');
  }
  final booster = asJsonObject(settings['booster']);
  for (final check in _boosterScalarChecks) {
    if (!_numberInRange(booster?[check.field], check.minimum, check.maximum)) {
      errors.add(check.message);
    }
  }
  errors.addAll(
    validatePresetCollectionJson(
      settings['compressorPresets'],
      'compressor',
      validateCompressorPreset,
    ),
  );
  errors.addAll(
    validatePresetCollectionJson(
      settings['boosterPresets'],
      'booster',
      validateBoosterPreset,
    ),
  );
  errors.addAll(
    _namedPresetLoopErrors(
      gasPresets,
      validateGasPreset,
      'Gas preset names must be unique.',
    ),
  );
  errors.addAll(
    _namedPresetLoopErrors(
      cylinderPresets,
      validateCylinderPreset,
      'Cylinder preset names must be unique.',
    ),
  );
  errors.addAll(validateCostSettings(settings['costs']));
  return errors;
}

typedef _ScalarCheck = ({
  String field,
  num minimum,
  num maximum,
  String message,
});

/// Booster scalar checks, in JS `validateSettings` order.
const List<_ScalarCheck> _boosterScalarChecks = <_ScalarCheck>[
  (
    field: 'minimumSourcePressureBar',
    minimum: 0,
    maximum: 100,
    message: 'Booster minimum source pressure must be between 0 and 100 bar.',
  ),
  (
    field: 'cylinderVolumeCm3',
    minimum: 0.1,
    maximum: 1000,
    message: 'Booster cylinder volume must be between 0.1 and 1000 cm³.',
  ),
  (
    field: 'oxygenBoostBpm',
    minimum: 1,
    maximum: 1000,
    message: 'Oxygen booster speed must be between 1 and 1000 BPM.',
  ),
  (
    field: 'otherBoostBpm',
    minimum: 1,
    maximum: 1000,
    message: 'Other-gas booster speed must be between 1 and 1000 BPM.',
  ),
  (
    field: 'oxygenDecantRateBarPerMin',
    minimum: 0.01,
    maximum: 1000,
    message: 'Oxygen manual decant rate must be between 0.01 and 1000 bar/min.',
  ),
  (
    field: 'otherDecantRateBarPerMin',
    minimum: 0.01,
    maximum: 1000,
    message:
        'Other-gas manual decant rate must be between 0.01 and 1000 bar/min.',
  ),
  (
    field: 'drainingRateBarPerMin',
    minimum: 0.01,
    maximum: 1000,
    message: 'Draining rate must be between 0.01 and 1000 bar/min.',
  ),
  (
    field: 'compressorInletFlowLPerMin',
    minimum: 0.1,
    maximum: 10000,
    message: 'Compressor inlet flow must be between 0.1 and 10000 L/min.',
  ),
  (
    field: 'maxCompressorPressureBar',
    minimum: 10,
    maximum: 350,
    message: 'Maximum compressor pressure must be between 10 and 350 bar.',
  ),
  (
    field: 'maxBoosterOutputPressureBar',
    minimum: 10,
    maximum: 350,
    message: 'Maximum booster output pressure must be between 10 and 350 bar.',
  ),
  (
    field: 'boosterTemperatureModifierC',
    minimum: -100,
    maximum: 100,
    message: 'Booster temperature modifier must be between -100 and 100°C.',
  ),
  (
    field: 'compressorTemperatureModifierC',
    minimum: -100,
    maximum: 100,
    message: 'Compressor temperature modifier must be between -100 and 100°C.',
  ),
];

/// Port of JS `validatePresetCollection`.
List<String> validatePresetCollectionJson(
  Object? presets,
  String category,
  PresetValidator validator,
) {
  if (presets is! List<Object?>) {
    return <String>['Settings must contain a $category preset list.'];
  }
  if (presets.isEmpty) {
    return <String>['At least one $category preset is required.'];
  }
  final capitalized = '${category[0].toUpperCase()}${category.substring(1)}';
  return _namedPresetLoopErrors(
    presets,
    validator,
    '$capitalized preset names must be unique.',
  );
}

/// Shared loop of JS `validatePresetCollection` and the gas and cylinder
/// loops in `validateSettings`. Presets without a usable name contribute only
/// their "needs a name" errors and are excluded from the duplicate check.
List<String> _namedPresetLoopErrors(
  List<Object?> presets,
  PresetValidator validator,
  String duplicateMessage,
) {
  final errors = <String>[];
  final names = <String>{};
  for (final preset in presets) {
    final presetErrors = validator(preset);
    final name = asJsonObject(preset)?['name'];
    if (name is! String || name.trim().isEmpty) {
      errors.addAll(
        presetErrors.where((error) => error.contains('needs a name')),
      );
      continue;
    }
    final normalizedName = normalizePresetName(name);
    if (names.contains(normalizedName)) {
      errors.add(duplicateMessage);
    }
    names.add(normalizedName);
    errors.addAll(presetErrors);
  }
  return errors;
}

// ---------------------------------------------------------------------------
// Typed parsing. Callers must validate with [validateSettingsJson] first; the
// parsers then only convert values that the validators have already checked.
// ---------------------------------------------------------------------------

double _toDouble(Map<String, Object?> json, String key) {
  return (json[key] as num).toDouble();
}

/// Absent or `null` becomes null; a number becomes a double. The validators
/// run first, so a present value is a finite positive number or the settings
/// were rejected.
double? _optionalDouble(Map<String, Object?> json, String key) {
  return (json[key] as num?)?.toDouble();
}

Map<String, Object?> _map(Map<String, Object?> json, String key) {
  return json[key] as Map<String, Object?>;
}

List<Object?> _list(Map<String, Object?> json, String key) {
  return json[key] as List<Object?>;
}

/// Parses a validated `gasPresets` entry.
GasPreset gasPresetFromJson(Map<String, Object?> json) => GasPreset(
  name: json['name'] as String,
  oxygenPercent: _toDouble(json, 'oxygenPercent'),
  heliumPercent: _toDouble(json, 'heliumPercent'),
);

/// Parses a validated `cylinderPresets` entry.
CylinderPreset cylinderPresetFromJson(Map<String, Object?> json) =>
    CylinderPreset(
      name: json['name'] as String,
      volumeL: _toDouble(json, 'volumeL'),
      material: json['material'] as String,
      massKg: _toDouble(json, 'massKg'),
      workingPressureBar: _toDouble(json, 'workingPressureBar'),
      hotOverfillPercent: _toDouble(json, 'hotOverfillPercent'),
      diameterMm: _optionalDouble(json, 'diameterMm'),
      lengthMm: _optionalDouble(json, 'lengthMm'),
    );

/// Parses a validated `compressorPresets` entry.
CompressorPreset compressorPresetFromJson(Map<String, Object?> json) =>
    CompressorPreset(
      name: json['name'] as String,
      inletFlowLPerMin: _toDouble(json, 'inletFlowLPerMin'),
      maxPressureBar: _toDouble(json, 'maxPressureBar'),
      temperatureModifierC: _toDouble(json, 'temperatureModifierC'),
    );

/// Parses a validated `boosterPresets` entry.
BoosterPreset boosterPresetFromJson(Map<String, Object?> json) => BoosterPreset(
  name: json['name'] as String,
  minimumSourcePressureBar: _toDouble(json, 'minimumSourcePressureBar'),
  cylinderVolumeCm3: _toDouble(json, 'cylinderVolumeCm3'),
  oxygenBoostBpm: _toDouble(json, 'oxygenBoostBpm'),
  otherBoostBpm: _toDouble(json, 'otherBoostBpm'),
  oxygenDecantRateBarPerMin: _toDouble(json, 'oxygenDecantRateBarPerMin'),
  otherDecantRateBarPerMin: _toDouble(json, 'otherDecantRateBarPerMin'),
  maxOutputPressureBar: _toDouble(json, 'maxOutputPressureBar'),
  temperatureModifierC: _toDouble(json, 'temperatureModifierC'),
  drainingRateBarPerMin: _toDouble(json, 'drainingRateBarPerMin'),
);

/// Parses a validated `booster` object.
SettingsBooster settingsBoosterFromJson(
  Map<String, Object?> json,
) => SettingsBooster(
  minimumSourcePressureBar: _toDouble(json, 'minimumSourcePressureBar'),
  cylinderVolumeCm3: _toDouble(json, 'cylinderVolumeCm3'),
  oxygenBoostBpm: _toDouble(json, 'oxygenBoostBpm'),
  otherBoostBpm: _toDouble(json, 'otherBoostBpm'),
  oxygenDecantRateBarPerMin: _toDouble(json, 'oxygenDecantRateBarPerMin'),
  otherDecantRateBarPerMin: _toDouble(json, 'otherDecantRateBarPerMin'),
  drainingRateBarPerMin: _toDouble(json, 'drainingRateBarPerMin'),
  compressorInletFlowLPerMin: _toDouble(json, 'compressorInletFlowLPerMin'),
  maxCompressorPressureBar: _toDouble(json, 'maxCompressorPressureBar'),
  maxBoosterOutputPressureBar: _toDouble(json, 'maxBoosterOutputPressureBar'),
  boosterTemperatureModifierC: _toDouble(json, 'boosterTemperatureModifierC'),
  compressorTemperatureModifierC: _toDouble(
    json,
    'compressorTemperatureModifierC',
  ),
);

/// Parses a validated `physics` object.
PhysicsSettings physicsFromJson(Map<String, Object?> json) =>
    PhysicsSettings(model: json['model'] as String);

/// Parses a `costs` object that has passed [validateCostSettings].
Costs costsFromJson(Map<String, Object?> json) {
  final prices = _map(json, 'operationPrices');
  return Costs(
    currencySymbol: json['currencySymbol'] as String,
    leftoverDiscountPercent: _toDouble(json, 'leftoverDiscountPercent'),
    operationPrices: OperationPrices(
      boost: _toDouble(prices, 'boost'),
      decant: _toDouble(prices, 'decant'),
      topUp: _toDouble(prices, 'topUp'),
    ),
  );
}

/// Parses a validated, normalized settings object into typed [Settings].
Settings settingsFromJson(Map<String, Object?> json) => Settings(
  units: json['units'] as String,
  pressureLimitMode: json['pressureLimitMode'] as String,
  pressureWarningUnlocked: json['pressureWarningUnlocked'] as bool,
  interimPressureTolerancePercent: _toDouble(
    json,
    'interimPressureTolerancePercent',
  ),
  costs: costsFromJson(_map(json, 'costs')),
  physics: physicsFromJson(_map(json, 'physics')),
  gasPresets: _list(
    json,
    'gasPresets',
  ).map((p) => gasPresetFromJson(p as Map<String, Object?>)).toList(),
  compressorPresets: _list(
    json,
    'compressorPresets',
  ).map((p) => compressorPresetFromJson(p as Map<String, Object?>)).toList(),
  boosterPresets: _list(
    json,
    'boosterPresets',
  ).map((p) => boosterPresetFromJson(p as Map<String, Object?>)).toList(),
  cylinderPresets: _list(
    json,
    'cylinderPresets',
  ).map((p) => cylinderPresetFromJson(p as Map<String, Object?>)).toList(),
  booster: settingsBoosterFromJson(_map(json, 'booster')),
);

// ---------------------------------------------------------------------------
// Serialization. Key order follows JS `copySettings`.
// ---------------------------------------------------------------------------

/// JS `copyCosts` output shape for typed [Costs].
Map<String, Object?> costsToJson(Costs costs) => <String, Object?>{
  'currencySymbol': costs.currencySymbol,
  'leftoverDiscountPercent': costs.leftoverDiscountPercent,
  'operationPrices': <String, Object?>{
    'boost': costs.operationPrices.boost,
    'decant': costs.operationPrices.decant,
    'topUp': costs.operationPrices.topUp,
  },
};

Map<String, Object?> physicsToJson(PhysicsSettings physics) =>
    <String, Object?>{'model': physics.model};

Map<String, Object?> settingsBoosterToJson(SettingsBooster booster) =>
    <String, Object?>{
      'minimumSourcePressureBar': booster.minimumSourcePressureBar,
      'cylinderVolumeCm3': booster.cylinderVolumeCm3,
      'oxygenBoostBpm': booster.oxygenBoostBpm,
      'otherBoostBpm': booster.otherBoostBpm,
      'oxygenDecantRateBarPerMin': booster.oxygenDecantRateBarPerMin,
      'otherDecantRateBarPerMin': booster.otherDecantRateBarPerMin,
      'drainingRateBarPerMin': booster.drainingRateBarPerMin,
      'compressorInletFlowLPerMin': booster.compressorInletFlowLPerMin,
      'maxCompressorPressureBar': booster.maxCompressorPressureBar,
      'maxBoosterOutputPressureBar': booster.maxBoosterOutputPressureBar,
      'boosterTemperatureModifierC': booster.boosterTemperatureModifierC,
      'compressorTemperatureModifierC': booster.compressorTemperatureModifierC,
    };

/// JS `copySettings` output shape for typed [Settings]. Preset objects carry
/// only their typed fields; unknown keys are not retained.
Map<String, Object?> settingsToJson(Settings settings) => <String, Object?>{
  'units': settings.units,
  'pressureLimitMode': settings.pressureLimitMode,
  'pressureWarningUnlocked': settings.pressureWarningUnlocked,
  'interimPressureTolerancePercent': settings.interimPressureTolerancePercent,
  'costs': costsToJson(settings.costs),
  'physics': physicsToJson(settings.physics),
  'gasPresets': settings.gasPresets.map((p) => p.toJson()).toList(),
  'compressorPresets': settings.compressorPresets
      .map((p) => p.toJson())
      .toList(),
  'boosterPresets': settings.boosterPresets.map((p) => p.toJson()).toList(),
  'cylinderPresets': settings.cylinderPresets.map((p) => p.toJson()).toList(),
  'booster': settingsBoosterToJson(settings.booster),
};

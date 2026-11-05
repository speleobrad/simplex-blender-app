part of '../optimizer.dart';

// The optimizer's public entries take only the JS-shaped blend input map (JS `input`).
// `_parseBlendInput` turns its `physics`, `banks`, `settings`, and `thermal` entries into
// the typed values the solver uses. Every entry validates the map with `_validateBlendInput`
// before parsing, so the casts below rely on the validated JS shapes.

/// JS `settings` as the optimizer reads it. Each field is optional because the optimizer
/// falls back per field (JS defaults: 232, 200, and 20 bar).
class BlendSettings {
  const BlendSettings({this.pressureLimitMode, this.booster});

  /// JS `settings.pressureLimitMode`; null when absent or not text.
  final String? pressureLimitMode;

  /// JS `settings.booster`; null when absent.
  final BlendBooster? booster;
}

/// JS `settings.booster`. Each field is nullable and falls back when absent or not finite.
class BlendBooster {
  const BlendBooster({
    this.minimumSourcePressureBar,
    this.maxCompressorPressureBar,
    this.maxBoosterOutputPressureBar,
    this.cylinderVolumeCm3,
    this.oxygenBoostBpm,
    this.otherBoostBpm,
    this.oxygenDecantRateBarPerMin,
    this.otherDecantRateBarPerMin,
    this.drainingRateBarPerMin,
    this.compressorInletFlowLPerMin,
    this.boosterTemperatureModifierC,
    this.compressorTemperatureModifierC,
  });

  final double? minimumSourcePressureBar;
  final double? maxCompressorPressureBar;
  final double? maxBoosterOutputPressureBar;
  final double? cylinderVolumeCm3;
  final double? oxygenBoostBpm;
  final double? otherBoostBpm;
  final double? oxygenDecantRateBarPerMin;
  final double? otherDecantRateBarPerMin;
  final double? drainingRateBarPerMin;
  final double? compressorInletFlowLPerMin;
  final double? boosterTemperatureModifierC;
  final double? compressorTemperatureModifierC;
}

/// The typed view of one blend input map.
typedef _ParsedBlendInput = ({
  PhysicsInput physics,
  List<Bank> banks,
  BlendSettings? settings,
  ThermalInput? thermal,
});

/// Parses a validated JS blend input. Absent or non-object `settings` and `thermal`
/// become null; the solver's callers decide the fallback.
_ParsedBlendInput _parseBlendInput(Map<String, Object?> input) {
  return (
    physics: _parsePhysics(input['physics'] as Map<String, Object?>),
    banks: _parseBanks(input['banks'] as List<Object?>),
    settings: _parseSettings(input['settings']),
    thermal: _parseThermal(input['thermal']),
  );
}

PhysicsInput _parsePhysics(Map<String, Object?> raw) {
  return PhysicsInput(
    model: raw['model'] as String,
    temperatureC: _numberOrNan(raw['temperatureC']),
  );
}

List<Bank> _parseBanks(List<Object?> raw) {
  return [for (final bank in raw) _parseBank(bank as Map<String, Object?>)];
}

Bank _parseBank(Map<String, Object?> raw) {
  final isCompressor = raw['isCompressor'];
  return Bank(
    id: raw['id'] as String,
    name: raw['name'] as String,
    volumeL: _numberOrNan(raw['volumeL']),
    pressureBar: _numberOrNan(raw['pressureBar']),
    oxygenPercent: _numberOrNan(raw['oxygenPercent']),
    heliumPercent: _numberOrNan(raw['heliumPercent']),
    enabled: raw['enabled'] as bool,
    pricePerLitre: _numberOrNull(raw['pricePerLitre']),
    maxPressureBar: _numberOrNull(raw['maxPressureBar']),
    isCompressor: isCompressor is bool ? isCompressor : null,
    minimumPressureBar: _numberOrNull(raw['minimumPressureBar']),
  );
}

BlendSettings? _parseSettings(Object? raw) {
  if (raw is! Map<String, Object?>) {
    return null;
  }
  final booster = raw['booster'];
  return BlendSettings(
    pressureLimitMode: _stringOrNull(raw['pressureLimitMode']),
    booster: booster is Map<String, Object?> ? _parseBooster(booster) : null,
  );
}

BlendBooster _parseBooster(Map<String, Object?> raw) {
  return BlendBooster(
    minimumSourcePressureBar: _numberOrNull(raw['minimumSourcePressureBar']),
    maxCompressorPressureBar: _numberOrNull(raw['maxCompressorPressureBar']),
    maxBoosterOutputPressureBar: _numberOrNull(
      raw['maxBoosterOutputPressureBar'],
    ),
    cylinderVolumeCm3: _numberOrNull(raw['cylinderVolumeCm3']),
    oxygenBoostBpm: _numberOrNull(raw['oxygenBoostBpm']),
    otherBoostBpm: _numberOrNull(raw['otherBoostBpm']),
    oxygenDecantRateBarPerMin: _numberOrNull(raw['oxygenDecantRateBarPerMin']),
    otherDecantRateBarPerMin: _numberOrNull(raw['otherDecantRateBarPerMin']),
    drainingRateBarPerMin: _numberOrNull(raw['drainingRateBarPerMin']),
    compressorInletFlowLPerMin: _numberOrNull(
      raw['compressorInletFlowLPerMin'],
    ),
    boosterTemperatureModifierC: _numberOrNull(
      raw['boosterTemperatureModifierC'],
    ),
    compressorTemperatureModifierC: _numberOrNull(
      raw['compressorTemperatureModifierC'],
    ),
  );
}

ThermalInput? _parseThermal(Object? raw) {
  if (raw is! Map<String, Object?>) {
    return null;
  }
  return ThermalInput(
    ambientTemperatureC: _numberOrNan(raw['ambientTemperatureC']),
    tankMaterial: _stringOrNull(raw['tankMaterial']),
    coolingMedium: _stringOrNull(raw['coolingMedium']),
    waterSubmersionPercent: _numberOrNull(raw['waterSubmersionPercent']),
    tankMassKg: _numberOrNull(raw['tankMassKg']),
    inletTemperatureC: _numberOrNull(raw['inletTemperatureC']),
    targetMediumTemperatureC: _numberOrNull(raw['targetMediumTemperatureC']),
    targetTemperatureC: _numberOrNull(raw['targetTemperatureC']),
    targetInWaterTemperatureC: _numberOrNull(raw['targetInWaterTemperatureC']),
    waitMode: _stringOrNull(raw['waitMode']),
    waitMinutes: _numberOrNull(raw['waitMinutes']),
    interimMeasurements: _parseInterimMeasurements(raw['interimMeasurements']),
  );
}

/// JS `thermal.interimMeasurements`. A non-array yields null. A null or non-object
/// entry yields null, which the simulation skips; the validator reports non-object entries.
List<InterimMeasurement?>? _parseInterimMeasurements(Object? raw) {
  if (raw is! List<Object?>) {
    return null;
  }
  return <InterimMeasurement?>[
    for (final entry in raw)
      if (entry is Map<String, Object?>)
        InterimMeasurement(
          pressureBar: _numberOrNull(entry['pressureBar']),
          temperatureC: _numberOrNull(entry['temperatureC']),
        )
      else
        null,
  ];
}

/// JS string field read as text; any other JSON type reads as absent.
String? _stringOrNull(Object? value) => value is String ? value : null;

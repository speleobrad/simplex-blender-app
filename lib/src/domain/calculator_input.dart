/// Port of `readInput()` in `js/main.js`, plus the `settings` key that every
/// JS caller adds (`{ ...readInput(), settings: state.settings }`).
///
/// This is the only builder of the calculator input map. JS `readInput()`
/// reads the DOM; here each DOM-derived value is a parameter, so the caller
/// (UI or controller) supplies the already-parsed value.
library;

import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/interim_measurements.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/settings_json.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

/// JS `readInput()` plus `settings`. Key order matches the JS object literal.
///
/// Source mapping (JS `readInput`, `js/main.js` lines 1065-1100):
/// - `cylinder` <- `cylinderPreset` (name, volume, working pressure, hot
///   overfill) and the `init-*` / `target-*` fields.
/// - `physics.model` <- `settings.physics.model`; `physics.temperatureC` and
///   `thermal.ambientTemperatureC` <- the `ambient-temperature` field.
/// - `thermal.tankMaterial` / `tankMassKg` <- the selected cylinder preset.
/// - `thermal.targetMediumTemperatureC` and `thermal.targetTemperatureC` are
///   both read from `wait-target-temperature` in JS, so one parameter feeds
///   both keys.
/// - `thermal.interimMeasurements` <- `state.interimMeasurements`; a missing
///   reading is JS `null`.
/// - `banks` <- `state.banks`, in the optimizer bank shape.
/// - `settings` <- `state.settings`, in the JS `copySettings` shape.
CalculatorInput buildCalculatorInput({
  required CylinderPreset cylinderPreset,
  required double initialPressureBar,
  required double initialOxygenPercent,
  required double initialHeliumPercent,
  required double targetPressureBar,
  required double targetOxygenPercent,
  required double targetHeliumPercent,
  required double ambientTemperatureC,
  required double targetInWaterTemperatureC,
  required double waitTargetTemperatureC,
  required double inletTemperatureC,
  required String coolingMedium,
  required double waterSubmersionPercent,
  required String waitMode,
  required double waitMinutes,
  required List<Bank> banks,
  required Settings settings,
  List<InterimMeasurement?> interimMeasurements = const <InterimMeasurement?>[],
}) {
  return <String, Object?>{
    'cylinder': <String, Object?>{
      'presetName': cylinderPreset.name,
      'volumeL': cylinderPreset.volumeL,
      'workingPressureBar': cylinderPreset.workingPressureBar,
      'hotOverfillPercent': cylinderPreset.hotOverfillPercent,
      'initialPressureBar': initialPressureBar,
      'initialOxygenPercent': initialOxygenPercent,
      'initialHeliumPercent': initialHeliumPercent,
      'targetPressureBar': targetPressureBar,
      'targetOxygenPercent': targetOxygenPercent,
      'targetHeliumPercent': targetHeliumPercent,
    },
    'physics': <String, Object?>{
      'model': settings.physics.model,
      'temperatureC': ambientTemperatureC,
    },
    'thermal': <String, Object?>{
      'tankMaterial': cylinderPreset.material,
      'tankMassKg': cylinderPreset.massKg,
      'coolingMedium': coolingMedium,
      'waterSubmersionPercent': waterSubmersionPercent,
      'ambientTemperatureC': ambientTemperatureC,
      'targetInWaterTemperatureC': targetInWaterTemperatureC,
      'targetMediumTemperatureC': waitTargetTemperatureC,
      'inletTemperatureC': inletTemperatureC,
      'waitMode': waitMode,
      'waitMinutes': waitMinutes,
      'interimMeasurements': <Object?>[
        for (final measurement in interimMeasurements)
          measurement == null ? null : _interimMeasurementJson(measurement),
      ],
      'targetTemperatureC': waitTargetTemperatureC,
    },
    'banks': <Map<String, Object?>>[
      for (final bank in banks) optimizerBankJson(bank),
    ],
    'settings': settingsToJson(settings),
  };
}

Map<String, Object?> _interimMeasurementJson(InterimMeasurement measurement) =>
    <String, Object?>{
      'pressureBar': measurement.pressureBar,
      'temperatureC': measurement.temperatureC,
    };

/// Optimizer-shaped bank record (JS bank object as the optimizer reads it).
Map<String, Object?> optimizerBankJson(Bank bank) => <String, Object?>{
  'id': bank.id,
  'name': bank.name,
  'enabled': bank.enabled,
  'volumeL': bank.volumeL,
  'pressureBar': bank.pressureBar,
  'maxPressureBar': bank.maxPressureBar,
  'minimumPressureBar': bank.minimumPressureBar,
  'oxygenPercent': bank.oxygenPercent,
  'heliumPercent': bank.heliumPercent,
  'pricePerLitre': bank.pricePerLitre,
  'isCompressor': bank.isCompressor,
};

/// Optimizer-shaped settings subset (`pressureLimitMode` and `booster`).
Map<String, Object?> optimizerSettingsJson(
  Settings settings,
) => <String, Object?>{
  'pressureLimitMode': settings.pressureLimitMode,
  'booster': <String, Object?>{
    'minimumSourcePressureBar': settings.booster.minimumSourcePressureBar,
    'maxCompressorPressureBar': settings.booster.maxCompressorPressureBar,
    'maxBoosterOutputPressureBar': settings.booster.maxBoosterOutputPressureBar,
    'cylinderVolumeCm3': settings.booster.cylinderVolumeCm3,
    'oxygenBoostBpm': settings.booster.oxygenBoostBpm,
    'otherBoostBpm': settings.booster.otherBoostBpm,
    'oxygenDecantRateBarPerMin': settings.booster.oxygenDecantRateBarPerMin,
    'otherDecantRateBarPerMin': settings.booster.otherDecantRateBarPerMin,
    'drainingRateBarPerMin': settings.booster.drainingRateBarPerMin,
    'compressorInletFlowLPerMin': settings.booster.compressorInletFlowLPerMin,
    'boosterTemperatureModifierC': settings.booster.boosterTemperatureModifierC,
    'compressorTemperatureModifierC':
        settings.booster.compressorTemperatureModifierC,
  },
};

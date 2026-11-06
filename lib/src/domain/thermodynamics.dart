import 'dart:math' as math;

import 'package:simplex_blender/src/domain/materials.dart';
import 'package:simplex_blender/src/domain/physics.dart';

part 'thermodynamics/transfer_profile.dart';

const double atmosphericPressureBar = 1.01325;
const double gaugePressureOffsetBar = 1;
const double clearanceRatio = 0.05;
const double gamma = 1.4;
const double oxygenRichThreshold = 40;

const double pascalsPerBar = 100000;
const double thermalIntegrationStepSeconds = 0.5;
const double heatTransferAirWPerM2K = 12;
const double heatTransferWaterWPerM2K = 250;

/// JS `Number.EPSILON`.
const double _numberEpsilon = 2.220446049250313e-16;

const List<double> waterSubmersionPercentOptions = [20, 40, 60, 80];
const double defaultWaterSubmersionPercent = 60;

const Set<String> _transferProfileSources = {
  'booster',
  'compressor',
  'decant-rate',
  'draining-rate',
  'salvage-decant',
  'salvage-booster',
};

// ---------------------------------------------------------------------------
// Typed inputs and outputs (mirror the JS plain objects).
// ---------------------------------------------------------------------------

/// JS `{ oxygenPercent, heliumPercent }`.
class GasMixPercent {
  const GasMixPercent({
    required this.oxygenPercent,
    required this.heliumPercent,
  });

  final double oxygenPercent;
  final double heliumPercent;
}

/// Cylinder fields read by the thermal simulation.
class CylinderInput {
  const CylinderInput({
    required this.volumeL,
    this.initialPressureBar,
    this.initialOxygenPercent,
    this.initialHeliumPercent,
  });

  final double volumeL;
  final double? initialPressureBar;
  final double? initialOxygenPercent;
  final double? initialHeliumPercent;
}

/// Physics fields read by the thermal simulation.
class PhysicsInput {
  const PhysicsInput({required this.model, required this.temperatureC});

  final String model;
  final double temperatureC;

  bool get useVdw => model == 'vdw';
}

/// One interim reading. Either field may be absent (JS `undefined`/`null`).
class InterimMeasurement {
  const InterimMeasurement({this.pressureBar, this.temperatureC});

  final double? pressureBar;
  final double? temperatureC;
}

/// Thermal fields read by the simulation.
class ThermalInput {
  const ThermalInput({
    required this.ambientTemperatureC,
    this.tankMaterial,
    this.coolingMedium,
    this.waterSubmersionPercent,
    this.tankMassKg,
    this.inletTemperatureC,
    this.targetMediumTemperatureC,
    this.targetTemperatureC,
    this.waitMode,
    this.waitMinutes,
    this.interimMeasurements,
    this.targetInWaterTemperatureC,
  });

  final double ambientTemperatureC;
  final String? tankMaterial;
  final String? coolingMedium;
  final double? waterSubmersionPercent;
  final double? tankMassKg;
  final double? inletTemperatureC;
  final double? targetMediumTemperatureC;
  final double? targetTemperatureC;
  final String? waitMode;
  final double? waitMinutes;
  final List<InterimMeasurement?>? interimMeasurements;
  final double? targetInWaterTemperatureC;
}

/// JS `settings.booster`. Each field falls back to its default when absent or
/// not finite.
class BoosterSettings {
  const BoosterSettings({
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

class _ThermalBooster {
  const _ThermalBooster({
    required this.cylinderVolumeCm3,
    required this.oxygenBoostBpm,
    required this.otherBoostBpm,
    required this.oxygenDecantRateBarPerMin,
    required this.otherDecantRateBarPerMin,
    required this.drainingRateBarPerMin,
    required this.compressorInletFlowLPerMin,
    required this.boosterTemperatureModifierC,
    required this.compressorTemperatureModifierC,
  });

  factory _ThermalBooster.from(BoosterSettings? booster) => _ThermalBooster(
    cylinderVolumeCm3: _finiteOr(booster?.cylinderVolumeCm3, 9),
    oxygenBoostBpm: _finiteOr(booster?.oxygenBoostBpm, 50),
    otherBoostBpm: _finiteOr(booster?.otherBoostBpm, 50),
    oxygenDecantRateBarPerMin: _finiteOr(booster?.oxygenDecantRateBarPerMin, 5),
    otherDecantRateBarPerMin: _finiteOr(booster?.otherDecantRateBarPerMin, 5),
    drainingRateBarPerMin: _finiteOr(booster?.drainingRateBarPerMin, 5),
    compressorInletFlowLPerMin: _finiteOr(
      booster?.compressorInletFlowLPerMin,
      100,
    ),
    boosterTemperatureModifierC: _finiteOr(
      booster?.boosterTemperatureModifierC,
      0,
    ),
    compressorTemperatureModifierC: _finiteOr(
      booster?.compressorTemperatureModifierC,
      0,
    ),
  );

  final double cylinderVolumeCm3;
  final double oxygenBoostBpm;
  final double otherBoostBpm;
  final double oxygenDecantRateBarPerMin;
  final double otherDecantRateBarPerMin;
  final double drainingRateBarPerMin;
  final double compressorInletFlowLPerMin;
  final double boosterTemperatureModifierC;
  final double compressorTemperatureModifierC;
}

/// One simulated point of a temperature history.
class TemperatureSample {
  const TemperatureSample({
    required this.elapsedMinutes,
    required this.temperatureC,
  });

  final double elapsedMinutes;
  final double temperatureC;
}

/// One simulated point of a thermal step profile. Optional fields are present
/// only for the sample kinds that carry them.
class ThermalSample {
  const ThermalSample({
    required this.elapsedMinutes,
    required this.temperatureC,
    required this.pressureBar,
    this.projectedPressureBar,
    this.ambientPressureBar,
    this.oxygenPercent,
    this.heliumPercent,
    this.pressureReferenceTemperatureC,
    this.pressureAtTransferEndReferenceBar,
    this.pressureAtTransferEndAmbientBar,
    this.pressureAtTransferEndHotBar,
    this.rateBarPerMin,
  });

  final double elapsedMinutes;
  final double temperatureC;
  final double pressureBar;
  final double? projectedPressureBar;
  final double? ambientPressureBar;
  final double? oxygenPercent;
  final double? heliumPercent;
  final double? pressureReferenceTemperatureC;
  final double? pressureAtTransferEndReferenceBar;
  final double? pressureAtTransferEndAmbientBar;
  final double? pressureAtTransferEndHotBar;
  final double? rateBarPerMin;
}

/// JS transfer descriptor returned by the rate functions.
class TransferRate {
  const TransferRate({
    required this.rateSource,
    required this.rateBarPerMin,
    required this.pressureIncreaseBar,
    this.pressureChangeBar,
  });

  final String rateSource;
  final double? rateBarPerMin;
  final double pressureIncreaseBar;
  final double? pressureChangeBar;
}

/// JS `thermal` object attached to each simulated protocol step. Fields that
/// only the protocol (non-compare) simulation produces are nullable.
class ThermalStep {
  const ThermalStep({
    required this.rateSource,
    required this.rateBarPerMin,
    required this.durationMinutes,
    required this.inletTemperatureC,
    required this.pressureStartBar,
    required this.temperatureStartC,
    required this.temperatureAtTransferEndC,
    required this.pressureReferenceTemperatureC,
    required this.pressureAtTransferEndReferenceBar,
    required this.pressureAtTransferEndAmbientBar,
    required this.waitMinutes,
    required this.temperatureAfterWaitC,
    required this.pressureAtTransferEndBar,
    required this.pressureAtTransferEndHotBar,
    required this.pressureAfterWaitBar,
    required this.samples,
    this.plannedStartPressureBar,
    this.plannedStartTemperatureC,
    this.measurementIndex,
    this.measurementApplied,
    this.measuredStartPressureBar,
    this.measuredStartTemperatureC,
    this.receiverStartMix,
    this.configuredWaitMinutes,
    this.automaticWaitMinutes,
    this.measuredWaitMinutes,
  });

  final String rateSource;
  final double? rateBarPerMin;
  final double durationMinutes;
  final double inletTemperatureC;
  final double pressureStartBar;
  final double temperatureStartC;
  final double temperatureAtTransferEndC;
  final double pressureReferenceTemperatureC;
  final double pressureAtTransferEndReferenceBar;
  final double pressureAtTransferEndAmbientBar;
  final double waitMinutes;
  final double temperatureAfterWaitC;
  final double pressureAtTransferEndBar;
  final double pressureAtTransferEndHotBar;
  final double pressureAfterWaitBar;
  final List<ThermalSample> samples;

  final double? plannedStartPressureBar;
  final double? plannedStartTemperatureC;
  final int? measurementIndex;
  final bool? measurementApplied;
  final double? measuredStartPressureBar;
  final double? measuredStartTemperatureC;
  final GasMixPercent? receiverStartMix;
  final double? configuredWaitMinutes;
  final double? automaticWaitMinutes;
  final double? measuredWaitMinutes;
}

/// JS protocol step. Passed through to output as `{...step, thermal}`.
class ProtocolStep {
  const ProtocolStep({
    this.type,
    this.operation,
    this.title,
    this.method,
    this.stage,
    this.receiverStartPressureBar,
    this.receiverEndPressureBar,
    this.resultingPressureBar,
    this.resultingMix,
    this.receiverStartMix,
    this.receiverVolumeL,
    this.sourceStartPressureBar,
    this.sourceEndPressureBar,
    this.sourcePressureBar,
    this.sourceOxygenPercent,
    this.sourceHeliumPercent,
    this.pressureReferenceTemperatureC,
    this.pressureAtTransferEndReferenceBar,
    this.pressureAtTransferEndAmbientBar,
    this.pressureAtTransferEndHotBar,
    this.automaticWaitMinutes,
    this.waitMode,
    this.waitMinutes,
    this.targetTemperatureC,
    this.measurementIndex,
    this.measurementIndexExplicitNull = false,
    this.applyInterimMeasurement,
    this.scheduledMeasuredStartPressureBar,
    this.scheduledMeasuredStartTemperatureC,
    this.safetyWaitOnly,
    this.costOperation,
    this.costOperationId,
    this.sourceConsumedMoles,
    this.thermalSplit = false,
    this.sourceInventory,
    this.sourceVolumeL,
    this.sourceStartMoles,
    this.sourceEndMoles,
    this.receiverStartMoles,
    this.receiverEndMoles,
    this.recipeGas,
    this.recipeLabel,
    this.id,
    this.automaticWaitMetadata,
    this.thermal,
    this.recipeAction,
    this.sourceBankId,
    this.description,
    this.pressureDeltaBar,
    this.minimumSourcePressureBar,
    this.sourceExhausted,
    this.oxygenCompressionRatio,
    this.badgeClass,
    this.receiverBankId,
    this.receiverBankName,
    this.movedMoles,
    this.movedHeliumLitres,
    this.receiverEndMix,
  });

  final String? type;
  final String? operation;
  final String? title;
  final String? method;
  final String? stage;
  final double? receiverStartPressureBar;
  final double? receiverEndPressureBar;
  final double? resultingPressureBar;
  final GasMixPercent? resultingMix;
  final GasMixPercent? receiverStartMix;
  final double? receiverVolumeL;
  final double? sourceStartPressureBar;
  final double? sourceEndPressureBar;
  final double? sourcePressureBar;
  final double? sourceOxygenPercent;
  final double? sourceHeliumPercent;
  final double? pressureReferenceTemperatureC;
  final double? pressureAtTransferEndReferenceBar;
  final double? pressureAtTransferEndAmbientBar;
  final double? pressureAtTransferEndHotBar;
  final double? automaticWaitMinutes;

  /// Opaque cost fields passed through from the input step (JS spread).
  final String? costOperation;
  final String? costOperationId;
  final double? sourceConsumedMoles;
  final String? waitMode;
  final double? waitMinutes;
  final double? targetTemperatureC;

  /// JS `_measurementIndex`. When [measurementIndexExplicitNull] is true the
  /// JS value was `null` (no measurement); otherwise a null [measurementIndex]
  /// means "absent" and the step index is used.
  final int? measurementIndex;
  final bool measurementIndexExplicitNull;

  /// JS `_applyInterimMeasurement`; applied unless `false`.
  final bool? applyInterimMeasurement;
  final double? scheduledMeasuredStartPressureBar;
  final double? scheduledMeasuredStartTemperatureC;

  /// JS `_safetyWaitOnly`; only `true` enables it.
  final bool? safetyWaitOnly;

  final ThermalStep? thermal;

  /// Recipe-step fields written by the no-salvage blend protocol (JS
  /// `solveBlendWithoutSalvage`): action verb, source bank id, human description,
  /// pressure change, source minimum pressure, exhaustion flag, O2 compression
  /// ratio and badge class.
  final String? recipeAction;
  final String? sourceBankId;
  final String? description;
  final double? pressureDeltaBar;
  final double? minimumSourcePressureBar;
  final bool? sourceExhausted;
  final double? oxygenCompressionRatio;
  final String? badgeClass;

  /// JS salvage step `receiverBankId`: the bank that received salvaged gas.
  final String? receiverBankId;

  /// JS salvage step `receiverBankName`.
  final String? receiverBankName;

  /// JS salvage step `movedMoles`: moles moved from the cylinder into the receiver.
  final double? movedMoles;

  /// JS salvage step `movedHeliumLitres`: helium litres recovered by the transfer.
  final double? movedHeliumLitres;

  /// JS salvage step `receiverEndMix`.
  final GasMixPercent? receiverEndMix;

  /// JS `_thermalSplit`; marks a transfer step split across thermal states.
  final bool thermalSplit;

  /// Replay fields: source inventory name, source volume and moles before and
  /// after the step, receiver moles before and after, recipe gas and label,
  /// and step id. Null when not provided.
  final String? sourceInventory;
  final double? sourceVolumeL;
  final double? sourceStartMoles;
  final double? sourceEndMoles;
  final double? receiverStartMoles;
  final double? receiverEndMoles;
  final String? recipeGas;
  final String? recipeLabel;
  final String? id;

  /// JS `automaticWaitMetadata`: `{ stepIndex, stepIdentifier,
  /// configuredWaitMinutes, actualWaitMinutes, addedWaitMinutes, warning }`,
  /// attached only to steps that received an automatic safety wait.
  final Map<String, Object?>? automaticWaitMetadata;

  ProtocolStep copyWith({
    String? type,
    String? operation,
    String? title,
    double? sourceStartPressureBar,
    double? sourceEndPressureBar,
    ThermalStep? thermal,
    GasMixPercent? receiverStartMix,
    bool? thermalSplit,
    String? sourceInventory,
    double? sourceVolumeL,
    double? sourceStartMoles,
    double? sourceEndMoles,
    double? receiverStartMoles,
    double? receiverEndMoles,
    String? recipeGas,
    String? recipeLabel,
    String? id,
    Map<String, Object?>? automaticWaitMetadata,
    String? recipeAction,
    String? sourceBankId,
    String? description,
    double? pressureDeltaBar,
    double? minimumSourcePressureBar,
    bool? sourceExhausted,
    double? oxygenCompressionRatio,
    String? badgeClass,
    String? receiverBankId,
    String? receiverBankName,
    double? movedMoles,
    double? movedHeliumLitres,
    GasMixPercent? receiverEndMix,
  }) {
    return ProtocolStep(
      type: type ?? this.type,
      operation: operation ?? this.operation,
      title: title ?? this.title,
      method: method,
      stage: stage,
      receiverStartPressureBar: receiverStartPressureBar,
      receiverEndPressureBar: receiverEndPressureBar,
      resultingPressureBar: resultingPressureBar,
      resultingMix: resultingMix,
      costOperation: costOperation,
      costOperationId: costOperationId,
      sourceConsumedMoles: sourceConsumedMoles,
      receiverVolumeL: receiverVolumeL,
      sourceStartPressureBar:
          sourceStartPressureBar ?? this.sourceStartPressureBar,
      sourceEndPressureBar: sourceEndPressureBar ?? this.sourceEndPressureBar,
      sourcePressureBar: sourcePressureBar,
      sourceOxygenPercent: sourceOxygenPercent,
      sourceHeliumPercent: sourceHeliumPercent,
      pressureReferenceTemperatureC: pressureReferenceTemperatureC,
      pressureAtTransferEndReferenceBar: pressureAtTransferEndReferenceBar,
      pressureAtTransferEndAmbientBar: pressureAtTransferEndAmbientBar,
      pressureAtTransferEndHotBar: pressureAtTransferEndHotBar,
      automaticWaitMinutes: automaticWaitMinutes,
      waitMode: waitMode,
      waitMinutes: waitMinutes,
      targetTemperatureC: targetTemperatureC,
      measurementIndex: measurementIndex,
      measurementIndexExplicitNull: measurementIndexExplicitNull,
      applyInterimMeasurement: applyInterimMeasurement,
      scheduledMeasuredStartPressureBar: scheduledMeasuredStartPressureBar,
      scheduledMeasuredStartTemperatureC: scheduledMeasuredStartTemperatureC,
      safetyWaitOnly: safetyWaitOnly,
      receiverStartMix: receiverStartMix ?? this.receiverStartMix,
      thermalSplit: thermalSplit ?? this.thermalSplit,
      sourceInventory: sourceInventory ?? this.sourceInventory,
      sourceVolumeL: sourceVolumeL ?? this.sourceVolumeL,
      sourceStartMoles: sourceStartMoles ?? this.sourceStartMoles,
      sourceEndMoles: sourceEndMoles ?? this.sourceEndMoles,
      receiverStartMoles: receiverStartMoles ?? this.receiverStartMoles,
      receiverEndMoles: receiverEndMoles ?? this.receiverEndMoles,
      recipeGas: recipeGas ?? this.recipeGas,
      recipeLabel: recipeLabel ?? this.recipeLabel,
      id: id ?? this.id,
      thermal: thermal ?? this.thermal,
      automaticWaitMetadata:
          automaticWaitMetadata ?? this.automaticWaitMetadata,
      recipeAction: recipeAction ?? this.recipeAction,
      sourceBankId: sourceBankId ?? this.sourceBankId,
      description: description ?? this.description,
      pressureDeltaBar: pressureDeltaBar ?? this.pressureDeltaBar,
      minimumSourcePressureBar:
          minimumSourcePressureBar ?? this.minimumSourcePressureBar,
      sourceExhausted: sourceExhausted ?? this.sourceExhausted,
      oxygenCompressionRatio:
          oxygenCompressionRatio ?? this.oxygenCompressionRatio,
      badgeClass: badgeClass ?? this.badgeClass,
      receiverBankId: receiverBankId ?? this.receiverBankId,
      receiverBankName: receiverBankName ?? this.receiverBankName,
      movedMoles: movedMoles ?? this.movedMoles,
      movedHeliumLitres: movedHeliumLitres ?? this.movedHeliumLitres,
      receiverEndMix: receiverEndMix ?? this.receiverEndMix,
    );
  }
}

/// JS `final` object of [simulateThermalProtocol].
class ThermalFinal {
  const ThermalFinal({
    required this.finalTransferEndPressureBar,
    required this.finalTransferEndTemperatureC,
    required this.finalAmbientPressureBar,
    required this.finalAmbientTemperatureC,
  });

  final double finalTransferEndPressureBar;
  final double finalTransferEndTemperatureC;
  final double finalAmbientPressureBar;
  final double finalAmbientTemperatureC;
}

class ThermalProtocolResult {
  const ThermalProtocolResult({
    required this.protocolSteps,
    required this.finalSummary,
  });

  final List<ProtocolStep> protocolSteps;
  final ThermalFinal finalSummary;
}

/// JS `{ pressureBar, temperatureC, oxygenPercent, heliumPercent }`.
class StateSnapshot {
  const StateSnapshot({
    required this.pressureBar,
    required this.temperatureC,
    required this.oxygenPercent,
    required this.heliumPercent,
  });

  final double pressureBar;
  final double temperatureC;
  final double oxygenPercent;
  final double heliumPercent;
}

class CompareFinal {
  const CompareFinal({
    required this.recipeEnd,
    required this.ambientSettled,
    required this.ambientSettledDurationMinutes,
    required this.inWater,
  });

  final StateSnapshot recipeEnd;
  final StateSnapshot ambientSettled;
  final double ambientSettledDurationMinutes;
  final StateSnapshot? inWater;
}

class ThermalCompareResult {
  const ThermalCompareResult({
    required this.protocolSteps,
    required this.finalSummary,
  });

  final List<ProtocolStep> protocolSteps;
  final CompareFinal finalSummary;
}

class PressureProjection {
  const PressureProjection({
    required this.temperatureC,
    required this.pressureBar,
  });

  final double temperatureC;
  final double pressureBar;
}

/// JS `RangeError` named `CompareSimulationError`, code
/// `COMPARE_TARGET_STATE_UNREACHABLE`.
class CompareSimulationError implements Exception {
  const CompareSimulationError(this.message, this.details);

  final String message;
  final Map<String, Object?> details;

  String get name => 'CompareSimulationError';
  String get code => 'COMPARE_TARGET_STATE_UNREACHABLE';

  @override
  String toString() => '$name: $message';
}

// ---------------------------------------------------------------------------
// Helpers.
// ---------------------------------------------------------------------------

double _clamp(double value, double minimum, double maximum) =>
    math.min(maximum, math.max(minimum, value));

/// JS `Number.isFinite(x) ? x : fallback` for nullable doubles.
double _finiteOr(double? value, double fallback) =>
    value != null && value.isFinite ? value : fallback;

/// Returns [value] when it is non-null and finite, else null.
double? _finiteOrNull(double? value) =>
    value != null && value.isFinite ? value : null;

/// JS `Number(x) || fallback`: null, NaN and zero yield the fallback.
double _orFallback(double? value, double fallback) =>
    value == null || value.isNaN || value == 0 ? fallback : value;

double _wetSurfaceFraction(double? waterSubmersionPercent) {
  final percent = waterSubmersionPercent ?? defaultWaterSubmersionPercent;
  return math.min(100.0, math.max(0.0, _orFallback(percent, 0))) / 100;
}

bool _hasTransferProfile(String rateSource) =>
    _transferProfileSources.contains(rateSource);

GasMixPercent _stepMix(ProtocolStep step) => GasMixPercent(
  oxygenPercent: step.resultingMix?.oxygenPercent ?? 0,
  heliumPercent: step.resultingMix?.heliumPercent ?? 0,
);

// ---------------------------------------------------------------------------
// Fill rates.
// ---------------------------------------------------------------------------

class BoosterFillRate {
  const BoosterFillRate({
    required this.fillRateBarPerMin,
    required this.volumetricEfficiency,
    required this.zSource,
    required this.zReceiver,
    required this.molesPerMin,
  });

  final double fillRateBarPerMin;
  final double volumetricEfficiency;
  final double zSource;
  final double zReceiver;
  final double molesPerMin;
}

BoosterFillRate calculateBoosterFillRate({
  required double cylinderVolumeCm3,
  required double bpm,
  required double sourcePressureBar,
  required double receiverPressureBar,
  required double sourceOxygenPercent,
  required double sourceHeliumPercent,
  required double receiverOxygenPercent,
  required double receiverHeliumPercent,
  required double receiverVolumeL,
  required double temperatureC,
  required bool useVdw,
}) {
  final sourceAbsolutePressureBar = math.max(
    0.0,
    sourcePressureBar + gaugePressureOffsetBar,
  );
  final receiverAbsolutePressureBar = math.max(
    0.0,
    receiverPressureBar + gaugePressureOffsetBar,
  );
  final zSource = calcZ(
    sourceAbsolutePressureBar,
    sourceOxygenPercent,
    sourceHeliumPercent,
    temperatureC,
    useVdw,
  );
  final zReceiver = calcZ(
    receiverAbsolutePressureBar,
    receiverOxygenPercent,
    receiverHeliumPercent,
    temperatureC,
    useVdw,
  );
  final compressionRatio = sourceAbsolutePressureBar > 0
      ? receiverAbsolutePressureBar / sourceAbsolutePressureBar
      : double.infinity;
  final volumetricEfficiency =
      receiverAbsolutePressureBar <= sourceAbsolutePressureBar
      ? 1.0
      : _clamp(
          1 -
              clearanceRatio *
                  (math.pow(compressionRatio, 1 / gamma).toDouble() - 1),
          0.10,
          0.98,
        );
  final effectiveFlowLPerMin =
      cylinderVolumeCm3 / 1000 * bpm * volumetricEfficiency;
  final temperatureK = temperatureC + 273.15;
  final molesPerMin =
      sourceAbsolutePressureBar *
      effectiveFlowLPerMin /
      (zSource * gasConstant * temperatureK);
  final fillRateBarPerMin =
      molesPerMin * zReceiver * gasConstant * temperatureK / receiverVolumeL;

  return BoosterFillRate(
    fillRateBarPerMin: fillRateBarPerMin,
    volumetricEfficiency: volumetricEfficiency,
    zSource: zSource,
    zReceiver: zReceiver,
    molesPerMin: molesPerMin,
  );
}

class CompressorFillRate {
  const CompressorFillRate({
    required this.fillRateBarPerMin,
    required this.molesPerMin,
  });

  final double fillRateBarPerMin;
  final double molesPerMin;
}

CompressorFillRate calculateCompressorFillRate({
  required double inletFlowLPerMin,
  required double receiverPressureBar,
  required double receiverOxygenPercent,
  required double receiverHeliumPercent,
  required double receiverVolumeL,
  required double ambientTemperatureC,
  required double receiverTemperatureC,
  required bool useVdw,
}) {
  final inletTemperatureK = ambientTemperatureC + 273.15;
  final receiverTemperatureK = receiverTemperatureC + 273.15;
  final zInlet = calcZ(
    atmosphericPressureBar,
    21,
    0,
    ambientTemperatureC,
    useVdw,
  );
  final zReceiver = calcZ(
    receiverPressureBar + gaugePressureOffsetBar,
    receiverOxygenPercent,
    receiverHeliumPercent,
    receiverTemperatureC,
    useVdw,
  );
  final molesPerMin =
      atmosphericPressureBar *
      inletFlowLPerMin /
      (zInlet * gasConstant * inletTemperatureK);
  final fillRateBarPerMin =
      molesPerMin *
      zReceiver *
      gasConstant *
      receiverTemperatureK /
      receiverVolumeL;

  return CompressorFillRate(
    fillRateBarPerMin: fillRateBarPerMin,
    molesPerMin: molesPerMin,
  );
}

// ---------------------------------------------------------------------------
// Cooling and pressure.
// ---------------------------------------------------------------------------

double calculateCoolingTime({
  required double transferEndTemperatureC,
  required double ambientTemperatureC,
  required double targetTemperatureC,
  required double tauMinutes,
}) {
  if (transferEndTemperatureC <= targetTemperatureC) return 0;

  return tauMinutes *
      math.log(
        (transferEndTemperatureC - ambientTemperatureC) /
            (targetTemperatureC - ambientTemperatureC),
      );
}

double? _estimateMeasuredWaitMinutes({
  required double? transferEndTemperatureC,
  required double ambientTemperatureC,
  required double? measuredTemperatureC,
  required double tauMinutes,
}) {
  if (transferEndTemperatureC == null || measuredTemperatureC == null) {
    return null;
  }
  if (!transferEndTemperatureC.isFinite ||
      !ambientTemperatureC.isFinite ||
      !measuredTemperatureC.isFinite ||
      !tauMinutes.isFinite) {
    return null;
  }
  if (measuredTemperatureC > transferEndTemperatureC ||
      measuredTemperatureC <= ambientTemperatureC) {
    return null;
  }
  final waitMinutes = calculateCoolingTime(
    transferEndTemperatureC: transferEndTemperatureC,
    ambientTemperatureC: ambientTemperatureC,
    targetTemperatureC: measuredTemperatureC,
    tauMinutes: tauMinutes,
  );
  return waitMinutes.isFinite && waitMinutes >= 0 ? waitMinutes : null;
}

double calculateTemperatureAfterWait({
  required double transferEndTemperatureC,
  required double ambientTemperatureC,
  required double waitMinutes,
  required double tauMinutes,
}) {
  return ambientTemperatureC +
      (transferEndTemperatureC - ambientTemperatureC) *
          math.exp(-waitMinutes / tauMinutes);
}

double calculatePressureAtTemperature({
  required double pressureBar,
  required double oxygenPercent,
  required double heliumPercent,
  required double fromTemperatureC,
  required double toTemperatureC,
  required double volumeL,
  required bool useVdw,
}) {
  final molarDensity = calcMolarDensity(
    pressureBar,
    oxygenPercent,
    heliumPercent,
    fromTemperatureC,
    useVdw,
  );

  return calcPressure(
    molarDensity,
    oxygenPercent,
    heliumPercent,
    toTemperatureC,
    useVdw,
  );
}

List<PressureProjection> projectPressureAtTemperatures({
  required double pressureBar,
  required double oxygenPercent,
  required double heliumPercent,
  required double fromTemperatureC,
  required List<double> temperaturesC,
  required double volumeL,
  required bool useVdw,
}) {
  return [
    for (final temperatureC in temperaturesC)
      PressureProjection(
        temperatureC: temperatureC,
        pressureBar: calculatePressureAtTemperature(
          pressureBar: pressureBar,
          oxygenPercent: oxygenPercent,
          heliumPercent: heliumPercent,
          fromTemperatureC: fromTemperatureC,
          toTemperatureC: temperatureC,
          volumeL: volumeL,
          useVdw: useVdw,
        ),
      ),
  ];
}

// ---------------------------------------------------------------------------
// Transfer temperature estimate.
// ---------------------------------------------------------------------------

List<TemperatureSample> _estimateTransferTemperatureSamples({
  required double startTemperatureC,
  double? startPressureBar,
  double? addedPressureBar,
  double? fillTimeMinutes,
  double? volumeL,
  double? heliumFraction,
  double? oxygenFraction,
  String? tankMaterial,
  String? coolingMedium,
  double? waterSubmersionPercent,
  double? tankMassKg,
  required double ambientTemperatureC,
  required double inletTemperatureC,
}) {
  final pressureChangeBar = _orFallback(addedPressureBar, 0);
  final pressureMagnitudeBar = pressureChangeBar.abs();
  final fillTimeSeconds = math.max(0.0, _orFallback(fillTimeMinutes, 0)) * 60;
  if (pressureMagnitudeBar <= 0 || fillTimeSeconds <= 0) {
    return [
      TemperatureSample(elapsedMinutes: 0, temperatureC: startTemperatureC),
    ];
  }

  final tankVolumeL = math.max(0.1, _orFallback(volumeL, 0.1));
  final startTemperatureK = startTemperatureC + 273.15;
  final ambientTemperatureK = ambientTemperatureC + 273.15;
  final inletTemperatureK = inletTemperatureC + 273.15;
  final fHe = _clamp(_orFallback(heliumFraction, 0), 0, 1);
  final fOxygen = _clamp(_orFallback(oxygenFraction ?? 0.21, 0), 0, 1 - fHe);
  final fNitrogen = math.max(0.0, 1 - fHe - fOxygen);
  final cvMolar = fHe * 12.47 + (fOxygen + fNitrogen) * 20.78;
  final cpMolar = fHe * 20.78 + (fOxygen + fNitrogen) * 29.10;
  final averageMolarMassKg = fHe * 0.004 + fOxygen * 0.032 + fNitrogen * 0.028;
  final cvKg = cvMolar / averageMolarMassKg;
  final cpKg = cpMolar / averageMolarMassKg;
  final specificGasConstant = 8.314 / averageMolarMassKg;

  final materialParams = materialThermal(tankMaterial);
  final defaultTankMassKg = materialParams.defaultTankMassKg;
  final tankMass = math.max(0.1, _orFallback(tankMassKg, defaultTankMassKg));
  final metalSpecificHeat = materialParams.specificHeatJPerKgK;
  final areaM2 = materialParams.areaM2;
  final wetFraction = _wetSurfaceFraction(waterSubmersionPercent);
  final heatTransferCoefficient = coolingMedium == 'water'
      ? wetFraction * heatTransferWaterWPerM2K +
            (1 - wetFraction) * heatTransferAirWPerM2K
      : heatTransferAirWPerM2K;
  final heatTransferArea = heatTransferCoefficient * areaM2;
  final volumeM3 = tankVolumeL * 0.001;
  final initialPressureBar = math.max(0.0, _orFallback(startPressureBar, 0));
  final targetPressureBar = math.max(
    0.0,
    initialPressureBar + pressureChangeBar,
  );
  var gasMassKg =
      (initialPressureBar + 1) *
      pascalsPerBar *
      volumeM3 /
      (specificGasConstant * startTemperatureK);
  final targetGasMassKg =
      (targetPressureBar + 1) *
      pascalsPerBar *
      volumeM3 /
      (specificGasConstant * ambientTemperatureK);
  final massFlowKgPerSecond = (targetGasMassKg - gasMassKg) / fillTimeSeconds;
  var temperatureK = startTemperatureK;
  var elapsedSeconds = 0.0;
  var nextSampleSeconds = 60.0;
  final samples = <TemperatureSample>[
    TemperatureSample(elapsedMinutes: 0, temperatureC: startTemperatureC),
  ];

  while (elapsedSeconds < fillTimeSeconds) {
    final stepSeconds = math.min(
      thermalIntegrationStepSeconds,
      fillTimeSeconds - elapsedSeconds,
    );
    final thermalCapacityJPerK =
        tankMass * metalSpecificHeat + gasMassKg * cvKg;
    final flowWorkWatts =
        massFlowKgPerSecond * (cpKg * inletTemperatureK - cvKg * temperatureK);
    final heatLossWatts =
        heatTransferArea * (temperatureK - ambientTemperatureK);
    temperatureK +=
        (flowWorkWatts - heatLossWatts) / thermalCapacityJPerK * stepSeconds;
    gasMassKg += massFlowKgPerSecond * stepSeconds;
    elapsedSeconds += stepSeconds;

    if (elapsedSeconds + _numberEpsilon >= nextSampleSeconds) {
      samples.add(
        TemperatureSample(
          elapsedMinutes: nextSampleSeconds / 60,
          temperatureC: temperatureK - 273.15,
        ),
      );
      nextSampleSeconds += 60;
    }
  }

  final finalTemperatureC = temperatureK - 273.15;
  if (samples.last.elapsedMinutes != fillTimeSeconds / 60) {
    samples.add(
      TemperatureSample(
        elapsedMinutes: fillTimeSeconds / 60,
        temperatureC: finalTemperatureC,
      ),
    );
  } else {
    samples[samples.length - 1] = TemperatureSample(
      elapsedMinutes: samples.last.elapsedMinutes,
      temperatureC: finalTemperatureC,
    );
  }
  return samples;
}

/// Final temperature after a transfer of [addedPressureBar] over
/// [fillTimeMinutes]. `inletTemperatureC` defaults to `ambientTemperatureC`,
/// which in turn defaults to `startTemperatureC`.
double estimateTransferTemperature({
  required double startTemperatureC,
  double? startPressureBar,
  double? addedPressureBar,
  double? fillTimeMinutes,
  double? volumeL,
  double? heliumFraction,
  double? oxygenFraction,
  String? tankMaterial,
  String? coolingMedium,
  double? waterSubmersionPercent,
  double? tankMassKg,
  double? ambientTemperatureC,
  double? inletTemperatureC,
}) {
  final ambient = ambientTemperatureC ?? startTemperatureC;
  return _estimateTransferTemperatureSamples(
    startTemperatureC: startTemperatureC,
    startPressureBar: startPressureBar,
    addedPressureBar: addedPressureBar,
    fillTimeMinutes: fillTimeMinutes,
    volumeL: volumeL,
    heliumFraction: heliumFraction,
    oxygenFraction: oxygenFraction,
    tankMaterial: tankMaterial,
    coolingMedium: coolingMedium,
    waterSubmersionPercent: waterSubmersionPercent,
    tankMassKg: tankMassKg,
    ambientTemperatureC: ambient,
    inletTemperatureC: inletTemperatureC ?? ambient,
  ).last.temperatureC;
}

double coolingTimeConstantMinutes(
  String? tankMaterial,
  String? coolingMedium, [
  double? waterSubmersionPercent,
]) {
  final materialParams = materialThermal(tankMaterial);
  final airTauMinutes = materialParams.airTauMinutes;
  if (coolingMedium != 'water') return airTauMinutes;
  final waterTauMinutes = materialParams.waterTauMinutes;
  final wetFraction = _wetSurfaceFraction(waterSubmersionPercent);
  return 1 /
      (wetFraction / waterTauMinutes + (1 - wetFraction) / airTauMinutes);
}

double _inletTemperatureFor(
  String rateSource,
  ThermalInput thermal,
  _ThermalBooster booster,
) {
  final baseTemperatureC = _finiteOr(
    thermal.inletTemperatureC,
    thermal.ambientTemperatureC,
  );
  if (rateSource == 'booster') {
    return baseTemperatureC + booster.boosterTemperatureModifierC;
  }
  if (rateSource == 'compressor') {
    return baseTemperatureC + booster.compressorTemperatureModifierC;
  }
  return baseTemperatureC;
}

double _stepTransferEndPressure(ProtocolStep step, double currentPressureBar) {
  if (step.type == 'salvage') {
    final resulting = _finiteOrNull(step.resultingPressureBar);
    if (resulting != null) return math.max(0.0, resulting);
  }
  final receiverEnd = _finiteOrNull(step.receiverEndPressureBar);
  if (receiverEnd != null) return math.max(0.0, receiverEnd);
  final resulting = _finiteOrNull(step.resultingPressureBar);
  if (resulting != null) return math.max(0.0, resulting);
  return math.max(0.0, currentPressureBar);
}

TransferRate _salvageTransferRate({
  required ProtocolStep step,
  required double currentPressureBar,
  required double currentTemperatureC,
  required double transferEndPressureBar,
  required PhysicsInput physics,
  required _ThermalBooster booster,
}) {
  final tankDropBar = math.max(
    0.0,
    currentPressureBar - transferEndPressureBar,
  );
  final bankStartPressureBar = math.max(
    0.0,
    step.receiverStartPressureBar ?? 0,
  );
  final bankRiseBar = math.max(
    0.0,
    (step.receiverEndPressureBar ?? bankStartPressureBar) -
        bankStartPressureBar,
  );
  if (tankDropBar <= 0 || bankRiseBar <= 0) {
    return TransferRate(
      rateSource: 'none',
      rateBarPerMin: null,
      pressureIncreaseBar: 0,
      pressureChangeBar: -tankDropBar,
    );
  }
  final sourceOxygenPercent =
      step.sourceOxygenPercent ?? step.resultingMix?.oxygenPercent ?? 0;
  final sourceHeliumPercent =
      step.sourceHeliumPercent ?? step.resultingMix?.heliumPercent ?? 0;
  final isOxygenRich = sourceOxygenPercent >= oxygenRichThreshold;
  final pressureChangeBar = -tankDropBar;
  if (step.stage == 'boost') {
    return TransferRate(
      rateSource: 'salvage-booster',
      rateBarPerMin: calculateBoosterFillRate(
        cylinderVolumeCm3: booster.cylinderVolumeCm3,
        bpm: isOxygenRich ? booster.oxygenBoostBpm : booster.otherBoostBpm,
        sourcePressureBar: (currentPressureBar + transferEndPressureBar) / 2,
        receiverPressureBar: bankStartPressureBar + bankRiseBar / 2,
        sourceOxygenPercent: sourceOxygenPercent,
        sourceHeliumPercent: sourceHeliumPercent,
        receiverOxygenPercent: step.receiverStartMix?.oxygenPercent ?? 0,
        receiverHeliumPercent: step.receiverStartMix?.heliumPercent ?? 0,
        receiverVolumeL: step.receiverVolumeL ?? double.nan,
        temperatureC: currentTemperatureC,
        useVdw: physics.useVdw,
      ).fillRateBarPerMin,
      pressureIncreaseBar: bankRiseBar,
      pressureChangeBar: pressureChangeBar,
    );
  }
  return TransferRate(
    rateSource: 'salvage-decant',
    rateBarPerMin: isOxygenRich
        ? booster.oxygenDecantRateBarPerMin
        : booster.otherDecantRateBarPerMin,
    pressureIncreaseBar: bankRiseBar,
    pressureChangeBar: pressureChangeBar,
  );
}

TransferRate _rateForProtocolStep({
  required ProtocolStep step,
  required double currentPressureBar,
  required double currentTemperatureC,
  required double transferEndPressureBar,
  required CylinderInput cylinder,
  required PhysicsInput physics,
  required ThermalInput thermal,
  required _ThermalBooster booster,
}) {
  if (step.type == 'salvage') {
    return _salvageTransferRate(
      step: step,
      currentPressureBar: currentPressureBar,
      currentTemperatureC: currentTemperatureC,
      transferEndPressureBar: transferEndPressureBar,
      physics: physics,
      booster: booster,
    );
  }
  final receiverMix = _stepMix(step);
  final sourceOxygenPercent =
      step.sourceOxygenPercent ?? receiverMix.oxygenPercent;
  final sourceHeliumPercent =
      step.sourceHeliumPercent ?? receiverMix.heliumPercent;
  final isOxygenRich = sourceOxygenPercent >= oxygenRichThreshold;
  final pressureDecreaseBar = math.max(
    0.0,
    currentPressureBar - transferEndPressureBar,
  );
  if (step.type == 'drain' && pressureDecreaseBar > 0) {
    return TransferRate(
      rateSource: 'draining-rate',
      rateBarPerMin: booster.drainingRateBarPerMin,
      pressureIncreaseBar: pressureDecreaseBar,
      pressureChangeBar: -pressureDecreaseBar,
    );
  }
  final pressureIncreaseBar = math.max(
    0.0,
    transferEndPressureBar - currentPressureBar,
  );
  if (pressureIncreaseBar <= 0) {
    return TransferRate(
      rateSource: 'none',
      rateBarPerMin: null,
      pressureIncreaseBar: pressureIncreaseBar,
      pressureChangeBar: 0,
    );
  }
  final useVdw = physics.useVdw;

  if (step.operation == 'Top-up') {
    return TransferRate(
      rateSource: 'compressor',
      rateBarPerMin: calculateCompressorFillRate(
        inletFlowLPerMin: booster.compressorInletFlowLPerMin,
        receiverPressureBar: (currentPressureBar + transferEndPressureBar) / 2,
        receiverOxygenPercent: receiverMix.oxygenPercent,
        receiverHeliumPercent: receiverMix.heliumPercent,
        receiverVolumeL: cylinder.volumeL,
        ambientTemperatureC: thermal.ambientTemperatureC,
        receiverTemperatureC: currentTemperatureC,
        useVdw: useVdw,
      ).fillRateBarPerMin,
      pressureIncreaseBar: pressureIncreaseBar,
    );
  }

  if (step.type == 'boost') {
    final sourcePressureBar =
        ((step.sourceStartPressureBar ?? 0) +
            (step.sourceEndPressureBar ?? 0)) /
        2;
    return TransferRate(
      rateSource: 'booster',
      rateBarPerMin: calculateBoosterFillRate(
        cylinderVolumeCm3: booster.cylinderVolumeCm3,
        bpm: isOxygenRich ? booster.oxygenBoostBpm : booster.otherBoostBpm,
        sourcePressureBar: sourcePressureBar,
        receiverPressureBar: (currentPressureBar + transferEndPressureBar) / 2,
        sourceOxygenPercent: sourceOxygenPercent,
        sourceHeliumPercent: sourceHeliumPercent,
        receiverOxygenPercent: receiverMix.oxygenPercent,
        receiverHeliumPercent: receiverMix.heliumPercent,
        receiverVolumeL: cylinder.volumeL,
        temperatureC: currentTemperatureC,
        useVdw: useVdw,
      ).fillRateBarPerMin,
      pressureIncreaseBar: pressureIncreaseBar,
    );
  }

  if (step.type == 'decant') {
    return TransferRate(
      rateSource: 'decant-rate',
      rateBarPerMin: isOxygenRich
          ? booster.oxygenDecantRateBarPerMin
          : booster.otherDecantRateBarPerMin,
      pressureIncreaseBar: pressureIncreaseBar,
    );
  }

  return TransferRate(
    rateSource: 'none',
    rateBarPerMin: null,
    pressureIncreaseBar: pressureIncreaseBar,
  );
}

/// Duration, rate, and temperature history of one transfer. Profiled sources
/// take them from [solveTransferProfile]; closed-form steps keep `dP / rate`.
class _TransferTimeline {
  const _TransferTimeline({
    required this.rateBarPerMin,
    required this.durationMinutes,
    required this.temperatureSamples,
    this.profileSamples,
  });

  final double? rateBarPerMin;
  final double durationMinutes;
  final List<TemperatureSample> temperatureSamples;
  final List<TransferProfileSample>? profileSamples;
}

_TransferTimeline _transferTimeline({
  required ProtocolStep step,
  required TransferRate transfer,
  required double currentPressureBar,
  required double currentTemperatureC,
  required double transferEndPressureBar,
  required GasMixPercent currentMix,
  required GasMixPercent receiverMix,
  required CylinderInput cylinder,
  required PhysicsInput physics,
  required ThermalInput thermal,
  required BoosterSettings? booster,
  required double inletTemperatureC,
}) {
  final profile = solveTransferProfile(
    TransferProfileInput(
      step: step,
      transfer: transfer,
      currentPressureBar: currentPressureBar,
      currentTemperatureC: currentTemperatureC,
      transferEndPressureBar: transferEndPressureBar,
      currentMix: currentMix,
      receiverMix: receiverMix,
      cylinder: cylinder,
      physics: physics,
      thermal: thermal,
      booster: booster,
      inletTemperatureC: inletTemperatureC,
    ),
  );
  if (profile != null) {
    return _TransferTimeline(
      rateBarPerMin: profile.rateBarPerMin,
      durationMinutes: profile.durationMinutes,
      temperatureSamples: profile.temperatureSamples,
      profileSamples: profile.profileSamples,
    );
  }
  final rate = transfer.rateBarPerMin;
  final durationMinutes = rate != null && rate > 0
      ? transfer.pressureIncreaseBar / rate
      : 0.0;
  final temperatureSamples = _hasTransferProfile(transfer.rateSource)
      ? _estimateTransferTemperatureSamples(
          startTemperatureC: currentTemperatureC,
          startPressureBar: currentPressureBar,
          addedPressureBar:
              transfer.pressureChangeBar ?? transfer.pressureIncreaseBar,
          fillTimeMinutes: durationMinutes,
          volumeL: cylinder.volumeL,
          heliumFraction:
              (step.sourceHeliumPercent ?? receiverMix.heliumPercent) / 100,
          oxygenFraction:
              (step.sourceOxygenPercent ?? receiverMix.oxygenPercent) / 100,
          tankMaterial: thermal.tankMaterial,
          coolingMedium: thermal.coolingMedium,
          waterSubmersionPercent: thermal.waterSubmersionPercent,
          tankMassKg: thermal.tankMassKg,
          ambientTemperatureC: thermal.ambientTemperatureC,
          inletTemperatureC: inletTemperatureC,
        )
      : [
          TemperatureSample(
            elapsedMinutes: 0,
            temperatureC: currentTemperatureC,
          ),
        ];
  return _TransferTimeline(
    rateBarPerMin: rate,
    durationMinutes: durationMinutes,
    temperatureSamples: temperatureSamples,
  );
}

// ---------------------------------------------------------------------------
// Thermal step sample profile.
// ---------------------------------------------------------------------------

List<ThermalSample> _buildThermalStepSamples({
  required double currentPressureBar,
  required double currentTemperatureC,
  required TransferRate transfer,
  required List<TemperatureSample> transferTemperatureSamples,
  List<TransferProfileSample>? transferProfileSamples,
  required double durationMinutes,
  required double transferEndPressureBar,
  required double pressureAtTransferEndAmbientBar,
  required double pressureAtTransferEndHotBar,
  required GasMixPercent receiverMix,
  GasMixPercent? receiverStartMix,
  required double temperatureAtTransferEndC,
  required double waitMinutes,
  required double temperatureAfterWaitC,
  required double pressureAfterWaitBar,
  required bool isFinalStep,
  required bool skipsConfiguredWait,
  required ThermalInput thermal,
  required double waitAmbientTemperatureC,
  required double tauMinutes,
  required CylinderInput cylinder,
  required bool useVdw,
}) {
  final samples = <ThermalSample>[];
  void append(
    double elapsedMinutes,
    double temperatureC,
    double pressureBar, {
    double? projectedPressureBar,
    double? ambientPressureBar,
    double? oxygenPercent,
    double? heliumPercent,
    double? pressureReferenceTemperatureC,
    double? pressureAtTransferEndReferenceBar,
    double? pressureAtTransferEndAmbientBar,
    double? pressureAtTransferEndHotBar,
    double? rateBarPerMin,
  }) {
    final sample = ThermalSample(
      elapsedMinutes: elapsedMinutes,
      temperatureC: temperatureC,
      pressureBar: math.max(0.0, pressureBar),
      projectedPressureBar: projectedPressureBar,
      ambientPressureBar: ambientPressureBar,
      oxygenPercent: oxygenPercent,
      heliumPercent: heliumPercent,
      pressureReferenceTemperatureC: pressureReferenceTemperatureC,
      pressureAtTransferEndReferenceBar: pressureAtTransferEndReferenceBar,
      pressureAtTransferEndAmbientBar: pressureAtTransferEndAmbientBar,
      pressureAtTransferEndHotBar: pressureAtTransferEndHotBar,
      rateBarPerMin: rateBarPerMin,
    );
    if (samples.isNotEmpty &&
        (samples.last.elapsedMinutes - elapsedMinutes).abs() < 1e-9) {
      samples[samples.length - 1] = sample;
    } else {
      samples.add(sample);
    }
  }

  append(
    0,
    currentTemperatureC,
    currentPressureBar,
    projectedPressureBar: currentPressureBar,
    pressureReferenceTemperatureC: currentTemperatureC,
  );
  final hotTransferEndPressure = pressureAtTransferEndHotBar;
  final ambientTransferEndPressure = pressureAtTransferEndAmbientBar;
  if (transferProfileSamples != null) {
    for (final point in transferProfileSamples) {
      final ambientPressureBar = calculatePressureAtTemperature(
        pressureBar: point.pressureBar,
        oxygenPercent: point.oxygenPercent,
        heliumPercent: point.heliumPercent,
        fromTemperatureC: point.temperatureC,
        toTemperatureC: thermal.ambientTemperatureC,
        volumeL: cylinder.volumeL,
        useVdw: useVdw,
      );
      final projectedPressureBar = calculatePressureAtTemperature(
        pressureBar: ambientPressureBar,
        oxygenPercent: point.oxygenPercent,
        heliumPercent: point.heliumPercent,
        fromTemperatureC: thermal.ambientTemperatureC,
        toTemperatureC: point.temperatureC,
        volumeL: cylinder.volumeL,
        useVdw: useVdw,
      );
      append(
        point.elapsedMinutes,
        point.temperatureC,
        point.pressureBar,
        projectedPressureBar: projectedPressureBar,
        ambientPressureBar: ambientPressureBar,
        oxygenPercent: point.oxygenPercent,
        heliumPercent: point.heliumPercent,
        pressureReferenceTemperatureC: point.temperatureC,
        rateBarPerMin: point.rateBarPerMin,
      );
    }
  } else if (_hasTransferProfile(transfer.rateSource)) {
    final startMix = receiverStartMix ?? receiverMix;
    final startAmbientPressureBar = calculatePressureAtTemperature(
      pressureBar: currentPressureBar,
      oxygenPercent: startMix.oxygenPercent,
      heliumPercent: startMix.heliumPercent,
      fromTemperatureC: currentTemperatureC,
      toTemperatureC: thermal.ambientTemperatureC,
      volumeL: cylinder.volumeL,
      useVdw: useVdw,
    );
    for (final sample in transferTemperatureSamples) {
      final transferProgress = durationMinutes > 0
          ? _clamp(sample.elapsedMinutes / durationMinutes, 0, 1)
          : 1.0;
      final ambientPressureBar =
          startAmbientPressureBar +
          (ambientTransferEndPressure - startAmbientPressureBar) *
              transferProgress;
      final oxygenPercent =
          startMix.oxygenPercent +
          (receiverMix.oxygenPercent - startMix.oxygenPercent) *
              transferProgress;
      final heliumPercent =
          startMix.heliumPercent +
          (receiverMix.heliumPercent - startMix.heliumPercent) *
              transferProgress;
      final projectedPressureBar = calculatePressureAtTemperature(
        pressureBar: ambientPressureBar,
        oxygenPercent: oxygenPercent,
        heliumPercent: heliumPercent,
        fromTemperatureC: thermal.ambientTemperatureC,
        toTemperatureC: sample.temperatureC,
        volumeL: cylinder.volumeL,
        useVdw: useVdw,
      );
      append(
        sample.elapsedMinutes,
        sample.temperatureC,
        currentPressureBar +
            (transferEndPressureBar - currentPressureBar) * transferProgress,
        projectedPressureBar: projectedPressureBar,
        ambientPressureBar: ambientPressureBar,
        oxygenPercent: oxygenPercent,
        heliumPercent: heliumPercent,
        pressureReferenceTemperatureC: sample.temperatureC,
      );
    }
  } else {
    append(
      0,
      temperatureAtTransferEndC,
      transferEndPressureBar,
      projectedPressureBar: hotTransferEndPressure,
      pressureReferenceTemperatureC: temperatureAtTransferEndC,
    );
  }
  final transferEndSamplePressureBar = samples.last.pressureBar;

  void appendWaitSample(double elapsedMinutes) {
    final double temperatureC;
    if (skipsConfiguredWait) {
      temperatureC = temperatureAtTransferEndC;
    } else if (isFinalStep && elapsedMinutes >= waitMinutes) {
      temperatureC = thermal.ambientTemperatureC;
    } else {
      temperatureC = calculateTemperatureAfterWait(
        transferEndTemperatureC: temperatureAtTransferEndC,
        ambientTemperatureC: waitAmbientTemperatureC,
        waitMinutes: elapsedMinutes,
        tauMinutes: tauMinutes,
      );
    }
    final pressureBar = elapsedMinutes >= waitMinutes
        ? pressureAfterWaitBar
        : calculatePressureAtTemperature(
            pressureBar: transferEndSamplePressureBar,
            oxygenPercent: receiverMix.oxygenPercent,
            heliumPercent: receiverMix.heliumPercent,
            fromTemperatureC: temperatureAtTransferEndC,
            toTemperatureC: temperatureC,
            volumeL: cylinder.volumeL,
            useVdw: useVdw,
          );
    final projectedPressureBar = elapsedMinutes >= waitMinutes
        ? pressureAfterWaitBar
        : calculatePressureAtTemperature(
            pressureBar: hotTransferEndPressure,
            oxygenPercent: receiverMix.oxygenPercent,
            heliumPercent: receiverMix.heliumPercent,
            fromTemperatureC: temperatureAtTransferEndC,
            toTemperatureC: temperatureC,
            volumeL: cylinder.volumeL,
            useVdw: useVdw,
          );
    append(
      durationMinutes + elapsedMinutes,
      temperatureC,
      pressureBar,
      projectedPressureBar: projectedPressureBar,
      oxygenPercent: receiverMix.oxygenPercent,
      heliumPercent: receiverMix.heliumPercent,
      pressureReferenceTemperatureC: temperatureC,
    );
  }

  for (
    var elapsedMinutes = 1.0;
    elapsedMinutes < waitMinutes;
    elapsedMinutes += 1
  ) {
    appendWaitSample(elapsedMinutes);
  }
  if (waitMinutes > 0) appendWaitSample(waitMinutes);
  append(
    durationMinutes + waitMinutes,
    temperatureAfterWaitC,
    pressureAfterWaitBar,
    projectedPressureBar: pressureAfterWaitBar,
    oxygenPercent: receiverMix.oxygenPercent,
    heliumPercent: receiverMix.heliumPercent,
    pressureReferenceTemperatureC: temperatureAfterWaitC,
    pressureAtTransferEndReferenceBar: transferEndPressureBar,
    pressureAtTransferEndAmbientBar: ambientTransferEndPressure,
    pressureAtTransferEndHotBar: hotTransferEndPressure,
  );
  return samples;
}

// ---------------------------------------------------------------------------
// Protocol simulations.
// ---------------------------------------------------------------------------

ThermalProtocolResult simulateThermalProtocol({
  required List<ProtocolStep> protocolSteps,
  required CylinderInput cylinder,
  required PhysicsInput physics,
  required ThermalInput thermal,
  BoosterSettings? booster,
}) {
  final boosterSettings = _ThermalBooster.from(booster);
  final tauMinutes = coolingTimeConstantMinutes(
    thermal.tankMaterial,
    thermal.coolingMedium,
    thermal.waterSubmersionPercent,
  );
  final finalSettledTemperatureC = thermal.ambientTemperatureC;
  final useVdw = physics.useVdw;
  final firstStep = protocolSteps.isEmpty ? null : protocolSteps.first;
  var currentPressureBar = math.max(
    0.0,
    cylinder.initialPressureBar ??
        firstStep?.receiverStartPressureBar ??
        firstStep?.resultingPressureBar ??
        0,
  );
  var currentTemperatureC = physics.temperatureC;
  if (protocolSteps.isEmpty) {
    final finalAmbientPressureBar = calculatePressureAtTemperature(
      pressureBar: currentPressureBar,
      oxygenPercent: cylinder.initialOxygenPercent ?? 0,
      heliumPercent: cylinder.initialHeliumPercent ?? 0,
      fromTemperatureC: currentTemperatureC,
      toTemperatureC: thermal.ambientTemperatureC,
      volumeL: cylinder.volumeL,
      useVdw: useVdw,
    );
    return ThermalProtocolResult(
      protocolSteps: const [],
      finalSummary: ThermalFinal(
        finalTransferEndPressureBar: currentPressureBar,
        finalTransferEndTemperatureC: currentTemperatureC,
        finalAmbientPressureBar: finalAmbientPressureBar,
        finalAmbientTemperatureC: thermal.ambientTemperatureC,
      ),
    );
  }

  var currentMix = GasMixPercent(
    oxygenPercent: cylinder.initialOxygenPercent ?? 0,
    heliumPercent: cylinder.initialHeliumPercent ?? 0,
  );
  ThermalStep? previousThermal;
  final simulatedProtocolSteps = <ProtocolStep>[];
  for (var index = 0; index < protocolSteps.length; index++) {
    final step = protocolSteps[index];
    final int? measurementIndex = step.measurementIndexExplicitNull
        ? null
        : (step.measurementIndex ?? index);
    final InterimMeasurement? measuredStart = measurementIndex == null
        ? null
        : _interimAt(thermal.interimMeasurements, measurementIndex);
    final plannedStartPressureBar = currentPressureBar;
    final plannedStartTemperatureC = currentTemperatureC;
    final measurementApplied = step.applyInterimMeasurement != false;
    final measuredPressureBar = _finiteOrNull(measuredStart?.pressureBar);
    if (measurementApplied && measuredPressureBar != null) {
      currentPressureBar = math.max(0.0, measuredPressureBar);
    }
    final measuredTemperatureC = _finiteOrNull(measuredStart?.temperatureC);
    if (measurementApplied && measuredTemperatureC != null) {
      currentTemperatureC = measuredTemperatureC;
    }
    final measuredWaitMinutes = _estimateMeasuredWaitMinutes(
      transferEndTemperatureC: previousThermal?.temperatureAtTransferEndC,
      ambientTemperatureC: thermal.ambientTemperatureC,
      measuredTemperatureC: measuredStart?.temperatureC,
      tauMinutes: tauMinutes,
    );
    final pressureStartBar = currentPressureBar;
    final temperatureStartC = currentTemperatureC;
    final pressureReferenceTemperatureC = _finiteOr(
      step.pressureReferenceTemperatureC,
      physics.temperatureC,
    );
    final targetMix = _stepMix(step);
    final referencePressureBar = _finiteOrNull(
      step.pressureAtTransferEndReferenceBar,
    );
    final hasTransferEndPressure =
        referencePressureBar != null ||
        _finiteOrNull(step.receiverEndPressureBar) != null ||
        _finiteOrNull(step.resultingPressureBar) != null;
    final transferEndReferencePressureBar = referencePressureBar != null
        ? math.max(0.0, referencePressureBar)
        : hasTransferEndPressure
        ? _stepTransferEndPressure(step, currentPressureBar)
        : calculatePressureAtTemperature(
            pressureBar: currentPressureBar,
            oxygenPercent: currentMix.oxygenPercent,
            heliumPercent: currentMix.heliumPercent,
            fromTemperatureC: currentTemperatureC,
            toTemperatureC: pressureReferenceTemperatureC,
            volumeL: cylinder.volumeL,
            useVdw: useVdw,
          );
    final transferEndPressureBar = calculatePressureAtTemperature(
      pressureBar: transferEndReferencePressureBar,
      oxygenPercent: targetMix.oxygenPercent,
      heliumPercent: targetMix.heliumPercent,
      fromTemperatureC: pressureReferenceTemperatureC,
      toTemperatureC: currentTemperatureC,
      volumeL: cylinder.volumeL,
      useVdw: useVdw,
    );
    final transfer = _rateForProtocolStep(
      step: step,
      currentPressureBar: currentPressureBar,
      currentTemperatureC: currentTemperatureC,
      transferEndPressureBar: transferEndPressureBar,
      cylinder: cylinder,
      physics: physics,
      thermal: thermal,
      booster: boosterSettings,
    );
    final noTransfer =
        transfer.rateSource == 'none' && transfer.pressureIncreaseBar <= 0;
    final receiverMix = noTransfer ? currentMix : targetMix;
    final receiverStartMix = step.receiverStartMix ?? currentMix;
    final inletTemperatureC = _inletTemperatureFor(
      transfer.rateSource,
      thermal,
      boosterSettings,
    );
    final timeline = _transferTimeline(
      step: step,
      transfer: transfer,
      currentPressureBar: currentPressureBar,
      currentTemperatureC: currentTemperatureC,
      transferEndPressureBar: transferEndPressureBar,
      currentMix: currentMix,
      receiverMix: receiverMix,
      cylinder: cylinder,
      physics: physics,
      thermal: thermal,
      booster: booster,
      inletTemperatureC: inletTemperatureC,
    );
    final durationMinutes = timeline.durationMinutes;
    final transferTemperatureSamples = timeline.temperatureSamples;
    final temperatureAtTransferEndC =
        transferTemperatureSamples.last.temperatureC;
    final pressureAtTransferEndReferenceBar = noTransfer
        ? calculatePressureAtTemperature(
            pressureBar: currentPressureBar,
            oxygenPercent: currentMix.oxygenPercent,
            heliumPercent: currentMix.heliumPercent,
            fromTemperatureC: currentTemperatureC,
            toTemperatureC: pressureReferenceTemperatureC,
            volumeL: cylinder.volumeL,
            useVdw: useVdw,
          )
        : transferEndReferencePressureBar;
    final pressureAtTransferEndAmbientBar = noTransfer
        ? calculatePressureAtTemperature(
            pressureBar: currentPressureBar,
            oxygenPercent: currentMix.oxygenPercent,
            heliumPercent: currentMix.heliumPercent,
            fromTemperatureC: currentTemperatureC,
            toTemperatureC: thermal.ambientTemperatureC,
            volumeL: cylinder.volumeL,
            useVdw: useVdw,
          )
        : step.pressureAtTransferEndAmbientBar ??
              calculatePressureAtTemperature(
                pressureBar: pressureAtTransferEndReferenceBar,
                oxygenPercent: receiverMix.oxygenPercent,
                heliumPercent: receiverMix.heliumPercent,
                fromTemperatureC: pressureReferenceTemperatureC,
                toTemperatureC: thermal.ambientTemperatureC,
                volumeL: cylinder.volumeL,
                useVdw: useVdw,
              );
    final pressureAtTransferEndHotBar = noTransfer
        ? currentPressureBar
        : step.pressureAtTransferEndHotBar ??
              calculatePressureAtTemperature(
                pressureBar: pressureAtTransferEndReferenceBar,
                oxygenPercent: receiverMix.oxygenPercent,
                heliumPercent: receiverMix.heliumPercent,
                fromTemperatureC: pressureReferenceTemperatureC,
                toTemperatureC: temperatureAtTransferEndC,
                volumeL: cylinder.volumeL,
                useVdw: useVdw,
              );
    final isFinalStep = index == protocolSteps.length - 1;
    final skipsConfiguredWait =
        !isFinalStep && index == 0 && step.type == 'keep';
    final safetyWaitOnly = step.safetyWaitOnly == true;
    final waitAmbientTemperatureC = thermal.ambientTemperatureC;
    final intermediateTargetTemperatureC =
        thermal.targetMediumTemperatureC ??
        thermal.targetTemperatureC ??
        double.nan;
    final intermediateIsAmbient =
        (intermediateTargetTemperatureC - thermal.ambientTemperatureC).abs() <
        1e-9;
    final double configuredWaitMinutes;
    if (skipsConfiguredWait || safetyWaitOnly) {
      configuredWaitMinutes = 0;
    } else if (isFinalStep) {
      configuredWaitMinutes = 4.6 * tauMinutes;
    } else if (thermal.waitMode == 'temperature') {
      configuredWaitMinutes = intermediateIsAmbient
          ? 4.6 * tauMinutes
          : calculateCoolingTime(
              transferEndTemperatureC: temperatureAtTransferEndC,
              ambientTemperatureC: thermal.ambientTemperatureC,
              targetTemperatureC: intermediateTargetTemperatureC,
              tauMinutes: tauMinutes,
            );
    } else {
      configuredWaitMinutes = _finiteOr(thermal.waitMinutes, 0);
    }
    final waitMinutes = skipsConfiguredWait
        ? 0.0
        : math.max(
            0.0,
            configuredWaitMinutes + _orFallback(step.automaticWaitMinutes, 0),
          );
    final double temperatureAfterWaitC;
    if (skipsConfiguredWait) {
      temperatureAfterWaitC = temperatureAtTransferEndC;
    } else if (isFinalStep) {
      temperatureAfterWaitC = finalSettledTemperatureC;
    } else if (thermal.waitMode == 'temperature' && intermediateIsAmbient) {
      temperatureAfterWaitC = thermal.ambientTemperatureC;
    } else {
      temperatureAfterWaitC = calculateTemperatureAfterWait(
        transferEndTemperatureC: temperatureAtTransferEndC,
        ambientTemperatureC: thermal.ambientTemperatureC,
        waitMinutes: waitMinutes,
        tauMinutes: tauMinutes,
      );
    }
    final pressureAfterWaitBar = math.max(
      0.0,
      calculatePressureAtTemperature(
        pressureBar: pressureAtTransferEndHotBar,
        oxygenPercent: receiverMix.oxygenPercent,
        heliumPercent: receiverMix.heliumPercent,
        fromTemperatureC: temperatureAtTransferEndC,
        toTemperatureC: temperatureAfterWaitC,
        volumeL: cylinder.volumeL,
        useVdw: useVdw,
      ),
    );
    final thermalStep = ThermalStep(
      plannedStartPressureBar: plannedStartPressureBar,
      plannedStartTemperatureC: plannedStartTemperatureC,
      pressureStartBar: pressureStartBar,
      rateSource: transfer.rateSource,
      rateBarPerMin: timeline.rateBarPerMin,
      durationMinutes: durationMinutes,
      inletTemperatureC: inletTemperatureC,
      measurementIndex: measurementIndex,
      measurementApplied: measurementApplied,
      measuredStartPressureBar:
          measuredStart?.pressureBar ??
          (measurementIndex == null
              ? pressureStartBar
              : step.scheduledMeasuredStartPressureBar ?? pressureStartBar),
      measuredStartTemperatureC:
          measuredStart?.temperatureC ??
          (measurementIndex == null
              ? temperatureStartC
              : step.scheduledMeasuredStartTemperatureC ?? temperatureStartC),
      temperatureStartC: temperatureStartC,
      temperatureAtTransferEndC: temperatureAtTransferEndC,
      pressureReferenceTemperatureC: pressureReferenceTemperatureC,
      receiverStartMix: receiverStartMix,
      configuredWaitMinutes: configuredWaitMinutes,
      automaticWaitMinutes: _orFallback(step.automaticWaitMinutes, 0),
      measuredWaitMinutes: measuredWaitMinutes,
      waitMinutes: waitMinutes,
      temperatureAfterWaitC: temperatureAfterWaitC,
      pressureAtTransferEndReferenceBar: pressureAtTransferEndReferenceBar,
      pressureAtTransferEndAmbientBar: pressureAtTransferEndAmbientBar,
      pressureAtTransferEndBar: pressureAtTransferEndHotBar,
      pressureAtTransferEndHotBar: pressureAtTransferEndHotBar,
      pressureAfterWaitBar: pressureAfterWaitBar,
      samples: _buildThermalStepSamples(
        currentPressureBar: currentPressureBar,
        currentTemperatureC: currentTemperatureC,
        transfer: transfer,
        transferTemperatureSamples: transferTemperatureSamples,
        transferProfileSamples: timeline.profileSamples,
        durationMinutes: durationMinutes,
        transferEndPressureBar: pressureAtTransferEndReferenceBar,
        pressureAtTransferEndAmbientBar: pressureAtTransferEndAmbientBar,
        pressureAtTransferEndHotBar: pressureAtTransferEndHotBar,
        receiverMix: receiverMix,
        receiverStartMix: receiverStartMix,
        temperatureAtTransferEndC: temperatureAtTransferEndC,
        waitMinutes: waitMinutes,
        temperatureAfterWaitC: temperatureAfterWaitC,
        pressureAfterWaitBar: pressureAfterWaitBar,
        isFinalStep: isFinalStep,
        skipsConfiguredWait: skipsConfiguredWait,
        thermal: thermal,
        waitAmbientTemperatureC: waitAmbientTemperatureC,
        tauMinutes: tauMinutes,
        cylinder: cylinder,
        useVdw: useVdw,
      ),
    );

    currentPressureBar = math.max(0.0, pressureAfterWaitBar);
    currentTemperatureC = temperatureAfterWaitC;
    previousThermal = thermalStep;
    currentMix = receiverMix;
    simulatedProtocolSteps.add(step.copyWith(thermal: thermalStep));
  }

  final finalStep = simulatedProtocolSteps.last.thermal;
  return ThermalProtocolResult(
    protocolSteps: simulatedProtocolSteps,
    finalSummary: ThermalFinal(
      finalTransferEndPressureBar: finalStep == null
          ? currentPressureBar
          : finalStep.pressureAtTransferEndHotBar,
      finalTransferEndTemperatureC: finalStep == null
          ? currentTemperatureC
          : finalStep.temperatureAtTransferEndC,
      finalAmbientPressureBar: finalStep == null
          ? currentPressureBar
          : finalStep.pressureAfterWaitBar,
      finalAmbientTemperatureC: finalStep == null
          ? currentTemperatureC
          : finalStep.temperatureAfterWaitC,
    ),
  );
}

InterimMeasurement? _interimAt(
  List<InterimMeasurement?>? measurements,
  int index,
) {
  if (measurements == null || index < 0 || index >= measurements.length) {
    return null;
  }
  return measurements[index];
}

ThermalCompareResult simulateCompareProtocol({
  required List<ProtocolStep> protocolSteps,
  required CylinderInput cylinder,
  required PhysicsInput physics,
  required ThermalInput thermal,
  BoosterSettings? booster,
}) {
  final boosterSettings = _ThermalBooster.from(booster);
  final tauMinutes = coolingTimeConstantMinutes(
    thermal.tankMaterial,
    thermal.coolingMedium,
    thermal.waterSubmersionPercent,
  );
  final useVdw = physics.useVdw;
  final firstStep = protocolSteps.isEmpty ? null : protocolSteps.first;
  var currentPressureBar = math.max(
    0.0,
    cylinder.initialPressureBar ??
        firstStep?.receiverStartPressureBar ??
        firstStep?.resultingPressureBar ??
        0,
  );
  var currentTemperatureC = physics.temperatureC;
  var currentMix = GasMixPercent(
    oxygenPercent:
        cylinder.initialOxygenPercent ??
        firstStep?.resultingMix?.oxygenPercent ??
        0,
    heliumPercent:
        cylinder.initialHeliumPercent ??
        firstStep?.resultingMix?.heliumPercent ??
        0,
  );

  final simulatedProtocolSteps = <ProtocolStep>[];
  for (final step in protocolSteps) {
    final pressureStartBar = currentPressureBar;
    final temperatureStartC = currentTemperatureC;
    final receiverMix = _stepMix(step);
    final isWait = step.type == 'wait';
    final isKeep = step.type == 'keep';
    final requestedTransferEndPressureBar = isWait || isKeep
        ? currentPressureBar
        : _stepTransferEndPressure(step, currentPressureBar);
    var transferEndPressureBar =
        step.pressureAtTransferEndReferenceBar ??
        requestedTransferEndPressureBar;
    var transfer = const TransferRate(
      rateSource: 'none',
      rateBarPerMin: null,
      pressureIncreaseBar: 0,
    );
    var durationMinutes = 0.0;
    var inletTemperatureC = _inletTemperatureFor(
      'none',
      thermal,
      boosterSettings,
    );
    var transferTemperatureSamples = <TemperatureSample>[
      TemperatureSample(elapsedMinutes: 0, temperatureC: currentTemperatureC),
    ];
    var temperatureAtTransferEndC = currentTemperatureC;
    var hasTransferProfile = false;
    double? transferRateBarPerMin;
    List<TransferProfileSample>? transferProfileSamples;
    var pressureAtTransferEndHotBar = transferEndPressureBar;
    final solveHotEndpoint =
        !isWait &&
        !isKeep &&
        _finiteOrNull(step.pressureAtTransferEndReferenceBar) == null;

    final iterations = solveHotEndpoint ? 8 : 1;
    for (var iteration = 0; iteration < iterations; iteration++) {
      final ProtocolStep transferStep;
      if (step.type == 'add') {
        if (step.method == 'boost') {
          transferStep = step.copyWith(
            type: 'boost',
            sourceStartPressureBar: step.sourcePressureBar,
            sourceEndPressureBar: step.sourcePressureBar,
          );
        } else if (step.method == 'compressor') {
          transferStep = step.copyWith(type: 'boost', operation: 'Top-up');
        } else {
          transferStep = step.copyWith(type: 'decant');
        }
      } else if (step.type == 'equalize') {
        transferStep = step.copyWith(type: 'decant');
      } else {
        transferStep = step;
      }
      transfer = isWait || isKeep
          ? const TransferRate(
              rateSource: 'none',
              rateBarPerMin: null,
              pressureIncreaseBar: 0,
              pressureChangeBar: 0,
            )
          : _rateForProtocolStep(
              step: transferStep,
              currentPressureBar: currentPressureBar,
              currentTemperatureC: currentTemperatureC,
              transferEndPressureBar: transferEndPressureBar,
              cylinder: cylinder,
              physics: physics,
              thermal: thermal,
              booster: boosterSettings,
            );
      inletTemperatureC = _inletTemperatureFor(
        transfer.rateSource,
        thermal,
        boosterSettings,
      );
      hasTransferProfile = _hasTransferProfile(transfer.rateSource);
      final timeline = _transferTimeline(
        step: transferStep,
        transfer: transfer,
        currentPressureBar: currentPressureBar,
        currentTemperatureC: currentTemperatureC,
        transferEndPressureBar: transferEndPressureBar,
        currentMix: currentMix,
        receiverMix: receiverMix,
        cylinder: cylinder,
        physics: physics,
        thermal: thermal,
        booster: booster,
        inletTemperatureC: inletTemperatureC,
      );
      durationMinutes = timeline.durationMinutes;
      transferRateBarPerMin = timeline.rateBarPerMin;
      transferProfileSamples = timeline.profileSamples;
      transferTemperatureSamples = timeline.temperatureSamples;
      temperatureAtTransferEndC = transferTemperatureSamples.last.temperatureC;
      pressureAtTransferEndHotBar = hasTransferProfile
          ? calculatePressureAtTemperature(
              pressureBar: transferEndPressureBar,
              oxygenPercent: receiverMix.oxygenPercent,
              heliumPercent: receiverMix.heliumPercent,
              fromTemperatureC: physics.temperatureC,
              toTemperatureC: temperatureAtTransferEndC,
              volumeL: cylinder.volumeL,
              useVdw: useVdw,
            )
          : transferEndPressureBar;
      if (!solveHotEndpoint || !hasTransferProfile) break;
      final solvedReferencePressureBar = calculatePressureAtTemperature(
        pressureBar: requestedTransferEndPressureBar,
        oxygenPercent: receiverMix.oxygenPercent,
        heliumPercent: receiverMix.heliumPercent,
        fromTemperatureC: temperatureAtTransferEndC,
        toTemperatureC: physics.temperatureC,
        volumeL: cylinder.volumeL,
        useVdw: useVdw,
      );
      final lowerBound = math.min(
        currentPressureBar,
        requestedTransferEndPressureBar,
      );
      final upperBound = math.max(
        currentPressureBar,
        requestedTransferEndPressureBar,
      );
      final nextReferencePressureBar = _clamp(
        solvedReferencePressureBar,
        lowerBound,
        upperBound,
      );
      if ((nextReferencePressureBar - transferEndPressureBar).abs() < 1e-7) {
        break;
      }
      transferEndPressureBar = nextReferencePressureBar;
    }
    final pressureAtTransferEndReferenceBar = transferEndPressureBar;
    final pressureAtTransferEndAmbientBar = hasTransferProfile
        ? calculatePressureAtTemperature(
            pressureBar: pressureAtTransferEndReferenceBar,
            oxygenPercent: receiverMix.oxygenPercent,
            heliumPercent: receiverMix.heliumPercent,
            fromTemperatureC: physics.temperatureC,
            toTemperatureC: thermal.ambientTemperatureC,
            volumeL: cylinder.volumeL,
            useVdw: useVdw,
          )
        : pressureAtTransferEndReferenceBar;
    var waitMinutes = isWait ? _finiteOr(step.waitMinutes, 0) : 0.0;
    double? targetWaitTemperatureC;
    if (isWait && step.waitMode == 'target') {
      final targetTemperatureC = step.targetTemperatureC ?? double.nan;
      final targetIsAmbient =
          (targetTemperatureC - thermal.ambientTemperatureC).abs() < 1e-9;
      if (!targetTemperatureC.isFinite ||
          targetTemperatureC < thermal.ambientTemperatureC - 1e-9 ||
          temperatureAtTransferEndC < targetTemperatureC - 1e-9) {
        throw CompareSimulationError(
          'Compare target wait cannot reach the requested target temperature.',
          {
            'targetTemperatureC': step.targetTemperatureC,
            'temperatureAtTransferEndC': temperatureAtTransferEndC,
            'ambientTemperatureC': thermal.ambientTemperatureC,
          },
        );
      }
      targetWaitTemperatureC = targetIsAmbient
          ? thermal.ambientTemperatureC
          : targetTemperatureC;
      waitMinutes = targetIsAmbient
          ? 4.6 * tauMinutes
          : calculateCoolingTime(
              transferEndTemperatureC: temperatureAtTransferEndC,
              ambientTemperatureC: thermal.ambientTemperatureC,
              targetTemperatureC: targetTemperatureC,
              tauMinutes: tauMinutes,
            );
    }
    final temperatureAfterWaitC =
        targetWaitTemperatureC ??
        calculateTemperatureAfterWait(
          transferEndTemperatureC: temperatureAtTransferEndC,
          ambientTemperatureC: thermal.ambientTemperatureC,
          waitMinutes: waitMinutes,
          tauMinutes: tauMinutes,
        );
    final pressureAfterWaitBar = math.max(
      0.0,
      calculatePressureAtTemperature(
        pressureBar: pressureAtTransferEndHotBar,
        oxygenPercent: receiverMix.oxygenPercent,
        heliumPercent: receiverMix.heliumPercent,
        fromTemperatureC: temperatureAtTransferEndC,
        toTemperatureC: temperatureAfterWaitC,
        volumeL: cylinder.volumeL,
        useVdw: useVdw,
      ),
    );
    final thermalStep = ThermalStep(
      rateSource: transfer.rateSource,
      rateBarPerMin: transferRateBarPerMin,
      durationMinutes: durationMinutes,
      inletTemperatureC: inletTemperatureC,
      pressureStartBar: pressureStartBar,
      temperatureStartC: temperatureStartC,
      temperatureAtTransferEndC: temperatureAtTransferEndC,
      pressureReferenceTemperatureC: physics.temperatureC,
      pressureAtTransferEndReferenceBar: pressureAtTransferEndReferenceBar,
      pressureAtTransferEndAmbientBar: pressureAtTransferEndAmbientBar,
      waitMinutes: waitMinutes,
      temperatureAfterWaitC: temperatureAfterWaitC,
      pressureAtTransferEndBar: pressureAtTransferEndHotBar,
      pressureAtTransferEndHotBar: pressureAtTransferEndHotBar,
      pressureAfterWaitBar: pressureAfterWaitBar,
      samples: _buildThermalStepSamples(
        currentPressureBar: currentPressureBar,
        currentTemperatureC: currentTemperatureC,
        transfer: transfer,
        transferTemperatureSamples: transferTemperatureSamples,
        durationMinutes: durationMinutes,
        transferProfileSamples: transferProfileSamples,
        transferEndPressureBar: transferEndPressureBar,
        pressureAtTransferEndAmbientBar: pressureAtTransferEndAmbientBar,
        pressureAtTransferEndHotBar: pressureAtTransferEndHotBar,
        receiverMix: receiverMix,
        temperatureAtTransferEndC: temperatureAtTransferEndC,
        waitMinutes: waitMinutes,
        temperatureAfterWaitC: temperatureAfterWaitC,
        pressureAfterWaitBar: pressureAfterWaitBar,
        isFinalStep: false,
        skipsConfiguredWait: false,
        thermal: thermal,
        waitAmbientTemperatureC: thermal.ambientTemperatureC,
        tauMinutes: tauMinutes,
        cylinder: cylinder,
        useVdw: useVdw,
      ),
    );

    currentPressureBar = pressureAfterWaitBar;
    currentTemperatureC = temperatureAfterWaitC;
    currentMix = receiverMix;
    simulatedProtocolSteps.add(step.copyWith(thermal: thermalStep));
  }

  final recipeEnd = StateSnapshot(
    pressureBar: currentPressureBar,
    temperatureC: currentTemperatureC,
    oxygenPercent: currentMix.oxygenPercent,
    heliumPercent: currentMix.heliumPercent,
  );
  final ambientSettled = StateSnapshot(
    pressureBar: math.max(
      0.0,
      calculatePressureAtTemperature(
        pressureBar: recipeEnd.pressureBar,
        oxygenPercent: recipeEnd.oxygenPercent,
        heliumPercent: recipeEnd.heliumPercent,
        fromTemperatureC: recipeEnd.temperatureC,
        toTemperatureC: thermal.ambientTemperatureC,
        volumeL: cylinder.volumeL,
        useVdw: useVdw,
      ),
    ),
    temperatureC: thermal.ambientTemperatureC,
    oxygenPercent: recipeEnd.oxygenPercent,
    heliumPercent: recipeEnd.heliumPercent,
  );
  final inWaterTemperatureC = _finiteOrNull(thermal.targetInWaterTemperatureC);
  final StateSnapshot? inWater = inWaterTemperatureC == null
      ? null
      : StateSnapshot(
          pressureBar: math.max(
            0.0,
            calculatePressureAtTemperature(
              pressureBar: ambientSettled.pressureBar,
              oxygenPercent: ambientSettled.oxygenPercent,
              heliumPercent: ambientSettled.heliumPercent,
              fromTemperatureC: ambientSettled.temperatureC,
              toTemperatureC: inWaterTemperatureC,
              volumeL: cylinder.volumeL,
              useVdw: useVdw,
            ),
          ),
          temperatureC: inWaterTemperatureC,
          oxygenPercent: ambientSettled.oxygenPercent,
          heliumPercent: ambientSettled.heliumPercent,
        );
  return ThermalCompareResult(
    protocolSteps: simulatedProtocolSteps,
    finalSummary: CompareFinal(
      recipeEnd: recipeEnd,
      ambientSettled: ambientSettled,
      ambientSettledDurationMinutes: 4.6 * tauMinutes,
      inWater: inWater,
    ),
  );
}

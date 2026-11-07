part of '../compare_recipe.dart';

// ---------------------------------------------------------------------------
// Protocol results
// ---------------------------------------------------------------------------

class CompareSourceState {
  const CompareSourceState({
    required this.bankId,
    required this.name,
    required this.volumeL,
    required this.pressureBar,
    required this.moles,
    required this.oxygenPercent,
    required this.heliumPercent,
  });

  final String bankId;
  final String name;
  final double volumeL;
  final double pressureBar;
  final double moles;
  final double oxygenPercent;
  final double heliumPercent;
}

class CompareSourceSnapshot {
  const CompareSourceSnapshot({
    required this.pressureBar,
    required this.moles,
    required this.oxygenPercent,
    required this.heliumPercent,
  });

  final double? pressureBar;
  final double? moles;
  final double oxygenPercent;
  final double heliumPercent;
}

class CompareSourceBankSummary {
  const CompareSourceBankSummary({
    required this.id,
    required this.name,
    required this.initial,
    required this.finalState,
  });

  final String id;
  final String name;
  final CompareSourceSnapshot initial;
  final CompareSourceSnapshot finalState;
}

class CompareTransferRate {
  const CompareTransferRate({
    required this.source,
    this.rateBarPerMin,
    this.estimatedDurationMinutes,
    this.boosterBpm,
    this.boosterCylinderVolumeCm3,
  });

  final String source;
  final double? rateBarPerMin;
  final double? estimatedDurationMinutes;
  final double? boosterBpm;
  final double? boosterCylinderVolumeCm3;
}

class CompareStep {
  const CompareStep({
    required this.type,
    required this.compareRowId,
    required this.receiverStartPressureBar,
    required this.receiverEndPressureBar,
    required this.resultingPressureBar,
    required this.resultingMix,
    required this.operation,
    required this.recipeAction,
    required this.title,
    required this.recipeLabel,
    this.method,
    this.sourceBankId,
    this.sourceBankName,
    this.sourceComposition,
    this.sourceOxygenPercent,
    this.sourceHeliumPercent,
    this.sourceStartPressureBar,
    this.sourceEndPressureBar,
    this.sourceState,
    this.sourceMolesAfter,
    this.transferRate,
    this.oxygenCompressionRatio,
    this.recipeGas,
    this.waitMinutes,
    this.waitMode,
    this.targetTemperatureC,
    this.costOperation,
    this.sourceConsumedMoles,
    this.costOperationId,
    this.sourceVolumeL,
    this.sourceStartMoles,
  });

  final String type;
  final String? method;
  final String compareRowId;
  final String? sourceBankId;
  final String? sourceBankName;
  final GasMixPercent? sourceComposition;
  final double? sourceOxygenPercent;
  final double? sourceHeliumPercent;
  final double? sourceStartPressureBar;
  final double? sourceEndPressureBar;
  final CompareSourceState? sourceState;
  final double? sourceMolesAfter;
  final double receiverStartPressureBar;
  final double receiverEndPressureBar;
  final double resultingPressureBar;
  final GasMixPercent resultingMix;
  final CompareTransferRate? transferRate;
  final double? oxygenCompressionRatio;
  final String operation;
  final String recipeAction;
  final String? recipeGas;
  final String title;
  final String recipeLabel;
  final double? waitMinutes;
  final String? waitMode;
  final double? targetTemperatureC;
  final String? costOperation;
  final double? sourceConsumedMoles;
  final String? costOperationId;
  final double? sourceVolumeL;
  final double? sourceStartMoles;
}

class CompareTrajectoryPoint {
  const CompareTrajectoryPoint({
    required this.step,
    required this.label,
    required this.oxygenPercent,
    required this.heliumPercent,
    required this.nitrogenPercent,
    required this.pressureBar,
    required this.pressureDeltaBar,
    required this.color,
  });

  final int step;
  final String label;
  final double oxygenPercent;
  final double heliumPercent;
  final double nitrogenPercent;
  final double pressureBar;
  final double pressureDeltaBar;
  final String color;
}

class CompareSummary {
  const CompareSummary({
    required this.retainedPressureBar,
    required this.retainedPercent,
    required this.ventedPressureBar,
    required this.ventedGasLitres,
    required this.heliumVentedLitres,
    required this.heliumSalvagedLitres,
    required this.heliumRetainedLitres,
  });

  final double retainedPressureBar;
  final double retainedPercent;
  final double ventedPressureBar;
  final double ventedGasLitres;
  final double heliumVentedLitres;
  final double heliumSalvagedLitres;
  final double heliumRetainedLitres;
}

class CompareProtocol {
  const CompareProtocol({
    required this.protocolSteps,
    required this.trajectory,
    required this.initialMix,
    required this.sourceBanks,
    required this.summary,
  });

  final List<CompareStep> protocolSteps;
  final List<CompareTrajectoryPoint> trajectory;
  final GasMixPercent initialMix;
  final List<CompareSourceBankSummary> sourceBanks;
  final CompareSummary summary;
}

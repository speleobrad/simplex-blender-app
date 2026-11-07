part of '../compare_recipe.dart';

CompareTransferRate _transferRate({
  required String type,
  required CompareSourceState sourceStart,
  required CompareSourceState sourceEnd,
  required _Receiver receiverStart,
  required _Receiver receiverEnd,
  required _Limits limits,
  required double receiverVolumeL,
  required double temperatureC,
  required bool useVdw,
}) {
  final pressureIncreaseBar = math.max(
    0.0,
    receiverEnd.pressureBar - receiverStart.pressureBar,
  );
  if (type == 'decant' || type == 'equalize') {
    final rate = sourceStart.oxygenPercent >= 40
        ? limits.oxygenDecantRateBarPerMin
        : limits.otherDecantRateBarPerMin;
    return CompareTransferRate(
      source: 'decant',
      rateBarPerMin: rate,
      estimatedDurationMinutes: pressureIncreaseBar / rate,
    );
  }
  final boosterBpm = sourceStart.oxygenPercent >= 40
      ? limits.oxygenBoostBpm
      : limits.otherBoostBpm;
  final rate = calculateBoosterFillRate(
    cylinderVolumeCm3: limits.cylinderVolumeCm3,
    bpm: boosterBpm,
    sourcePressureBar: (sourceStart.pressureBar + sourceEnd.pressureBar) / 2,
    receiverPressureBar:
        (receiverStart.pressureBar + receiverEnd.pressureBar) / 2,
    sourceOxygenPercent: sourceStart.oxygenPercent,
    sourceHeliumPercent: sourceStart.heliumPercent,
    receiverOxygenPercent: receiverEnd.mix.oxygenPercent,
    receiverHeliumPercent: receiverEnd.mix.heliumPercent,
    receiverVolumeL: receiverVolumeL,
    temperatureC: temperatureC,
    useVdw: useVdw,
  ).fillRateBarPerMin;
  return CompareTransferRate(
    source: 'booster',
    boosterBpm: boosterBpm,
    boosterCylinderVolumeCm3: limits.cylinderVolumeCm3,
    rateBarPerMin: rate,
    estimatedDurationMinutes: pressureIncreaseBar / rate,
  );
}

CompareStep _plannedTransferStep({
  required String type,
  required CompareRow row,
  required Bank bank,
  required CompareSourceState sourceStart,
  required CompareSourceState sourceEnd,
  required _Receiver receiverStart,
  required _Receiver receiverEnd,
  required _Limits limits,
  required double receiverVolumeL,
  required double temperatureC,
  required bool useVdw,
  required String costOperation,
  required double sourceConsumedMoles,
  required String costOperationId,
}) {
  final operation = '${type[0].toUpperCase()}${type.substring(1)}';
  final oxygenCompressionRatio =
      type == 'boost' && bank.oxygenPercent > 40 && sourceEnd.pressureBar > 0
      ? receiverEnd.pressureBar / sourceEnd.pressureBar
      : null;
  return CompareStep(
    type: type,
    compareRowId: row.id,
    sourceBankId: bank.id,
    sourceBankName: bank.name,
    sourceComposition: GasMixPercent(
      oxygenPercent: bank.oxygenPercent,
      heliumPercent: bank.heliumPercent,
    ),
    sourceOxygenPercent: bank.oxygenPercent,
    sourceHeliumPercent: bank.heliumPercent,
    sourceStartPressureBar: sourceStart.pressureBar,
    sourceEndPressureBar: sourceEnd.pressureBar,
    sourceState: sourceEnd,
    sourceMolesAfter: sourceEnd.moles,
    receiverStartPressureBar: receiverStart.pressureBar,
    receiverEndPressureBar: receiverEnd.pressureBar,
    resultingPressureBar: receiverEnd.pressureBar,
    resultingMix: receiverEnd.mix,
    oxygenCompressionRatio: oxygenCompressionRatio,
    transferRate: _transferRate(
      type: type,
      sourceStart: sourceStart,
      sourceEnd: sourceEnd,
      receiverStart: receiverStart,
      receiverEnd: receiverEnd,
      limits: limits,
      receiverVolumeL: receiverVolumeL,
      temperatureC: temperatureC,
      useVdw: useVdw,
    ),
    operation: operation,
    recipeAction: operation,
    recipeGas: bank.name,
    title: operation,
    recipeLabel: operation,
    costOperation: costOperation,
    sourceConsumedMoles: sourceConsumedMoles,
    costOperationId: costOperationId,
    sourceVolumeL: bank.volumeL,
    sourceStartMoles: sourceStart.moles,
  );
}

CompareStep _plannedCompressorStep({
  required CompareRow row,
  required Bank bank,
  required _Receiver receiverStart,
  required _Receiver receiverEnd,
  required double sourceConsumedMoles,
  required String costOperationId,
}) {
  return CompareStep(
    type: 'add',
    method: 'compressor',
    compareRowId: row.id,
    sourceBankId: bank.id,
    sourceBankName: bank.name,
    sourceComposition: GasMixPercent(
      oxygenPercent: bank.oxygenPercent,
      heliumPercent: bank.heliumPercent,
    ),
    sourceOxygenPercent: bank.oxygenPercent,
    sourceHeliumPercent: bank.heliumPercent,
    receiverStartPressureBar: receiverStart.pressureBar,
    receiverEndPressureBar: receiverEnd.pressureBar,
    resultingPressureBar: receiverEnd.pressureBar,
    resultingMix: receiverEnd.mix,
    transferRate: const CompareTransferRate(source: 'compressor'),
    operation: 'Top-up',
    recipeAction: 'Top-up',
    recipeGas: bank.name,
    title: 'Top-up',
    recipeLabel: 'Top-up',
    costOperation: 'topUp',
    sourceConsumedMoles: sourceConsumedMoles,
    costOperationId: costOperationId,
  );
}

CompareStep _passiveStep({
  required CompareRow row,
  required String type,
  required _Receiver receiverStart,
  required double receiverEndPressureBar,
  required GasMixPercent resultingMix,
}) {
  final String operation;
  if (type == 'wait') {
    operation = 'Wait';
  } else if (type == 'drain') {
    operation = 'Drain';
  } else {
    operation = 'Keep';
  }
  return CompareStep(
    type: type,
    compareRowId: row.id,
    waitMinutes: row.waitMinutes,
    waitMode: row.waitMode,
    targetTemperatureC: row.targetTemperatureC,
    receiverStartPressureBar: receiverStart.pressureBar,
    receiverEndPressureBar: receiverEndPressureBar,
    resultingPressureBar: receiverEndPressureBar,
    resultingMix: resultingMix,
    operation: operation,
    recipeAction: operation,
    title: operation,
    recipeLabel: operation,
  );
}

_Receiver _receiverAfterDrain(
  _Receiver receiver,
  double targetPressureBar,
  double volumeL,
  double temperatureC,
  bool useVdw,
) {
  final receiverTemperatureC = _receiverTemperature(receiver, temperatureC);
  final oxygenPercent = receiver.mix.oxygenPercent;
  final heliumPercent = receiver.mix.heliumPercent;
  final totalMoles =
      calcMolarDensity(
        targetPressureBar,
        oxygenPercent,
        heliumPercent,
        receiverTemperatureC,
        useVdw,
      ) *
      volumeL;
  return _Receiver(
    totalMoles: totalMoles,
    oxygenMoles: totalMoles * (oxygenPercent / 100),
    heliumMoles: totalMoles * (heliumPercent / 100),
    mix: receiver.mix,
    pressureBar: targetPressureBar,
    temperatureC: receiverTemperatureC,
  );
}

_Limits _equipmentLimits(CompareSettings? settings) {
  final booster = settings?.booster;
  double pick(double? value, double fallback) {
    return value != null && value.isFinite ? value : fallback;
  }

  return _Limits(
    minimumSourcePressureBar: pick(booster?.minimumSourcePressureBar, 0),
    maxBoosterOutputPressureBar: pick(
      booster?.maxBoosterOutputPressureBar,
      MAX_PRESSURE_BAR,
    ),
    oxygenDecantRateBarPerMin: pick(booster?.oxygenDecantRateBarPerMin, 5),
    otherDecantRateBarPerMin: pick(booster?.otherDecantRateBarPerMin, 10),
    cylinderVolumeCm3: pick(booster?.cylinderVolumeCm3, 9),
    oxygenBoostBpm: pick(booster?.oxygenBoostBpm, 35),
    otherBoostBpm: pick(booster?.otherBoostBpm, 50),
  );
}

int _addTrajectoryPoint(
  List<CompareTrajectoryPoint> trajectory,
  CompareStep step,
  int currentStep,
) {
  if (step.type == 'keep') {
    return currentStep;
  }
  final trajectoryStep = currentStep + 1;
  trajectory.add(
    _trajectoryPoint(
      step: trajectoryStep,
      label: 'Step $trajectoryStep',
      mix: step.resultingMix,
      pressureBar: step.resultingPressureBar,
      pressureDeltaBar:
          step.resultingPressureBar - step.receiverStartPressureBar,
      color: STEP_COLORS[(trajectoryStep - 1) % STEP_COLORS.length],
    ),
  );
  return trajectoryStep;
}

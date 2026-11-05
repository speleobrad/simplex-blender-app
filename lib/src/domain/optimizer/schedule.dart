part of '../optimizer.dart';

// Port of `scheduleSafeThermalProtocol` (js/optimizer.js 634–800).
//
// JS object spreads that set `_measurementIndex`, `_applyInterimMeasurement`,
// and `_scheduledMeasuredStart*` map onto the typed `ProtocolStep` fields of the
// same meaning. [_withSchedule] rebuilds a step with every other field copied.

/// JS `scheduleSafeThermalProtocol`. Returns a map with the JS keys
/// `protocolSteps`, `automaticWaits`, `simulation`, and `unsafe`.
Map<String, Object?> scheduleSafeThermalProtocol({
  required List<ProtocolStep> protocolSteps,
  required ThermalInput thermal,
  required Map<String, Object?> cylinder,
  required PhysicsInput physics,
  BlendSettings? settings,
}) {
  _cylinderHotOverfillPercent(cylinder);
  final options = _SafetyContext(
    thermal: thermal,
    physics: physics,
    cylinder: cylinder,
    settings: settings,
  );
  final steps = <ProtocolStep>[
    for (var index = 0; index < protocolSteps.length; index++)
      _withSchedule(
        protocolSteps[index],
        measurementIndex: index,
        applyInterimMeasurement: protocolSteps[index].applyInterimMeasurement,
        automaticWaitMinutes: protocolSteps[index].automaticWaitMinutes,
        scheduledMeasuredStartPressureBar:
            protocolSteps[index].scheduledMeasuredStartPressureBar,
        scheduledMeasuredStartTemperatureC:
            protocolSteps[index].scheduledMeasuredStartTemperatureC,
      ),
  ];
  const maxWait = MAX_AUTOMATIC_WAIT_MINUTES;
  final workingPressureBar = _numberOrNull(cylinder['workingPressureBar']);
  final passLimit = math.max(16, steps.length * 8 + 8);
  for (var pass = 0; pass < passLimit; pass++) {
    final simulation = _simulated(steps, options);
    final unsafeIndex = _firstUnsafeThermalIndex(
      simulation,
      workingPressureBar,
      options,
    );
    final overWaitLimit =
        _totalWaitMinutes(simulation) > maxWait + THERMAL_SAFETY_TOLERANCE_BAR;
    if (unsafeIndex == -1 && !overWaitLimit) {
      return _finishSchedule(simulation);
    }
    if (unsafeIndex == -2) {
      return _finishSchedule(simulation, unsafe: true);
    }

    final targetIndex = unsafeIndex < 0 ? steps.length - 1 : unsafeIndex;
    final targetState = _protocolStepAt(
      simulation.protocolSteps,
      targetIndex,
    )?.thermal;
    if (targetState != null && _protocolStepAt(steps, targetIndex) != null) {
      final target = steps[targetIndex];
      final measurementIndex = target.measurementIndex;
      final measuredStart = measurementIndex == null
          ? null
          : _interimAt(thermal.interimMeasurements, measurementIndex);
      final hasMeasurement =
          _finiteValueOrNull(measuredStart?.pressureBar) != null ||
          _finiteValueOrNull(measuredStart?.temperatureC) != null;
      final receiverStartPressureBar = _finiteValueOrNull(
        target.receiverStartPressureBar,
      );
      steps[targetIndex] = _withSchedule(
        target,
        measurementIndex: target.measurementIndex,
        applyInterimMeasurement: target.applyInterimMeasurement,
        automaticWaitMinutes: target.automaticWaitMinutes,
        scheduledMeasuredStartPressureBar: hasMeasurement
            ? (target.scheduledMeasuredStartPressureBar ??
                  receiverStartPressureBar ??
                  targetState.pressureStartBar)
            : null,
        scheduledMeasuredStartTemperatureC: hasMeasurement
            ? (target.scheduledMeasuredStartTemperatureC ??
                  (_isRestBefore(steps, targetIndex)
                      ? targetState.temperatureStartC
                      : thermal.ambientTemperatureC))
            : null,
      );
    }

    // detachInitialMeasurement: the first measured non-keep step loses its
    // interim reading.
    final waitIndex = targetIndex - 1;
    final affectedStep = _protocolStepAt(steps, targetIndex);
    if (affectedStep != null &&
        affectedStep.type != 'keep' &&
        affectedStep.measurementIndex == 0) {
      steps[targetIndex] = _withSchedule(
        affectedStep,
        measurementIndex: affectedStep.measurementIndex,
        applyInterimMeasurement: false,
        automaticWaitMinutes: affectedStep.automaticWaitMinutes,
        scheduledMeasuredStartPressureBar: null,
        scheduledMeasuredStartTemperatureC: null,
      );
    }

    if (waitIndex < 0 || _isRestBefore(steps, targetIndex)) {
      final current = _protocolStepAt(steps, targetIndex);
      if (current != null && current.type != 'keep') {
        steps[targetIndex] = _withSchedule(
          current,
          measurementIndex: current.measurementIndex,
          applyInterimMeasurement: false,
          automaticWaitMinutes: current.automaticWaitMinutes,
          scheduledMeasuredStartPressureBar:
              current.scheduledMeasuredStartPressureBar,
          scheduledMeasuredStartTemperatureC:
              current.scheduledMeasuredStartTemperatureC,
        );
      }
      final state = _protocolStepAt(
        simulation.protocolSteps,
        targetIndex,
      )?.thermal;
      final pressureBar =
          state?.pressureStartBar ??
          _numberOrNull(cylinder['initialPressureBar']) ??
          0.0;
      final stepNow = _protocolStepAt(steps, targetIndex);
      final resultingMix =
          state?.receiverStartMix ??
          stepNow?.receiverStartMix ??
          stepNow?.resultingMix ??
          GasMixPercent(
            oxygenPercent:
                _numberOrNull(cylinder['initialOxygenPercent']) ?? 21,
            heliumPercent: _numberOrNull(cylinder['initialHeliumPercent']) ?? 0,
          );
      steps.insert(
        targetIndex,
        ProtocolStep(
          type: 'wait',
          measurementIndex: null,
          measurementIndexExplicitNull: true,
          safetyWaitOnly: true,
          recipeLabel: 'Automatic safety wait',
          receiverStartPressureBar: pressureBar,
          receiverEndPressureBar: pressureBar,
          resultingPressureBar: pressureBar,
          resultingMix: resultingMix,
          receiverStartMix: resultingMix,
          waitMinutes: 0,
          automaticWaitMinutes: 0,
        ),
      );
      continue;
    }

    final existingAdded = _numberOrZero(steps[waitIndex].automaticWaitMinutes);
    if (steps[waitIndex].safetyWaitOnly == true || existingAdded > 0) {
      final current = steps[targetIndex];
      steps[targetIndex] = _withSchedule(
        current,
        measurementIndex: current.measurementIndex,
        applyInterimMeasurement: false,
        automaticWaitMinutes: current.automaticWaitMinutes,
        scheduledMeasuredStartPressureBar:
            current.scheduledMeasuredStartPressureBar,
        scheduledMeasuredStartTemperatureC:
            current.scheduledMeasuredStartTemperatureC,
      );
    }
    final baselineTotal = _totalWaitMinutes(simulation);
    final baselineWithoutExisting = baselineTotal - existingAdded;
    final availableAdded = math.max(0.0, maxWait - baselineWithoutExisting);
    bool safeThroughTarget(ThermalProtocolResult candidateSimulation) {
      final candidateUnsafeIndex = _firstUnsafeThermalIndex(
        candidateSimulation,
        workingPressureBar,
        options,
      );
      return candidateUnsafeIndex == -1 || candidateUnsafeIndex > targetIndex;
    }

    bool safeAt(double added) {
      steps[waitIndex] = _withAutomaticWait(steps[waitIndex], added);
      return safeThroughTarget(_simulated(steps, options));
    }

    if (availableAdded > existingAdded && safeAt(availableAdded)) {
      var low = existingAdded;
      var high = availableAdded;
      for (var iteration = 0; iteration < 50; iteration++) {
        final middle = (low + high) / 2;
        if (safeAt(middle)) {
          high = middle;
        } else {
          low = middle;
        }
      }
      steps[waitIndex] = _withAutomaticWait(steps[waitIndex], high);
      continue;
    }
    steps[waitIndex] = _withAutomaticWait(steps[waitIndex], existingAdded);

    final split = unsafeIndex >= 0
        ? _splitTransferAtSafeHotEndpoint(
            steps: steps,
            unsafeIndex: unsafeIndex,
            simulation: simulation,
            options: options,
          )
        : null;
    if (split != null) {
      steps.removeAt(unsafeIndex);
      steps.insertAll(unsafeIndex, [split.first, split.wait, split.second]);
      continue;
    }
    return _finishSchedule(simulation, unsafe: true);
  }
  final simulation = _simulated(steps, options);
  return _finishSchedule(simulation, unsafe: true);
}

/// JS `finish` inside `scheduleSafeThermalProtocol`. Strips the scheduling-only
/// fields and builds the JS result object.
///
/// JS `finish`: attaches `automaticWaitMetadata` to steps that received an
/// automatic wait and returns `automaticWaits` as JS-keyed maps.
Map<String, Object?> _finishSchedule(
  ThermalProtocolResult simulation, {
  bool unsafe = false,
}) {
  final automaticWaits = _automaticWaitMetadata(simulation);
  final metadataByIndex = <int, Map<String, Object?>>{
    for (final metadata in automaticWaits) metadata.stepIndex: metadata.toMap(),
  };
  final protocol = <ProtocolStep>[
    for (var index = 0; index < simulation.protocolSteps.length; index++)
      _withSchedule(
        simulation.protocolSteps[index],
        measurementIndex: simulation.protocolSteps[index].measurementIndex,
        applyInterimMeasurement: null,
        automaticWaitMinutes:
            simulation.protocolSteps[index].automaticWaitMinutes,
        scheduledMeasuredStartPressureBar: null,
        scheduledMeasuredStartTemperatureC: null,
      ).copyWith(automaticWaitMetadata: metadataByIndex[index]),
  ];
  return <String, Object?>{
    'protocolSteps': protocol,
    'automaticWaits': <Map<String, Object?>>[
      for (final metadata in automaticWaits) metadata.toMap(),
    ],
    'simulation': ThermalProtocolResult(
      protocolSteps: protocol,
      finalSummary: simulation.finalSummary,
    ),
    'unsafe': unsafe,
  };
}

/// JS `totalWaitMinutes`: sum of finite `thermal.waitMinutes`.
double _totalWaitMinutes(ThermalProtocolResult? simulation) {
  var total = 0.0;
  for (final step in simulation?.protocolSteps ?? const <ProtocolStep>[]) {
    total += _finiteValueOrNull(step.thermal?.waitMinutes) ?? 0;
  }
  return total;
}

/// JS `Number(x) || 0`: missing, NaN, and zero all read as 0.
double _numberOrZero(double? value) {
  if (value == null || value.isNaN || value == 0) {
    return 0;
  }
  return value;
}

/// JS `thermalProtocol?.[index]` for the interim-measurement list.
InterimMeasurement? _interimAt(List<InterimMeasurement?>? list, int index) {
  if (list == null || index < 0 || index >= list.length) {
    return null;
  }
  return list[index];
}

/// Copies [source] with the scheduling fields replaced. Every other field is
/// carried over unchanged (JS object spread).
ProtocolStep _withSchedule(
  ProtocolStep source, {
  required int? measurementIndex,
  required bool? applyInterimMeasurement,
  required double? automaticWaitMinutes,
  required double? scheduledMeasuredStartPressureBar,
  required double? scheduledMeasuredStartTemperatureC,
}) {
  return ProtocolStep(
    type: source.type,
    operation: source.operation,
    title: source.title,
    method: source.method,
    stage: source.stage,
    receiverStartPressureBar: source.receiverStartPressureBar,
    receiverEndPressureBar: source.receiverEndPressureBar,
    resultingPressureBar: source.resultingPressureBar,
    resultingMix: source.resultingMix,
    receiverStartMix: source.receiverStartMix,
    receiverVolumeL: source.receiverVolumeL,
    sourceStartPressureBar: source.sourceStartPressureBar,
    sourceEndPressureBar: source.sourceEndPressureBar,
    sourcePressureBar: source.sourcePressureBar,
    sourceOxygenPercent: source.sourceOxygenPercent,
    sourceHeliumPercent: source.sourceHeliumPercent,
    pressureReferenceTemperatureC: source.pressureReferenceTemperatureC,
    pressureAtTransferEndReferenceBar: source.pressureAtTransferEndReferenceBar,
    pressureAtTransferEndAmbientBar: source.pressureAtTransferEndAmbientBar,
    pressureAtTransferEndHotBar: source.pressureAtTransferEndHotBar,
    automaticWaitMinutes: automaticWaitMinutes,
    waitMode: source.waitMode,
    waitMinutes: source.waitMinutes,
    targetTemperatureC: source.targetTemperatureC,
    measurementIndex: measurementIndex,
    measurementIndexExplicitNull: measurementIndex == null,
    applyInterimMeasurement: applyInterimMeasurement,
    scheduledMeasuredStartPressureBar: scheduledMeasuredStartPressureBar,
    scheduledMeasuredStartTemperatureC: scheduledMeasuredStartTemperatureC,
    safetyWaitOnly: source.safetyWaitOnly,
    costOperation: source.costOperation,
    costOperationId: source.costOperationId,
    sourceConsumedMoles: source.sourceConsumedMoles,
    thermalSplit: source.thermalSplit,
    sourceInventory: source.sourceInventory,
    sourceVolumeL: source.sourceVolumeL,
    sourceStartMoles: source.sourceStartMoles,
    sourceEndMoles: source.sourceEndMoles,
    receiverStartMoles: source.receiverStartMoles,
    receiverEndMoles: source.receiverEndMoles,
    recipeGas: source.recipeGas,
    recipeLabel: source.recipeLabel,
    id: source.id,
    thermal: source.thermal,
    automaticWaitMetadata: source.automaticWaitMetadata,
    recipeAction: source.recipeAction,
    sourceBankId: source.sourceBankId,
    description: source.description,
    pressureDeltaBar: source.pressureDeltaBar,
    minimumSourcePressureBar: source.minimumSourcePressureBar,
    sourceExhausted: source.sourceExhausted,
    oxygenCompressionRatio: source.oxygenCompressionRatio,
    badgeClass: source.badgeClass,
    receiverBankId: source.receiverBankId,
    receiverBankName: source.receiverBankName,
    movedMoles: source.movedMoles,
    movedHeliumLitres: source.movedHeliumLitres,
    receiverEndMix: source.receiverEndMix,
  );
}

/// JS `steps[waitIndex].automaticWaitMinutes = minutes` on a copy.
ProtocolStep _withAutomaticWait(ProtocolStep source, double minutes) {
  return _withSchedule(
    source,
    measurementIndex: source.measurementIndex,
    applyInterimMeasurement: source.applyInterimMeasurement,
    automaticWaitMinutes: minutes,
    scheduledMeasuredStartPressureBar: source.scheduledMeasuredStartPressureBar,
    scheduledMeasuredStartTemperatureC:
        source.scheduledMeasuredStartTemperatureC,
  );
}

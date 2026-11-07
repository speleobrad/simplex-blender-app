part of '../compare_recipe.dart';

CompareProtocol buildCompareProtocol(
  List<CompareRow> rows, {
  required CompareCylinder cylinder,
  required PhysicsInput physics,
  List<Bank> banks = const <Bank>[],
  CompareSettings? settings,
  Map<String, CompareWaitState> waitStates = const <String, CompareWaitState>{},
}) {
  final validation = validateCompareRecipe(
    rows,
    cylinder: cylinder,
    banks: banks,
    physics: physics,
    settings: settings,
    waitStates: waitStates,
  );
  if (!validation.valid) {
    final messages = validation.errors.map((error) => error.message).join(' ');
    throw DomainError('Invalid compare recipe: $messages');
  }

  final volumeL = cylinder.volumeL;
  final initialP = cylinder.initialPressureBar ?? double.nan;
  if (!volumeL.isFinite || volumeL <= 0 || !_validPressure(initialP)) {
    throw RangeError(
      'Compare protocol requires a finite cylinder volume and initial pressure.',
    );
  }
  if (!physics.temperatureC.isFinite) {
    throw RangeError('Compare protocol requires a finite gas temperature.');
  }
  final temperatureC = physics.temperatureC;
  final useVdw = physics.model != 'ideal';
  final ceiling = _receiverPressureCeiling(cylinder, settings);
  if (initialP > ceiling + PRESSURE_TOLERANCE_BAR) {
    throw RangeError(
      'Compare protocol initial pressure cannot exceed the cylinder working pressure of ${_formatNumber(ceiling)} bar.',
    );
  }

  final limits = _equipmentLimits(settings);
  final bankIndex = _indexedBanks(banks);
  final bankStates = <String, _BankState>{};
  for (final entry in bankIndex.byId.entries) {
    final bank = entry.value;
    bankStates[entry.key] = _BankState(
      bank: _copiedBank(bank),
      moles:
          calcMolarDensity(
            bank.pressureBar,
            bank.oxygenPercent,
            bank.heliumPercent,
            temperatureC,
            useVdw,
          ) *
          bank.volumeL,
    );
  }

  final initialMix = GasMixPercent(
    oxygenPercent: cylinder.initialOxygenPercent,
    heliumPercent: cylinder.initialHeliumPercent,
  );
  final initialMoles =
      calcMolarDensity(
        initialP,
        initialMix.oxygenPercent,
        initialMix.heliumPercent,
        temperatureC,
        useVdw,
      ) *
      volumeL;
  var receiver = _Receiver(
    totalMoles: initialMoles,
    oxygenMoles: initialMoles * (initialMix.oxygenPercent / 100),
    heliumMoles: initialMoles * (initialMix.heliumPercent / 100),
    mix: initialMix,
    pressureBar: initialP,
  );
  var retainedInitialMoles = initialMoles;
  var addedHeliumMoles = 0.0;

  double salvagedHeliumFrom(double moles, double heliumPercent) {
    return heliumPercent < 98 ? moles * (heliumPercent / 100) : 0;
  }

  final protocolSteps = <CompareStep>[];
  var costOperationCounter = 0;
  String nextCostOperationId() {
    costOperationCounter += 1;
    return 'op-$costOperationCounter';
  }

  final sourceSummaries = <String, CompareSourceBankSummary>{};

  void recordCompressorSummary(Bank bank) {
    if (sourceSummaries.containsKey(bank.id)) {
      return;
    }
    final initial = CompareSourceSnapshot(
      pressureBar: null,
      moles: null,
      oxygenPercent: bank.oxygenPercent,
      heliumPercent: bank.heliumPercent,
    );
    sourceSummaries[bank.id] = CompareSourceBankSummary(
      id: bank.id,
      name: bank.name,
      initial: initial,
      finalState: initial,
    );
  }

  void recordFiniteSummary(
    Bank bank,
    CompareSourceState sourceStart,
    CompareSourceState sourceFinal,
  ) {
    final existing = sourceSummaries[bank.id];
    final initial =
        existing?.initial ??
        CompareSourceSnapshot(
          pressureBar: bank.pressureBar,
          moles: sourceStart.moles,
          oxygenPercent: sourceStart.oxygenPercent,
          heliumPercent: sourceStart.heliumPercent,
        );
    sourceSummaries[bank.id] = CompareSourceBankSummary(
      id: bank.id,
      name: bank.name,
      initial: initial,
      finalState: _sourceSummaryState(sourceFinal),
    );
  }

  final trajectory = <CompareTrajectoryPoint>[
    _trajectoryPoint(
      step: 0,
      label: 'Start Mix',
      mix: receiver.mix,
      pressureBar: receiver.pressureBar,
      pressureDeltaBar: 0,
      color: '#f43f5e',
    ),
  ];
  var trajectoryStep = 0;

  for (final row in validation.normalizedRows) {
    if (row.type == 'drain') {
      final receiverStart = receiver;
      final receiverFinal = _receiverAfterDrain(
        receiver,
        row.targetPressureBar ?? double.nan,
        volumeL,
        temperatureC,
        useVdw,
      );
      final retainedFraction = receiver.totalMoles > 0
          ? receiverFinal.totalMoles / receiver.totalMoles
          : 0.0;
      retainedInitialMoles *= retainedFraction;
      addedHeliumMoles *= retainedFraction;
      final step = _passiveStep(
        row: row,
        type: 'drain',
        receiverStart: receiverStart,
        receiverEndPressureBar: receiverFinal.pressureBar,
        resultingMix: receiverFinal.mix,
      );
      protocolSteps.add(step);
      trajectoryStep = _addTrajectoryPoint(trajectory, step, trajectoryStep);
      receiver = receiverFinal;
      continue;
    }

    if (row.type != 'add') {
      final receiverStart = receiver;
      final waitState = row.type == 'wait' ? waitStates[row.id] : null;
      if (waitState != null && waitState.pressureBar.isFinite) {
        final totalMoles = waitState.totalMoles;
        final oxygenMoles = waitState.oxygenMoles;
        final heliumMoles = waitState.heliumMoles;
        if (totalMoles != null &&
            totalMoles.isFinite &&
            oxygenMoles != null &&
            oxygenMoles.isFinite &&
            heliumMoles != null &&
            heliumMoles.isFinite) {
          final waitTemperatureC = waitState.temperatureC;
          receiver = _Receiver(
            totalMoles: totalMoles,
            oxygenMoles: oxygenMoles,
            heliumMoles: heliumMoles,
            mix: waitState.mix ?? receiver.mix,
            pressureBar: waitState.pressureBar,
            temperatureC: waitTemperatureC != null && waitTemperatureC.isFinite
                ? waitTemperatureC
                : (receiver.temperatureC ?? temperatureC),
          );
        } else {
          receiver = receiver.withPressureBar(waitState.pressureBar);
        }
      }
      final step = _passiveStep(
        row: row,
        type: row.type,
        receiverStart: receiverStart,
        receiverEndPressureBar: receiver.pressureBar,
        resultingMix: receiver.mix,
      );
      protocolSteps.add(step);
      trajectoryStep = _addTrajectoryPoint(trajectory, step, trajectoryStep);
      continue;
    }

    // Add row.
    final targetRow = normalizeComparePressureFields(row, receiver.pressureBar);
    final targetPressureBar = targetRow.targetPressureBar;
    if (targetPressureBar > ceiling + PRESSURE_TOLERANCE_BAR) {
      throw RangeError(
        'Compare protocol target pressure cannot exceed the cylinder working pressure of ${_formatNumber(ceiling)} bar.',
      );
    }
    final bank = row.sourceBank;
    if (bank == null) {
      throw StateError('Compare add row ${row.id} has no source bank.');
    }

    if (bank.isCompressor == true) {
      recordCompressorSummary(bank);
      final requiredMoles = _solveAddedMoles(
        receiver,
        targetPressureBar,
        bank,
        volumeL,
        temperatureC,
        useVdw,
      );
      if (requiredMoles <= 1e-9) {
        final step = _passiveStep(
          row: row,
          type: 'keep',
          receiverStart: receiver,
          receiverEndPressureBar: receiver.pressureBar,
          resultingMix: receiver.mix,
        );
        protocolSteps.add(step);
        trajectoryStep = _addTrajectoryPoint(trajectory, step, trajectoryStep);
        continue;
      }
      addedHeliumMoles += salvagedHeliumFrom(requiredMoles, bank.heliumPercent);
      final receiverStart = receiver;
      final receiverFinal = _receiverAfterAddedMoles(
        receiver,
        requiredMoles,
        bank,
        volumeL,
        temperatureC,
        useVdw,
      ).withPressureBar(targetPressureBar);
      final step = _plannedCompressorStep(
        row: row,
        bank: bank,
        receiverStart: receiverStart,
        receiverEnd: receiverFinal,
        sourceConsumedMoles: requiredMoles,
        costOperationId: nextCostOperationId(),
      );
      protocolSteps.add(step);
      trajectoryStep = _addTrajectoryPoint(trajectory, step, trajectoryStep);
      receiver = receiverFinal;
      continue;
    }

    final source = bankStates[bank.id];
    if (source == null) {
      throw StateError('Compare supply bank ${bank.id} was not indexed.');
    }
    final sourceBank = source.bank;
    final requiredMoles = _solveAddedMoles(
      receiver,
      targetPressureBar,
      sourceBank,
      volumeL,
      temperatureC,
      useVdw,
    );
    if (requiredMoles <= 1e-9) {
      final step = _passiveStep(
        row: row,
        type: 'keep',
        receiverStart: receiver,
        receiverEndPressureBar: receiver.pressureBar,
        resultingMix: receiver.mix,
      );
      protocolSteps.add(step);
      trajectoryStep = _addTrajectoryPoint(trajectory, step, trajectoryStep);
      continue;
    }
    addedHeliumMoles += salvagedHeliumFrom(
      requiredMoles,
      sourceBank.heliumPercent,
    );
    final sourceMinimumMoles =
        calcMolarDensity(
          limits.minimumSourcePressureBar,
          sourceBank.oxygenPercent,
          sourceBank.heliumPercent,
          temperatureC,
          useVdw,
        ) *
        sourceBank.volumeL;
    if (source.moles - requiredMoles <
        sourceMinimumMoles - PRESSURE_TOLERANCE_BAR) {
      throw RangeError(
        'Supply bank ${sourceBank.name} cannot retain its ${_formatNumber(limits.minimumSourcePressureBar)} bar minimum pressure for this transfer.',
      );
    }

    final receiverStart = receiver;
    final sourceStart = _sourceState(
      sourceBank,
      source.moles,
      temperatureC,
      useVdw,
    );
    final receiverFinal = _receiverAfterAddedMoles(
      receiver,
      requiredMoles,
      sourceBank,
      volumeL,
      temperatureC,
      useVdw,
    ).withPressureBar(targetPressureBar);
    final sourceFinal = _sourceState(
      sourceBank,
      source.moles - requiredMoles,
      temperatureC,
      useVdw,
    );
    recordFiniteSummary(sourceBank, sourceStart, sourceFinal);

    if (sourceFinal.pressureBar >= targetPressureBar - PRESSURE_TOLERANCE_BAR) {
      final step = _plannedTransferStep(
        type: 'decant',
        row: row,
        bank: sourceBank,
        sourceStart: sourceStart,
        sourceEnd: sourceFinal,
        receiverStart: receiverStart,
        receiverEnd: receiverFinal,
        limits: limits,
        receiverVolumeL: volumeL,
        temperatureC: temperatureC,
        useVdw: useVdw,
        costOperation: 'decant',
        sourceConsumedMoles: requiredMoles,
        costOperationId: nextCostOperationId(),
      );
      protocolSteps.add(step);
      trajectoryStep = _addTrajectoryPoint(trajectory, step, trajectoryStep);
    } else {
      if (targetPressureBar >
          limits.maxBoosterOutputPressureBar + PRESSURE_TOLERANCE_BAR) {
        throw RangeError(
          'Supply bank transfer requires boosting above the ${_formatNumber(limits.maxBoosterOutputPressureBar)} bar booster output limit.',
        );
      }
      final sourceStartsAboveReceiver =
          sourceStart.pressureBar >
          receiverStart.pressureBar + PRESSURE_TOLERANCE_BAR;
      final equalizationMoles = sourceStartsAboveReceiver
          ? _solveEqualizationMoles(
              receiver,
              source.moles,
              requiredMoles,
              sourceBank,
              volumeL,
              temperatureC,
              useVdw,
            )
          : 0.0;
      if (equalizationMoles > 1e-7) {
        final sourceEqualized = _sourceState(
          sourceBank,
          source.moles - equalizationMoles,
          temperatureC,
          useVdw,
        );
        final receiverEqualized = _receiverAfterAddedMoles(
          receiver,
          equalizationMoles,
          sourceBank,
          volumeL,
          temperatureC,
          useVdw,
        ).withPressureBar(sourceEqualized.pressureBar);
        final equalizeStep = _plannedTransferStep(
          type: 'equalize',
          row: row,
          bank: sourceBank,
          sourceStart: sourceStart,
          sourceEnd: sourceEqualized,
          receiverStart: receiverStart,
          receiverEnd: receiverEqualized,
          limits: limits,
          receiverVolumeL: volumeL,
          temperatureC: temperatureC,
          useVdw: useVdw,
          costOperation: 'equalize',
          sourceConsumedMoles: equalizationMoles,
          costOperationId: nextCostOperationId(),
        );
        protocolSteps.add(equalizeStep);
        trajectoryStep = _addTrajectoryPoint(
          trajectory,
          equalizeStep,
          trajectoryStep,
        );

        final boostStep = _plannedTransferStep(
          type: 'boost',
          row: row,
          bank: sourceBank,
          sourceStart: sourceEqualized,
          sourceEnd: sourceFinal,
          receiverStart: receiverEqualized,
          receiverEnd: receiverFinal,
          limits: limits,
          receiverVolumeL: volumeL,
          temperatureC: temperatureC,
          useVdw: useVdw,
          costOperation: 'boost',
          sourceConsumedMoles: requiredMoles - equalizationMoles,
          costOperationId: nextCostOperationId(),
        );
        protocolSteps.add(boostStep);
        trajectoryStep = _addTrajectoryPoint(
          trajectory,
          boostStep,
          trajectoryStep,
        );
      } else {
        final boostStep = _plannedTransferStep(
          type: 'boost',
          row: row,
          bank: sourceBank,
          sourceStart: sourceStart,
          sourceEnd: sourceFinal,
          receiverStart: receiverStart,
          receiverEnd: receiverFinal,
          limits: limits,
          receiverVolumeL: volumeL,
          temperatureC: temperatureC,
          useVdw: useVdw,
          costOperation: 'boost',
          sourceConsumedMoles: requiredMoles,
          costOperationId: nextCostOperationId(),
        );
        protocolSteps.add(boostStep);
        trajectoryStep = _addTrajectoryPoint(
          trajectory,
          boostStep,
          trajectoryStep,
        );
      }
    }
    source.moles -= requiredMoles;
    receiver = receiverFinal;
  }

  final retainedPressureBar = calcPressure(
    retainedInitialMoles / volumeL,
    initialMix.oxygenPercent,
    initialMix.heliumPercent,
    temperatureC,
    useVdw,
  );
  final ventedMoles = math.max(0.0, initialMoles - retainedInitialMoles);
  final gasMolarVolumeL = gasConstant * (temperatureC + 273.15);
  final summary = CompareSummary(
    retainedPressureBar: retainedPressureBar,
    retainedPercent: initialMoles > 0
        ? (retainedInitialMoles / initialMoles) * 100
        : 0.0,
    ventedPressureBar: math.max(0.0, initialP - retainedPressureBar),
    ventedGasLitres: ventedMoles * gasMolarVolumeL,
    heliumVentedLitres:
        ventedMoles * (initialMix.heliumPercent / 100) * gasMolarVolumeL,
    heliumSalvagedLitres:
        (salvagedHeliumFrom(retainedInitialMoles, initialMix.heliumPercent) +
            addedHeliumMoles) *
        gasMolarVolumeL,
    heliumRetainedLitres:
        retainedInitialMoles *
        (initialMix.heliumPercent / 100) *
        gasMolarVolumeL,
  );

  return CompareProtocol(
    protocolSteps: protocolSteps,
    trajectory: trajectory,
    initialMix: initialMix,
    sourceBanks: sourceSummaries.values.toList(),
    summary: summary,
  );
}

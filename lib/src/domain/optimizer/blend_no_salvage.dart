part of '../optimizer.dart';

// Port of js/optimizer.js `solveBlendWithoutSalvage` (1770–2441). The closure
// search helpers (JS 1845–2120) live in blend_no_salvage_search.dart. An optional
// `_salvagePlan` (from the salvage chunk) supplies the salvage steps, moved moles,
// transfers and post-cascade banks.

/// JS `minimumSourcePressureBarFor(settings, bank)`: the configured booster
/// minimum; else the bank's `minimumPressureBar` when finite; else 20 bar.
/// Pass a null [bankMinimumPressureBar] for the salvage tank, which is not a bank.
double _minimumSourcePressureBarFor(
  BlendSettings? settings,
  double? bankMinimumPressureBar,
) {
  return _finiteOr(
    settings?.booster?.minimumSourcePressureBar,
    _finiteOr(bankMinimumPressureBar, 20),
  );
}

/// JS `boosterOutputLimitBar`.
double _boosterOutputLimitBar(BlendSettings? settings) {
  return _finiteOr(settings?.booster?.maxBoosterOutputPressureBar, 200);
}

/// JS `solveBlendWithoutSalvage`. [input] is the raw blend input map (the same
/// object that `_validateBlendInput` checks); [physics], [banks], [settings] and
/// [thermal] are its typed views. [thermal] non-null mirrors JS `input.thermal`.
Map<String, Object?> _solveBlendWithoutSalvage(
  Map<String, Object?> input, {
  required PhysicsInput physics,
  required List<Bank> banks,
  required BlendSettings? settings,
  required ThermalInput? thermal,
}) {
  final inputErrors = _validateBlendInput(
    input,
    internalThermalTarget: _internalThermalTargetFlag(input),
  );
  if (inputErrors.isNotEmpty) {
    return _failedResult(
      'Invalid blend input: ${inputErrors.join(' ')}',
      null,
      const [],
    );
  }
  final cylinder = input['cylinder']! as Map<String, Object?>;
  final salvagePlan = input['_salvagePlan'] as Map<String, Object?>?;
  final salvagedMoles = salvagePlan == null
      ? 0.0
      : (salvagePlan['movedMoles'] as num?)?.toDouble() ?? 0.0;
  final effectiveBanks = (salvagePlan?['banks'] as List<Bank>?) ?? banks;
  final maxCompressorPressureBar = _finiteOr(
    settings?.booster?.maxCompressorPressureBar,
    232,
  );
  final maxBoosterOutputPressureBar = _boosterOutputLimitBar(settings);
  double minimumSourcePressureFor(Bank bank) =>
      _minimumSourcePressureBarFor(settings, bank.minimumPressureBar);

  final useVdw = physics.useVdw;
  final temperatureC = physics.temperatureC;
  final volumeL = _numberOrNan(cylinder['volumeL']);
  final initialPressureBar = _numberOrNan(cylinder['initialPressureBar']);
  final initialOxygenPercent = _numberOrNan(cylinder['initialOxygenPercent']);
  final initialHeliumPercent = _numberOrNan(cylinder['initialHeliumPercent']);
  final targetPressureBar = _numberOrNan(cylinder['targetPressureBar']);
  final targetOxygenPercent = _numberOrNan(cylinder['targetOxygenPercent']);
  final targetHeliumPercent = _numberOrNan(cylinder['targetHeliumPercent']);

  final initialDensity = calcMolarDensity(
    initialPressureBar,
    initialOxygenPercent,
    initialHeliumPercent,
    temperatureC,
    useVdw,
  );
  final initialMoles = initialDensity * volumeL;
  final initialZ = calcZFromDensity(
    initialPressureBar,
    initialDensity,
    temperatureC,
    useVdw,
  );
  final targetDensity = calcMolarDensity(
    targetPressureBar,
    targetOxygenPercent,
    targetHeliumPercent,
    temperatureC,
    useVdw,
  );
  final targetMoles = targetDensity * volumeL;
  final targetZ = calcZFromDensity(
    targetPressureBar,
    targetDensity,
    temperatureC,
    useVdw,
  );
  final gas = <String, Object?>{
    'initialPressureBar': initialPressureBar,
    'initialMoles': initialMoles,
    'initialZ': initialZ,
    'targetPressureBar': targetPressureBar,
    'targetMoles': targetMoles,
    'targetZ': targetZ,
  };

  final solverBanks = <Bank>[
    ...effectiveBanks,
    _compressorAirBank(maxCompressorPressureBar),
  ];
  final availableMolesByBankId = <String, double>{};
  final bankDensityByBankId = <String, double>{};
  for (final bank in solverBanks) {
    if (_isAirBank(bank)) {
      bankDensityByBankId[bank.id] = calcMolarDensity(
        bank.pressureBar,
        bank.oxygenPercent,
        bank.heliumPercent,
        temperatureC,
        useVdw,
      );
      availableMolesByBankId[bank.id] = targetMoles;
      continue;
    }
    final bankMinimumPressureBar = minimumSourcePressureFor(bank);
    final hasAvailableGas =
        bank.enabled && bank.pressureBar > bankMinimumPressureBar;
    final currentDensity = hasAvailableGas
        ? calcMolarDensity(
            bank.pressureBar,
            bank.oxygenPercent,
            bank.heliumPercent,
            temperatureC,
            useVdw,
          )
        : 0.0;
    bankDensityByBankId[bank.id] = currentDensity;
    final availableMoles = hasAvailableGas
        ? _jsMathMax(
            0.0,
            (currentDensity -
                    calcMolarDensity(
                      bankMinimumPressureBar,
                      bank.oxygenPercent,
                      bank.heliumPercent,
                      temperatureC,
                      useVdw,
                    )) *
                bank.volumeL,
          )
        : 0.0;
    availableMolesByBankId[bank.id] = availableMoles;
  }
  final activeBanks = solverBanks.where((bank) => bank.enabled).toList();
  final bankMaxMoles = <double>[
    for (final bank in activeBanks) availableMolesByBankId[bank.id]!,
  ];

  final componentShortfalls = _componentShortfallsFor(
    initialMoles: initialMoles,
    initialOxygenPercent: initialOxygenPercent,
    initialHeliumPercent: initialHeliumPercent,
    targetMoles: targetMoles,
    targetOxygenPercent: targetOxygenPercent,
    targetHeliumPercent: targetHeliumPercent,
    activeBanks: activeBanks,
    bankMaxMoles: bankMaxMoles,
  );

  final search = _BlendSearch(
    initialMoles: initialMoles,
    initialOxygenPercent: initialOxygenPercent,
    initialHeliumPercent: initialHeliumPercent,
    targetPressureBar: targetPressureBar,
    targetMoles: targetMoles,
    targetOxygenPercent: targetOxygenPercent,
    targetHeliumPercent: targetHeliumPercent,
    volumeL: volumeL,
    temperatureC: temperatureC,
    useVdw: useVdw,
    maxCompressorPressureBar: maxCompressorPressureBar,
    maxBoosterOutputPressureBar: maxBoosterOutputPressureBar,
    activeBanks: activeBanks,
    bankMaxMoles: bankMaxMoles,
    bankDensityByBankId: bankDensityByBankId,
  );

  // JS 2120–2205: exact target first, then the maximum safe mix.
  var solverResult = search.solveAtPressure(targetPressureBar);
  var requestedSafetyError = solverResult.feasible
      ? search.isUnsafe(solverResult)
      : null;
  if (solverResult.feasible && requestedSafetyError != null) {
    final safetyResult = search.safeAtPressure(
      targetPressureBar,
      seedResult: solverResult,
    );
    if (safetyResult != null) {
      solverResult = safetyResult;
      requestedSafetyError = null;
    }
  }

  final exactTargetFeasible =
      solverResult.feasible && requestedSafetyError == null;
  var recipeSolverResult = solverResult;
  var recipeTargetPressureBar = targetPressureBar;

  if (!exactTargetFeasible) {
    final maximumResult = _solveMaximumTargetMix(
      initialMoles: initialMoles,
      initialOxygenPercent: initialOxygenPercent,
      initialHeliumPercent: initialHeliumPercent,
      targetOxygenPercent: targetOxygenPercent,
      targetHeliumPercent: targetHeliumPercent,
      activeBanks: activeBanks,
      bankMaxMoles: bankMaxMoles,
    );
    final maximumMoles = maximumResult.feasible
        ? _jsOrZero(maximumResult.solution?['n_total'])
        : 0.0;
    if (maximumMoles <= 1e-6) {
      return _failedResult(
        requestedSafetyError ?? 'The exact target mix cannot be made from the current cylinder and enabled gas banks at any positive pressure.',
        gas,
        maximumResult.steps ?? solverResult.steps ?? const [],
        diagnostics: _createBlendDiagnostics(
          componentShortfalls: componentShortfalls,
          solverResult: maximumResult,
          activeBanks: activeBanks,
          bankMaxMoles: bankMaxMoles,
          temperatureC: temperatureC,
          useVdw: useVdw,
          minimumSourcePressureFor: minimumSourcePressureFor,
        ),
      );
    }

    final inventoryMaximumPressure = calcPressure(
      maximumMoles / volumeL,
      targetOxygenPercent,
      targetHeliumPercent,
      temperatureC,
      useVdw,
    );
    final maximumRecipeError = search.isUnsafe(
      maximumResult,
      pressureBar: inventoryMaximumPressure,
    );
    _LinearProgramResult? safeSolverResult;
    if (inventoryMaximumPressure <= targetPressureBar) {
      if (maximumRecipeError != null) {
        safeSolverResult = search.safeAtPressure(
          inventoryMaximumPressure,
          seedResult: maximumResult,
        );
      } else {
        final retentionResult = search.solveAtPressure(
          inventoryMaximumPressure,
          prioritizeTransferSafety: true,
        );
        final keepsAtLeastAsMuch =
            retentionResult.feasible &&
            search.isUnsafe(
                  retentionResult,
                  pressureBar: inventoryMaximumPressure,
                ) ==
                null &&
            _jsOrZero(retentionResult.solution?['x_cyl']) >=
                _jsOrZero(maximumResult.solution?['x_cyl']);
        safeSolverResult = keepsAtLeastAsMuch ? retentionResult : maximumResult;
      }
    }

    if (safeSolverResult != null) {
      recipeSolverResult = safeSolverResult;
      recipeTargetPressureBar = inventoryMaximumPressure;
    } else {
      var safePressureBar = 0.0;
      var unsafePressureBar = _jsMathMin(
        inventoryMaximumPressure,
        targetPressureBar,
      );
      for (var iteration = 0; iteration < 40; iteration++) {
        final candidatePressureBar = (safePressureBar + unsafePressureBar) / 2;
        final candidate = search.safeAtPressure(candidatePressureBar);
        if (candidate != null) {
          safePressureBar = candidatePressureBar;
          safeSolverResult = candidate;
        } else {
          unsafePressureBar = candidatePressureBar;
        }
      }
      if (safeSolverResult == null || safePressureBar <= 1e-6) {
        return _failedResult(
          requestedSafetyError ?? maximumRecipeError ?? 'The exact target mix cannot be made safely at any positive pressure with the current gas banks.',
          gas,
          maximumResult.steps ?? const [],
          diagnostics: _createBlendDiagnostics(
            componentShortfalls: componentShortfalls,
            solverResult: maximumResult,
            activeBanks: activeBanks,
            bankMaxMoles: bankMaxMoles,
            temperatureC: temperatureC,
            useVdw: useVdw,
            minimumSourcePressureFor: minimumSourcePressureFor,
          ),
        );
      }
      recipeSolverResult = safeSolverResult;
      recipeTargetPressureBar = safePressureBar;
      requestedSafetyError ??= maximumRecipeError;
    }
  }

  // JS 2208–2440: output.
  final gasMolarVolumeL = gasConstant * (temperatureC + 273.15);
  final retainedMoles = _jsOrZero(recipeSolverResult.solution?['x_cyl']);
  final ventedMoles = _jsMathMax(
    0.0,
    initialMoles - retainedMoles - salvagedMoles,
  );
  final retainedDensity = retainedMoles / volumeL;
  final retainedPressure = calcPressure(
    retainedDensity,
    initialOxygenPercent,
    initialHeliumPercent,
    temperatureC,
    useVdw,
  );
  final postSalvagePressure = salvagedMoles > 0
      ? calcPressure(
          (initialMoles - salvagedMoles) / volumeL,
          initialOxygenPercent,
          initialHeliumPercent,
          temperatureC,
          useVdw,
        )
      : initialPressureBar;
  final drainPressure = _jsMathMax(0.0, postSalvagePressure - retainedPressure);
  final recipeBoosts = _activeBoostsFor(
    recipeSolverResult,
    activeBanks,
    airFirst: recipeTargetPressureBar > maxCompressorPressureBar,
  );
  final retainedHeliumMoles = initialHeliumPercent < heliumSalvageMaxPercent
      ? retainedMoles * (initialHeliumPercent / 100)
      : 0.0;
  final salvagedSupplyHeliumMoles = recipeBoosts
      .where((boost) => boost.bank.heliumPercent < heliumSalvageMaxPercent)
      .fold<double>(
        0.0,
        (total, boost) =>
            total + boost.addedMoles * (boost.bank.heliumPercent / 100),
      );
  final heliumSalvagedLitres =
      (retainedHeliumMoles + salvagedSupplyHeliumMoles) * gasMolarVolumeL;
  final heliumRetainedLitres =
      retainedMoles * (initialHeliumPercent / 100) * gasMolarVolumeL;
  final ventedGasLitres = ventedMoles * gasMolarVolumeL;
  final heliumVentedLitres = ventedGasLitres * (initialHeliumPercent / 100);

  final protocolSteps = <ProtocolStep>[
    ...?(salvagePlan?['steps'] as List<ProtocolStep>?),
  ];
  final trajectory = <Map<String, Object?>>[
    <String, Object?>{
      'step': 0,
      'label': 'Start Mix',
      'oxygenPercent': initialOxygenPercent,
      'heliumPercent': initialHeliumPercent,
      'nitrogenPercent': _jsMathMax(
        0.0,
        100 - initialOxygenPercent - initialHeliumPercent,
      ),
      'pressureBar': initialPressureBar,
      'color': '#f43f5e',
    },
  ];

  var currentPressure = postSalvagePressure;
  var cumulativeMoles = retainedMoles;
  var cumulativeOxygenMoles = retainedMoles * (initialOxygenPercent / 100);
  var cumulativeHeliumMoles = retainedMoles * (initialHeliumPercent / 100);

  final pressureScale = _jsMathMax(
    _jsMathMax(1.0, initialPressureBar),
    retainedPressure,
  );
  final pressureTolerance = 2.220446049250313e-16 * pressureScale * 32;
  final shouldDrain = drainPressure > pressureTolerance;
  final drainPrecision = drainPressure > 0 && drainPressure < 0.5
      ? math.max(2, (-math.log(drainPressure) / math.ln10).ceil() + 1)
      : 1;
  if (shouldDrain) {
    currentPressure = retainedPressure;
    protocolSteps.add(
      ProtocolStep(
        type: 'drain',
        title: 'Drain / Vent Cylinder Gas',
        recipeLabel: 'Drain / Vent Cylinder Gas',
        description:
            'Bleed cylinder from ${postSalvagePressure.toStringAsFixed(drainPrecision)} bar down to ${retainedPressure.toStringAsFixed(drainPrecision)} bar (-${drainPressure.toStringAsFixed(drainPrecision)} bar vented). Retains ${((retainedMoles / (initialMoles == 0 || initialMoles.isNaN ? 1.0 : initialMoles)) * 100).toStringAsFixed(0)}% of the original mix.',
        pressureReferenceTemperatureC: temperatureC,
        resultingPressureBar: currentPressure,
        resultingMix: GasMixPercent(
          oxygenPercent: initialOxygenPercent,
          heliumPercent: initialHeliumPercent,
        ),
        oxygenCompressionRatio: null,
        badgeClass: 'bg-rose-500/20 text-rose-300 border-rose-500/40',
      ),
    );
  } else if (salvagedMoles <= 0) {
    protocolSteps.add(
      ProtocolStep(
        type: 'keep',
        title: 'Preserve 100% of Cylinder Gas',
        recipeLabel: 'Preserve 100% of Cylinder Gas',
        pressureReferenceTemperatureC: temperatureC,
        resultingPressureBar: currentPressure,
        resultingMix: GasMixPercent(
          oxygenPercent: initialOxygenPercent,
          heliumPercent: initialHeliumPercent,
        ),
        oxygenCompressionRatio: null,
        badgeClass: 'bg-cyan-500/20 text-cyan-300 border-cyan-500/40',
      ),
    );
  }

  const stepColors = <String>[
    '#06b6d4',
    '#f59e0b',
    '#10b981',
    '#a855f7',
    '#ec4899',
  ];
  var stepNumber = 0;
  var costOperationCounter = 0;
  for (final boost in recipeBoosts) {
    final bank = boost.bank;
    final transferStages = _pressureTransferStages(
      cumulativeMoles: cumulativeMoles,
      cumulativeOxygenMoles: cumulativeOxygenMoles,
      cumulativeHeliumMoles: cumulativeHeliumMoles,
      addedMoles: boost.addedMoles,
      bank: bank,
      bankDensityByBankId: bankDensityByBankId,
      volumeL: volumeL,
      temperatureC: temperatureC,
      useVdw: useVdw,
      airTopUp: _isAirBank(bank),
    );

    for (final stage in transferStages) {
      final stageAddedMoles =
          boost.addedMoles * (stage.endFraction - stage.startFraction);
      cumulativeMoles += stageAddedMoles;
      cumulativeOxygenMoles += stageAddedMoles * (bank.oxygenPercent / 100);
      cumulativeHeliumMoles += stageAddedMoles * (bank.heliumPercent / 100);

      final oxygenPercent = (cumulativeOxygenMoles / cumulativeMoles) * 100;
      final heliumPercent = (cumulativeHeliumMoles / cumulativeMoles) * 100;
      final nitrogenPercent = _jsMathMax(
        0.0,
        100 - oxygenPercent - heliumPercent,
      );
      final nextPressure = stage.receiverEndPressureBar;
      final pressureDelta = nextPressure - currentPressure;
      currentPressure = nextPressure;
      final oxygenCompressionRatio =
          stage.type == 'boost' &&
              bank.oxygenPercent > 40 &&
              stage.sourceEndPressureBar > 0
          ? currentPressure / stage.sourceEndPressureBar
          : null;
      stepNumber++;
      final costOperationId = 'op-${++costOperationCounter}';
      final isAir = _isAirBank(bank);
      final stageMinimumSourcePressureBar = isAir
          ? null
          : minimumSourcePressureFor(bank);
      final sourcePressureTolerance = stageMinimumSourcePressureBar == null
          ? 0.0
          : _jsMathMax(
              1e-9,
              _jsMathMax(
                    stage.sourceEndPressureBar.abs(),
                    stageMinimumSourcePressureBar.abs(),
                  ) *
                  1e-9,
            );
      final sourceExhausted =
          stageMinimumSourcePressureBar != null &&
          (stage.sourceEndPressureBar - stageMinimumSourcePressureBar).abs() <=
              sourcePressureTolerance;
      final color = stepColors[(stepNumber - 1) % stepColors.length];

      trajectory.add(<String, Object?>{
        'step': stepNumber,
        'label': 'Step $stepNumber',
        'bankId': bank.id,
        'bankName': bank.name,
        'oxygenPercent': oxygenPercent,
        'heliumPercent': heliumPercent,
        'nitrogenPercent': nitrogenPercent,
        'pressureBar': currentPressure,
        'pressureDeltaBar': pressureDelta,
        'sourceStartPressureBar': stage.sourceStartPressureBar,
        'sourceEndPressureBar': stage.sourceEndPressureBar,
        'addedMoles': stageAddedMoles,
        'color': color,
      });

      final pressureAmount =
          (stage.receiverEndPressureBar - stage.receiverStartPressureBar).abs();
      final operation = _protocolOperation(stage, bank, cascade: boost.cascade);
      final targetPressure = stage.receiverEndPressureBar.toStringAsFixed(1);
      final leftoverPressure = stage.sourceEndPressureBar.toStringAsFixed(1);
      final descriptionParts = <String>[
        '$operation ${pressureAmount.toStringAsFixed(1)} bar from ${bank.name} to $targetPressure bar.',
        sourceExhausted
            ? 'This empties ${bank.name} and leaves only ${stageMinimumSourcePressureBar.toStringAsFixed(1)} bar of gas.'
            : 'This will leave $leftoverPressure bar of ${bank.name}.',
        'Interim mix is ${oxygenPercent.toStringAsFixed(1)}/${heliumPercent.toStringAsFixed(1)}.',
      ];
      if (oxygenCompressionRatio != null && oxygenCompressionRatio.isFinite) {
        descriptionParts.add(
          'O2 compression ratio is ${oxygenCompressionRatio.toStringAsFixed(2)}:1 (source ${stage.sourceEndPressureBar.toStringAsFixed(1)} bar to receiver ${stage.receiverEndPressureBar.toStringAsFixed(1)} bar).',
        );
      }
      protocolSteps.add(
        ProtocolStep(
          type: stage.type,
          operation: operation,
          title:
              'Step $stepNumber: $operation ${bank.name} to $targetPressure bar',
          recipeLabel: '$operation ${bank.name}',
          recipeAction: operation,
          recipeGas: bank.name,
          sourceBankId: bank.id,
          sourceConsumedMoles: stageAddedMoles,
          costOperation: isAir
              ? 'topUp'
              : (stage.type == 'decant' ? 'decant' : 'boost'),
          costOperationId: costOperationId,
          description: descriptionParts.join(' '),
          pressureDeltaBar: pressureDelta,
          pressureReferenceTemperatureC: temperatureC,
          pressureAtTransferEndReferenceBar: currentPressure,
          resultingPressureBar: currentPressure,
          resultingMix: GasMixPercent(
            oxygenPercent: oxygenPercent,
            heliumPercent: heliumPercent,
          ),
          sourceStartPressureBar: stage.sourceStartPressureBar,
          sourceEndPressureBar: stage.sourceEndPressureBar,
          sourceVolumeL: bank.volumeL,
          sourceStartMoles: isAir
              ? null
              : _jsMathMax(
                  0.0,
                  bankDensityByBankId[bank.id]! * bank.volumeL -
                      boost.addedMoles * stage.startFraction,
                ),
          receiverStartPressureBar: stage.receiverStartPressureBar,
          receiverEndPressureBar: stage.receiverEndPressureBar,
          sourceOxygenPercent: thermal != null ? bank.oxygenPercent : null,
          sourceHeliumPercent: thermal != null ? bank.heliumPercent : null,
          minimumSourcePressureBar: stageMinimumSourcePressureBar,
          sourceExhausted: sourceExhausted,
          oxygenCompressionRatio: oxygenCompressionRatio,
          badgeClass: bank.heliumPercent > 0
              ? 'bg-amber-500/20 text-amber-300 border-amber-500/40'
              : 'bg-emerald-500/20 text-emerald-300 border-emerald-500/40',
        ),
      );
    }
  }

  final blend = _blendSummary(
    retainedPressure: retainedPressure,
    retainedMoles: retainedMoles,
    initialMoles: initialMoles,
    drainPressure: drainPressure,
    ventedMoles: ventedMoles,
    ventedGasLitres: ventedGasLitres,
    heliumVentedLitres: heliumVentedLitres,
    heliumSalvagedLitres: heliumSalvagedLitres,
    heliumRetainedLitres: heliumRetainedLitres,
    finalPressureBar: recipeTargetPressureBar,
    targetOxygenPercent: targetOxygenPercent,
    targetHeliumPercent: targetHeliumPercent,
  );

  if (!exactTargetFeasible) {
    final message = requestedSafetyError != null
        ? '$requestedSafetyError Maximum safe pressure for the exact target mix is ${recipeTargetPressureBar.toStringAsFixed(1)} bar (requested ${targetPressureBar.toStringAsFixed(1)} bar).'
        : 'Requested pressure ${targetPressureBar.toStringAsFixed(1)} bar is unavailable for the exact target mix; maximum safely achievable pressure is ${recipeTargetPressureBar.toStringAsFixed(1)} bar.';
    return _failedResult(
      message,
      gas,
      recipeSolverResult.steps ?? const [],
      maximumPressure: _maximumPressureResult(
        pressureBar: recipeTargetPressureBar,
        solverResult: recipeSolverResult,
        blend: blend,
        protocolSteps: protocolSteps,
        trajectory: trajectory,
      ),
      diagnostics: _createBlendDiagnostics(
        componentShortfalls: componentShortfalls,
        solverResult: recipeSolverResult,
        activeBanks: activeBanks,
        bankMaxMoles: bankMaxMoles,
        temperatureC: temperatureC,
        useVdw: useVdw,
        minimumSourcePressureFor: minimumSourcePressureFor,
      ),
    );
  }

  final result = <String, Object?>{
    'feasible': true,
    'error': null,
    'gas': gas,
    'solution': recipeSolverResult.solution,
    'tableauSteps': recipeSolverResult.steps,
    'blend': blend,
    'protocolSteps': protocolSteps,
    'trajectory': trajectory,
    'maximumPressure': null,
  };
  if (salvagePlan != null) {
    result['salvageTransfers'] = salvagePlan['transfers'];
    result['salvageBanks'] = salvagePlan['banks'];
    result['lpCost'] = recipeSolverResult.cost;
  }
  return result;
}

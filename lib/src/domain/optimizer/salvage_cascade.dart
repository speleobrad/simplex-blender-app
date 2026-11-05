part of '../optimizer.dart';

// Port of js/optimizer.js salvage cascade (JS 2443–2690): moves the working tank's
// surplus into receivers in order, then re-solves the recipe for each variant.

// ignore: constant_identifier_names
const double SALVAGE_MOLE_TOLERANCE = 1e-9;
// ignore: constant_identifier_names
const String SALVAGE_BADGE_CLASS =
    'bg-emerald-500/20 text-emerald-300 border-emerald-500/40';

/// Stand-in id/name for the working cylinder passed to `salvageTransferMoles`.
const String _salvageTankId = '__salvageTank';
const String _salvageTankName = 'Cylinder';

/// Result of [_runSalvageCascade] (JS `{ steps, movedMoles, banks }`) plus the
/// transfer records that JS derives from `steps` via `salvageTransferRecord`.
class _SalvageCascade {
  const _SalvageCascade({
    required this.steps,
    required this.records,
    required this.movedMoles,
    required this.banks,
  });

  final List<ProtocolStep> steps;
  final List<SalvageTransferRecord> records;
  final double movedMoles;
  final List<Bank> banks;
}

/// Salvage context for a solved vent-only baseline (JS `salvageContext`).
class _SalvageContext {
  const _SalvageContext({
    required this.banks,
    required this.physics,
    required this.surplusMoles,
    required this.tankMix,
    required this.tankAtStart,
    required this.retainedMoles,
    required this.initialMoles,
    required this.minimumSourcePressureBar,
    required this.maxBoosterOutputPressureBar,
    required this.bankReachOf,
    required this.bankScoresOf,
  });

  final List<Bank> banks;
  final PhysicsInput physics;
  final double surplusMoles;
  final ({double oxygenPercent, double heliumPercent}) tankMix;
  final Bank tankAtStart;
  final double retainedMoles;
  final double initialMoles;
  final double minimumSourcePressureBar;
  final double maxBoosterOutputPressureBar;
  final double Function(Bank) bankReachOf;
  final double Function(Bank) bankScoresOf;
}

/// One salvage variant plus the data needed to replay it (JS `buildSalvageVariant`
/// return value: `receiverIds` and `result` alongside the selector variant).
class _SalvageBuild {
  const _SalvageBuild({
    required this.receiverIds,
    required this.result,
    required this.variant,
  });

  final List<String> receiverIds;
  final Map<String, Object?> result;
  final SalvageVariant variant;
}

/// JS `runSalvageCascade`. Each receiver yields one `salvage` step per stage
/// (decant, then boost when both apply) that lowers the tank.
_SalvageCascade _runSalvageCascade({
  required Map<String, Object?> input,
  required PhysicsInput physics,
  required List<Bank> banks,
  required double initialMoles,
  required List<String> receiverIds,
  required double surplusMoles,
  required double retainedMoles,
  required double minimumSourcePressureBar,
  required double? maxBoosterOutputPressureBar,
}) {
  final cylinder = input['cylinder']! as Map<String, Object?>;
  final useVdw = physics.useVdw;
  final temperatureC = physics.temperatureC;
  final tankMix = (
    oxygenPercent: _numberOrNan(cylinder['initialOxygenPercent']),
    heliumPercent: _numberOrNan(cylinder['initialHeliumPercent']),
  );
  final tankVolumeL = _numberOrNan(cylinder['volumeL']);
  final litresPerMole = gasConstant * (temperatureC + 273.15);
  Bank tankAt(double pressureBar) => Bank(
    id: _salvageTankId,
    name: _salvageTankName,
    volumeL: tankVolumeL,
    pressureBar: pressureBar,
    oxygenPercent: tankMix.oxygenPercent,
    heliumPercent: tankMix.heliumPercent,
    enabled: true,
  );

  var currentBanks = banks;
  var tankMoles = initialMoles;
  var tankPressureBar = _numberOrNan(cylinder['initialPressureBar']);
  var remainingMoles = surplusMoles;
  var movedMoles = 0.0;
  final steps = <ProtocolStep>[];
  final records = <SalvageTransferRecord>[];

  for (final receiverId in receiverIds) {
    var receiver = currentBanks.firstWhere((bank) => bank.id == receiverId);
    final probe = salvageTransferMoles(
      bank: receiver,
      tank: tankAt(tankPressureBar),
      surplusMoles: remainingMoles,
      physics: physics,
      minimumSourcePressureBar: minimumSourcePressureBar,
      maxBoosterOutputPressureBar: maxBoosterOutputPressureBar,
      retainedMoles: retainedMoles,
    );
    if (probe.movedMoles <= SALVAGE_MOLE_TOLERANCE) {
      continue;
    }
    // A null booster limit is JS `undefined`: no booster limit on the decant pass.
    final boosterLimits = probe.stage == 'decant+boost'
        ? <double?>[null, maxBoosterOutputPressureBar]
        : <double?>[maxBoosterOutputPressureBar];

    for (final boosterLimit in boosterLimits) {
      final sized = salvageTransferMoles(
        bank: receiver,
        tank: tankAt(tankPressureBar),
        surplusMoles: remainingMoles,
        physics: physics,
        minimumSourcePressureBar: minimumSourcePressureBar,
        maxBoosterOutputPressureBar: boosterLimit,
        retainedMoles: retainedMoles,
      );
      if (sized.movedMoles <= SALVAGE_MOLE_TOLERANCE) {
        continue;
      }

      final stage = sized.stage == 'boost' ? 'boost' : 'decant';
      final receiverStart = receiver;
      final receiverEnd = applyTransferToBank(
        receiverStart,
        tankMix,
        sized.movedMoles,
        physics,
      );
      tankMoles -= sized.movedMoles;
      tankPressureBar = _pressureFromMoles(
        tankMoles,
        tankVolumeL,
        tankMix.oxygenPercent,
        tankMix.heliumPercent,
        temperatureC,
        useVdw,
      );
      final movedHeliumLitres =
          sized.movedMoles * (tankMix.heliumPercent / 100) * litresPerMole;
      final verb = stage == 'boost' ? 'Boosts' : 'Decants';
      steps.add(
        ProtocolStep(
          type: 'salvage',
          stage: stage,
          receiverBankId: receiverStart.id,
          receiverBankName: receiverStart.name,
          movedMoles: sized.movedMoles,
          movedHeliumLitres: movedHeliumLitres,
          receiverStartPressureBar: receiverStart.pressureBar,
          receiverEndPressureBar: receiverEnd.pressureBar,
          receiverStartMix: GasMixPercent(
            oxygenPercent: receiverStart.oxygenPercent,
            heliumPercent: receiverStart.heliumPercent,
          ),
          receiverEndMix: GasMixPercent(
            oxygenPercent: receiverEnd.oxygenPercent,
            heliumPercent: receiverEnd.heliumPercent,
          ),
          receiverVolumeL: receiverStart.volumeL,
          title:
              'Salvage: $stage into ${receiverStart.name} to ${receiverEnd.pressureBar.toStringAsFixed(1)} bar',
          recipeLabel: 'Salvage into ${receiverStart.name}',
          description:
              '$verb ${(sized.movedMoles * litresPerMole).toStringAsFixed(0)} L of cylinder gas into ${receiverStart.name}, from ${receiverStart.pressureBar.toStringAsFixed(1)} to ${receiverEnd.pressureBar.toStringAsFixed(1)} bar. Cylinder falls to ${tankPressureBar.toStringAsFixed(1)} bar and ${movedHeliumLitres.toStringAsFixed(0)} L of helium is recovered.',
          pressureReferenceTemperatureC: temperatureC,
          resultingPressureBar: tankPressureBar,
          resultingMix: GasMixPercent(
            oxygenPercent: tankMix.oxygenPercent,
            heliumPercent: tankMix.heliumPercent,
          ),
          sourceOxygenPercent: tankMix.oxygenPercent,
          sourceHeliumPercent: tankMix.heliumPercent,
          badgeClass: SALVAGE_BADGE_CLASS,
        ),
      );
      records.add(
        SalvageTransferRecord(
          receiverId: receiverStart.id,
          movedMoles: sized.movedMoles,
        ),
      );
      currentBanks = [
        for (final bank in currentBanks)
          bank.id == receiverStart.id ? receiverEnd : bank,
      ];
      receiver = receiverEnd;
      remainingMoles -= sized.movedMoles;
      movedMoles += sized.movedMoles;
    }
  }

  return _SalvageCascade(
    steps: steps,
    records: records,
    movedMoles: movedMoles,
    banks: currentBanks,
  );
}

/// JS `salvageTransferRecord`: the replay map for one salvage step. Mixes are
/// written as `{ oxygenPercent, heliumPercent }` maps, as in JS; absent mixes
/// are absent keys.
Map<String, Object?> _salvageTransferRecord(ProtocolStep step) {
  final receiverStartMix = step.receiverStartMix;
  final receiverEndMix = step.receiverEndMix;
  final resultingMix = step.resultingMix;
  return {
    'type': step.type,
    'stage': step.stage,
    'receiverBankId': step.receiverBankId,
    'receiverBankName': step.receiverBankName,
    'movedMoles': step.movedMoles,
    'movedHeliumLitres': step.movedHeliumLitres,
    'receiverStartPressureBar': step.receiverStartPressureBar,
    'receiverEndPressureBar': step.receiverEndPressureBar,
    if (receiverStartMix != null) 'receiverStartMix': _mixMap(receiverStartMix),
    if (receiverEndMix != null) 'receiverEndMix': _mixMap(receiverEndMix),
    'receiverVolumeL': step.receiverVolumeL,
    'resultingPressureBar': step.resultingPressureBar,
    if (resultingMix != null) 'resultingMix': _mixMap(resultingMix),
  };
}

/// Output-map form of a gas mix: `{ oxygenPercent, heliumPercent }` as doubles.
Map<String, Object?> _mixMap(GasMixPercent mix) {
  return {
    'oxygenPercent': mix.oxygenPercent,
    'heliumPercent': mix.heliumPercent,
  };
}

/// JS `salvageContext`. Null when nothing is vented.
_SalvageContext? _salvageContext(
  Map<String, Object?> input,
  Map<String, Object?> baseline, {
  required List<Bank> banks,
  required PhysicsInput physics,
  required BlendSettings? settings,
}) {
  final blend = baseline['blend'] as Map<String, Object?>?;
  final surplusMoles = _numberOrNan(blend?['ventedMoles']);
  if (!(surplusMoles > SALVAGE_MOLE_TOLERANCE)) {
    return null;
  }
  final cylinder = input['cylinder']! as Map<String, Object?>;
  final temperatureC = physics.temperatureC;
  final oxygenPercent = _numberOrNan(cylinder['initialOxygenPercent']);
  final heliumPercent = _numberOrNan(cylinder['initialHeliumPercent']);
  final tankMix = (oxygenPercent: oxygenPercent, heliumPercent: heliumPercent);
  final solution = baseline['solution'] as Map<String, double>?;
  final gas = baseline['gas'] as Map<String, Object?>?;
  return _SalvageContext(
    banks: banks,
    physics: physics,
    surplusMoles: surplusMoles,
    tankMix: tankMix,
    tankAtStart: Bank(
      id: _salvageTankId,
      name: _salvageTankName,
      volumeL: _numberOrNan(cylinder['volumeL']),
      pressureBar: _numberOrNan(cylinder['initialPressureBar']),
      oxygenPercent: oxygenPercent,
      heliumPercent: heliumPercent,
      enabled: true,
    ),
    retainedMoles: _jsOrZero(solution?['x_cyl']),
    initialMoles: _numberOrNan(gas?['initialMoles']),
    // The tank is the salvage source: its floor is the configured source minimum, not a bank's.
    minimumSourcePressureBar: _minimumSourcePressureBarFor(settings, null),
    maxBoosterOutputPressureBar: _boosterOutputLimitBar(settings),
    bankReachOf: (bank) => leftoverReachability(
      oxygenPercent: bank.oxygenPercent,
      heliumPercent: bank.heliumPercent,
      pressureBar: bank.pressureBar,
      maxPressureBar: bank.maxPressureBar,
    ),
    bankScoresOf: (bank) => leftoverAttractiveness(
      oxygenPercent: bank.oxygenPercent,
      heliumPercent: bank.heliumPercent,
      pressureBar: bank.pressureBar,
      volumeL: bank.volumeL,
      maxPressureBar: bank.maxPressureBar,
      temperatureC: temperatureC,
      physics: physics,
    ),
  );
}

/// JS `rankSalvageReceivers`: receiver ids that accept some salvage, best first.
List<String> _rankSalvageReceivers(_SalvageContext context) {
  final candidates = <ReceiverCandidate>[];
  for (final receiver in context.banks.where(isSalvageReceiver)) {
    final probe = salvageTransferMoles(
      bank: receiver,
      tank: context.tankAtStart,
      surplusMoles: context.surplusMoles,
      physics: context.physics,
      minimumSourcePressureBar: context.minimumSourcePressureBar,
      maxBoosterOutputPressureBar: context.maxBoosterOutputPressureBar,
      retainedMoles: context.retainedMoles,
    );
    if (probe.movedMoles <= SALVAGE_MOLE_TOLERANCE) {
      continue;
    }
    candidates.add(
      ReceiverCandidate(
        id: receiver.id,
        receiver: receiver,
        transferredReceiver: applyTransferToBank(
          receiver,
          context.tankMix,
          probe.movedMoles,
          context.physics,
        ),
      ),
    );
  }
  return rankReceivers(
    candidates,
    context.bankScoresOf,
    context.bankReachOf,
  ).map((candidate) => candidate.receiver.id).toList();
}

/// JS `buildSalvageVariant`: one variant that moves gas into the given receiver
/// prefix, re-solved for the recipe. Null when nothing moves or the re-solve is infeasible.
_SalvageBuild? _buildSalvageVariant(
  Map<String, Object?> input,
  _SalvageContext context,
  List<String> receiverIds, {
  required BlendSettings? settings,
  required ThermalInput? thermal,
}) {
  final cascade = _runSalvageCascade(
    input: input,
    physics: context.physics,
    banks: context.banks,
    initialMoles: context.initialMoles,
    receiverIds: receiverIds,
    surplusMoles: context.surplusMoles,
    retainedMoles: context.retainedMoles,
    minimumSourcePressureBar: context.minimumSourcePressureBar,
    maxBoosterOutputPressureBar: context.maxBoosterOutputPressureBar,
  );
  if (cascade.movedMoles <= SALVAGE_MOLE_TOLERANCE) {
    return null;
  }
  final plan = <String, Object?>{
    'movedMoles': cascade.movedMoles,
    'steps': cascade.steps,
    'transfers': [
      for (final step in cascade.steps) _salvageTransferRecord(step),
    ],
    'banks': cascade.banks,
  };
  final result = _solveBlendWithoutSalvage(
    {...input, '_salvagePlan': plan},
    physics: context.physics,
    banks: cascade.banks,
    settings: settings,
    thermal: thermal,
  );
  if (result['feasible'] != true) {
    return null;
  }
  final solution = result['solution'] as Map<String, double>?;
  final retainedMoles = _jsOrZero(solution?['x_cyl']);
  return _SalvageBuild(
    receiverIds: receiverIds,
    result: result,
    variant: SalvageVariant(
      id: receiverIds.join(','),
      salvagedMoles: cascade.movedMoles,
      resolvedSurplusMoles: context.initialMoles - retainedMoles,
      finalBanks: _bankStatesAfterRecipe(
        result,
        cascade.banks,
        context.physics,
      ),
      transfers: cascade.records,
      retainedMoles: retainedMoles,
      lpCost: _numberOrNull(result['lpCost']),
    ),
  );
}

/// JS `salvageBaseline`.
SalvageBaseline _salvageBaseline(
  Map<String, Object?> baseline,
  _SalvageContext context,
) {
  return SalvageBaseline(
    retainedMoles: context.retainedMoles,
    finalBanks: _bankStatesAfterRecipe(
      baseline,
      context.banks,
      context.physics,
    ),
  );
}

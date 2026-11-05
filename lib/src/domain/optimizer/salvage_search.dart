part of '../optimizer.dart';

// Port of js/optimizer.js salvage search and static salvage entry point
// (JS 2679–2776). The cascade and variant builders live in salvage_cascade.dart.

/// JS `requestedSalvageCandidate`: the requested-target candidate of a thermal
/// input, carrying the internal thermal-target flag. Returns [input] when there is no thermal.
Map<String, Object?> _requestedSalvageCandidate(
  Map<String, Object?> input, {
  required PhysicsInput physics,
  required ThermalInput? thermal,
}) {
  if (thermal == null) {
    return input;
  }
  final cylinder = input['cylinder']! as Map<String, Object?>;
  return {
    ...input,
    INTERNAL_THERMAL_TARGET: true,
    'cylinder': {
      ...cylinder,
      'targetPressureBar': _normalizeInWaterTarget(
        input,
        thermal: thermal,
        physics: physics,
      ),
    },
  };
}

/// Picks the salvage receiver prefix once, on the requested target: the N+1 prefix
/// search with the selector's gates. Returns the winning receiver ids, or null for
/// vent-only or invalid input. JS `searchSalvageVariant`.
List<String>? searchSalvageVariant(Map<String, Object?> input) {
  if (_validateBlendInput(
    input,
    internalThermalTarget: _internalThermalTargetFlag(input),
  ).isNotEmpty) {
    return null;
  }
  final parsed = _parseBlendInput(input);
  final physics = parsed.physics;
  final banks = parsed.banks;
  final settings = parsed.settings;
  final thermal = parsed.thermal;
  final candidate = _requestedSalvageCandidate(
    input,
    physics: physics,
    thermal: thermal,
  );
  final baseline = _solveBlendWithoutSalvage(
    candidate,
    physics: physics,
    banks: banks,
    settings: settings,
    thermal: thermal,
  );
  if (baseline['feasible'] != true) {
    return null;
  }
  final context = _salvageContext(
    candidate,
    baseline,
    banks: banks,
    physics: physics,
    settings: settings,
  );
  if (context == null) {
    return null;
  }

  final rankedReceiverIds = _rankSalvageReceivers(context);
  final builds = <_SalvageBuild>[];
  for (var count = 1; count <= rankedReceiverIds.length; count++) {
    final build = _buildSalvageVariant(
      candidate,
      context,
      rankedReceiverIds.sublist(0, count),
      settings: settings,
      thermal: thermal,
    );
    if (build != null) {
      builds.add(build);
    }
  }
  // A receiver ranked first can fail a gate that another receiver alone would pass, so every
  // other receiver is also tried on its own.
  for (final receiverId in rankedReceiverIds.skip(1)) {
    final build = _buildSalvageVariant(
      candidate,
      context,
      [receiverId],
      settings: settings,
      thermal: thermal,
    );
    if (build != null) {
      builds.add(build);
    }
  }
  final selected = selectSalvageVariant(
    baseline: _salvageBaseline(baseline, context),
    variants: [for (final build in builds) build.variant],
    bankScoresOf: context.bankScoresOf,
    bankReachOf: context.bankReachOf,
    physics: physics,
  );
  if (selected == null) {
    return null;
  }
  return _buildOf(builds, selected).receiverIds;
}

/// Static blend with salvage. The receiver prefix comes from [searchSalvageVariant]
/// (run once per optimize). It is replayed here on this input's own vent-only
/// solve, and the variant is kept only if the selector's gates still pass.
/// Otherwise vent-only. JS `optimizeBlendWithoutThermal`.
Map<String, Object?> optimizeBlendWithoutThermal(Map<String, Object?> input) {
  final inputErrors = _validateBlendInput(
    input,
    internalThermalTarget: _internalThermalTargetFlag(input),
  );
  if (inputErrors.isNotEmpty) {
    return _invalidBlendInputResult(inputErrors);
  }
  final parsed = _parseBlendInput(input);
  final physics = parsed.physics;
  final banks = parsed.banks;
  final settings = parsed.settings;
  final thermal = parsed.thermal;
  final baseline = _solveBlendWithoutSalvage(
    input,
    physics: physics,
    banks: banks,
    settings: settings,
    thermal: thermal,
  );
  final receiverIds = input['_salvageReceiverIds'] as List<String>?;
  if (input['_salvage'] == false ||
      baseline['feasible'] != true ||
      receiverIds == null) {
    return baseline;
  }
  final context = _salvageContext(
    input,
    baseline,
    banks: banks,
    physics: physics,
    settings: settings,
  );
  if (context == null) {
    return baseline;
  }
  final build = _buildSalvageVariant(
    input,
    context,
    receiverIds,
    settings: settings,
    thermal: thermal,
  );
  if (build == null) {
    return baseline;
  }
  final selected = selectSalvageVariant(
    baseline: _salvageBaseline(baseline, context),
    variants: [build.variant],
    bankScoresOf: context.bankScoresOf,
    bankReachOf: context.bankReachOf,
    physics: physics,
  );
  if (selected == null) {
    return baseline;
  }
  final output = Map<String, Object?>.of(_buildOf([build], selected).result);
  output.remove('lpCost');
  return output;
}

_SalvageBuild _buildOf(List<_SalvageBuild> builds, SalvageVariant selected) {
  return builds.firstWhere((build) => identical(build.variant, selected));
}

/// Bank states once the recipe has drawn its gas. Draws are keyed by the enabled-bank
/// index that `_solveBlendWithoutSalvage` uses for its variable names; the compressor
/// bank is appended after the real banks, so it never shifts these names. JS `bankStatesAfterRecipe`.
List<Bank> _bankStatesAfterRecipe(
  Map<String, Object?> result,
  List<Bank> banks,
  PhysicsInput physics,
) {
  final names = _bankVariableNames(
    banks.where((bank) => bank.enabled).toList(),
  );
  final solution = result['solution'] as Map<String, double>?;
  var enabledIndex = 0;
  return [
    for (final bank in banks)
      if (!bank.enabled)
        bank
      else
        applyDrawToBank(
          bank,
          _jsOrZero(solution?[names[enabledIndex++]]),
          physics,
        ),
  ];
}

// ignore: constant_identifier_names
const double THERMAL_TARGET_TOLERANCE_BAR = 1e-5;
// ignore: constant_identifier_names
const double MINIMUM_TARGET_PRESSURE_BAR = 10;
// ignore: constant_identifier_names
const double MAXIMUM_TARGET_PRESSURE_BAR = 350;

/// JS `normalizeInWaterTarget`: the cylinder's requested in-water pressure, moved
/// from the in-water temperature to ambient. The JS `input.thermal` is passed as
/// [thermal] and `input.physics` as [physics]; the cylinder map is read from [input].
double _normalizeInWaterTarget(
  Map<String, Object?> input, {
  required ThermalInput thermal,
  required PhysicsInput physics,
}) {
  final cylinder = input['cylinder']! as Map<String, Object?>;
  final requestedInWaterPressureBar = _numberOrNan(
    cylinder['targetPressureBar'],
  );
  final requestedInWaterTemperatureC =
      thermal.targetInWaterTemperatureC ?? thermal.ambientTemperatureC;
  return calculatePressureAtTemperature(
    pressureBar: requestedInWaterPressureBar,
    oxygenPercent: _numberOrNan(cylinder['targetOxygenPercent']),
    heliumPercent: _numberOrNan(cylinder['targetHeliumPercent']),
    fromTemperatureC: requestedInWaterTemperatureC,
    toTemperatureC: thermal.ambientTemperatureC,
    volumeL: _numberOrNan(cylinder['volumeL']),
    useVdw: physics.model == 'vdw',
  );
}

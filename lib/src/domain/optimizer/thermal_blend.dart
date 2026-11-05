part of '../optimizer.dart';

/// Typed views shared by one thermal search. JS spreads `input` into every
/// candidate, but `physics`, `settings`, and `thermal` never change between
/// candidates, so they travel here instead of in the candidate map.
class _ThermalContext {
  const _ThermalContext({
    required this.physics,
    required this.settings,
    required this.thermal,
  });

  final PhysicsInput physics;
  final BlendSettings? settings;
  final ThermalInput thermal;
}

/// JS candidate object `{candidateInput, result, simulation}`.
class _ThermalCandidate {
  const _ThermalCandidate({
    required this.candidateInput,
    required this.result,
    required this.simulation,
  });

  final Map<String, Object?> candidateInput;
  final Map<String, Object?> result;
  final ThermalProtocolResult? simulation;
}

const String _thermalUnsafeError =
    'Thermal protocol cannot remain within cylinder pressure limits within the 1440-minute wait limit.';

/// JS truthiness for values read from map-shaped trajectory points.
bool _thermalTruthy(Object? value) {
  if (value == null) {
    return false;
  }
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0 && !value.isNaN;
  }
  if (value is String) {
    return value.isNotEmpty;
  }
  return true;
}

List<ProtocolStep> _protocolStepsOf(Object? value) {
  return [for (final step in value! as List<Object?>) step! as ProtocolStep];
}

List<Map<String, Object?>> _trajectoryOf(Object? value) {
  return [
    for (final point in value! as List<Object?>) point! as Map<String, Object?>,
  ];
}

Map<String, Object?> _nullThermalState(
  double requestedInWaterPressureBar,
  double requestedInWaterTemperatureC,
  double ambientSettledTargetPressureBar,
) {
  return <String, Object?>{
    'finalTransferEndPressureBar': null,
    'finalTransferEndTemperatureC': null,
    'finalAmbientPressureBar': null,
    'finalAmbientTemperatureC': null,
    'finalInWaterPressureBar': null,
    'finalInWaterTemperatureC': null,
    'requestedInWaterPressureBar': requestedInWaterPressureBar,
    'requestedInWaterTemperatureC': requestedInWaterTemperatureC,
    'ambientSettledTargetPressureBar': ambientSettledTargetPressureBar,
  };
}

/// JS `gas && { ...gas, targetPressureBar }`.
Map<String, Object?>? _gasWithTarget(Object? gas, double targetPressureBar) {
  if (gas == null) {
    return null;
  }
  return <String, Object?>{
    ...(gas as Map<String, Object?>),
    'targetPressureBar': targetPressureBar,
  };
}

/// JS `trajectoryWithThermalEndpoints`. [simulation] must be non-null (JS
/// returns early on a missing simulation, which the typed caller never passes).
List<Map<String, Object?>> _trajectoryWithThermalEndpoints(
  List<Map<String, Object?>> trajectory,
  ThermalProtocolResult simulation,
) {
  final transferSteps = <({ProtocolStep step, ThermalStep state})>[
    for (final step in simulation.protocolSteps)
      if (step.type != 'drain' &&
          step.type != 'salvage' &&
          step.thermal != null &&
          step.thermal!.rateSource.isNotEmpty &&
          step.thermal!.rateSource != 'none')
        (step: step, state: step.thermal!),
  ];
  final mappedTrajectory = <Map<String, Object?>>[];
  var transferCursor = 0;
  var trajectoryStep = 0;
  for (final point in trajectory) {
    if (!_thermalTruthy(point['bankId'])) {
      mappedTrajectory.add(point);
      final stepValue = _numberOrNull(point['step']);
      final pointStep = stepValue == null || stepValue.isNaN || stepValue == 0
          ? 0
          : stepValue.toInt();
      trajectoryStep = _jsMathMax(
        trajectoryStep.toDouble(),
        pointStep.toDouble(),
      ).toInt();
      continue;
    }
    if (transferCursor >= transferSteps.length) {
      mappedTrajectory.add(point);
      trajectoryStep++;
      continue;
    }
    final firstTransfer = transferSteps[transferCursor];
    final stages = <({ProtocolStep step, ThermalStep state})>[firstTransfer];
    transferCursor++;
    if (firstTransfer.step.thermalSplit) {
      while (transferCursor < transferSteps.length &&
          transferSteps[transferCursor].step.thermalSplit &&
          transferSteps[transferCursor].step.measurementIndexExplicitNull) {
        stages.add(transferSteps[transferCursor]);
        transferCursor++;
      }
    }
    for (var stageIndex = 0; stageIndex < stages.length; stageIndex++) {
      final step = stages[stageIndex].step;
      final state = stages[stageIndex].state;
      final resultingMix = step.resultingMix;
      final pointOxygen = _numberOrNull(point['oxygenPercent']);
      final pointHelium = _numberOrNull(point['heliumPercent']);
      final oxygenPercent = resultingMix?.oxygenPercent ?? pointOxygen;
      final heliumPercent = resultingMix?.heliumPercent ?? pointHelium;
      final pressureBar = _isFinite(step.resultingPressureBar)
          ? step.resultingPressureBar!
          : state.pressureAtTransferEndReferenceBar;
      final receiverStartPressureBar = _isFinite(step.receiverStartPressureBar)
          ? step.receiverStartPressureBar!
          : _numberOrNan(point['pressureBar']) -
                (_numberOrNull(point['pressureDeltaBar']) ?? 0.0);
      final pressureDeltaBar = pressureBar - receiverStartPressureBar;
      final splitLabel = firstTransfer.step.thermalSplit
          ? ' (safe stage ${stageIndex + 1})'
          : '';
      trajectoryStep++;
      final nitrogenFallback = _jsMathMax(
        0.0,
        100.0 - (oxygenPercent ?? double.nan) - (heliumPercent ?? double.nan),
      );
      mappedTrajectory.add(<String, Object?>{
        ...point,
        'step': trajectoryStep,
        'label':
            '${point['label'] ?? step.title ?? 'Step $trajectoryStep'}$splitLabel',
        'oxygenPercent': oxygenPercent,
        'heliumPercent': heliumPercent,
        'nitrogenPercent':
            _numberOrNull(point['nitrogenPercent']) != null &&
                resultingMix == null
            ? _numberOrNull(point['nitrogenPercent'])
            : nitrogenFallback,
        'pressureBar': pressureBar,
        'pressureDeltaBar': pressureDeltaBar,
        'sourceStartPressureBar': _isFinite(step.sourceStartPressureBar)
            ? step.sourceStartPressureBar
            : point['sourceStartPressureBar'],
        'sourceEndPressureBar': _isFinite(step.sourceEndPressureBar)
            ? step.sourceEndPressureBar
            : point['sourceEndPressureBar'],
        'addedMoles': _isFinite(step.sourceConsumedMoles)
            ? step.sourceConsumedMoles
            : point['addedMoles'],
        'pressureAtTransferEndReferenceBar':
            state.pressureAtTransferEndReferenceBar,
        'pressureAtTransferEndAmbientBar':
            state.pressureAtTransferEndAmbientBar,
        'pressureAtTransferEndHotBar': state.pressureAtTransferEndHotBar,
        'ambientPressureBar': state.pressureAtTransferEndAmbientBar,
        'hotPressureBar': state.pressureAtTransferEndHotBar,
      });
    }
  }
  return mappedTrajectory;
}

bool _isFinite(double? value) => value != null && value.isFinite;

/// JS `thermalState`. Reads the candidate's simulation; a missing simulation
/// throws, as the JS dereference does.
Map<String, Object?> _thermalState(
  _ThermalCandidate candidate,
  double requestedInWaterPressureBar,
  double requestedInWaterTemperatureC,
  double ambientSettledTargetPressureBar,
  _ThermalContext ctx,
) {
  final simulation = candidate.simulation!;
  final finalSummary = simulation.finalSummary;
  final cylinder =
      candidate.candidateInput['cylinder']! as Map<String, Object?>;
  final finalInWaterPressureBar = calculatePressureAtTemperature(
    pressureBar: finalSummary.finalAmbientPressureBar,
    oxygenPercent: _numberOrNan(cylinder['targetOxygenPercent']),
    heliumPercent: _numberOrNan(cylinder['targetHeliumPercent']),
    fromTemperatureC: finalSummary.finalAmbientTemperatureC,
    toTemperatureC: requestedInWaterTemperatureC,
    volumeL: _numberOrNan(cylinder['volumeL']),
    useVdw: ctx.physics.useVdw,
  );
  return <String, Object?>{
    'finalTransferEndPressureBar': finalSummary.finalTransferEndPressureBar,
    'finalTransferEndTemperatureC': finalSummary.finalTransferEndTemperatureC,
    'finalAmbientPressureBar': finalSummary.finalAmbientPressureBar,
    'finalAmbientTemperatureC': finalSummary.finalAmbientTemperatureC,
    'finalInWaterPressureBar': finalInWaterPressureBar,
    'finalInWaterTemperatureC': requestedInWaterTemperatureC,
    'requestedInWaterPressureBar': requestedInWaterPressureBar,
    'requestedInWaterTemperatureC': requestedInWaterTemperatureC,
    'ambientSettledTargetPressureBar': ambientSettledTargetPressureBar,
    'requestedSettledTargetPressureBar': ambientSettledTargetPressureBar,
  };
}

/// JS `evaluateThermalCandidate`.
_ThermalCandidate _evaluateThermalCandidate(
  Map<String, Object?> input,
  Map<String, Object?> Function(Map<String, Object?>) optimizeStatic,
  double targetPressureBar,
  _ThermalContext ctx,
) {
  final candidateInput = <String, Object?>{
    ...input,
    INTERNAL_THERMAL_TARGET: true,
    'cylinder': <String, Object?>{
      ...(input['cylinder']! as Map<String, Object?>),
      'targetPressureBar': targetPressureBar,
    },
  };
  final result = optimizeStatic(candidateInput);
  if (result['feasible'] != true) {
    return _ThermalCandidate(
      candidateInput: candidateInput,
      result: result,
      simulation: null,
    );
  }
  final scheduled = scheduleSafeThermalProtocol(
    protocolSteps: _protocolStepsOf(result['protocolSteps']),
    cylinder: candidateInput['cylinder']! as Map<String, Object?>,
    physics: ctx.physics,
    thermal: ctx.thermal,
    settings: ctx.settings,
  );
  if (scheduled['unsafe'] == true) {
    return _ThermalCandidate(
      candidateInput: candidateInput,
      result: <String, Object?>{
        ...result,
        'feasible': false,
        'error': _thermalUnsafeError,
      },
      simulation: null,
    );
  }
  return _ThermalCandidate(
    candidateInput: candidateInput,
    result: result,
    simulation: scheduled['simulation']! as ThermalProtocolResult,
  );
}

/// JS `thermalResult` with its default arguments (all JS callers pass only
/// the candidate).
Map<String, Object?> _thermalResult(
  _ThermalCandidate candidate,
  _ThermalContext ctx,
) {
  final candidateInput = candidate.candidateInput;
  final cylinder = candidateInput['cylinder']! as Map<String, Object?>;
  final requestedInWaterPressureBar =
      _numberOrNull(candidateInput['_requestedInWaterPressureBar']) ??
      _numberOrNan(cylinder['targetPressureBar']);
  final requestedInWaterTemperatureC =
      ctx.thermal.targetInWaterTemperatureC ?? ctx.thermal.ambientTemperatureC;
  final ambientSettledTargetPressureBar =
      _numberOrNull(candidateInput['_ambientSettledTargetPressureBar']) ??
      _numberOrNan(cylinder['targetPressureBar']);
  final thermal = _thermalState(
    candidate,
    requestedInWaterPressureBar,
    requestedInWaterTemperatureC,
    ambientSettledTargetPressureBar,
    ctx,
  );
  final result = candidate.result;
  final simulation = candidate.simulation!;
  return <String, Object?>{
    ...result,
    'gas': _gasWithTarget(result['gas'], requestedInWaterPressureBar),
    'logicalPlan':
        result['logicalPlan'] ??
        <String, Object?>{
          'protocolSteps': result['protocolSteps'],
          'trajectory': result['trajectory'],
          'targetPressureBar': _numberOrNan(cylinder['targetPressureBar']),
        },
    'protocolSteps': simulation.protocolSteps,
    'trajectory': _trajectoryWithThermalEndpoints(
      _trajectoryOf(result['trajectory']),
      simulation,
    ),
    'thermal': thermal,
  };
}

/// JS `finalizeComposedPlan`. [input] is a validated blend input whose thermal
/// entry must be present (JS `thermalResult` reads it). Returns null when the
/// merged protocol cannot be scheduled within the cylinder limits.
Map<String, Object?>? finalizeComposedPlan(
  Map<String, Object?> input, {
  required Map<String, Object?> template,
  required List<ProtocolStep> protocolSteps,
  required List<Map<String, Object?>> trajectory,
  required double targetPressureBar,
}) {
  final parsed = _parseBlendInput(input);
  final physics = parsed.physics;
  final settings = parsed.settings;
  final thermal = parsed.thermal!;
  final ctx = _ThermalContext(
    physics: physics,
    settings: settings,
    thermal: thermal,
  );
  final inputCylinder = input['cylinder']! as Map<String, Object?>;
  final candidateInput = <String, Object?>{
    ...input,
    INTERNAL_THERMAL_TARGET: true,
    '_requestedInWaterPressureBar': _numberOrNan(
      inputCylinder['targetPressureBar'],
    ),
    '_ambientSettledTargetPressureBar': _normalizeInWaterTarget(
      input,
      thermal: thermal,
      physics: physics,
    ),
    'cylinder': <String, Object?>{
      ...inputCylinder,
      'targetPressureBar': targetPressureBar,
    },
  };
  final scheduled = scheduleSafeThermalProtocol(
    protocolSteps: protocolSteps,
    cylinder: candidateInput['cylinder']! as Map<String, Object?>,
    physics: physics,
    thermal: thermal,
    settings: settings,
  );
  if (scheduled['unsafe'] == true) {
    return null;
  }
  return _thermalResult(
    _ThermalCandidate(
      candidateInput: candidateInput,
      result: <String, Object?>{
        ...template,
        'protocolSteps': protocolSteps,
        'trajectory': trajectory,
        'logicalPlan': <String, Object?>{
          'protocolSteps': protocolSteps,
          'trajectory': trajectory,
          'targetPressureBar': targetPressureBar,
        },
      },
      simulation: scheduled['simulation']! as ThermalProtocolResult,
    ),
    ctx,
  );
}

/// JS `thermalizedMaximumResult`.
Map<String, Object?> _thermalizedMaximumResult(
  _ThermalCandidate candidate,
  double requestedInWaterPressureBar,
  double requestedInWaterTemperatureC,
  double ambientSettledTargetPressureBar,
  _ThermalContext ctx,
) {
  final result = candidate.result;
  final gas = _gasWithTarget(result['gas'], requestedInWaterPressureBar);
  final maximum = result['maximumPressure'] as Map<String, Object?>?;
  if (maximum == null) {
    return <String, Object?>{
      ...result,
      'gas': gas,
      'thermal': _nullThermalState(
        requestedInWaterPressureBar,
        requestedInWaterTemperatureC,
        ambientSettledTargetPressureBar,
      ),
    };
  }
  final candidateInput = candidate.candidateInput;
  final scheduled = scheduleSafeThermalProtocol(
    protocolSteps: _protocolStepsOf(maximum['protocolSteps']),
    cylinder: candidateInput['cylinder']! as Map<String, Object?>,
    physics: ctx.physics,
    thermal: ctx.thermal,
    settings: ctx.settings,
  );
  if (scheduled['unsafe'] == true) {
    return <String, Object?>{
      ...result,
      'gas': gas,
      'maximumPressure': null,
      'thermal': _nullThermalState(
        requestedInWaterPressureBar,
        requestedInWaterTemperatureC,
        ambientSettledTargetPressureBar,
      ),
    };
  }
  final simulation = scheduled['simulation']! as ThermalProtocolResult;
  final maximumCandidate = _ThermalCandidate(
    candidateInput: candidate.candidateInput,
    result: candidate.result,
    simulation: simulation,
  );
  final thermal = _thermalState(
    maximumCandidate,
    requestedInWaterPressureBar,
    requestedInWaterTemperatureC,
    ambientSettledTargetPressureBar,
    ctx,
  );
  final trajectory = _trajectoryWithThermalEndpoints(
    _trajectoryOf(maximum['trajectory']),
    simulation,
  );
  return <String, Object?>{
    ...result,
    'gas': gas,
    'trajectory': trajectory,
    'maximumPressure': <String, Object?>{
      ...maximum,
      'protocolSteps': simulation.protocolSteps,
      'trajectory': trajectory,
      'thermal': thermal,
    },
    'thermal': thermal,
  };
}

/// JS `thermalLimitResult`. [input] is the original (un-searched) input.
Map<String, Object?> _thermalLimitResult(
  Map<String, Object?> input,
  _ThermalCandidate requested,
  _ThermalCandidate maximum,
  _ThermalContext ctx,
) {
  final inputCylinder = input['cylinder']! as Map<String, Object?>;
  final requestedInWaterPressureBar = _numberOrNan(
    inputCylinder['targetPressureBar'],
  );
  final requestedInWaterTemperatureC =
      ctx.thermal.targetInWaterTemperatureC ?? ctx.thermal.ambientTemperatureC;
  final ambientSettledTargetPressureBar = _normalizeInWaterTarget(
    input,
    thermal: ctx.thermal,
    physics: ctx.physics,
  );
  final thermal = _thermalState(
    _ThermalCandidate(
      candidateInput: maximum.candidateInput,
      result: maximum.result,
      simulation: maximum.simulation,
    ),
    requestedInWaterPressureBar,
    requestedInWaterTemperatureC,
    ambientSettledTargetPressureBar,
    ctx,
  );
  final maximumResult = maximum.result;
  final maximumSimulation = maximum.simulation!;
  final trajectory = _trajectoryWithThermalEndpoints(
    _trajectoryOf(maximumResult['trajectory']),
    maximumSimulation,
  );
  final blend = maximumResult['blend'] as Map<String, Object?>;
  final maximumPressure = <String, Object?>{
    'pressureBar': blend['finalPressureBar'],
    'solution': maximumResult['solution'],
    'tableauSteps': maximumResult['tableauSteps'],
    'blend': blend,
    'protocolSteps': maximumSimulation.protocolSteps,
    'trajectory': trajectory,
    'thermal': thermal,
  };
  final requestedResult = requested.result;
  final requestedGas = requestedResult['gas'] as Map<String, Object?>?;
  final failed = _failedResult(
    'Requested in-water pressure ${requestedInWaterPressureBar.toStringAsFixed(1)} bar cannot be reached; maximum predicted ambient pressure is ${maximumSimulation.finalSummary.finalAmbientPressureBar.toStringAsFixed(1)} bar.',
    <String, Object?>{
      ...?requestedGas,
      'targetPressureBar': requestedInWaterPressureBar,
    },
    maximumResult['tableauSteps']! as List<Object?>,
    maximumPressure: maximumPressure,
    diagnostics: requestedResult['diagnostics'] as Map<String, Object?>?,
    reasonCode: requestedResult.containsKey('reasonCode')
        ? requestedResult['reasonCode']
        : _inferReasonDefault,
  );
  return <String, Object?>{
    ...failed,
    if (maximumResult['salvageTransfers'] != null) ...<String, Object?>{
      'salvageTransfers': maximumResult['salvageTransfers'],
      'salvageBanks': maximumResult['salvageBanks'],
    },
    'thermal': thermal,
  };
}

/// JS `highestSafeThermalCandidate`.
_ThermalCandidate? _highestSafeThermalCandidate(
  Map<String, Object?> searchInput,
  Map<String, Object?> Function(Map<String, Object?>) optimizeStatic,
  double upperPressureBar,
  _ThermalContext ctx,
) {
  final floor = _evaluateThermalCandidate(
    searchInput,
    optimizeStatic,
    MINIMUM_TARGET_PRESSURE_BAR,
    ctx,
  );
  if (floor.result['feasible'] != true) {
    return null;
  }
  var lowerPressureBar = MINIMUM_TARGET_PRESSURE_BAR;
  var upperPressure = upperPressureBar;
  var highestFeasible = floor;
  for (var iteration = 0; iteration < 40; iteration++) {
    final candidatePressureBar = (lowerPressureBar + upperPressure) / 2;
    final candidate = _evaluateThermalCandidate(
      searchInput,
      optimizeStatic,
      candidatePressureBar,
      ctx,
    );
    if (candidate.result['feasible'] != true) {
      upperPressure = candidatePressureBar;
      continue;
    }
    lowerPressureBar = candidatePressureBar;
    highestFeasible = candidate;
  }
  return highestFeasible;
}

/// JS `optimizeThermalBlend` (not exported). Requires a thermal input.
Map<String, Object?> _optimizeThermalBlend(
  Map<String, Object?> input,
  Map<String, Object?> Function(Map<String, Object?>) optimizeStatic,
  _ThermalContext ctx,
) {
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

  final inputCylinder = input['cylinder']! as Map<String, Object?>;
  final thermal = ctx.thermal;
  final requestedInWaterPressureBar = _numberOrNan(
    inputCylinder['targetPressureBar'],
  );
  final requestedInWaterTemperatureC =
      thermal.targetInWaterTemperatureC ?? thermal.ambientTemperatureC;
  final ambientSettledTargetPressureBar = _normalizeInWaterTarget(
    input,
    thermal: thermal,
    physics: ctx.physics,
  );
  final searchInput = <String, Object?>{
    ...input,
    '_requestedInWaterPressureBar': requestedInWaterPressureBar,
    '_ambientSettledTargetPressureBar': ambientSettledTargetPressureBar,
    'cylinder': <String, Object?>{
      ...inputCylinder,
      'targetPressureBar': ambientSettledTargetPressureBar,
    },
  };
  final requestedPressureBar = ambientSettledTargetPressureBar;
  final ambientDiagnostic =
      'Ambient-settled target: ${ambientSettledTargetPressureBar.toStringAsFixed(1)} bar.';
  final requested = _evaluateThermalCandidate(
    searchInput,
    optimizeStatic,
    requestedPressureBar,
    ctx,
  );
  if (requested.result['feasible'] != true) {
    final highestSafe = _highestSafeThermalCandidate(
      searchInput,
      optimizeStatic,
      requestedPressureBar,
      ctx,
    );
    if (highestSafe != null) {
      return _thermalLimitResult(input, requested, highestSafe, ctx);
    }
    final infeasible = _thermalizedMaximumResult(
      requested,
      requestedInWaterPressureBar,
      requestedInWaterTemperatureC,
      ambientSettledTargetPressureBar,
      ctx,
    );
    return <String, Object?>{
      ...infeasible,
      'error':
          'Requested in-water pressure ${requestedInWaterPressureBar.toStringAsFixed(1)} bar cannot be reached. ${infeasible['error'] ?? 'No safe thermal recipe is available.'} $ambientDiagnostic',
    };
  }

  final requestedPressureDifference =
      requested.simulation!.finalSummary.finalAmbientPressureBar -
      requestedPressureBar;
  if (requestedPressureDifference.abs() <= THERMAL_TARGET_TOLERANCE_BAR) {
    return _thermalResult(requested, ctx);
  }
  if (requestedPressureDifference > 0) {
    final floor = _evaluateThermalCandidate(
      searchInput,
      optimizeStatic,
      MINIMUM_TARGET_PRESSURE_BAR,
      ctx,
    );
    if (floor.result['feasible'] != true) {
      final fallback = _thermalizedMaximumResult(
        floor,
        requestedInWaterPressureBar,
        requestedInWaterTemperatureC,
        ambientSettledTargetPressureBar,
        ctx,
      );
      return <String, Object?>{
        ...fallback,
        'error':
            'Requested in-water pressure ${requestedInWaterPressureBar.toStringAsFixed(1)} bar cannot be reached. ${fallback['error'] ?? 'No safe thermal recipe is available.'} $ambientDiagnostic',
      };
    }

    final floorPressureDifference =
        floor.simulation!.finalSummary.finalAmbientPressureBar -
        requestedPressureBar;
    if (floorPressureDifference.abs() <= THERMAL_TARGET_TOLERANCE_BAR) {
      return _thermalResult(floor, ctx);
    }
    if (floorPressureDifference > 0) {
      return _thermalLimitResult(input, requested, requested, ctx);
    }

    var lowerPressureBar = MINIMUM_TARGET_PRESSURE_BAR;
    var upperPressureBar = requestedPressureBar;
    var highestBelowTarget = floor;
    for (var iteration = 0; iteration < 40; iteration++) {
      final candidatePressureBar = (lowerPressureBar + upperPressureBar) / 2;
      final candidate = _evaluateThermalCandidate(
        searchInput,
        optimizeStatic,
        candidatePressureBar,
        ctx,
      );
      if (candidate.result['feasible'] != true) {
        lowerPressureBar = candidatePressureBar;
        continue;
      }

      final pressureDifference =
          candidate.simulation!.finalSummary.finalAmbientPressureBar -
          requestedPressureBar;
      if (pressureDifference.abs() <= THERMAL_TARGET_TOLERANCE_BAR) {
        return _thermalResult(candidate, ctx);
      }
      if (pressureDifference < 0) {
        lowerPressureBar = candidatePressureBar;
        highestBelowTarget = candidate;
      } else {
        upperPressureBar = candidatePressureBar;
      }
    }
    return _thermalLimitResult(input, requested, highestBelowTarget, ctx);
  }

  final ceiling = _evaluateThermalCandidate(
    searchInput,
    optimizeStatic,
    MAXIMUM_TARGET_PRESSURE_BAR,
    ctx,
  );
  if (ceiling.result['feasible'] == true) {
    final ceilingPressureDifference =
        ceiling.simulation!.finalSummary.finalAmbientPressureBar -
        requestedPressureBar;
    if (ceilingPressureDifference.abs() <= THERMAL_TARGET_TOLERANCE_BAR) {
      return _thermalResult(ceiling, ctx);
    }
    if (ceilingPressureDifference < 0) {
      return _thermalLimitResult(input, requested, ceiling, ctx);
    }
  }

  var lowerPressureBar = requestedPressureBar;
  var upperPressureBar = MAXIMUM_TARGET_PRESSURE_BAR;
  var highestFeasible = requested;
  for (var iteration = 0; iteration < 40; iteration++) {
    final candidatePressureBar = (lowerPressureBar + upperPressureBar) / 2;
    final candidate = _evaluateThermalCandidate(
      searchInput,
      optimizeStatic,
      candidatePressureBar,
      ctx,
    );
    if (candidate.result['feasible'] != true) {
      upperPressureBar = candidatePressureBar;
      continue;
    }

    final pressureDifference =
        candidate.simulation!.finalSummary.finalAmbientPressureBar -
        requestedPressureBar;
    if (pressureDifference.abs() <= THERMAL_TARGET_TOLERANCE_BAR) {
      return _thermalResult(candidate, ctx);
    }
    if (pressureDifference < 0) {
      lowerPressureBar = candidatePressureBar;
      highestFeasible = candidate;
    } else {
      upperPressureBar = candidatePressureBar;
    }
  }

  if (ceiling.result['feasible'] != true) {
    final maximum = _thermalizedMaximumResult(
      ceiling,
      requestedInWaterPressureBar,
      requestedInWaterTemperatureC,
      ambientSettledTargetPressureBar,
      ctx,
    );
    if (maximum['maximumPressure'] != null) {
      return <String, Object?>{
        ...maximum,
        'error':
            'Requested in-water pressure ${requestedInWaterPressureBar.toStringAsFixed(1)} bar cannot be reached. ${maximum['error']}',
      };
    }
  }
  return _thermalLimitResult(input, requested, highestFeasible, ctx);
}

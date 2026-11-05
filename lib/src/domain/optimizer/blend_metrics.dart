part of '../optimizer.dart';

// Port of js/optimizer.js 1479–1769: result builders, infeasibility reason
// inference, component shortfalls, blend diagnostics, blend summary, and
// blend input validation.

Map<String, Object?> _maximumPressureResult({
  required double pressureBar,
  required _LinearProgramResult solverResult,
  required Map<String, Object?>? blend,
  required List<ProtocolStep> protocolSteps,
  required List<Map<String, Object?>> trajectory,
}) {
  return <String, Object?>{
    'pressureBar': pressureBar,
    'solution': solverResult.solution,
    'tableauSteps': solverResult.steps,
    'blend': blend,
    'protocolSteps': protocolSteps,
    'trajectory': trajectory,
  };
}

/// JS `inferInfeasibilityReason`.
String? _inferInfeasibilityReason(
  String? error, [
  List<Map<String, Object?>> componentShortfalls = const [],
]) {
  final message = error ?? '';
  if (RegExp(
    r'4:1|oxygen (?:boost|compression) ratio',
    caseSensitive: false,
  ).hasMatch(message)) {
    return 'oxygen-boost-ratio';
  }
  if (RegExp(
    r'working pressure|cylinder pressure|1440-minute wait limit',
    caseSensitive: false,
  ).hasMatch(message)) {
    return 'working-pressure';
  }
  if (RegExp(
    r'booster output|compressor air cannot top up|compressor pressure|pressure limit',
    caseSensitive: false,
  ).hasMatch(message)) {
    return 'equipment-pressure-limit';
  }
  final hasShortfall = componentShortfalls.any((shortfall) {
    final deficit = _numberOrNull(shortfall['deficitMoles']);
    return deficit != null && deficit.isFinite && deficit > 1e-9;
  });
  if (hasShortfall ||
      RegExp(
        r'insufficient source|not enough|current cylinder and enabled gas banks|current gas banks',
        caseSensitive: false,
      ).hasMatch(message)) {
    return 'insufficient-source-gas';
  }
  return null;
}

const Object _inferReasonDefault = Object();

/// JS `failedResult`. [reasonCode] omitted → inferred from [error] and the
/// diagnostics' component shortfalls; an explicit `null` is kept as `null`.
Map<String, Object?> _failedResult(
  String? error,
  Map<String, Object?>? gas,
  List<Object?> tableauSteps, {
  Map<String, Object?>? maximumPressure,
  Map<String, Object?>? diagnostics,
  Object? reasonCode = _inferReasonDefault,
}) {
  final resolvedReason = identical(reasonCode, _inferReasonDefault)
      ? _inferInfeasibilityReason(
          error,
          _shortfallList(diagnostics?['componentShortfalls']),
        )
      : reasonCode;
  return <String, Object?>{
    'feasible': false,
    'error': error,
    'reasonCode': resolvedReason,
    'gas': gas,
    'solution': null,
    'tableauSteps': tableauSteps,
    'blend': null,
    'protocolSteps': <Object?>[],
    'trajectory': <Object?>[],
    'maximumPressure': maximumPressure,
    'diagnostics': diagnostics,
  };
}

List<Map<String, Object?>> _shortfallList(Object? value) {
  if (value is! List) {
    return const <Map<String, Object?>>[];
  }
  return <Map<String, Object?>>[
    for (final entry in value)
      if (entry is Map<String, Object?>) entry,
  ];
}

/// JS `componentShortfallsFor`.
List<Map<String, Object?>> _componentShortfallsFor({
  required double initialMoles,
  required double initialOxygenPercent,
  required double initialHeliumPercent,
  required double targetMoles,
  required double targetOxygenPercent,
  required double targetHeliumPercent,
  required List<Bank> activeBanks,
  required List<double> bankMaxMoles,
}) {
  final sourceFractions =
      <({double moles, double oxygen, double helium, double nitrogen})>[
        (
          moles: initialMoles,
          oxygen: initialOxygenPercent / 100,
          helium: initialHeliumPercent / 100,
          nitrogen:
              _jsMathMax(
                0.0,
                100 - initialOxygenPercent - initialHeliumPercent,
              ) /
              100,
        ),
        for (var index = 0; index < activeBanks.length; index++)
          (
            moles: bankMaxMoles[index],
            oxygen: activeBanks[index].oxygenPercent / 100,
            helium: activeBanks[index].heliumPercent / 100,
            nitrogen:
                _jsMathMax(
                  0.0,
                  100 -
                      activeBanks[index].oxygenPercent -
                      activeBanks[index].heliumPercent,
                ) /
                100,
          ),
      ];
  final targetFractions = <(String, double)>[
    ('Oxygen', targetOxygenPercent / 100),
    ('Helium', targetHeliumPercent / 100),
    (
      'Nitrogen',
      _jsMathMax(0.0, 100 - targetOxygenPercent - targetHeliumPercent) / 100,
    ),
  ];

  final shortfalls = <Map<String, Object?>>[];
  for (final (component, fraction) in targetFractions) {
    var availableMoles = 0.0;
    for (final source in sourceFractions) {
      final componentFractionValue = switch (component) {
        'Oxygen' => source.oxygen,
        'Helium' => source.helium,
        _ => source.nitrogen,
      };
      availableMoles += source.moles * componentFractionValue;
    }
    final requiredMoles = targetMoles * fraction;
    final deficitMoles = requiredMoles - availableMoles;
    if (deficitMoles <= _jsMathMax(1e-6, requiredMoles * 1e-6)) {
      continue;
    }
    shortfalls.add(<String, Object?>{
      'component': component,
      'requiredMoles': requiredMoles,
      'availableMoles': availableMoles,
      'deficitMoles': deficitMoles,
      'sourceBank': null,
    });
  }
  return shortfalls;
}

/// JS `componentFraction`.
double _componentFraction(String component, Bank bank) {
  if (component == 'Oxygen') {
    return bank.oxygenPercent / 100;
  }
  if (component == 'Helium') {
    return bank.heliumPercent / 100;
  }
  return _jsMathMax(0.0, 100 - bank.oxygenPercent - bank.heliumPercent) / 100;
}

/// JS `sourceBankPressureNeed`.
Map<String, Object?> _sourceBankPressureNeed({
  required Bank bank,
  required String component,
  required double deficitMoles,
  required double temperatureC,
  required bool useVdw,
  required double minimumSourcePressureBar,
}) {
  final requiredBankMoles = deficitMoles / _componentFraction(component, bank);
  final currentDensity = calcMolarDensity(
    bank.pressureBar,
    bank.oxygenPercent,
    bank.heliumPercent,
    temperatureC,
    useVdw,
  );
  final requiredDensity = currentDensity + requiredBankMoles / bank.volumeL;
  final requiredPressureOutOfRange =
      useVdw &&
      requiredDensity >=
          0.96 / getMixParams(bank.oxygenPercent, bank.heliumPercent).b;
  final requiredPressureBar = requiredPressureOutOfRange
      ? null
      : calcPressure(
          requiredDensity,
          bank.oxygenPercent,
          bank.heliumPercent,
          temperatureC,
          useVdw,
        );
  return <String, Object?>{
    'id': bank.id,
    'name': bank.name,
    'volumeL': bank.volumeL,
    'currentPressureBar': bank.pressureBar,
    'minimumSourcePressureBar': minimumSourcePressureBar,
    'pressureModel': useVdw ? 'real-gas' : 'ideal-gas',
    'pressureEstimateOutOfRange': requiredPressureOutOfRange,
    'requiredPressureBar': requiredPressureBar,
    'pressureIncreaseBar': requiredPressureOutOfRange
        ? null
        : _jsMathMax(0.0, requiredPressureBar! - bank.pressureBar),
  };
}

/// JS `createBlendDiagnostics`.
Map<String, Object?> _createBlendDiagnostics({
  required List<Map<String, Object?>> componentShortfalls,
  required _LinearProgramResult solverResult,
  required List<Bank> activeBanks,
  required List<double> bankMaxMoles,
  required double temperatureC,
  required bool useVdw,
  required double Function(Bank) minimumSourcePressureFor,
}) {
  final solution = solverResult.solution;
  final variableNames = solverResult.variableNames;
  final exhaustedBanks = <Map<String, Object?>>[];
  if (solution != null && variableNames.isNotEmpty) {
    for (var index = 0; index < activeBanks.length; index++) {
      final bank = activeBanks[index];
      if (bank.isCompressor ?? false) {
        continue;
      }
      final availableMoles = bankMaxMoles[index];
      if (availableMoles <= 1e-9) {
        continue;
      }
      final variableName = variableNames[index + 1];
      final drawnMoles = solution[variableName] ?? 0.0;
      if (drawnMoles <= 1e-9) {
        continue;
      }
      final exhaustionTolerance = math.min(1e-3, availableMoles * 1e-5);
      if (availableMoles - drawnMoles > exhaustionTolerance) {
        continue;
      }
      exhaustedBanks.add(<String, Object?>{
        'id': bank.id,
        'name': bank.name,
        'availableMoles': availableMoles,
        'drawnMoles': drawnMoles,
        'currentPressureBar': bank.pressureBar,
        'minimumSourcePressureBar': minimumSourcePressureFor(bank),
      });
    }
  }

  final diagnosedShortfalls = <Map<String, Object?>>[];
  for (final shortfall in componentShortfalls) {
    final component = shortfall['component'] as String;
    Bank? sourceBank;
    var greatestDrawnComponentMoles = 0.0;
    for (var index = 0; index < activeBanks.length; index++) {
      final bank = activeBanks[index];
      if (bank.isCompressor ?? false) {
        continue;
      }
      final fraction = _componentFraction(component, bank);
      if (fraction <= 1e-9 || bank.volumeL <= 0) {
        continue;
      }
      final variableName = index + 1 < variableNames.length
          ? variableNames[index + 1]
          : null;
      final drawnMoles =
          (variableName == null ? null : solution?[variableName]) ?? 0.0;
      final drawnComponentMoles = drawnMoles * fraction;
      if (drawnComponentMoles > greatestDrawnComponentMoles) {
        greatestDrawnComponentMoles = drawnComponentMoles;
        sourceBank = bank;
      }
    }

    if (sourceBank == null) {
      var greatestAvailableComponentMoles = 0.0;
      for (var index = 0; index < activeBanks.length; index++) {
        final bank = activeBanks[index];
        if (bank.isCompressor ?? false) {
          continue;
        }
        final fraction = _componentFraction(component, bank);
        if (fraction <= 1e-9 || bank.volumeL <= 0) {
          continue;
        }
        final availableComponentMoles = bankMaxMoles[index] * fraction;
        if (availableComponentMoles > greatestAvailableComponentMoles) {
          greatestAvailableComponentMoles = availableComponentMoles;
          sourceBank = bank;
        }
      }
    }

    diagnosedShortfalls.add(<String, Object?>{
      ...shortfall,
      'sourceBank': sourceBank == null
          ? null
          : _sourceBankPressureNeed(
              bank: sourceBank,
              component: component,
              deficitMoles: shortfall['deficitMoles'] as double,
              temperatureC: temperatureC,
              useVdw: useVdw,
              minimumSourcePressureBar: minimumSourcePressureFor(sourceBank),
            ),
    });
  }

  return <String, Object?>{
    'componentShortfalls': diagnosedShortfalls,
    'exhaustedBanks': exhaustedBanks,
  };
}

/// JS `blendSummary`.
Map<String, Object?> _blendSummary({
  required double retainedPressure,
  required double retainedMoles,
  required double initialMoles,
  required double drainPressure,
  required double ventedMoles,
  required double ventedGasLitres,
  required double heliumVentedLitres,
  required double heliumSalvagedLitres,
  required double heliumRetainedLitres,
  required double finalPressureBar,
  required double targetOxygenPercent,
  required double targetHeliumPercent,
}) {
  final denominator = (initialMoles == 0 || initialMoles.isNaN)
      ? 1.0
      : initialMoles;
  return <String, Object?>{
    'retainedPressureBar': retainedPressure,
    'retainedPercent': (retainedMoles / denominator) * 100,
    'ventedPressureBar': drainPressure,
    'ventedMoles': ventedMoles,
    'ventedGasLitres': ventedGasLitres,
    'heliumVentedLitres': heliumVentedLitres,
    'heliumSalvagedLitres': heliumSalvagedLitres,
    'heliumRetainedLitres': heliumRetainedLitres,
    'finalPressureBar': finalPressureBar,
    'finalOxygenPercent': targetOxygenPercent,
    'finalHeliumPercent': targetHeliumPercent,
  };
}

/// JS `validateBlendInput`. [input] is the JS-shaped blend input map; its
/// `cylinder`, `physics`, `thermal`, `settings`, and `banks` entries are read by
/// JS key. [internalThermalTarget] is the JS `INTERNAL_THERMAL_TARGET` flag
/// (see [_internalThermalTargetFlag]).
List<String> _validateBlendInput(
  Map<String, Object?>? input, {
  bool internalThermalTarget = false,
}) {
  if (input == null) {
    return <String>['Blend input is missing.'];
  }
  final cylinderRaw = input['cylinder'];
  if (cylinderRaw is! Map<String, Object?>) {
    return <String>['Cylinder input is missing.'];
  }
  final physicsRaw = input['physics'];
  final banksRaw = input['banks'];
  final settingsRaw = input['settings'];

  final targetPressureRaw = _numberOrNan(cylinderRaw['targetPressureBar']);
  final validationTargetPressure = internalThermalTarget
      ? _jsMathMin(350.0, _jsMathMax(10.0, targetPressureRaw))
      : null;

  final cylinderCalc = CalculatorCylinder(
    volumeL: _numberOrNull(cylinderRaw['volumeL']),
    initialPressureBar: _numberOrNull(cylinderRaw['initialPressureBar']),
    targetPressureBar:
        validationTargetPressure ??
        _numberOrNull(cylinderRaw['targetPressureBar']),
    workingPressureBar: _numberOrNull(cylinderRaw['workingPressureBar']),
    hotOverfillPercent: _numberOrNull(cylinderRaw['hotOverfillPercent']),
  );
  final physicsCalc = physicsRaw is Map<String, Object?>
      ? CalculatorPhysics(
          temperatureC: _numberOrNull(physicsRaw['temperatureC']),
        )
      : null;
  final thermalRaw = input['thermal'];
  final thermalCalc = thermalRaw is Map<String, Object?>
      ? CalculatorThermal(
          ambientTemperatureC: _numberOrNull(thermalRaw['ambientTemperatureC']),
          tankMaterial: _stringOrNull(thermalRaw['tankMaterial']),
          coolingMedium: _stringOrNull(thermalRaw['coolingMedium']),
          waterSubmersionPercent: _numberOrNull(
            thermalRaw['waterSubmersionPercent'],
          ),
          inletTemperatureC: _numberOrNull(thermalRaw['inletTemperatureC']),
          targetMediumTemperatureC: _numberOrNull(
            thermalRaw['targetMediumTemperatureC'],
          ),
          targetTemperatureC: _numberOrNull(thermalRaw['targetTemperatureC']),
          targetInWaterTemperatureC: _numberOrNull(
            thermalRaw['targetInWaterTemperatureC'],
          ),
          settledTemperatureC: _numberOrNull(thermalRaw['settledTemperatureC']),
          waitMode: _stringOrNull(thermalRaw['waitMode']),
          waitMinutes: _numberOrNull(thermalRaw['waitMinutes']),
          interimMeasurements: _parseInterimMeasurements(
            thermalRaw['interimMeasurements'],
          ),
        )
      : null;
  final settingsMode = settingsRaw is Map<String, Object?>
      ? _stringOrNull(settingsRaw['pressureLimitMode'])
      : null;

  final errors = validateCalculatorInputs(
    cylinderCalc,
    physicsCalc,
    thermalCalc,
    pressureLimitMode: settingsMode,
  );
  final interimRaw = thermalRaw is Map<String, Object?>
      ? thermalRaw['interimMeasurements']
      : null;
  if (interimRaw != null) {
    if (interimRaw is! List<Object?>) {
      errors.add('Measured interim readings must be an array.');
    } else {
      for (final entry in interimRaw) {
        if (entry != null && entry is! Map<String, Object?>) {
          errors.add(
            'Measured interim readings must contain pressure and temperature values.',
          );
        }
      }
    }
  }
  if (!isValidGasComposition(
    _numberOrNull(cylinderRaw['initialOxygenPercent']),
    _numberOrNull(cylinderRaw['initialHeliumPercent']),
  )) {
    errors.add('Initial gas composition must total at most 100% O₂ and He.');
  }
  if (!isValidGasComposition(
    _numberOrNull(cylinderRaw['targetOxygenPercent']),
    _numberOrNull(cylinderRaw['targetHeliumPercent']),
  )) {
    errors.add('Target gas composition must total at most 100% O₂ and He.');
  }
  final model = physicsRaw is Map<String, Object?> ? physicsRaw['model'] : null;
  if (model != 'ideal' && model != 'vdw') {
    errors.add('Gas model must be either ideal or vdw.');
  }
  if (banksRaw is! List<Object?>) {
    errors.add('Supply banks must be a list.');
  } else {
    final ids = <String>{};
    for (final bank in banksRaw) {
      errors.addAll(validateSupplyBankInput(bank));
      if (bank is Map<String, Object?>) {
        final id = bank['id'];
        if (id is String && id.isNotEmpty) {
          if (ids.contains(id)) {
            errors.add('Supply bank IDs must be unique.');
          }
          ids.add(id);
        }
      }
    }
  }
  return errors;
}

/// JS `input[INTERNAL_THERMAL_TARGET]` truthiness, read from the input map.
bool _internalThermalTargetFlag(Map<String, Object?> input) {
  final flag = input[INTERNAL_THERMAL_TARGET];
  return flag != null && flag != false;
}

/// The JS failed result for invalid blend input: `Invalid blend input: <errors>`.
Map<String, Object?> _invalidBlendInputResult(List<String> errors) {
  return _failedResult(
    'Invalid blend input: ${errors.join(' ')}',
    null,
    const [],
  );
}

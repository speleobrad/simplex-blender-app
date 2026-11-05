part of '../optimizer.dart';

// Port of js/optimizer.js 1291–1478: equipment (compressor and booster) safety,
// feasible oxygen-share ranges, and the maximum outside-oxygen search.

/// JS `equipmentSafety`: worst compressor and booster output margin.
({double margin, String? error}) _equipmentSafety({
  required _LinearProgramResult solverResult,
  required List<Bank> activeBanks,
  required Map<String, double> bankDensityByBankId,
  required double initialOxygenPercent,
  required double initialHeliumPercent,
  required double volumeL,
  required double temperatureC,
  required bool useVdw,
  required double targetPressureBar,
  required double maxCompressorPressureBar,
  required double maxBoosterOutputPressureBar,
}) {
  var cumulativeMoles = _jsOrZero(solverResult.solution?['x_cyl']);
  var cumulativeOxygenMoles = cumulativeMoles * (initialOxygenPercent / 100);
  var cumulativeHeliumMoles = cumulativeMoles * (initialHeliumPercent / 100);
  final airFirst = targetPressureBar > maxCompressorPressureBar;
  var worstMargin = double.infinity;
  String? worstError;

  for (final boost in _activeBoostsFor(
    solverResult,
    activeBanks,
    airFirst: airFirst,
  )) {
    final bank = boost.bank;
    final addedMoles = boost.addedMoles;
    final stages = _pressureTransferStages(
      cumulativeMoles: cumulativeMoles,
      cumulativeOxygenMoles: cumulativeOxygenMoles,
      cumulativeHeliumMoles: cumulativeHeliumMoles,
      addedMoles: addedMoles,
      bank: bank,
      bankDensityByBankId: bankDensityByBankId,
      volumeL: volumeL,
      temperatureC: temperatureC,
      useVdw: useVdw,
      airTopUp: _isAirBank(bank),
    );

    for (final stage in stages) {
      final stageAddedMoles =
          addedMoles * (stage.endFraction - stage.startFraction);
      final receiverEndPressureBar = stage.receiverEndPressureBar;
      if (_isAirBank(bank)) {
        final margin = maxCompressorPressureBar - receiverEndPressureBar;
        if (margin < worstMargin) {
          worstMargin = margin;
          worstError =
              'Compressor Air cannot top up above ${maxCompressorPressureBar.toStringAsFixed(1)} bar.';
        }
      } else if (stage.type == 'boost') {
        final margin = maxBoosterOutputPressureBar - receiverEndPressureBar;
        if (margin < worstMargin) {
          worstMargin = margin;
          worstError =
              'Booster output cannot exceed ${maxBoosterOutputPressureBar.toStringAsFixed(1)} bar.';
        }
      }
      cumulativeMoles += stageAddedMoles;
      cumulativeOxygenMoles += stageAddedMoles * (bank.oxygenPercent / 100);
      cumulativeHeliumMoles += stageAddedMoles * (bank.heliumPercent / 100);
    }
  }

  return (margin: worstMargin, error: worstMargin < -1e-9 ? worstError : null);
}

/// JS `feasibleOxygenShareRanges`: shares of total oxygen that meet the
/// required oxygen, as merged `[start, end]` ranges.
List<List<double>> _feasibleOxygenShareRanges(
  double totalOxygenMoles,
  double requiredPairOxygenMoles,
  double firstBankOxygenMoles,
  double secondBankOxygenMoles,
) {
  if (totalOxygenMoles <= 1e-9 || requiredPairOxygenMoles <= 1e-9) {
    return <List<double>>[
      <double>[0.0, 1.0],
    ];
  }

  double oxygenAvailableAtShare(double share) {
    return _jsMathMin(firstBankOxygenMoles, totalOxygenMoles * share) +
        _jsMathMin(secondBankOxygenMoles, totalOxygenMoles * (1 - share));
  }

  final rawBreakpoints = <double>[
    0.0,
    1.0,
    _jsMathMax(0.0, _jsMathMin(1.0, firstBankOxygenMoles / totalOxygenMoles)),
    _jsMathMax(
      0.0,
      _jsMathMin(1.0, 1 - secondBankOxygenMoles / totalOxygenMoles),
    ),
  ];
  final breakpoints = <double>[];
  for (final value in rawBreakpoints) {
    final alreadyPresent = breakpoints.any(
      (existing) => existing == value || (existing.isNaN && value.isNaN),
    );
    if (!alreadyPresent) {
      breakpoints.add(value);
    }
  }
  breakpoints.sort();

  final ranges = <List<double>>[];
  for (var index = 0; index < breakpoints.length - 1; index++) {
    final start = breakpoints[index];
    final end = breakpoints[index + 1];
    final startOxygen = oxygenAvailableAtShare(start);
    final endOxygen = oxygenAvailableAtShare(end);
    final startFeasible = startOxygen + 1e-9 >= requiredPairOxygenMoles;
    final endFeasible = endOxygen + 1e-9 >= requiredPairOxygenMoles;

    if (startFeasible && endFeasible) {
      ranges.add(<double>[start, end]);
    } else if (startFeasible || endFeasible) {
      final boundary =
          start +
          ((requiredPairOxygenMoles - startOxygen) /
                  (endOxygen - startOxygen)) *
              (end - start);
      ranges.add(
        startFeasible ? <double>[start, boundary] : <double>[boundary, end],
      );
    }
  }

  final merged = <List<double>>[];
  for (final range in ranges) {
    final previous = merged.isEmpty ? null : merged.last;
    if (previous != null && range[0] <= previous[1] + 1e-9) {
      previous[1] = _jsMathMax(previous[1], range[1]);
    } else {
      merged.add(range);
    }
  }
  return merged;
}

class _OutsideSource {
  const _OutsideSource({
    required this.variableName,
    required this.maximumMoles,
    required this.oxygenFraction,
    required this.heliumFraction,
    required this.nitrogenFraction,
  });

  final String variableName;
  final double maximumMoles;
  final double oxygenFraction;
  final double heliumFraction;
  final double nitrogenFraction;
}

/// JS `maximumOutsideOxygenMoles`: largest oxygen delivery from banks outside
/// [excludedBankIds] that still meets the target mix (LP).
double _maximumOutsideOxygenMoles({
  required double initialMoles,
  required double initialOxygenPercent,
  required double initialHeliumPercent,
  required double targetMoles,
  required double targetOxygenPercent,
  required double targetHeliumPercent,
  required List<Bank> activeBanks,
  required List<double> bankMaxMoles,
  required Set<String> excludedBankIds,
}) {
  final outsideBanks = activeBanks
      .where((bank) => !excludedBankIds.contains(bank.id))
      .toList();
  final bankNames = _bankVariableNames(outsideBanks);
  final sources = <_OutsideSource>[
    _OutsideSource(
      variableName: 'x_cyl',
      maximumMoles: initialMoles,
      oxygenFraction: initialOxygenPercent / 100,
      heliumFraction: initialHeliumPercent / 100,
      nitrogenFraction:
          _jsMathMax(0.0, 100 - initialOxygenPercent - initialHeliumPercent) /
          100,
    ),
    for (var index = 0; index < outsideBanks.length; index++)
      _OutsideSource(
        variableName: bankNames[index],
        maximumMoles: bankMaxMoles[activeBanks.indexOf(outsideBanks[index])],
        oxygenFraction: outsideBanks[index].oxygenPercent / 100,
        heliumFraction: outsideBanks[index].heliumPercent / 100,
        nitrogenFraction:
            _jsMathMax(
              0.0,
              100 -
                  outsideBanks[index].oxygenPercent -
                  outsideBanks[index].heliumPercent,
            ) /
            100,
      ),
  ];
  final decisionVariableNames = <String>[
    for (final source in sources) source.variableName,
    's_he_budget',
    's_n2_budget',
    's_total_budget',
  ];
  final decisionCount = decisionVariableNames.length;
  final constraints = <_LpConstraint>[
    _LpConstraint(
      coefficients: <double>[
        for (final source in sources) source.heliumFraction,
        1,
        0,
        0,
      ],
      rhs: targetMoles * (targetHeliumPercent / 100),
    ),
    _LpConstraint(
      coefficients: <double>[
        for (final source in sources) source.nitrogenFraction,
        0,
        1,
        0,
      ],
      rhs:
          targetMoles *
          (_jsMathMax(0.0, 100 - targetOxygenPercent - targetHeliumPercent) /
              100),
    ),
    _LpConstraint(
      coefficients: <double>[for (final _ in sources) 1, 0, 0, 1],
      rhs: targetMoles,
    ),
    for (var index = 0; index < sources.length; index++)
      _LpConstraint(
        coefficients: <double>[
          for (var column = 0; column < decisionCount; column++)
            column == index ? 1.0 : 0.0,
        ],
        rhs: sources[index].maximumMoles,
      ),
  ];
  final decisionCosts = <double>[
    for (final source in sources) -source.oxygenFraction,
    0,
    0,
    0,
  ];
  final result = _solveLinearProgram(
    decisionVariableNames,
    <String>[
      's_cyl',
      for (var index = 0; index < outsideBanks.length; index++)
        's_b${index + 1}',
    ],
    constraints,
    decisionCosts,
  );
  if (!result.feasible) {
    return 0.0;
  }

  var oxygenMoles = 0.0;
  for (final source in sources) {
    oxygenMoles +=
        source.oxygenFraction *
        (result.solution?[source.variableName] ?? double.nan);
  }
  return oxygenMoles;
}

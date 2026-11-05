part of '../optimizer.dart';

// Port of js/optimizer.js 802–1005 (plus the cascade helpers at 1030–1050 that
// these solvers read).

// ignore: constant_identifier_names
const String INTERNAL_THERMAL_TARGET = '__internalThermalTarget';

// ignore: constant_identifier_names
const double _NORMAL_RETAINED_GAS_COST = -5;
// ignore: constant_identifier_names
const double _SAFETY_SOURCE_COST_RANGE = 10101;

/// Result of [_solveLinearProgram]: the JS `solverResult` spread with
/// `variableNames`.
class _LinearProgramResult {
  const _LinearProgramResult({
    required this.feasible,
    required this.variableNames,
    this.error,
    this.solution,
    this.steps,
    this.cost,
  });

  final bool feasible;
  final List<String> variableNames;
  final String? error;
  final Map<String, double>? solution;
  final List<SimplexStep>? steps;
  final double? cost;
}

/// One LP row: `coefficients · x` against `rhs`.
class _LpConstraint {
  const _LpConstraint({required this.coefficients, required this.rhs});

  final List<double> coefficients;
  final double rhs;
}

double _retainedGasCost(double targetMoles, bool prioritizeTransferSafety) {
  if (!prioritizeTransferSafety) {
    return _NORMAL_RETAINED_GAS_COST;
  }
  // The total-moles equality bounds every source allocation by targetMoles.
  // This makes safety source-selection costs strictly secondary to retaining gas.
  return -(targetMoles * _SAFETY_SOURCE_COST_RANGE + 1);
}

List<String> _bankVariableNames(List<Bank> activeBanks) {
  return [
    for (var index = 0; index < activeBanks.length; index++)
      'x_b${index + 1}_${activeBanks[index].name.split(' ').first}',
  ];
}

/// JS `isAirBank`: `bank?.isCompressor === true`.
bool _isAirBank(Bank? bank) {
  return bank?.isCompressor == true;
}

/// JS `cascadeCompositionKey`.
String _cascadeCompositionKey(Bank bank) {
  return '${jsNumberString(bank.oxygenPercent)}/'
      '${jsNumberString(bank.heliumPercent)}';
}

/// JS `cascadeGroups`: counts of non-air banks per composition key.
Map<String, int> _cascadeGroups(List<Bank> activeBanks) {
  final counts = <String, int>{};
  for (final bank in activeBanks) {
    if (!_isAirBank(bank)) {
      final key = _cascadeCompositionKey(bank);
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  return counts;
}

_LinearProgramResult _solveLinearProgram(
  List<String> decisionVariableNames,
  List<String> slackVariableNames,
  List<_LpConstraint> constraints,
  List<double> decisionCosts,
) {
  final numDecisionVars = decisionVariableNames.length;
  final numConstraints = constraints.length;
  final numSlackVars = numConstraints;
  final totalVars = numDecisionVars + numSlackVars + 3;
  final rhsColumn = totalVars;
  final artificialColumnOffset = numDecisionVars + numSlackVars;
  final variableNames = <String>[
    ...decisionVariableNames,
    's_eq1',
    's_eq2',
    's_eq3',
    ...slackVariableNames,
    'a_tot',
    'a_o2',
    'a_he',
  ];
  final tableau = List<List<double>>.generate(
    numConstraints + 2,
    (_) => List<double>.filled(totalVars + 1, 0),
  );

  for (var i = 0; i < numConstraints; i++) {
    final constraint = constraints[i];
    for (var j = 0; j < numDecisionVars; j++) {
      tableau[i][j] = j < constraint.coefficients.length
          ? constraint.coefficients[j]
          : 0;
    }
    tableau[i][rhsColumn] = constraint.rhs;
    if (i < 3) {
      tableau[i][artificialColumnOffset + i] = 1;
    } else {
      tableau[i][numDecisionVars + i] = 1;
    }
  }

  final costVector = List<double>.filled(totalVars, 0);
  for (var index = 0; index < decisionCosts.length; index++) {
    costVector[index] = decisionCosts[index];
  }
  final phase1ObjectiveRow = numConstraints;
  for (var i = 0; i < 3; i++) {
    for (var j = 0; j <= rhsColumn; j++) {
      tableau[phase1ObjectiveRow][j] -= tableau[i][j];
    }
  }
  for (var i = 0; i < 3; i++) {
    tableau[phase1ObjectiveRow][artificialColumnOffset + i] = 0;
  }

  final solverResult = solveTwoPhaseSimplex(
    tableau,
    numDecisionVars,
    numConstraints,
    variableNames,
    costVector,
  );
  if (solverResult.feasible) {
    final solution = solverResult.solution!;
    for (var i = 0; i < numConstraints; i++) {
      final constraint = constraints[i];
      final rhs = constraint.rhs;
      var lhs = 0.0;
      var scale = rhs.abs();
      for (var j = 0; j < numDecisionVars; j++) {
        final coefficient = j < constraint.coefficients.length
            ? constraint.coefficients[j]
            : 0.0;
        final term = coefficient * (solution[decisionVariableNames[j]] ?? 0);
        lhs += term;
        scale += term.abs();
      }
      final tolerance = math.max(1e-12, scale * 1e-9);
      final violation = i < 3 ? (lhs - rhs).abs() : lhs - rhs;
      if (!lhs.isFinite || !scale.isFinite || violation > tolerance) {
        return _LinearProgramResult(
          feasible: false,
          error:
              'Solver returned a solution outside the original LP constraints.',
          steps: solverResult.steps,
          variableNames: variableNames,
        );
      }
    }
  }

  return _LinearProgramResult(
    feasible: solverResult.feasible,
    error: solverResult.error,
    solution: solverResult.solution,
    steps: solverResult.steps,
    cost: solverResult.cost,
    variableNames: variableNames,
  );
}

_LinearProgramResult _solveTargetBlendAtMoles({
  required double initialMoles,
  required double targetMoles,
  required double initialOxygenPercent,
  required double initialHeliumPercent,
  required double targetOxygenPercent,
  required double targetHeliumPercent,
  required List<Bank> activeBanks,
  required List<double> bankMaxMoles,
  bool prioritizeTransferSafety = false,
  String? preferredBankId,
  String? excludedBankId,
}) {
  final bankNames = _bankVariableNames(activeBanks);
  final decisionVariableNames = <String>['x_cyl', ...bankNames];
  final sourceCount = decisionVariableNames.length;
  final constraints = <_LpConstraint>[
    _LpConstraint(
      coefficients: [1, ...activeBanks.map((_) => 1.0)],
      rhs: targetMoles,
    ),
    _LpConstraint(
      coefficients: [
        initialOxygenPercent / 100,
        ...activeBanks.map((bank) => bank.oxygenPercent / 100),
      ],
      rhs: (targetOxygenPercent / 100) * targetMoles,
    ),
    _LpConstraint(
      coefficients: [
        initialHeliumPercent / 100,
        ...activeBanks.map((bank) => bank.heliumPercent / 100),
      ],
      rhs: (targetHeliumPercent / 100) * targetMoles,
    ),
    _LpConstraint(
      coefficients: [1, ...activeBanks.map((_) => 0.0)],
      rhs: initialMoles,
    ),
    for (var index = 0; index < activeBanks.length; index++)
      () {
        final coefficients = List<double>.filled(sourceCount, 0);
        coefficients[index + 1] = 1;
        return _LpConstraint(
          coefficients: coefficients,
          rhs: activeBanks[index].id == excludedBankId
              ? 0
              : bankMaxMoles[index],
        );
      }(),
  ];
  final compositionCounts = _cascadeGroups(activeBanks);
  final decisionCosts = <double>[
    _retainedGasCost(targetMoles, prioritizeTransferSafety),
    for (final bank in activeBanks)
      () {
        final oxygenFraction = bank.oxygenPercent / 100;
        final heliumFraction = bank.heliumPercent / 100;
        if (prioritizeTransferSafety) {
          if (bank.oxygenPercent <= 25) {
            return heliumFraction * heliumFraction * 100 +
                oxygenFraction * 0.4 +
                1;
          }
          if (bank.id == preferredBankId) {
            return -10000.0;
          }
          return -bank.pressureBar + 1 / bank.volumeL;
        }
        final baseCost =
            heliumFraction * heliumFraction * 100 + oxygenFraction * 0.4 + 1;
        final isCascadeBank =
            !_isAirBank(bank) &&
            (compositionCounts[_cascadeCompositionKey(bank)] ?? 0) > 1;
        return baseCost + (isCascadeBank ? bank.pressureBar * 1e-6 : 0.0);
      }(),
  ];

  return _solveLinearProgram(
    decisionVariableNames,
    [
      's_cyl',
      for (var index = 0; index < activeBanks.length; index++)
        's_b${index + 1}',
    ],
    constraints,
    decisionCosts,
  );
}

_LinearProgramResult _solveMaximumTargetMix({
  required double initialMoles,
  required double initialOxygenPercent,
  required double initialHeliumPercent,
  required double targetOxygenPercent,
  required double targetHeliumPercent,
  required List<Bank> activeBanks,
  required List<double> bankMaxMoles,
}) {
  final bankNames = _bankVariableNames(activeBanks);
  final sourceCount = bankNames.length + 1;
  final decisionVariableNames = <String>['x_cyl', ...bankNames, 'n_total'];
  final totalMolesIndex = decisionVariableNames.length - 1;
  final constraints = <_LpConstraint>[
    _LpConstraint(
      coefficients: [...List<double>.filled(sourceCount, 1), -1],
      rhs: 0,
    ),
    _LpConstraint(
      coefficients: [
        (initialOxygenPercent - targetOxygenPercent) / 100,
        ...activeBanks.map(
          (bank) => (bank.oxygenPercent - targetOxygenPercent) / 100,
        ),
        0,
      ],
      rhs: 0,
    ),
    _LpConstraint(
      coefficients: [
        (initialHeliumPercent - targetHeliumPercent) / 100,
        ...activeBanks.map(
          (bank) => (bank.heliumPercent - targetHeliumPercent) / 100,
        ),
        0,
      ],
      rhs: 0,
    ),
    _LpConstraint(
      coefficients: [1, ...List<double>.filled(sourceCount - 1, 0), 0],
      rhs: initialMoles,
    ),
    for (var index = 0; index < activeBanks.length; index++)
      () {
        final coefficients = List<double>.filled(
          decisionVariableNames.length,
          0,
        );
        coefficients[index + 1] = 1;
        return _LpConstraint(
          coefficients: coefficients,
          rhs: bankMaxMoles[index],
        );
      }(),
  ];
  final decisionCosts = List<double>.filled(decisionVariableNames.length, 0);
  decisionCosts[totalMolesIndex] = -1;

  return _solveLinearProgram(
    decisionVariableNames,
    [
      's_cyl',
      for (var index = 0; index < activeBanks.length; index++)
        's_b${index + 1}',
    ],
    constraints,
    decisionCosts,
  );
}

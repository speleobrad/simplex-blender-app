// Two-phase simplex solver port of `js/simplex.js`.

/// One recorded tableau state of [solveTwoPhaseSimplex] (JS `snapshot`).
class SimplexStep {
  const SimplexStep({
    required this.phase,
    required this.note,
    required this.pivotRow,
    required this.pivotCol,
    required this.tableau,
    required this.varNames,
  });

  final int phase;
  final String note;
  final int pivotRow;
  final int pivotCol;
  final List<List<double>> tableau;
  final List<String> varNames;
}

/// Result of [solveTwoPhaseSimplex]. Infeasible results carry [error] and,
/// except for the unbounded phase-one exit, [steps]. Feasible results carry
/// [solution] and [cost].
class SimplexResult {
  const SimplexResult.feasible({
    required this.solution,
    required this.steps,
    required this.cost,
  }) : feasible = true,
       error = null;

  const SimplexResult.infeasible({required this.error, this.steps})
    : feasible = false,
      solution = null,
      cost = null;

  final bool feasible;
  final String? error;
  final Map<String, double>? solution;
  final List<SimplexStep>? steps;
  final double? cost;
}

const String _infeasibleTargetError =
    'Target mix cannot be achieved with currently enabled gas banks and constraints. Enable pure Helium, Oxygen, or Air.';

/// JS `Math.max` semantics: NaN propagates from either operand.
double _jsMax(double a, double b) {
  if (a.isNaN || b.isNaN) return double.nan;
  return a >= b ? a : b;
}

/// JS `varNames[i]` rendered inside a template literal.
String _nameForTemplate(List<String> varNames, int index) {
  if (index >= 0 && index < varNames.length) return varNames[index];
  return 'undefined';
}

/// Two-phase simplex solver with explicit basis tracking and tableau snapshots.
///
/// Line-faithful port of `js/simplex.js`. As in the JS original, [tableau] is
/// pivoted in place and [costVector] is indexed by decision variable.
SimplexResult solveTwoPhaseSimplex(
  List<List<double>> tableau,
  int numDecisionVars,
  int numConstraints,
  List<String> varNames,
  List<double> costVector,
) {
  final steps = <SimplexStep>[];
  final totalCols = tableau[0].length;
  final rhsCol = totalCols - 1;
  var phase1Scale = 0.0;
  for (var i = 0; i < numConstraints; i++) {
    phase1Scale = _jsMax(phase1Scale, tableau[i][rhsCol].abs());
  }
  final phase1FeasibilityTolerance = _jsMax(1e-12, phase1Scale * 1e-9);
  final numSlackVars = numConstraints;
  final numPhysicalVars = numDecisionVars + numSlackVars;

  final basis = List<int>.filled(numConstraints, 0);
  basis[0] = numPhysicalVars;
  basis[1] = numPhysicalVars + 1;
  basis[2] = numPhysicalVars + 2;
  for (var i = 3; i < numConstraints; i++) {
    basis[i] = numDecisionVars + i;
  }

  void snapshot(
    int phase,
    String note, [
    int pivotRow = -1,
    int pivotCol = -1,
  ]) {
    steps.add(
      SimplexStep(
        phase: phase,
        note: note,
        pivotRow: pivotRow,
        pivotCol: pivotCol,
        tableau: [for (final row in tableau) List<double>.of(row)],
        varNames: List<String>.of(varNames),
      ),
    );
  }

  void pivot(int row, int column) {
    final pivotValue = tableau[row][column];
    if (pivotValue.abs() < 1e-12) return;

    basis[row] = column;
    for (var j = 0; j < totalCols; j++) {
      tableau[row][j] /= pivotValue;
    }

    for (var i = 0; i < tableau.length; i++) {
      if (i == row) continue;
      final factor = tableau[i][column];
      if (factor.abs() <= 1e-12) continue;
      for (var j = 0; j < totalCols; j++) {
        tableau[i][j] -= factor * tableau[row][j];
      }
    }
  }

  final phase1ObjectiveRow = numConstraints;
  snapshot(1, 'Initial Phase 1 Tableau (Eliminating artificial variables)');

  var phase1Iterations = 80;
  while (phase1Iterations-- > 0) {
    var enteringColumn = -1;
    var minimumValue = -1e-6;
    for (var j = 0; j < numPhysicalVars; j++) {
      if (tableau[phase1ObjectiveRow][j] < minimumValue) {
        minimumValue = tableau[phase1ObjectiveRow][j];
        enteringColumn = j;
      }
    }
    if (enteringColumn == -1) break;

    var leavingRow = -1;
    var minimumRatio = double.infinity;
    for (var i = 0; i < numConstraints; i++) {
      final coefficient = tableau[i][enteringColumn];
      if (coefficient <= 1e-8) continue;
      final ratio = tableau[i][rhsCol] / coefficient;
      if (ratio < minimumRatio) {
        minimumRatio = ratio;
        leavingRow = i;
      }
    }

    if (leavingRow == -1) {
      return const SimplexResult.infeasible(error: 'Phase 1 unbounded');
    }

    final basisName = leavingRow < basis.length
        ? _nonEmptyOrSlack(varNames, basis[leavingRow])
        : 'slack';
    snapshot(
      1,
      'Phase 1 Pivot: Enter ${_nameForTemplate(varNames, enteringColumn)}, '
      'Leave Row ${leavingRow + 1} ($basisName)',
      leavingRow,
      enteringColumn,
    );
    pivot(leavingRow, enteringColumn);
  }

  var artificialSum = 0.0;
  for (var i = 0; i < 3; i++) {
    if (basis[i] < numPhysicalVars) continue;
    final residual = tableau[i][rhsCol];
    if (!residual.isFinite) {
      return SimplexResult.infeasible(
        error: _infeasibleTargetError,
        steps: steps,
      );
    }
    artificialSum += residual.abs();
  }
  if (!tableau[phase1ObjectiveRow][rhsCol].isFinite ||
      artificialSum > phase1FeasibilityTolerance ||
      tableau[phase1ObjectiveRow][rhsCol].abs() > phase1FeasibilityTolerance) {
    return SimplexResult.infeasible(
      error: _infeasibleTargetError,
      steps: steps,
    );
  }

  for (var i = 0; i < 3; i++) {
    if (basis[i] < numPhysicalVars) continue;
    tableau[i][rhsCol] = 0;
    var enteringColumn = -1;
    for (var j = 0; j < numPhysicalVars; j++) {
      if (basis.contains(j) || tableau[i][j].abs() < 1e-12) continue;
      enteringColumn = j;
      break;
    }
    if (enteringColumn == -1) continue;
    snapshot(
      1,
      'Phase 1 Pivot: Remove artificial basis '
      '${_nameForTemplate(varNames, basis[i])}, '
      'Enter ${_nameForTemplate(varNames, enteringColumn)}',
      i,
      enteringColumn,
    );
    pivot(i, enteringColumn);
  }

  final phase2ObjectiveRow = numConstraints + 1;
  for (var j = 0; j < totalCols; j++) {
    if (j == rhsCol) {
      var currentCost = 0.0;
      for (var i = 0; i < numConstraints; i++) {
        final basicVariable = basis[i];
        if (basicVariable < numDecisionVars) {
          currentCost += costVector[basicVariable] * tableau[i][rhsCol];
        }
      }
      tableau[phase2ObjectiveRow][rhsCol] = -currentCost;
    } else if (j < numPhysicalVars) {
      var basicCost = 0.0;
      for (var i = 0; i < numConstraints; i++) {
        final basicVariable = basis[i];
        if (basicVariable < numDecisionVars) {
          basicCost += costVector[basicVariable] * tableau[i][j];
        }
      }
      final variableCost = j < numDecisionVars ? costVector[j] : 0.0;
      tableau[phase2ObjectiveRow][j] = variableCost - basicCost;
    } else {
      tableau[phase2ObjectiveRow][j] = 0;
    }
  }

  snapshot(
    2,
    'Entering Phase 2: Optimizing Helium conservation & gas retention',
  );

  var phase2Iterations = 80;
  while (phase2Iterations-- > 0) {
    var enteringColumn = -1;
    var minimumValue = -1e-6;
    for (var j = 0; j < numPhysicalVars; j++) {
      if (tableau[phase2ObjectiveRow][j] < minimumValue) {
        minimumValue = tableau[phase2ObjectiveRow][j];
        enteringColumn = j;
      }
    }
    if (enteringColumn == -1) break;

    var leavingRow = -1;
    var minimumRatio = double.infinity;
    for (var i = 0; i < numConstraints; i++) {
      final coefficient = tableau[i][enteringColumn];
      if (coefficient <= 1e-8) continue;
      final ratio = tableau[i][rhsCol] / coefficient;
      if (ratio < minimumRatio) {
        minimumRatio = ratio;
        leavingRow = i;
      }
    }

    if (leavingRow == -1) {
      return SimplexResult.infeasible(error: 'Phase 2 unbounded', steps: steps);
    }

    snapshot(
      2,
      'Phase 2 Pivot: Enter ${_nameForTemplate(varNames, enteringColumn)}, '
      'Leave Row ${leavingRow + 1}',
      leavingRow,
      enteringColumn,
    );
    pivot(leavingRow, enteringColumn);
  }

  snapshot(2, 'Blend solution found');

  final solution = <String, double>{
    for (final name in varNames.take(numDecisionVars)) name: 0,
  };
  for (var i = 0; i < numConstraints; i++) {
    final basicVariable = basis[i];
    if (basicVariable < numDecisionVars) {
      solution[_nameForTemplate(varNames, basicVariable)] = _jsMax(
        0,
        tableau[i][rhsCol],
      );
    }
  }

  return SimplexResult.feasible(
    solution: solution,
    steps: steps,
    cost: -tableau[phase2ObjectiveRow][rhsCol],
  );
}

/// JS `varNames[index] || 'slack'`.
String _nonEmptyOrSlack(List<String> varNames, int index) {
  if (index < 0 || index >= varNames.length) return 'slack';
  final name = varNames[index];
  return name.isEmpty ? 'slack' : name;
}

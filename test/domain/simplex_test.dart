import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/simplex.dart';

void main() {
  test('phase-one pivot notes identify the capacity row slack basis', () {
    const decisionVariableCount = 1;
    const constraintCount = 4;
    const variableNames = [
      'x',
      's_eq1',
      's_eq2',
      's_eq3',
      's_cyl',
      'a_tot',
      'a_o2',
      'a_he',
    ];
    final tableau = List.generate(
      constraintCount + 2,
      (_) => List<double>.filled(9, 0),
    );

    tableau[0][0] = 1;
    tableau[0][5] = 1;
    tableau[0][8] = 10;
    tableau[1][6] = 1;
    tableau[2][7] = 1;
    tableau[3][0] = 1;
    tableau[3][4] = 1;
    tableau[3][8] = 1;
    tableau[constraintCount][0] = -1;

    final result = solveTwoPhaseSimplex(
      tableau,
      decisionVariableCount,
      constraintCount,
      variableNames,
      [0],
    );
    final capacityPivot = result.steps!.firstWhere(
      (step) => step.note.startsWith('Phase 1 Pivot:'),
    );
    expect(capacityPivot.note, 'Phase 1 Pivot: Enter x, Leave Row 4 (s_cyl)');
  });

  test('reported cost equals the objective value at the returned solution after phase-two pivots', () {
    const decisionVariableCount = 2;
    const constraintCount = 3;
    const physicalCount = decisionVariableCount + constraintCount;
    const columnCount = physicalCount + 3 + 1;
    final tableau = List.generate(
      constraintCount + 2,
      (_) => List<double>.filled(columnCount, 0),
    );

    tableau[0][0] = 1;
    tableau[0][1] = 1;
    tableau[0][columnCount - 1] = 2;
    tableau[0][physicalCount] = 1;
    tableau[1][physicalCount + 1] = 1;
    tableau[2][physicalCount + 2] = 1;
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < columnCount; j++) {
        tableau[constraintCount][j] -= tableau[i][j];
      }
    }
    for (var i = 0; i < 3; i++) {
      tableau[constraintCount][physicalCount + i] = 0;
    }

    final costVector = List<double>.filled(physicalCount, 0);
    costVector[0] = 5;
    costVector[1] = 3;
    final result = solveTwoPhaseSimplex(
      tableau,
      decisionVariableCount,
      constraintCount,
      ['x1', 'x2', 's1', 's2', 's3'],
      costVector,
    );

    expect(result.feasible, isTrue);
    expect(result.solution, {'x1': 0.0, 'x2': 2.0});
    expect(
      result.cost,
      closeTo(5 * result.solution!['x1']! + 3 * result.solution!['x2']!, 0),
    );
  });
}

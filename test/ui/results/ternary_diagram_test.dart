import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/ternary_geometry.dart';
import 'package:simplex_blender/src/ui/results/ternary_diagram.dart';

// Source of truth: js/ui/ternary.js readout and empty-state strings
// (lines 184, 626-633) and js/main.js `setTab` (1912-1923).

const List<TernaryBank> _banks = <TernaryBank>[
  TernaryBank(
    id: 'a',
    name: 'Bank A',
    enabled: true,
    oxygenPercent: 32,
    heliumPercent: 0,
    pressureBar: 200,
  ),
];

const List<TernaryTrajectoryPoint> _trajectory = <TernaryTrajectoryPoint>[
  TernaryTrajectoryPoint(
    label: 'Init',
    oxygenPercent: 21,
    heliumPercent: 0,
    nitrogenPercent: 79,
    step: 0,
    pressureBar: 50,
  ),
  TernaryTrajectoryPoint(
    label: 'Goal',
    oxygenPercent: 18,
    heliumPercent: 45,
    nitrogenPercent: 37,
    step: 1,
    pressureBar: 195,
  ),
];

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: SizedBox(width: 400, child: child)),
    ),
  );
}

void main() {
  testWidgets('shows the hover prompt by default', (tester) async {
    await tester.pumpWidget(
      _host(const TernaryDiagram(banks: _banks, trajectory: _trajectory)),
    );

    expect(find.text('Hover for gas fractions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no feasible blend shows the JS no-feasible readout', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const TernaryDiagram(
          banks: _banks,
          trajectory: <TernaryTrajectoryPoint>[],
          noFeasible: true,
        ),
      ),
    );

    expect(find.text('No feasible blend'), findsWidgets);
    expect(
      find.bySemanticsLabel(
        'Gas composition ternary diagram. No feasible blend.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tab activation resets the readout to the tab prompt', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const TernaryDiagram(
          banks: _banks,
          trajectory: _trajectory,
          activationCount: 0,
        ),
      ),
    );
    await tester.pumpWidget(
      _host(
        const TernaryDiagram(
          banks: _banks,
          trajectory: _trajectory,
          activationCount: 1,
        ),
      ),
    );

    expect(find.text('Move over diagram for gas fractions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

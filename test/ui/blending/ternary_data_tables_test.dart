import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/ternary_geometry.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/ui/blending/ternary_data.dart';
import 'package:simplex_blender/src/ui/blending/ternary_data_tables.dart';

// Source of truth: index.html 668-693 (status line and the two captioned
// tables) and js/ui/ternary.js 369-413 (cell content: O₂/He via the gas-mix
// formatter, pressure as one decimal with " bar", or a dash when missing).

const _mixA = GasMixPercent(oxygenPercent: 21, heliumPercent: 0);
const _mixB = GasMixPercent(oxygenPercent: 18, heliumPercent: 45);

TernaryTrajectoryPoint _point(String label, GasMixPercent mix) {
  return TernaryTrajectoryPoint(
    label: label,
    oxygenPercent: mix.oxygenPercent,
    heliumPercent: mix.heliumPercent,
    nitrogenPercent: 100 - mix.oxygenPercent - mix.heliumPercent,
  );
}

Future<void> _pump(WidgetTester tester, BlendingTernaryTables tables) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: TernaryDataTables(tables: tables)),
      ),
    ),
  );
}

void main() {
  testWidgets('shows captions, headers, and the status line without data', (
    tester,
  ) async {
    await _pump(
      tester,
      const BlendingTernaryTables(status: noFeasibleBlendDataText, data: null),
    );

    expect(find.text(noFeasibleBlendDataText), findsOneWidget);
    expect(find.text('Reference mixes in Tanks and costs'), findsOneWidget);
    expect(find.text('Blend trajectory'), findsOneWidget);
    for (final header in <String>[
      'Mix',
      'O₂/He',
      'Start pressure',
      'End pressure',
      'Stage',
      'Pressure',
    ]) {
      expect(find.text(header), findsWidgets);
    }
  });

  testWidgets('formats mix rows and trajectory rows with bar and dash cells', (
    tester,
  ) async {
    final tables = BlendingTernaryTables(
      status: 'Data covers 1 enabled supply bank and 2 trajectory points.',
      data: TernaryAccessibleData(
        mixRows: <TernaryMixRow>[
          TernaryMixRow(
            label: 'Start',
            mix: _mixA,
            startPressureBar: 50,
            endPressureBar: null,
          ),
        ],
        trajectoryRows: <TernaryTrajectoryRow>[
          TernaryTrajectoryRow(
            label: 'Stage 1',
            mix: _point('Stage 1', _mixB),
            pressureBar: 120.25,
          ),
          TernaryTrajectoryRow(
            label: 'Stage 2',
            mix: _point('Stage 2', _mixA),
            pressureBar: null,
          ),
        ],
        status: 'Data covers 1 enabled supply bank and 2 trajectory points.',
      ),
    );
    await _pump(tester, tables);

    expect(
      find.text('Data covers 1 enabled supply bank and 2 trajectory points.'),
      findsOneWidget,
    );
    expect(find.text('Start'), findsOneWidget);
    expect(find.text(formatGasMix(21, 0)), findsWidgets);
    expect(find.text(formatGasMix(18, 45)), findsOneWidget);
    expect(find.text('50.0 bar'), findsOneWidget);
    // JS toFixed rounds an exact binary tie (120.25) upward.
    expect(find.text('120.3 bar'), findsOneWidget);
    expect(find.text('Stage 1'), findsOneWidget);
    expect(find.text('Stage 2'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
  });
}

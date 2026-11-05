import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/thermal_chart_series.dart';
import 'package:simplex_blender/src/ui/results/thermal_charts.dart';

// Source of truth: js/ui/thermal-charts.js empty-state strings (lines 333,
// 465, 839) and the table caption/heading in index.html.

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  testWidgets('empty series shows JS empty-state text', (tester) async {
    final series = buildThermalSeries(
      const <ThermalProtocolStep>[],
      initial: const ThermalInitialState(),
    );
    await tester.pumpWidget(
      _host(ThermalCharts(series: series, units: 'metric')),
    );

    expect(find.text('Blending thermal history'), findsOneWidget);
    expect(
      find.text(
        'Chart data appears when a completed blend protocol is available.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Chart data appears when a blend protocol is available.'),
      findsWidgets,
    );
    expect(
      find.text(
        'Hover either graph to inspect time, temperature, and pressure.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('terminal projection renders the status line', (tester) async {
    final series = buildThermalSeries(
      <ThermalProtocolStep>[
        ThermalProtocolStep(
          type: 'transfer',
          title: 'Transfer 1',
          recipeLabel: 'Transfer 1',
          thermal: ThermalStepThermal(
            durationMinutes: 2,
            waitMinutes: 1,
            measuredStartPressureBar: 50,
            measuredStartTemperatureC: 21,
            temperatureStartC: 21,
            temperatureAtTransferEndC: 30,
            pressureAtTransferEndBar: 150,
            temperatureAfterWaitC: 25,
            pressureAfterWaitBar: 140,
          ),
        ),
      ],
      initial: const ThermalInitialState(
        initialPressureBar: 50,
        initialTemperatureC: 21,
      ),
      terminalProjection: const ThermalTerminalProjection(
        pressureBar: 200,
        temperatureC: 21,
        durationMinutes: 0,
      ),
    );
    await tester.pumpWidget(
      _host(
        ThermalCharts(series: series, units: 'metric', ambientTemperatureC: 21),
      ),
    );

    expect(
      find.textContaining('ambient-settled tank state at 200.0 bar'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

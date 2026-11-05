import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/ui/results/water_pressure_pane.dart';

// Source of truth: js/ui/water-pressure.js renderWaterPressurePane (161-207)
// and tests/water-pressure.test.js (warning icon before value, table split).

Widget _host(WaterPressurePane pane) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: pane)),
  );
}

void main() {
  testWidgets('null inputs show heading only, no tables', (tester) async {
    await tester.pumpWidget(
      _host(
        const WaterPressurePane(
          pressureBar: null,
          oxygenPercent: null,
          heliumPercent: null,
          fromTemperatureC: null,
          volumeL: null,
          workingPressureBar: null,
          units: 'metric',
        ),
      ),
    );

    expect(find.text('In water pressure'), findsOneWidget);
    expect(find.text('Water temperatures'), findsNothing);
    expect(find.text('Car temperatures'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('valid inputs render water and car tables in two columns', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const WaterPressurePane(
          pressureBar: 200,
          oxygenPercent: 18,
          heliumPercent: 45,
          fromTemperatureC: 21,
          volumeL: 12,
          workingPressureBar: 300,
          units: 'metric',
        ),
      ),
    );

    expect(find.text('Water temperatures'), findsOneWidget);
    expect(find.text('Car temperatures'), findsOneWidget);
    expect(find.text('Gauge pressure'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('readings above working pressure show the warning icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const WaterPressurePane(
          pressureBar: 200,
          oxygenPercent: 18,
          heliumPercent: 45,
          fromTemperatureC: 21,
          volumeL: 12,
          workingPressureBar: 150,
          units: 'metric',
        ),
      ),
    );

    expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

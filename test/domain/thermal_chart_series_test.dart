import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/thermal_chart_series.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart' as domain;

const List<ThermalProtocolStep> protocolSteps = [
  ThermalProtocolStep(
    title: 'Drain / Vent Cylinder Gas',
    recipeLabel: 'Drain / Vent Cylinder Gas',
    receiverStartPressureBar: 80,
    thermal: ThermalStepThermal(
      durationMinutes: 0,
      waitMinutes: 10,
      temperatureStartC: 20,
      temperatureAtTransferEndC: 20,
      pressureAtTransferEndBar: 60,
      temperatureAfterWaitC: 20,
      pressureAfterWaitBar: 60,
    ),
  ),
  ThermalProtocolStep(
    title: 'Step 1: Decant Supply Bank to 100 bar',
    recipeLabel: 'Decant Supply Bank',
    recipeAction: 'Decant',
    recipeGas: 'Supply Bank',
    receiverStartPressureBar: 60,
    thermal: ThermalStepThermal(
      durationMinutes: 3,
      waitMinutes: 10,
      temperatureStartC: 20,
      temperatureAtTransferEndC: 35,
      pressureAtTransferEndBar: 100,
      temperatureAfterWaitC: 25,
      pressureAfterWaitBar: 90,
    ),
  ),
];

const ThermalInitialState initial80 = ThermalInitialState(
  initialPressureBar: 80,
  initialTemperatureC: 20,
);

ThermalSeriesPoint markerPoint(String phase) => ThermalSeriesPoint(
  step: 1,
  phase: phase,
  title: 'Point',
  label: 'Point',
  pressureBar: 0,
  temperatureC: 0,
  elapsedMinutes: 0,
  timeLabel: '0.0 min',
);

void main() {
  group('thermal charts', () {
    test(
      'thermal series includes drain, transfer, and settled points in order',
      () {
        final series = buildThermalSeries(protocolSteps, initial: initial80);

        expect(series.points.map((point) => point.phase).toList(), [
          'start',
          'transfer-end',
          'settled',
          'start',
          'transfer-end',
          'settled',
        ]);
        expect(series.points.map((point) => point.pressureBar).toList(), [
          80,
          60,
          60,
          60,
          100,
          90,
        ]);
        expect(series.points.map((point) => point.temperatureC).toList(), [
          20,
          20,
          20,
          20,
          35,
          25,
        ]);
        expect(series.points.map((point) => point.title).toList(), [
          'Drain / Vent Cylinder Gas',
          'Drain / Vent Cylinder Gas',
          'Drain / Vent Cylinder Gas',
          'Decant Supply Bank',
          'Decant Supply Bank',
          'Decant Supply Bank',
        ]);
        expect(
          series.points
              .map((point) => [point.recipeAction, point.recipeGas])
              .toList(),
          [
            [null, null],
            [null, null],
            [null, null],
            ['Decant', 'Supply Bank'],
            ['Decant', 'Supply Bank'],
            ['Decant', 'Supply Bank'],
          ],
        );
        expect(series.points[0].step, 1);
        expect(series.points.last.step, 2);
        expect(
          series.bands
              .map(
                (band) => [
                  band.step,
                  band.title,
                  band.startMinute,
                  band.endMinute,
                ],
              )
              .toList(),
          [
            [1, 'Drain / Vent Cylinder Gas', 0, 10],
            [2, 'Decant Supply Bank', 10, 23],
          ],
        );
      },
    );

    test('thermal bands alternate caption rows', () {
      final series = buildThermalSeries([
        ...protocolSteps,
        protocolSteps[1],
      ], initial: initial80);

      expect(series.bands.map((band) => band.labelRow).toList(), [0, 1, 0]);
    });

    test('thermal series omits a preserve-only step without interrupting caption rows', () {
      const preserveStep = ThermalProtocolStep(
        type: 'keep',
        recipeLabel: 'Preserve 100% of Cylinder Gas',
        thermal: ThermalStepThermal(
          durationMinutes: 0,
          waitMinutes: 0,
          temperatureStartC: 20,
          temperatureAtTransferEndC: 20,
          pressureAtTransferEndBar: 80,
          temperatureAfterWaitC: 20,
          pressureAfterWaitBar: 80,
        ),
      );
      final series = buildThermalSeries([
        protocolSteps[0],
        preserveStep,
        protocolSteps[1],
      ], initial: initial80);

      expect(
        series.bands
            .map(
              (band) => [
                band.step,
                band.title,
                band.startMinute,
                band.endMinute,
              ],
            )
            .toList(),
        [
          [1, 'Drain / Vent Cylinder Gas', 0, 10],
          [2, 'Decant Supply Bank', 10, 23],
        ],
      );
      expect(series.bands.map((band) => band.labelRow).toList(), [0, 1]);
    });

    test('thermal series ends at the final ambient-settled state', () {
      final series = buildThermalSeries(protocolSteps, initial: initial80);
      final finalPoint = series.points.last;

      expect(finalPoint.phase, 'settled');
      expect(finalPoint.pressureBar, 90);
      expect(finalPoint.temperatureC, 25);
      expect(finalPoint.elapsedMinutes, 23);
      expect(series.finalPoint!.pressureBar, 90);
      expect(series.finalPoint!.temperatureC, 25);
      expect(series.finalPoint!.elapsedMinutes, 23);
    });

    test('compare series retains explicit waits before adding an ambient-settled projection', () {
      final series = buildThermalSeries(
        const [
          ThermalProtocolStep(
            title: 'Add trimix',
            recipeLabel: 'Add trimix',
            recipeAction: 'Decant',
            recipeGas: 'Trimix',
            thermal: ThermalStepThermal(
              durationMinutes: 2,
              waitMinutes: 0,
              temperatureStartC: 20,
              temperatureAtTransferEndC: 32,
              pressureAtTransferEndBar: 125,
              temperatureAfterWaitC: 32,
              pressureAfterWaitBar: 125,
            ),
          ),
          ThermalProtocolStep(
            type: 'wait',
            title: 'Wait 15 minutes',
            recipeLabel: 'Wait 15 minutes',
            recipeAction: 'Wait',
            thermal: ThermalStepThermal(
              durationMinutes: 0,
              waitMinutes: 15,
              temperatureStartC: 32,
              temperatureAtTransferEndC: 32,
              pressureAtTransferEndBar: 125,
              temperatureAfterWaitC: 24,
              pressureAfterWaitBar: 121,
            ),
          ),
        ],
        initial: const ThermalInitialState(
          initialPressureBar: 100,
          initialTemperatureC: 20,
        ),
        terminalProjection: const ThermalTerminalProjection(
          pressureBar: 119,
          temperatureC: 20,
          durationMinutes: 46,
        ),
      );

      expect(series.points.map((point) => point.phase).toList(), [
        'start',
        'transfer-end',
        'settled',
        'start',
        'transfer-end',
        'settled',
        'ambient-settled',
      ]);
      expect(series.points.map((point) => point.elapsedMinutes).toList(), [
        0,
        2,
        2,
        2,
        2,
        17,
        63,
      ]);
      expect(series.bands.map((band) => band.endMinute).toList(), [2, 17]);
      expect(series.points.last.label, 'Ambient-settled projection');
      expect(series.finalPoint!.pressureBar, 119);
      expect(series.finalPoint!.temperatureC, 20);
      expect(series.finalPoint!.elapsedMinutes, 63);
    });

    test('keep-only compare series projects from the initial state to ambient settled', () {
      final series = buildThermalSeries(
        const [ThermalProtocolStep(type: 'keep')],
        initial: const ThermalInitialState(
          initialPressureBar: 100,
          initialTemperatureC: 24,
        ),
        terminalProjection: const ThermalTerminalProjection(
          pressureBar: 98,
          temperatureC: 20,
          durationMinutes: 46,
        ),
      );

      expect(series.bands, isEmpty);
      expect(
        series.points
            .map(
              (point) => [
                point.phase,
                point.elapsedMinutes,
                point.pressureBar,
                point.temperatureC,
              ],
            )
            .toList(),
        [
          ['ambient-settled', 46, 98, 20],
        ],
      );
      expect(
        series.samples
            .map(
              (sample) => [
                sample.elapsedMinutes,
                sample.pressureBar,
                sample.temperatureC,
              ],
            )
            .toList(),
        [
          [0, 100, 24],
          [46, 98, 20],
        ],
      );
      expect(series.segments.length, 1);
      expect(series.segments.single.style, ThermalSegmentStyle.estimated);
      expect(series.segments.single.samples, equals(series.samples));
    });

    test('empty or incomplete protocol produces no chart points', () {
      final empty = buildThermalSeries(const []);
      expect(empty.points, isEmpty);
      expect(empty.samples, isEmpty);
      expect(empty.bands, isEmpty);
      expect(empty.segments, isEmpty);
      expect(empty.finalPoint, isNull);

      final incomplete = buildThermalSeries(const [
        ThermalProtocolStep(title: 'Missing thermal state'),
      ]);
      expect(incomplete.points, isEmpty);
      expect(incomplete.samples, isEmpty);
      expect(incomplete.bands, isEmpty);
      expect(incomplete.segments, isEmpty);
      expect(incomplete.finalPoint, isNull);
    });

    test('pressure chart domain never extends below zero bar', () {
      final domain = calculateChartDomain([0, 80, 210], 'bar');

      expect(domain.min, 0);
      expect(domain.max, greaterThan(210));
    });

    test('ambient reference line uses the temperature chart scale', () {
      expect(calculateReferenceLineY(25, 15, 35, 200), 128);
      expect(calculateReferenceLineY(15, 15, 35, 200), 228);
    });

    test('estimated thermal curve uses dotted presentation', () {
      final style = thermalCurveAttributes('var(--chart-feasible)');

      expect(style.fill, 'none');
      expect(style.stroke, 'var(--chart-feasible)');
      expect(style.strokeWidth, 2.5);
      expect(style.strokeDasharray, '2 4');
      expect(style.strokeLinecap, 'round');
      expect(style.strokeLinejoin, 'round');
    });

    test('observed thermal curve uses solid presentation', () {
      expect(
        thermalCurveAttributes(
          'var(--chart-feasible)',
          ThermalSegmentStyle.observed,
        ).strokeDasharray,
        isNull,
      );
    });

    test('measured thermal points use a distinct marker presentation', () {
      const color = 'var(--chart-feasible)';

      final measured = thermalPointMarkerAttributes(
        markerPoint('measured-start'),
        color,
      );
      expect(measured.r, 5);
      expect(measured.fill, 'var(--chart-badge)');
      expect(measured.stroke, color);
      expect(measured.strokeWidth, 2);

      final transfer = thermalPointMarkerAttributes(
        markerPoint('transfer-end'),
        color,
      );
      expect(transfer.r, 4);
      expect(transfer.fill, color);
      expect(transfer.stroke, 'var(--chart-point-outline)');
      expect(transfer.strokeWidth, 1.5);
    });

    test('thermal chart accessibility names estimated curves', () {
      expect(
        thermalChartAriaLabel('Temperature'),
        'Temperature during blending steps over time; solid curves show the current/observed path; dotted curves indicate estimated values',
      );
    });

    test('thermal series includes measured start readings with estimated elapsed time', () {
      final series = buildThermalSeries(
        const [
          ThermalProtocolStep(
            title: 'First transfer',
            thermal: ThermalStepThermal(
              durationMinutes: 2,
              waitMinutes: 10,
              temperatureStartC: 20,
              temperatureAtTransferEndC: 40,
              pressureAtTransferEndBar: 100,
              temperatureAfterWaitC: 30,
              pressureAfterWaitBar: 98,
            ),
          ),
          ThermalProtocolStep(
            title: 'Measured next transfer',
            thermal: ThermalStepThermal(
              measuredStartPressureBar: 95,
              measuredStartTemperatureC: 25,
              measuredWaitMinutes: 15,
              durationMinutes: 3,
              waitMinutes: 10,
              temperatureStartC: 25,
              temperatureAtTransferEndC: 35,
              pressureAtTransferEndBar: 120,
              temperatureAfterWaitC: 28,
              pressureAfterWaitBar: 118,
            ),
          ),
        ],
        initial: const ThermalInitialState(
          initialPressureBar: 80,
          initialTemperatureC: 20,
        ),
      );

      final measuredStart = series.points[3];
      expect(measuredStart.phase, 'measured-start');
      expect(measuredStart.pressureBar, 95);
      expect(measuredStart.temperatureC, 25);
      expect(measuredStart.elapsedMinutes, 17);
      expect(measuredStart.timeLabel, '~17.0 min');
      expect(series.segments.map((segment) => segment.style).toList(), [
        ThermalSegmentStyle.observed,
        ThermalSegmentStyle.estimated,
        ThermalSegmentStyle.observed,
        ThermalSegmentStyle.observed,
      ]);
      expect(
        series.segments[1].samples
            .map((sample) => sample.elapsedMinutes)
            .toList(),
        [2, 12],
      );
      expect(
        series.segments[2].samples
            .map((sample) => sample.elapsedMinutes)
            .toList(),
        [2, 17],
      );
    });

    test('thermal series marks measured start time as unknown when it cannot be estimated', () {
      final series = buildThermalSeries(
        const [
          ThermalProtocolStep(
            title: 'First transfer',
            thermal: ThermalStepThermal(
              durationMinutes: 2,
              waitMinutes: 10,
              temperatureStartC: 20,
              temperatureAtTransferEndC: 40,
              pressureAtTransferEndBar: 100,
              temperatureAfterWaitC: 30,
              pressureAfterWaitBar: 98,
            ),
          ),
          ThermalProtocolStep(
            title: 'Measured next transfer',
            thermal: ThermalStepThermal(
              measuredStartPressureBar: 95,
              measuredStartTemperatureC: 25,
              durationMinutes: 3,
              waitMinutes: 10,
              temperatureStartC: 25,
              temperatureAtTransferEndC: 35,
              pressureAtTransferEndBar: 120,
              temperatureAfterWaitC: 28,
              pressureAfterWaitBar: 118,
            ),
          ),
        ],
        initial: const ThermalInitialState(
          initialPressureBar: 80,
          initialTemperatureC: 20,
        ),
      );

      expect(series.points[3].timeLabel, '? min');
    });

    test('thermal series maps minute samples while preserving highlighted key points', () {
      final sampledStep = ThermalProtocolStep(
        title: protocolSteps[1].title,
        recipeLabel: protocolSteps[1].recipeLabel,
        recipeAction: protocolSteps[1].recipeAction,
        recipeGas: protocolSteps[1].recipeGas,
        receiverStartPressureBar: protocolSteps[1].receiverStartPressureBar,
        thermal: const ThermalStepThermal(
          durationMinutes: 3,
          waitMinutes: 10,
          temperatureStartC: 20,
          temperatureAtTransferEndC: 35,
          pressureAtTransferEndBar: 100,
          temperatureAfterWaitC: 25,
          pressureAfterWaitBar: 90,
          samples: [
            ThermalInputSample(
              elapsedMinutes: 0,
              temperatureC: 20,
              pressureBar: 60,
            ),
            ThermalInputSample(
              elapsedMinutes: 1,
              temperatureC: 28,
              pressureBar: 73.3,
            ),
            ThermalInputSample(
              elapsedMinutes: 2,
              temperatureC: 34,
              pressureBar: 86.7,
            ),
            ThermalInputSample(
              elapsedMinutes: 3,
              temperatureC: 35,
              pressureBar: 100,
            ),
            ThermalInputSample(
              elapsedMinutes: 8,
              temperatureC: 29,
              pressureBar: 94,
            ),
            ThermalInputSample(
              elapsedMinutes: 13,
              temperatureC: 25,
              pressureBar: 90,
            ),
          ],
        ),
      );

      final series = buildThermalSeries([
        protocolSteps[0],
        sampledStep,
      ], initial: initial80);

      expect(series.points.length, 6);
      expect(series.points.sublist(3).map((point) => point.phase).toList(), [
        'start',
        'transfer-end',
        'settled',
      ]);
      expect(
        series.samples
            .sublist(series.samples.length - 6)
            .map((sample) => sample.elapsedMinutes)
            .toList(),
        [10, 11, 12, 13, 18, 23],
      );
      expect(
        series.samples
            .sublist(series.samples.length - 6)
            .map((sample) => [sample.temperatureC, sample.pressureBar])
            .toList(),
        [
          [20, 60],
          [28, 73.3],
          [34, 86.7],
          [35, 100],
          [29, 94],
          [25, 90],
        ],
      );
    });

    test('chart path follows sampled values while key points stay separate', () {
      final path = buildChartPath(
        const [
          // pressureBar is not part of this assertion; the JS fixture omits it.
          ThermalSeriesSample(
            elapsedMinutes: 0,
            temperatureC: 20,
            pressureBar: 0,
          ),
          ThermalSeriesSample(
            elapsedMinutes: 1,
            temperatureC: 28,
            pressureBar: 0,
          ),
          ThermalSeriesSample(
            elapsedMinutes: 2,
            temperatureC: 25,
            pressureBar: 0,
          ),
        ],
        ThermalSampleKey.temperatureC,
        (minutes) => minutes * 10,
        (value) => value,
      );

      expect(path, 'M 0 20 L 10 28 L 20 25');
    });

    test(
      'thermal hover interpolation returns both values at the hovered time',
      () {
        const samples = [
          ThermalSeriesSample(
            elapsedMinutes: 0,
            temperatureC: 20,
            pressureBar: 40,
          ),
          ThermalSeriesSample(
            elapsedMinutes: 1,
            temperatureC: 30,
            pressureBar: 80,
          ),
          ThermalSeriesSample(
            elapsedMinutes: 2,
            temperatureC: 24,
            pressureBar: 70,
          ),
        ];

        final middle = interpolateThermalSample(samples, 1.5)!;
        expect(middle.elapsedMinutes, 1.5);
        expect(middle.temperatureC, 27);
        expect(middle.pressureBar, 75);
        expect(interpolateThermalSample(samples, -1), equals(samples[0]));
        expect(interpolateThermalSample(samples, 4), equals(samples.last));
      },
    );

    test(
      'labels What-if terminal projections without optimizer target wording',
      () {
        final series = buildThermalSeries(
          const [
            ThermalProtocolStep(
              type: 'drain',
              title: 'Step 1: Drain',
              thermal: ThermalStepThermal(
                durationMinutes: 1,
                waitMinutes: 0,
                temperatureStartC: 25,
                temperatureAtTransferEndC: 24,
                pressureAtTransferEndBar: 20,
                pressureAfterWaitBar: 20,
                temperatureAfterWaitC: 24,
                samples: [
                  ThermalInputSample(
                    elapsedMinutes: 0,
                    pressureBar: 50,
                    temperatureC: 25,
                  ),
                  ThermalInputSample(
                    elapsedMinutes: 1,
                    pressureBar: 20,
                    temperatureC: 24,
                  ),
                ],
              ),
            ),
          ],
          initial: const ThermalInitialState(
            initialPressureBar: 50,
            initialTemperatureC: 25,
          ),
          terminalProjection: const ThermalTerminalProjection(
            mode: 'what-if',
            pressureBar: 19,
            temperatureC: 25,
            durationMinutes: 4,
            inWaterPressureBar: 18,
            inWaterTemperatureC: 10,
          ),
        );

        final inWater = series.points.last;
        expect(inWater.phase, 'in-water-projection');
        expect(inWater.label, contains('In-water projection'));
        expect(inWater.label.toLowerCase(), isNot(contains('target')));
      },
    );

    test('thermal samples follow projected pressure so the curve joins the transfer-end peak', () {
      final series = buildThermalSeries(
        const [
          ThermalProtocolStep(
            title: 'Air fill',
            recipeLabel: 'Air fill',
            receiverStartPressureBar: 25,
            thermal: ThermalStepThermal(
              durationMinutes: 2,
              waitMinutes: 10,
              temperatureStartC: 9,
              temperatureAtTransferEndC: 26,
              pressureAtTransferEndBar: 212.44,
              temperatureAfterWaitC: 7,
              pressureAfterWaitBar: 200,
              samples: [
                ThermalInputSample(
                  elapsedMinutes: 0,
                  pressureBar: 25,
                  projectedPressureBar: 25,
                  temperatureC: 9,
                ),
                ThermalInputSample(
                  elapsedMinutes: 2,
                  pressureBar: 200,
                  projectedPressureBar: 212.44,
                  temperatureC: 26,
                ),
                ThermalInputSample(
                  elapsedMinutes: 4,
                  pressureBar: 199.37,
                  projectedPressureBar: 211.0,
                  temperatureC: 25,
                ),
                ThermalInputSample(
                  elapsedMinutes: 12,
                  pressureBar: 200,
                  projectedPressureBar: 200,
                  temperatureC: 7,
                ),
              ],
            ),
          ),
        ],
        initial: const ThermalInitialState(
          initialPressureBar: 25,
          initialTemperatureC: 9,
        ),
      );

      double pressureAt(double minute) => series.samples
          .firstWhere((sample) => (sample.elapsedMinutes - minute).abs() < 1e-9)
          .pressureBar;

      final peak = series.points.firstWhere(
        (point) => (point.elapsedMinutes - 2).abs() < 1e-9,
      );
      expect(pressureAt(2), closeTo(212.44, 1e-6));
      expect(peak.pressureBar, closeTo(pressureAt(2), 1e-6));
      expect(pressureAt(4), closeTo(211.0, 1e-6));
      expect(pressureAt(12), closeTo(200, 1e-6));
    });

    test('a multi-step domain run plots every transfer-end peak on the observed curve', () {
      final result = domain.simulateThermalProtocol(
        protocolSteps: const [
          domain.ProtocolStep(
            type: 'boost',
            operation: 'Air fill',
            resultingPressureBar: 80,
            receiverStartPressureBar: 25,
            sourceStartPressureBar: 300,
            sourceEndPressureBar: 200,
          ),
          domain.ProtocolStep(
            type: 'boost',
            operation: 'Air fill',
            resultingPressureBar: 130,
            sourceStartPressureBar: 200,
            sourceEndPressureBar: 150,
          ),
          domain.ProtocolStep(
            type: 'boost',
            operation: 'Air fill',
            resultingPressureBar: 170,
            sourceStartPressureBar: 150,
            sourceEndPressureBar: 120,
          ),
          domain.ProtocolStep(
            type: 'boost',
            operation: 'Air fill',
            resultingPressureBar: 200,
            sourceStartPressureBar: 120,
            sourceEndPressureBar: 100,
          ),
        ],
        cylinder: const domain.CylinderInput(
          initialPressureBar: 25,
          volumeL: 12,
        ),
        physics: const domain.PhysicsInput(model: 'ideal', temperatureC: 9),
        thermal: const domain.ThermalInput(
          tankMaterial: 'steel',
          coolingMedium: 'air',
          ambientTemperatureC: 9,
          inletTemperatureC: 9,
          waitMode: 'minutes',
          waitMinutes: 10,
          targetTemperatureC: 7,
          tankMassKg: 12.6,
          interimMeasurements: [
            null,
            domain.InterimMeasurement(pressureBar: 100, temperatureC: 14),
            domain.InterimMeasurement(pressureBar: 150, temperatureC: 12),
            domain.InterimMeasurement(pressureBar: 190, temperatureC: 10),
          ],
        ),
        booster: const domain.BoosterSettings(),
      );

      final steps = [
        for (final step in result.protocolSteps)
          ThermalProtocolStep(
            type: step.type,
            title: step.title,
            recipeLabel: step.recipeLabel,
            receiverStartPressureBar: step.receiverStartPressureBar,
            resultingPressureBar: step.resultingPressureBar,
            thermal: ThermalStepThermal(
              durationMinutes: step.thermal!.durationMinutes,
              waitMinutes: step.thermal!.waitMinutes,
              measuredStartPressureBar: step.thermal!.measuredStartPressureBar,
              temperatureStartC: step.thermal!.temperatureStartC,
              temperatureAtTransferEndC:
                  step.thermal!.temperatureAtTransferEndC,
              pressureAtTransferEndBar: step.thermal!.pressureAtTransferEndBar,
              temperatureAfterWaitC: step.thermal!.temperatureAfterWaitC,
              pressureAfterWaitBar: step.thermal!.pressureAfterWaitBar,
              samples: [
                for (final sample in step.thermal!.samples)
                  ThermalInputSample(
                    elapsedMinutes: sample.elapsedMinutes,
                    pressureBar: sample.pressureBar,
                    projectedPressureBar: sample.projectedPressureBar,
                    temperatureC: sample.temperatureC,
                  ),
              ],
            ),
          ),
      ];
      final series = buildThermalSeries(
        steps,
        initial: const ThermalInitialState(
          initialPressureBar: 25,
          initialTemperatureC: 9,
        ),
      );

      for (var index = 0; index < result.protocolSteps.length; index++) {
        final thermal = result.protocolSteps[index].thermal!;
        final stepNumber = index + 1;
        final peak = series.points.firstWhere(
          (point) => point.step == stepNumber && point.phase == 'transfer-end',
        );
        expect(
          peak.pressureBar,
          closeTo(thermal.pressureAtTransferEndBar, 1e-6),
        );
        final plotted = series.samples.firstWhere(
          (sample) =>
              sample.step == stepNumber &&
              (sample.elapsedMinutes - peak.elapsedMinutes).abs() < 1e-6,
        );
        expect(plotted.pressureBar, closeTo(peak.pressureBar, 1e-6));
      }
    });

    test('thermal samples fall back to reference pressure when no projection is given', () {
      final series = buildThermalSeries(
        const [
          ThermalProtocolStep(
            title: 'Air fill',
            recipeLabel: 'Air fill',
            receiverStartPressureBar: 25,
            thermal: ThermalStepThermal(
              durationMinutes: 2,
              waitMinutes: 10,
              temperatureStartC: 9,
              temperatureAtTransferEndC: 26,
              pressureAtTransferEndBar: 212.44,
              temperatureAfterWaitC: 7,
              pressureAfterWaitBar: 200,
              samples: [
                ThermalInputSample(
                  elapsedMinutes: 0,
                  pressureBar: 25,
                  temperatureC: 9,
                ),
                ThermalInputSample(
                  elapsedMinutes: 2,
                  pressureBar: 200,
                  temperatureC: 26,
                ),
              ],
            ),
          ),
        ],
        initial: const ThermalInitialState(
          initialPressureBar: 25,
          initialTemperatureC: 9,
        ),
      );

      final transfer = series.samples.firstWhere(
        (sample) => (sample.elapsedMinutes - 2).abs() < 1e-9,
      );
      expect(transfer.pressureBar, closeTo(200, 1e-6));
    });
  });
}

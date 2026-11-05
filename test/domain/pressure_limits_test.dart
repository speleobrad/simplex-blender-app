import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/pressure_limits.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

ThermalSample _sample({
  required double elapsedMinutes,
  required double pressureBar,
  required double? projectedPressureBar,
  required double temperatureC,
}) {
  return ThermalSample(
    elapsedMinutes: elapsedMinutes,
    temperatureC: temperatureC,
    pressureBar: pressureBar,
    projectedPressureBar: projectedPressureBar,
  );
}

ThermalStep _thermal({
  required String rateSource,
  required double durationMinutes,
  required double waitMinutes,
  required double pressureStartBar,
  required double temperatureStartC,
  required double pressureAtTransferEndAmbientBar,
  required double pressureAtTransferEndHotBar,
  required double temperatureAtTransferEndC,
  required double temperatureAfterWaitC,
  required double pressureAfterWaitBar,
  List<ThermalSample> samples = const [],
}) {
  return ThermalStep(
    rateSource: rateSource,
    rateBarPerMin: null,
    durationMinutes: durationMinutes,
    inletTemperatureC: temperatureStartC,
    pressureStartBar: pressureStartBar,
    temperatureStartC: temperatureStartC,
    temperatureAtTransferEndC: temperatureAtTransferEndC,
    pressureReferenceTemperatureC: temperatureStartC,
    pressureAtTransferEndReferenceBar: pressureAtTransferEndAmbientBar,
    pressureAtTransferEndAmbientBar: pressureAtTransferEndAmbientBar,
    waitMinutes: waitMinutes,
    temperatureAfterWaitC: temperatureAfterWaitC,
    pressureAtTransferEndBar: pressureAtTransferEndHotBar,
    pressureAtTransferEndHotBar: pressureAtTransferEndHotBar,
    pressureAfterWaitBar: pressureAfterWaitBar,
    samples: samples,
  );
}

const CylinderPressureSpec _cylinder100Hot2 = CylinderPressureSpec(
  workingPressureBar: 100,
  hotOverfillPercent: 2,
);

/// Protocol used by the endpoint-phase tests. The last wait step's endpoint
/// values are parameterised so the endpoint variant can be built without
/// copying objects.
List<ProtocolStep> _endpointProtocol({
  double lastPressureAfterWaitBar = 99.5,
  double lastTemperatureAfterWaitC = 21,
  double lastSamplePressureBar = 99.5,
}) {
  return [
    ProtocolStep(
      type: 'wait',
      title: 'Wait to 24 °C',
      waitMode: 'target',
      thermal: _thermal(
        rateSource: 'none',
        durationMinutes: 0,
        waitMinutes: 5,
        pressureStartBar: 90,
        temperatureStartC: 20,
        pressureAtTransferEndAmbientBar: 90,
        pressureAtTransferEndHotBar: 90,
        temperatureAtTransferEndC: 20,
        temperatureAfterWaitC: 24,
        pressureAfterWaitBar: 90,
        samples: [
          _sample(
            elapsedMinutes: 0,
            pressureBar: 90,
            projectedPressureBar: 90,
            temperatureC: 20,
          ),
          _sample(
            elapsedMinutes: 5,
            pressureBar: 90,
            projectedPressureBar: 90,
            temperatureC: 24,
          ),
        ],
      ),
    ),
    ProtocolStep(
      type: 'boost',
      title: 'Transfer from the target state',
      thermal: _thermal(
        rateSource: 'booster',
        durationMinutes: 2,
        waitMinutes: 0,
        pressureStartBar: 90,
        temperatureStartC: 24,
        pressureAtTransferEndAmbientBar: 99,
        pressureAtTransferEndHotBar: 103,
        temperatureAtTransferEndC: 30,
        temperatureAfterWaitC: 30,
        pressureAfterWaitBar: 103,
        samples: [
          _sample(
            elapsedMinutes: 0,
            pressureBar: 90,
            projectedPressureBar: 90,
            temperatureC: 24,
          ),
          _sample(
            elapsedMinutes: 1,
            pressureBar: 101.5,
            projectedPressureBar: 101.5,
            temperatureC: 24,
          ),
          _sample(
            elapsedMinutes: 2,
            pressureBar: 103,
            projectedPressureBar: 103,
            temperatureC: 30,
          ),
        ],
      ),
    ),
    ProtocolStep(
      type: 'wait',
      title: 'Wait to 22 °C',
      waitMode: 'target',
      thermal: _thermal(
        rateSource: 'none',
        durationMinutes: 0,
        waitMinutes: 5,
        pressureStartBar: 103,
        temperatureStartC: 30,
        pressureAtTransferEndAmbientBar: 99,
        pressureAtTransferEndHotBar: 103,
        temperatureAtTransferEndC: 30,
        temperatureAfterWaitC: lastTemperatureAfterWaitC,
        pressureAfterWaitBar: lastPressureAfterWaitBar,
        samples: [
          _sample(
            elapsedMinutes: 0,
            pressureBar: 103,
            projectedPressureBar: 103,
            temperatureC: 30,
          ),
          _sample(
            elapsedMinutes: 1,
            pressureBar: 101.5,
            projectedPressureBar: 101.5,
            temperatureC: 24,
          ),
          _sample(
            elapsedMinutes: 3,
            pressureBar: 101,
            projectedPressureBar: 101,
            temperatureC: 22,
          ),
          _sample(
            elapsedMinutes: 5,
            pressureBar: lastSamplePressureBar,
            projectedPressureBar: lastSamplePressureBar,
            temperatureC: 21,
          ),
        ],
      ),
    ),
  ];
}

void main() {
  test('classifies working and transient hot-overfill boundaries', () {
    const cylinder = _cylinder100Hot2;
    final working = getCylinderPressureLimit(cylinder: cylinder);
    expect(working?.kind, 'working-pressure');
    expect(working?.limitBar, 100);

    final hot = getCylinderPressureLimit(
      cylinder: cylinder,
      isTransientHot: true,
    );
    expect(hot?.kind, 'hot-overfill');
    expect(hot?.limitBar, 102);

    expect(
      getCylinderPressureExceedance(
        pressureBar: 102,
        cylinder: cylinder,
        isTransientHot: true,
      ),
      isNull,
    );

    final hotExceeded = getCylinderPressureExceedance(
      pressureBar: 102.1,
      cylinder: cylinder,
      isTransientHot: true,
    );
    expect(hotExceeded?.kind, 'hot-overfill');
    expect(hotExceeded?.pressureBar, 102.1);
    expect(hotExceeded?.limitBar, 102);

    final workingExceeded = getCylinderPressureExceedance(
      pressureBar: 100.1,
      cylinder: cylinder,
    );
    expect(workingExceeded?.kind, 'working-pressure');
    expect(workingExceeded?.pressureBar, 100.1);
    expect(workingExceeded?.limitBar, 100);
  });

  test('aggregates the highest limit exceedance per source and step', () {
    const cylinder = _cylinder100Hot2;
    final warnings = collectCylinderPressureWarnings(
      cylinder: cylinder,
      observations: const [
        PressureObservation(
          pressureBar: 102.1,
          isTransientHot: true,
          source: 'transfer',
          stepIdentifier: 'Transfer 2',
          stepIndex: null,
        ),
        PressureObservation(
          pressureBar: 103,
          isTransientHot: true,
          source: 'transfer',
          stepIdentifier: 'Transfer 2',
          stepIndex: null,
        ),
        PressureObservation(
          pressureBar: 100.1,
          isTransientHot: false,
          source: 'settled',
          stepIdentifier: null,
          stepIndex: null,
        ),
      ],
    );
    expect(warnings.length, 2);
    expect(
      warnings.any(
        (warning) =>
            warning.kind == 'hot-overfill' &&
            warning.pressureBar == 103 &&
            warning.limitBar == 102 &&
            warning.source == 'transfer' &&
            warning.stepIdentifier == 'Transfer 2',
      ),
      isTrue,
    );
    expect(
      warnings.any(
        (warning) =>
            warning.kind == 'working-pressure' &&
            warning.pressureBar == 100.1 &&
            warning.limitBar == 100 &&
            warning.source == 'settled' &&
            warning.stepIdentifier == null,
      ),
      isTrue,
    );
  });

  test('classifies thermal samples by target-wait endpoint rather than matching temperature', () {
    const cylinder = CylinderPressureSpec(
      workingPressureBar: 100,
      hotOverfillPercent: 5,
    );
    final protocolSteps = _endpointProtocol();
    final observations = collectThermalPressureWarningObservations(
      protocolSteps: protocolSteps,
      ambientTemperatureC: 20,
    );

    expect(
      collectCylinderPressureWarnings(
        cylinder: cylinder,
        observations: observations,
      ),
      isEmpty,
    );
  });

  test('thermal pressure notices classify target states by endpoint phase', () {
    const cylinder = CylinderPressureSpec(
      workingPressureBar: 100,
      hotOverfillPercent: 5,
    );
    final protocolSteps = _endpointProtocol();

    final observations = collectThermalPressureWarningObservations(
      protocolSteps: protocolSteps,
      ambientTemperatureC: 20,
    );
    expect(
      collectCylinderPressureWarnings(
        cylinder: cylinder,
        observations: observations,
      ),
      isEmpty,
    );

    final endpointWarnings = collectCylinderPressureWarnings(
      cylinder: cylinder,
      observations: collectThermalPressureWarningObservations(
        protocolSteps: _endpointProtocol(
          lastPressureAfterWaitBar: 101.5,
          lastTemperatureAfterWaitC: 22,
          lastSamplePressureBar: 101.5,
        ),
        ambientTemperatureC: 20,
      ),
    );
    expect(endpointWarnings.length, 1);
    final warning = endpointWarnings.single;
    expect(warning.kind, 'working-pressure');
    expect(warning.pressureBar, 101.5);
    expect(warning.limitBar, 100);
    expect(warning.source, 'settled');
    expect(warning.stepIdentifier, 'Wait to 22 °C');
    expect(warning.stepIndex, 2);
  });

  test('warning de-duplication keeps repeated step titles separate', () {
    final repeated = [
      ProtocolStep(
        title: 'Boost Oxygen',
        thermal: _thermal(
          rateSource: 'booster',
          durationMinutes: 1,
          waitMinutes: 1,
          pressureStartBar: 100,
          temperatureStartC: 30,
          pressureAtTransferEndAmbientBar: 100,
          pressureAtTransferEndHotBar: 110,
          temperatureAtTransferEndC: 30,
          temperatureAfterWaitC: 20,
          pressureAfterWaitBar: 100,
        ),
      ),
      ProtocolStep(
        title: 'Boost Oxygen',
        thermal: _thermal(
          rateSource: 'booster',
          durationMinutes: 1,
          waitMinutes: 1,
          pressureStartBar: 100,
          temperatureStartC: 30,
          pressureAtTransferEndAmbientBar: 100,
          pressureAtTransferEndHotBar: 115,
          temperatureAtTransferEndC: 30,
          temperatureAfterWaitC: 20,
          pressureAfterWaitBar: 100,
        ),
      ),
    ];
    final observations = collectThermalPressureWarningObservations(
      protocolSteps: repeated,
      ambientTemperatureC: 20,
    );
    final warnings = collectCylinderPressureWarnings(
      cylinder: const CylinderPressureSpec(
        workingPressureBar: 105,
        hotOverfillPercent: 0,
      ),
      observations: observations,
    );
    expect(warnings.where((warning) => warning.source == 'transfer').length, 2);
  });
}

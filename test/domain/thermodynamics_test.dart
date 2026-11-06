import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/physics.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

GasMixPercent _mix(double oxygenPercent, double heliumPercent) =>
    GasMixPercent(oxygenPercent: oxygenPercent, heliumPercent: heliumPercent);

ThermalProtocolResult _thermal({
  required List<ProtocolStep> steps,
  required CylinderInput cylinder,
  required PhysicsInput physics,
  required ThermalInput thermal,
  BoosterSettings? booster,
}) => simulateThermalProtocol(
  protocolSteps: steps,
  cylinder: cylinder,
  physics: physics,
  thermal: thermal,
  booster: booster,
);

ThermalCompareResult _compare({
  required List<ProtocolStep> steps,
  required CylinderInput cylinder,
  required PhysicsInput physics,
  required ThermalInput thermal,
  BoosterSettings? booster,
}) => simulateCompareProtocol(
  protocolSteps: steps,
  cylinder: cylinder,
  physics: physics,
  thermal: thermal,
  booster: booster,
);

ThermalStep _stepThermal(ThermalProtocolResult result, int index) =>
    result.protocolSteps[index].thermal!;

// Booster step driven by the profile solver. `sourceVolumeL` and
// `sourceStartMoles` feed the source-inventory model.
ThermalProtocolResult _profiledBoosterSimulation({
  required double sourceStartMoles,
}) => _thermal(
  steps: [
    ProtocolStep(
      type: 'boost',
      operation: 'Boost',
      resultingPressureBar: 150,
      resultingMix: const GasMixPercent(oxygenPercent: 21, heliumPercent: 0),
      receiverStartPressureBar: 50,
      receiverEndPressureBar: 150,
      sourceStartPressureBar: 200,
      sourceEndPressureBar: 150,
      sourceOxygenPercent: 21,
      sourceHeliumPercent: 0,
      sourceInventory: 'booster',
      sourceVolumeL: 12,
      sourceStartMoles: sourceStartMoles,
    ),
  ],
  cylinder: const CylinderInput(initialPressureBar: 50, volumeL: 12),
  physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
  thermal: const ThermalInput(
    tankMaterial: 'steel',
    coolingMedium: 'air',
    ambientTemperatureC: 20,
    inletTemperatureC: 20,
    waitMode: 'minutes',
    waitMinutes: 0,
    targetTemperatureC: 25,
    tankMassKg: 10,
  ),
  booster: const BoosterSettings(),
);

void main() {
  test(
    'booster rate uses displacement, BPM, and receiver/source compressibility',
    () {
      final rate = calculateBoosterFillRate(
        cylinderVolumeCm3: 9,
        bpm: 50,
        sourcePressureBar: 200,
        receiverPressureBar: 100,
        sourceOxygenPercent: 21,
        sourceHeliumPercent: 0,
        receiverOxygenPercent: 21,
        receiverHeliumPercent: 0,
        receiverVolumeL: 12,
        temperatureC: 20,
        useVdw: false,
      );

      expect(rate.fillRateBarPerMin, greaterThan(7));
      expect(rate.fillRateBarPerMin, lessThan(8));
      expect(rate.volumetricEfficiency, equals(1));
    },
  );

  test('booster molar flow uses absolute source pressure', () {
    final rate = calculateBoosterFillRate(
      cylinderVolumeCm3: 9,
      bpm: 50,
      sourcePressureBar: 200,
      receiverPressureBar: 100,
      sourceOxygenPercent: 21,
      sourceHeliumPercent: 0,
      receiverOxygenPercent: 21,
      receiverHeliumPercent: 0,
      receiverVolumeL: 12,
      temperatureC: 20,
      useVdw: false,
    );

    final expectedMolesPerMin = (201 * 0.45) / (0.083144626 * 293.15);
    expect(rate.molesPerMin, closeTo(expectedMolesPerMin, 1e-12));
  });

  test('booster clearance efficiency falls when receiver pressure exceeds source pressure', () {
    final rate = calculateBoosterFillRate(
      cylinderVolumeCm3: 9,
      bpm: 50,
      sourcePressureBar: 100,
      receiverPressureBar: 200,
      sourceOxygenPercent: 100,
      sourceHeliumPercent: 0,
      receiverOxygenPercent: 41,
      receiverHeliumPercent: 0,
      receiverVolumeL: 12,
      temperatureC: 20,
      useVdw: false,
    );

    expect(rate.volumetricEfficiency, greaterThan(0.96));
    expect(rate.volumetricEfficiency, lessThan(0.98));
    expect(rate.fillRateBarPerMin, greaterThan(0));
  });

  test(
    'compressor inlet flow converts free-air flow to receiver pressure rate',
    () {
      final rate = calculateCompressorFillRate(
        inletFlowLPerMin: 100,
        receiverPressureBar: 1.01325,
        receiverOxygenPercent: 21,
        receiverHeliumPercent: 0,
        receiverVolumeL: 12,
        ambientTemperatureC: 20,
        receiverTemperatureC: 20,
        useVdw: false,
      );

      expect(rate.fillRateBarPerMin, closeTo(8.447, 0.01));
    },
  );

  test(
    'compressor real-gas receiver compressibility uses absolute pressure',
    () {
      const inletFlowLPerMin = 100.0;
      const receiverPressureBar = 200.0;
      const receiverVolumeL = 12.0;
      const ambientTemperatureC = 20.0;
      const receiverTemperatureC = 20.0;
      final rate = calculateCompressorFillRate(
        inletFlowLPerMin: inletFlowLPerMin,
        receiverPressureBar: receiverPressureBar,
        receiverOxygenPercent: 21,
        receiverHeliumPercent: 0,
        receiverVolumeL: receiverVolumeL,
        ambientTemperatureC: ambientTemperatureC,
        receiverTemperatureC: receiverTemperatureC,
        useVdw: true,
      );
      const temperatureK = receiverTemperatureC + 273.15;
      final inletMolesPerMin =
          1.01325 *
          inletFlowLPerMin /
          (calcZ(1.01325, 21, 0, ambientTemperatureC, true) *
              gasConstant *
              temperatureK);
      final expected =
          inletMolesPerMin *
          calcZ(receiverPressureBar + 1, 21, 0, receiverTemperatureC, true) *
          gasConstant *
          temperatureK /
          receiverVolumeL;

      expect(rate.fillRateBarPerMin, closeTo(expected, 1e-12));
    },
  );

  test('compressor fill rate reports moles per minute', () {
    final result = calculateCompressorFillRate(
      inletFlowLPerMin: 100,
      receiverPressureBar: 1.01325,
      receiverOxygenPercent: 21,
      receiverHeliumPercent: 0,
      receiverVolumeL: 12,
      ambientTemperatureC: 20,
      receiverTemperatureC: 20,
      useVdw: false,
    );
    final zInlet = calcZ(1.01325, 21, 0, 20, false);
    final expectedMoles = 1.01325 * 100 / (zInlet * gasConstant * 293.15);
    expect(result.molesPerMin, closeTo(expectedMoles, 1e-12));
  });

  test('cooling reaches an absolute target using Newton cooling', () {
    final minutes = calculateCoolingTime(
      transferEndTemperatureC: 60,
      ambientTemperatureC: 20,
      targetTemperatureC: 30,
      tauMinutes: 18,
    );
    expect(minutes, closeTo(24.9533, 1e-3));
    expect(
      calculateTemperatureAfterWait(
        transferEndTemperatureC: 60,
        ambientTemperatureC: 20,
        waitMinutes: minutes,
        tauMinutes: 18,
      ),
      closeTo(30, 1e-9),
    );
  });

  test('pressure falls when a hot ideal-gas tank cools at fixed density', () {
    final pressure = calculatePressureAtTemperature(
      pressureBar: 200,
      oxygenPercent: 21,
      heliumPercent: 0,
      fromTemperatureC: 60,
      toTemperatureC: 20,
      volumeL: 12,
      useVdw: false,
    );
    expect(pressure, closeTo(175.989, 0.01));
  });

  test('pressure projection uses the selected Van der Waals model', () {
    final pressure = calculatePressureAtTemperature(
      pressureBar: 200,
      oxygenPercent: 21,
      heliumPercent: 0,
      fromTemperatureC: 60,
      toTemperatureC: 20,
      volumeL: 12,
      useVdw: true,
    );

    expect(pressure, closeTo(167.5505, 1e-3));
  });

  test('transfer temperature increases with pressure and is cooled faster in water', () {
    final airSteel = estimateTransferTemperature(
      startTemperatureC: 20,
      addedPressureBar: 70,
      fillTimeMinutes: 10,
      volumeL: 12,
      heliumFraction: 0,
      tankMaterial: 'steel',
      coolingMedium: 'air',
    );
    final heliumAluminumWater = estimateTransferTemperature(
      startTemperatureC: 20,
      addedPressureBar: 70,
      fillTimeMinutes: 10,
      volumeL: 12,
      heliumFraction: 0.35,
      tankMaterial: 'aluminum',
      coolingMedium: 'water',
    );

    expect(airSteel, greaterThan(20));
    expect(heliumAluminumWater, greaterThan(20));
    expect(heliumAluminumWater, lessThan(airSteel));
  });

  test('transfer heat loss uses the ambient gradient during filling', () {
    final matchedAmbient = estimateTransferTemperature(
      startTemperatureC: 24,
      addedPressureBar: 100,
      fillTimeMinutes: 10,
      volumeL: 12,
      heliumFraction: 1,
      tankMaterial: 'steel',
      coolingMedium: 'air',
      ambientTemperatureC: 24,
    );
    final coolerAmbient = estimateTransferTemperature(
      startTemperatureC: 24,
      addedPressureBar: 100,
      fillTimeMinutes: 10,
      volumeL: 12,
      heliumFraction: 1,
      tankMaterial: 'steel',
      coolingMedium: 'air',
      ambientTemperatureC: 0,
    );

    expect(coolerAmbient, lessThan(matchedAmbient - 1));
  });

  test('matches the corrected reference 12 L steel air-fill integration', () {
    final temperatureC = estimateTransferTemperature(
      startTemperatureC: 28,
      startPressureBar: 80,
      addedPressureBar: 100,
      fillTimeMinutes: 20,
      volumeL: 12,
      heliumFraction: 0.35,
      tankMaterial: 'steel',
      coolingMedium: 'air',
      ambientTemperatureC: 28,
      inletTemperatureC: 28,
    );

    expect(temperatureC, closeTo(37.8424, 0.01));
  });

  test('inlet gas temperature changes the transfer-end temperature', () {
    double run(double inletTemperatureC) => estimateTransferTemperature(
      startTemperatureC: 20,
      startPressureBar: 0,
      addedPressureBar: 210,
      fillTimeMinutes: 20,
      volumeL: 12,
      heliumFraction: 0,
      tankMaterial: 'steel',
      coolingMedium: 'air',
      ambientTemperatureC: 20,
      inletTemperatureC: inletTemperatureC,
    );

    final chilledInletC = run(0);
    final warmInletC = run(40);

    expect(warmInletC, greaterThan(chilledInletC + 5));
  });

  test('cylinder mass changes transfer-end temperature', () {
    double run(double tankMassKg) => estimateTransferTemperature(
      startTemperatureC: 20,
      startPressureBar: 0,
      addedPressureBar: 210,
      fillTimeMinutes: 20,
      volumeL: 12,
      heliumFraction: 0,
      tankMaterial: 'steel',
      coolingMedium: 'air',
      ambientTemperatureC: 20,
      inletTemperatureC: 20,
      tankMassKg: tankMassKg,
    );

    final lightTank = run(10);
    final heavyTank = run(20);

    expect(lightTank, greaterThan(heavyTank));
  });

  test(
    'thermal simulation passes the selected cylinder mass to transfer heating',
    () {
      ThermalProtocolResult run(double tankMassKg) => _thermal(
        steps: [
          const ProtocolStep(
            type: 'boost',
            operation: 'Boost',
            resultingPressureBar: 180,
            resultingMix: GasMixPercent(oxygenPercent: 21, heliumPercent: 0),
            receiverStartPressureBar: 0,
            receiverEndPressureBar: 180,
            sourceStartPressureBar: 200,
            sourceEndPressureBar: 20,
            sourceOxygenPercent: 21,
            sourceHeliumPercent: 0,
          ),
        ],
        cylinder: const CylinderInput(initialPressureBar: 0, volumeL: 12),
        physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
        thermal: ThermalInput(
          tankMaterial: 'steel',
          coolingMedium: 'air',
          ambientTemperatureC: 20,
          inletTemperatureC: 20,
          waitMode: 'minutes',
          waitMinutes: 0,
          targetTemperatureC: 25,
          tankMassKg: tankMassKg,
        ),
        booster: const BoosterSettings(
          compressorInletFlowLPerMin: 100,
          oxygenBoostBpm: 50,
          otherBoostBpm: 50,
          oxygenDecantRateBarPerMin: 5,
          otherDecantRateBarPerMin: 5,
        ),
      );

      final lightTank = run(10);
      final heavyTank = run(20);

      expect(
        _stepThermal(lightTank, 0).temperatureAtTransferEndC,
        greaterThan(_stepThermal(heavyTank, 0).temperatureAtTransferEndC),
      );
    },
  );

  test('compressor temperature modifier is added to the configured inlet temperature', () {
    final simulation = _thermal(
      steps: [
        const ProtocolStep(
          type: 'boost',
          operation: 'Top-up',
          resultingPressureBar: 150,
          resultingMix: GasMixPercent(oxygenPercent: 21, heliumPercent: 0),
          receiverStartPressureBar: 100,
          receiverEndPressureBar: 150,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 100, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        inletTemperatureC: 20,
        waitMode: 'minutes',
        waitMinutes: 0,
        targetTemperatureC: 25,
      ),
      booster: const BoosterSettings(
        compressorInletFlowLPerMin: 100,
        compressorTemperatureModifierC: 15,
      ),
    );

    expect(_stepThermal(simulation, 0).inletTemperatureC, equals(35));
  });

  test('sequential simulation carries post-wait pressure and temperature into the next stage', () {
    final simulation = _thermal(
      steps: [
        ProtocolStep(
          type: 'boost',
          operation: 'Boost',
          resultingPressureBar: 150,
          resultingMix: _mix(21, 0),
          sourceStartPressureBar: 200,
          sourceEndPressureBar: 150,
          receiverStartPressureBar: 100,
          receiverEndPressureBar: 150,
        ),
        ProtocolStep(
          type: 'decant',
          operation: 'Decant',
          resultingPressureBar: 180,
          resultingMix: _mix(21, 0),
          sourceStartPressureBar: 220,
          sourceEndPressureBar: 190,
          receiverStartPressureBar: 150,
          receiverEndPressureBar: 180,
        ),
      ],
      cylinder: const CylinderInput(volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        waitMode: 'minutes',
        waitMinutes: 10,
        targetTemperatureC: 25,
      ),
      booster: const BoosterSettings(
        cylinderVolumeCm3: 9,
        oxygenBoostBpm: 50,
        otherBoostBpm: 50,
        oxygenDecantRateBarPerMin: 5,
        otherDecantRateBarPerMin: 5,
        compressorInletFlowLPerMin: 100,
      ),
    );

    expect(simulation.protocolSteps.length, equals(2));
    expect(_stepThermal(simulation, 0).rateSource, equals('booster'));
    expect(_stepThermal(simulation, 1).rateSource, equals('decant-rate'));
    expect(
      _stepThermal(simulation, 1).temperatureAtTransferEndC,
      greaterThan(_stepThermal(simulation, 1).temperatureStartC),
    );
    expect(
      _stepThermal(simulation, 1).temperatureStartC,
      equals(_stepThermal(simulation, 0).temperatureAfterWaitC),
    );
  });

  test('measured interim readings replace the next step start state', () {
    final simulation = _thermal(
      steps: [
        ProtocolStep(
          type: 'boost',
          operation: 'Boost',
          resultingPressureBar: 150,
          resultingMix: _mix(21, 0),
          sourceStartPressureBar: 200,
          sourceEndPressureBar: 150,
          receiverStartPressureBar: 100,
          receiverEndPressureBar: 150,
        ),
        ProtocolStep(
          type: 'decant',
          operation: 'Decant',
          resultingPressureBar: 180,
          resultingMix: _mix(21, 0),
          sourceStartPressureBar: 220,
          sourceEndPressureBar: 190,
          receiverStartPressureBar: 150,
          receiverEndPressureBar: 180,
        ),
      ],
      cylinder: const CylinderInput(volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        waitMode: 'minutes',
        waitMinutes: 10,
        targetTemperatureC: 25,
        interimMeasurements: [
          null,
          InterimMeasurement(pressureBar: 149, temperatureC: 23),
        ],
      ),
      booster: const BoosterSettings(
        cylinderVolumeCm3: 9,
        oxygenBoostBpm: 50,
        otherBoostBpm: 50,
        oxygenDecantRateBarPerMin: 5,
        otherDecantRateBarPerMin: 5,
        compressorInletFlowLPerMin: 100,
      ),
    );
    final nextStep = _stepThermal(simulation, 1);

    expect(nextStep.measuredStartPressureBar, equals(149));
    expect(nextStep.pressureStartBar, equals(149));
    expect(nextStep.temperatureStartC, equals(23));
    expect(nextStep.measuredWaitMinutes, greaterThan(0));
    expect(
      nextStep.pressureAfterWaitBar,
      isNot(equals(_stepThermal(simulation, 0).pressureAfterWaitBar)),
    );
  });

  test('top-up uses compressor flow before stage type', () {
    final simulation = _thermal(
      steps: [
        ProtocolStep(
          type: 'boost',
          operation: 'Top-up',
          resultingPressureBar: 200,
          resultingMix: _mix(21, 0),
          sourceStartPressureBar: 190,
          sourceEndPressureBar: 100,
          receiverStartPressureBar: 150,
          receiverEndPressureBar: 200,
        ),
      ],
      cylinder: const CylinderInput(volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        waitMode: 'minutes',
        waitMinutes: 0,
        targetTemperatureC: 25,
      ),
      booster: const BoosterSettings(
        cylinderVolumeCm3: 9,
        oxygenBoostBpm: 50,
        otherBoostBpm: 50,
        oxygenDecantRateBarPerMin: 5,
        otherDecantRateBarPerMin: 5,
        compressorInletFlowLPerMin: 100,
      ),
    );

    expect(_stepThermal(simulation, 0).rateSource, equals('compressor'));
    expect(_stepThermal(simulation, 0).rateBarPerMin, greaterThan(0));
  });

  test('VDW top-up rate uses the receiver midpoint pressure', () {
    final simulation = _thermal(
      steps: [
        ProtocolStep(
          type: 'boost',
          operation: 'Top-up',
          resultingPressureBar: 300,
          resultingMix: _mix(21, 0),
          receiverStartPressureBar: 200,
          receiverEndPressureBar: 300,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 200, volumeL: 12),
      physics: const PhysicsInput(model: 'vdw', temperatureC: 20),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        waitMode: 'minutes',
        waitMinutes: 0,
        targetTemperatureC: 25,
      ),
      booster: const BoosterSettings(
        cylinderVolumeCm3: 9,
        oxygenBoostBpm: 50,
        otherBoostBpm: 50,
        oxygenDecantRateBarPerMin: 5,
        otherDecantRateBarPerMin: 5,
        compressorInletFlowLPerMin: 100,
      ),
    );

    expect(_stepThermal(simulation, 0).rateBarPerMin, greaterThan(8.6));
  });

  test('40 percent source oxygen selects oxygen-rich rates while lower concentrations use regular rates', () {
    final simulation = _thermal(
      steps: [
        ProtocolStep(
          type: 'boost',
          operation: 'Boost',
          resultingPressureBar: 110,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 40,
          sourceHeliumPercent: 0,
          sourceStartPressureBar: 200,
          sourceEndPressureBar: 190,
          receiverStartPressureBar: 100,
          receiverEndPressureBar: 110,
        ),
        ProtocolStep(
          type: 'decant',
          operation: 'Decant',
          resultingPressureBar: 120,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 40,
          sourceHeliumPercent: 0,
          sourceStartPressureBar: 220,
          sourceEndPressureBar: 210,
          receiverStartPressureBar: 110,
          receiverEndPressureBar: 120,
        ),
        ProtocolStep(
          type: 'boost',
          operation: 'Boost',
          resultingPressureBar: 130,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 39.9,
          sourceHeliumPercent: 0,
          sourceStartPressureBar: 200,
          sourceEndPressureBar: 190,
          receiverStartPressureBar: 120,
          receiverEndPressureBar: 130,
        ),
        ProtocolStep(
          type: 'decant',
          operation: 'Decant',
          resultingPressureBar: 140,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 39.9,
          sourceHeliumPercent: 0,
          sourceStartPressureBar: 220,
          sourceEndPressureBar: 210,
          receiverStartPressureBar: 130,
          receiverEndPressureBar: 140,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 100, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        waitMode: 'minutes',
        waitMinutes: 0,
        targetTemperatureC: 25,
      ),
      booster: const BoosterSettings(
        cylinderVolumeCm3: 9,
        oxygenBoostBpm: 100,
        otherBoostBpm: 1,
        oxygenDecantRateBarPerMin: 9,
        otherDecantRateBarPerMin: 3,
        compressorInletFlowLPerMin: 100,
      ),
    );

    expect(_stepThermal(simulation, 0).rateSource, equals('booster'));
    expect(
      _stepThermal(simulation, 0).rateBarPerMin!,
      greaterThan(_stepThermal(simulation, 2).rateBarPerMin! * 50),
    );
    expect(_stepThermal(simulation, 1).rateBarPerMin, equals(9));
    expect(_stepThermal(simulation, 3).rateBarPerMin, equals(3));
  });

  test(
    'draining uses the configured rate and cools the tank as pressure falls',
    () {
      final simulation = _thermal(
        steps: [
          ProtocolStep(
            type: 'drain',
            operation: 'Drain / Vent',
            resultingPressureBar: 50,
            resultingMix: _mix(21, 0),
            receiverStartPressureBar: 100,
            receiverEndPressureBar: 50,
          ),
        ],
        cylinder: const CylinderInput(initialPressureBar: 100, volumeL: 12),
        physics: const PhysicsInput(model: 'ideal', temperatureC: 40),
        thermal: const ThermalInput(
          tankMaterial: 'steel',
          coolingMedium: 'air',
          ambientTemperatureC: 20,
          inletTemperatureC: 20,
          waitMode: 'minutes',
          waitMinutes: 0,
          targetTemperatureC: 25,
        ),
        booster: const BoosterSettings(drainingRateBarPerMin: 10),
      );

      final thermal = _stepThermal(simulation, 0);
      expect(thermal.rateSource, equals('draining-rate'));
      expect(thermal.rateBarPerMin, equals(10));
      expect(thermal.durationMinutes, equals(5));
      expect(
        thermal.temperatureAtTransferEndC,
        lessThan(thermal.temperatureStartC),
      );
    },
  );

  test('preserving the original gas does not consume a fixed wait', () {
    final simulation = _thermal(
      steps: [
        ProtocolStep(
          type: 'keep',
          operation: 'Preserve',
          resultingPressureBar: 100,
          resultingMix: _mix(21, 0),
          receiverStartPressureBar: 100,
          receiverEndPressureBar: 100,
        ),
        ProtocolStep(
          type: 'decant',
          operation: 'Decant',
          resultingPressureBar: 110,
          resultingMix: _mix(21, 0),
          receiverStartPressureBar: 100,
          receiverEndPressureBar: 110,
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
          sourceStartPressureBar: 200,
          sourceEndPressureBar: 190,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 100, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 40),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        waitMode: 'minutes',
        waitMinutes: 10,
        targetTemperatureC: 25,
      ),
      booster: const BoosterSettings(otherDecantRateBarPerMin: 5),
    );

    expect(_stepThermal(simulation, 0).waitMinutes, equals(0));
    expect(_stepThermal(simulation, 0).temperatureAfterWaitC, equals(40));
  });

  test('zero-change stages have no transfer rate', () {
    final simulation = _thermal(
      steps: [
        ProtocolStep(
          type: 'boost',
          operation: 'Boost',
          resultingPressureBar: 100,
          resultingMix: _mix(21, 0),
          sourceStartPressureBar: 200,
          sourceEndPressureBar: 200,
          receiverStartPressureBar: 100,
          receiverEndPressureBar: 100,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 100, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        waitMode: 'minutes',
        waitMinutes: 0,
        targetTemperatureC: 25,
      ),
    );

    expect(_stepThermal(simulation, 0).rateSource, equals('none'));
    expect(_stepThermal(simulation, 0).rateBarPerMin, isNull);
    expect(_stepThermal(simulation, 0).durationMinutes, equals(0));
  });

  test(
    'thermal simulation retains minute samples and exact fractional endpoints',
    () {
      final simulation = _thermal(
        steps: [
          ProtocolStep(
            type: 'decant',
            operation: 'Decant',
            resultingPressureBar: 12,
            resultingMix: _mix(21, 0),
            receiverStartPressureBar: 0,
            receiverEndPressureBar: 12,
            sourceOxygenPercent: 21,
            sourceHeliumPercent: 0,
          ),
          ProtocolStep(
            type: 'keep',
            operation: 'Preserve',
            resultingPressureBar: 12,
            resultingMix: _mix(21, 0),
            receiverStartPressureBar: 12,
            receiverEndPressureBar: 12,
          ),
        ],
        cylinder: const CylinderInput(initialPressureBar: 0, volumeL: 12),
        physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
        thermal: const ThermalInput(
          tankMaterial: 'steel',
          coolingMedium: 'air',
          ambientTemperatureC: 20,
          waitMode: 'minutes',
          waitMinutes: 1.6,
          targetTemperatureC: 25,
        ),
        booster: const BoosterSettings(otherDecantRateBarPerMin: 5),
      );

      final thermal = _stepThermal(simulation, 0);
      expect([
        for (final sample in thermal.samples)
          double.parse(sample.elapsedMinutes.toStringAsFixed(3)),
      ], equals([0, 1, 2, 2.4, 3.4, 4]));
      expect(thermal.samples[1].pressureBar, equals(5));
      expect(thermal.samples[2].pressureBar, equals(10));
      expect(
        thermal.samples[3].pressureBar,
        equals(thermal.pressureAtTransferEndReferenceBar),
      );
      expect(
        thermal.samples.last.temperatureC,
        equals(thermal.temperatureAfterWaitC),
      );
      expect(
        thermal.samples.last.pressureBar,
        equals(thermal.pressureAfterWaitBar),
      );
      expect(
        thermal.samples[4].temperatureC,
        lessThan(thermal.samples[3].temperatureC),
      );
      expect(
        thermal.samples[4].pressureBar,
        lessThan(thermal.samples[3].pressureBar),
      );
    },
  );

  test('thermal transfer samples expose pressure projected at each sample temperature', () {
    final simulation = _thermal(
      steps: [
        ProtocolStep(
          type: 'decant',
          operation: 'Decant',
          receiverStartPressureBar: 0,
          receiverEndPressureBar: 95,
          resultingPressureBar: 95,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 0, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        inletTemperatureC: 40,
        waitMode: 'minutes',
        waitMinutes: 0,
      ),
      booster: const BoosterSettings(otherDecantRateBarPerMin: 5),
    );
    final thermal = _stepThermal(simulation, 0);
    expect(
      thermal.samples.every(
        (sample) =>
            sample.projectedPressureBar != null &&
            sample.projectedPressureBar!.isFinite,
      ),
      isTrue,
    );
    final hotSamples = thermal.samples
        .where((sample) => sample.temperatureC > 20)
        .toList();
    expect(hotSamples, isNotEmpty);
    final hotSample = hotSamples.first;
    expect(hotSample.projectedPressureBar!, greaterThan(hotSample.pressureBar));
    expect(
      hotSample.projectedPressureBar! -
          calculatePressureAtTemperature(
            pressureBar: hotSample.ambientPressureBar!,
            oxygenPercent: hotSample.oxygenPercent!,
            heliumPercent: hotSample.heliumPercent!,
            fromTemperatureC: 20,
            toTemperatureC: hotSample.temperatureC,
            volumeL: 12,
            useVdw: false,
          ),
      closeTo(0, 1e-9),
    );
  });

  test('an empty protocol cools the initial tank state to ambient', () {
    final simulation = _thermal(
      steps: const [],
      cylinder: const CylinderInput(
        initialPressureBar: 200,
        initialOxygenPercent: 21,
        initialHeliumPercent: 0,
        volumeL: 12,
      ),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 60),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        waitMode: 'minutes',
        waitMinutes: 10,
        targetTemperatureC: 25,
      ),
    );

    expect(simulation.protocolSteps.length, equals(0));
    expect(simulation.finalSummary.finalTransferEndPressureBar, equals(200));
    expect(simulation.finalSummary.finalTransferEndTemperatureC, equals(60));
    expect(simulation.finalSummary.finalAmbientTemperatureC, equals(20));
    expect(
      simulation.finalSummary.finalAmbientPressureBar,
      closeTo(175.989, 0.01),
    );
  });

  test(
    'projects final gauge pressure across the requested water temperatures',
    () {
      final projections = projectPressureAtTemperatures(
        pressureBar: 200,
        oxygenPercent: 18,
        heliumPercent: 45,
        fromTemperatureC: 20,
        temperaturesC: [6, 8, 10, 12, 20, 22, 24],
        volumeL: 12,
        useVdw: false,
      );

      expect([
        for (final projection in projections) projection.temperatureC,
      ], equals([6, 8, 10, 12, 20, 22, 24]));
      expect(projections[4].pressureBar, closeTo(200, 1e-9));
      expect(projections[0].pressureBar, lessThan(projections[4].pressureBar));
      expect(
        projections[6].pressureBar,
        greaterThan(projections[4].pressureBar),
      );
    },
  );

  test('compare simulation honors an explicit wait instead of configured inter-step wait', () {
    final result = _compare(
      steps: [
        ProtocolStep(
          type: 'keep',
          operation: 'Keep',
          resultingPressureBar: 50,
          resultingMix: _mix(21, 0),
        ),
        ProtocolStep(
          type: 'add',
          method: 'decant',
          operation: 'Decant',
          receiverStartPressureBar: 50,
          receiverEndPressureBar: 100,
          resultingPressureBar: 100,
          resultingMix: _mix(32, 0),
          sourceOxygenPercent: 32,
          sourceHeliumPercent: 0,
        ),
        ProtocolStep(
          type: 'wait',
          operation: 'Wait',
          receiverStartPressureBar: 100,
          receiverEndPressureBar: 100,
          resultingPressureBar: 100,
          resultingMix: _mix(32, 0),
          waitMinutes: 7,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 50, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        inletTemperatureC: 20,
        waitMinutes: 99,
      ),
      booster: const BoosterSettings(
        otherDecantRateBarPerMin: 5,
        drainingRateBarPerMin: 5,
      ),
    );

    expect(result.protocolSteps[2].thermal!.waitMinutes, equals(7));
    expect(
      result.finalSummary.recipeEnd.pressureBar,
      equals(result.protocolSteps.last.thermal!.pressureAfterWaitBar),
    );
    expect(result.finalSummary.ambientSettled.temperatureC, equals(20));
  });

  test('compare simulation maps drain, decant, boost, and compressor transfer rates', () {
    final result = _compare(
      steps: [
        ProtocolStep(
          type: 'drain',
          operation: 'Drain',
          receiverEndPressureBar: 80,
          resultingPressureBar: 80,
          resultingMix: _mix(21, 0),
        ),
        ProtocolStep(
          type: 'add',
          method: 'decant',
          operation: 'Decant',
          receiverEndPressureBar: 100,
          resultingPressureBar: 100,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
        ),
        ProtocolStep(
          type: 'add',
          method: 'boost',
          operation: 'Boost',
          receiverEndPressureBar: 110,
          resultingPressureBar: 110,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
          sourcePressureBar: 250,
        ),
        ProtocolStep(
          type: 'add',
          method: 'compressor',
          operation: 'Compressor',
          receiverEndPressureBar: 120,
          resultingPressureBar: 120,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 100, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 40),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        inletTemperatureC: 20,
      ),
      booster: const BoosterSettings(
        cylinderVolumeCm3: 9,
        otherBoostBpm: 50,
        otherDecantRateBarPerMin: 5,
        drainingRateBarPerMin: 10,
        compressorInletFlowLPerMin: 100,
      ),
    );

    final drain = result.protocolSteps[0].thermal!;
    final decant = result.protocolSteps[1].thermal!;
    final boost = result.protocolSteps[2].thermal!;
    final compressor = result.protocolSteps[3].thermal!;

    expect(drain.rateSource, equals('draining-rate'));
    expect(drain.rateBarPerMin, equals(10));
    expect(drain.temperatureAtTransferEndC, lessThan(drain.temperatureStartC));
    expect(decant.rateSource, equals('decant-rate'));
    expect(decant.rateBarPerMin, equals(5));
    final intermediateBoostSamples = boost.samples
        .where(
          (sample) =>
              sample.elapsedMinutes > 0 &&
              sample.elapsedMinutes < boost.durationMinutes,
        )
        .toList();
    expect(intermediateBoostSamples, isNotEmpty);
    final intermediateBoostSample = intermediateBoostSamples.first;
    expect(
      intermediateBoostSample.pressureBar,
      greaterThan(boost.pressureStartBar),
    );
    expect(
      intermediateBoostSample.pressureBar,
      lessThan(boost.pressureAtTransferEndBar),
    );
    expect(
      boost.rateBarPerMin,
      equals(
        calculateBoosterFillRate(
          cylinderVolumeCm3: 9,
          bpm: 50,
          sourcePressureBar: 250,
          receiverPressureBar:
              (boost.pressureStartBar + boost.pressureAtTransferEndBar) / 2,
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
          receiverOxygenPercent: 21,
          receiverHeliumPercent: 0,
          receiverVolumeL: 12,
          temperatureC: boost.temperatureStartC,
          useVdw: false,
        ).fillRateBarPerMin,
      ),
    );
    expect(compressor.rateSource, equals('compressor'));
    expect(compressor.rateBarPerMin, greaterThan(0));
  });

  test('compare simulation preserves cost operation fields through equalize and compressor rewrites', () {
    final result = _compare(
      steps: [
        ProtocolStep(
          type: 'equalize',
          method: 'decant',
          operation: 'Equalize',
          receiverEndPressureBar: 100,
          resultingPressureBar: 100,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
          costOperation: 'equalize',
          costOperationId: 'op-1',
          sourceConsumedMoles: 0.5,
        ),
        ProtocolStep(
          type: 'add',
          method: 'compressor',
          operation: 'Top-up',
          receiverEndPressureBar: 120,
          resultingPressureBar: 120,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
          costOperation: 'topUp',
          costOperationId: 'op-2',
          sourceConsumedMoles: 0.75,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 80, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 40),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        inletTemperatureC: 20,
      ),
      booster: const BoosterSettings(
        cylinderVolumeCm3: 9,
        otherBoostBpm: 50,
        otherDecantRateBarPerMin: 5,
        drainingRateBarPerMin: 10,
        compressorInletFlowLPerMin: 100,
      ),
    );

    final equalize = result.protocolSteps[0];
    final compressor = result.protocolSteps[1];
    expect(equalize.thermal!.rateSource, equals('decant-rate'));
    expect(equalize.costOperation, equals('equalize'));
    expect(equalize.costOperationId, equals('op-1'));
    expect(equalize.sourceConsumedMoles, equals(0.5));
    expect(compressor.thermal!.rateSource, equals('compressor'));
    expect(compressor.costOperation, equals('topUp'));
    expect(compressor.costOperationId, equals('op-2'));
    expect(compressor.sourceConsumedMoles, equals(0.75));
  });

  test('compare transfer samples retain reference, ambient, and hot endpoint identities', () {
    final result = _compare(
      steps: [
        ProtocolStep(
          type: 'add',
          method: 'compressor',
          operation: 'Top-up',
          receiverStartPressureBar: 0,
          receiverEndPressureBar: 95,
          resultingPressureBar: 95,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 0, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        inletTemperatureC: 40,
        waitMode: 'minutes',
        waitMinutes: 0,
      ),
      booster: const BoosterSettings(compressorInletFlowLPerMin: 100),
    );
    final thermal = result.protocolSteps[0].thermal!;
    expect(thermal.pressureAtTransferEndReferenceBar, lessThan(95));
    expect(thermal.pressureAtTransferEndAmbientBar, lessThan(95));
    expect(thermal.pressureAtTransferEndHotBar, closeTo(95, 1e-6));
    final finalSample = thermal.samples.last;
    expect(
      finalSample.pressureAtTransferEndReferenceBar,
      equals(thermal.pressureAtTransferEndReferenceBar),
    );
    expect(
      finalSample.pressureAtTransferEndAmbientBar,
      equals(thermal.pressureAtTransferEndAmbientBar),
    );
    expect(
      finalSample.pressureAtTransferEndHotBar,
      equals(thermal.pressureAtTransferEndHotBar),
    );
  });

  test('compare simulation keeps a wait at fixed transfer pressure and projects a hot final transfer', () {
    final waitResult = _compare(
      steps: [
        ProtocolStep(
          type: 'wait',
          operation: 'Wait',
          resultingPressureBar: 100,
          resultingMix: _mix(21, 0),
          waitMinutes: 7,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 100, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 40),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
      ),
    );
    final wait = waitResult.protocolSteps[0].thermal!;
    expect(wait.durationMinutes, equals(0));
    expect(wait.pressureAtTransferEndBar, equals(100));
    expect(wait.pressureAfterWaitBar, lessThan(wait.pressureAtTransferEndBar));

    final transferResult = _compare(
      steps: [
        ProtocolStep(
          type: 'add',
          method: 'decant',
          operation: 'Decant',
          receiverEndPressureBar: 100,
          resultingPressureBar: 100,
          resultingMix: _mix(32, 0),
          sourceOxygenPercent: 32,
          sourceHeliumPercent: 0,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 50, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        inletTemperatureC: 20,
        targetInWaterTemperatureC: 10,
      ),
      booster: const BoosterSettings(otherDecantRateBarPerMin: 5),
    );
    final summary = transferResult.finalSummary;
    expect(summary.recipeEnd.temperatureC, greaterThan(20));
    expect(
      summary.ambientSettled.pressureBar,
      lessThan(summary.recipeEnd.pressureBar),
    );
    expect(summary.ambientSettledDurationMinutes, equals(82.8));
    expect(summary.inWater!.temperatureC, equals(10));
    expect(summary.inWater!.pressureBar.isFinite, isTrue);
  });

  test(
    'What-if transfer targets are reached hot and settle below target pressure',
    () {
      final result = _compare(
        steps: [
          ProtocolStep(
            type: 'drain',
            operation: 'Drain',
            receiverEndPressureBar: 0,
            resultingPressureBar: 0,
            resultingMix: _mix(21, 0),
          ),
          ProtocolStep(
            type: 'wait',
            operation: 'Wait',
            resultingPressureBar: 0,
            resultingMix: _mix(21, 0),
            waitMinutes: 5,
          ),
          ProtocolStep(
            type: 'add',
            method: 'decant',
            operation: 'Decant',
            receiverEndPressureBar: 100,
            resultingPressureBar: 100,
            resultingMix: _mix(100, 0),
            sourceOxygenPercent: 100,
            sourceHeliumPercent: 0,
          ),
        ],
        cylinder: const CylinderInput(initialPressureBar: 50, volumeL: 12),
        physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
        thermal: const ThermalInput(
          tankMaterial: 'steel',
          coolingMedium: 'air',
          ambientTemperatureC: 20,
          inletTemperatureC: 20,
        ),
        booster: const BoosterSettings(
          oxygenDecantRateBarPerMin: 5,
          drainingRateBarPerMin: 5,
        ),
      );

      final add = result.protocolSteps.last.thermal!;
      expect(add.pressureAtTransferEndBar, closeTo(100, 1e-6));
      expect(add.pressureAtTransferEndReferenceBar, lessThan(100));
      expect(result.finalSummary.ambientSettled.pressureBar, lessThan(100));
    },
  );

  test(
    'compare simulation maps explicit decant, equalize, and boost stages',
    () {
      final result = _compare(
        steps: [
          ProtocolStep(
            type: 'decant',
            operation: 'Decant',
            receiverStartPressureBar: 50,
            receiverEndPressureBar: 80,
            sourceOxygenPercent: 0,
            sourceHeliumPercent: 100,
            resultingMix: _mix(12, 40),
          ),
          ProtocolStep(
            type: 'equalize',
            operation: 'Equalize',
            receiverStartPressureBar: 80,
            receiverEndPressureBar: 120,
            sourceStartPressureBar: 200,
            sourceEndPressureBar: 120,
            sourceOxygenPercent: 0,
            sourceHeliumPercent: 100,
            resultingMix: _mix(10, 50),
          ),
          ProtocolStep(
            type: 'boost',
            operation: 'Boost',
            receiverStartPressureBar: 120,
            receiverEndPressureBar: 200,
            sourceStartPressureBar: 120,
            sourceEndPressureBar: 80,
            sourceOxygenPercent: 0,
            sourceHeliumPercent: 100,
            resultingMix: _mix(8, 60),
          ),
        ],
        cylinder: const CylinderInput(initialPressureBar: 50, volumeL: 12),
        physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
        thermal: const ThermalInput(
          tankMaterial: 'steel',
          coolingMedium: 'air',
          ambientTemperatureC: 20,
        ),
        booster: const BoosterSettings(
          otherDecantRateBarPerMin: 5,
          otherBoostBpm: 50,
        ),
      );

      expect([
        for (final step in result.protocolSteps) step.type,
      ], equals(['decant', 'equalize', 'boost']));
      expect(
        result.protocolSteps[0].thermal!.rateSource,
        equals('decant-rate'),
      );
      expect(
        result.protocolSteps[1].thermal!.rateSource,
        equals('decant-rate'),
      );
      expect(result.protocolSteps[2].thermal!.rateSource, equals('booster'));
      expect(
        result.protocolSteps.every(
          (step) => step.thermal!.durationMinutes >= 0,
        ),
        isTrue,
      );
    },
  );

  test('compare target wait reaches the requested temperature and projects pressure', () {
    final result = _compare(
      steps: [
        ProtocolStep(
          type: 'wait',
          waitMode: 'target',
          targetTemperatureC: 25,
          receiverStartPressureBar: 100,
          resultingPressureBar: 100,
          resultingMix: _mix(21, 0),
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 100, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 30),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
      ),
    );
    final wait = result.protocolSteps[0];
    expect(wait.thermal!.temperatureAfterWaitC, closeTo(25, 0.05));
    expect(wait.thermal!.pressureAfterWaitBar, closeTo(98.4, 0.2));
  });

  test('compare target wait permits an already reached target temperature', () {
    final result = _compare(
      steps: [
        ProtocolStep(
          type: 'wait',
          waitMode: 'target',
          targetTemperatureC: 30,
          receiverStartPressureBar: 100,
          resultingPressureBar: 100,
          resultingMix: _mix(21, 0),
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 100, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 30),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
      ),
    );

    final wait = result.protocolSteps[0].thermal!;
    expect(wait.waitMinutes, equals(0));
    expect(wait.temperatureAfterWaitC, equals(30));
    expect(wait.pressureAfterWaitBar, closeTo(100, 1e-9));
  });

  test('compare target wait accepts a target equal to ambient', () {
    final result = _compare(
      steps: [
        ProtocolStep(
          type: 'wait',
          waitMode: 'target',
          targetTemperatureC: 20,
          receiverStartPressureBar: 100,
          resultingPressureBar: 100,
          resultingMix: _mix(21, 0),
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 100, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 30),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
      ),
    );
    final wait = result.protocolSteps[0].thermal!;
    expect(wait.temperatureAfterWaitC, equals(20));
    expect(wait.waitMinutes, greaterThan(0));
  });

  test(
    'compare rejects a target temperature that cannot be reached by cooling',
    () {
      expect(
        () => _compare(
          steps: [
            ProtocolStep(
              type: 'wait',
              waitMode: 'target',
              targetTemperatureC: 15,
              receiverStartPressureBar: 100,
              resultingPressureBar: 100,
              resultingMix: _mix(21, 0),
            ),
          ],
          cylinder: const CylinderInput(initialPressureBar: 100, volumeL: 12),
          physics: const PhysicsInput(model: 'ideal', temperatureC: 30),
          thermal: const ThermalInput(
            tankMaterial: 'steel',
            coolingMedium: 'air',
            ambientTemperatureC: 20,
          ),
        ),
        throwsA(
          isA<CompareSimulationError>().having(
            (error) => error.message,
            'message',
            matches(RegExp('target temperature', caseSensitive: false)),
          ),
        ),
      );
    },
  );

  test('optimizer thermal simulation retains its final ambient cool-off', () {
    final simulation = _thermal(
      steps: [
        ProtocolStep(
          type: 'decant',
          operation: 'Decant',
          receiverEndPressureBar: 100,
          resultingPressureBar: 100,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 50, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        waitMinutes: 0,
      ),
      booster: const BoosterSettings(otherDecantRateBarPerMin: 5),
    );

    expect(_stepThermal(simulation, 0).waitMinutes, equals(82.8));
  });

  test('non-final fixed-minute wait equal to ambient keeps duration and cools exponentially', () {
    final simulation = _thermal(
      steps: [
        ProtocolStep(
          type: 'decant',
          operation: 'Decant',
          receiverEndPressureBar: 100,
          resultingPressureBar: 100,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
        ),
        ProtocolStep(
          type: 'decant',
          operation: 'Decant',
          receiverEndPressureBar: 120,
          resultingPressureBar: 120,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 50, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        targetTemperatureC: 20,
        waitMode: 'minutes',
        waitMinutes: 5,
      ),
      booster: const BoosterSettings(otherDecantRateBarPerMin: 5),
    );
    final wait = _stepThermal(simulation, 0);
    expect(wait.waitMinutes, equals(5));
    expect(
      wait.temperatureAtTransferEndC,
      greaterThan(wait.temperatureAfterWaitC),
    );
    expect(wait.temperatureAfterWaitC, greaterThan(20));
    expect(
      wait.temperatureAfterWaitC,
      closeTo(
        calculateTemperatureAfterWait(
          transferEndTemperatureC: wait.temperatureAtTransferEndC,
          ambientTemperatureC: 20,
          waitMinutes: 5,
          tauMinutes: 18,
        ),
        1e-9,
      ),
    );
  });

  test('normal waits converge to ambient for air and water', () {
    for (final coolingMedium in ['air', 'water']) {
      final simulation = _thermal(
        steps: [
          ProtocolStep(
            type: 'decant',
            operation: 'Decant',
            receiverEndPressureBar: 100,
            resultingPressureBar: 100,
            resultingMix: _mix(21, 0),
            sourceOxygenPercent: 21,
            sourceHeliumPercent: 0,
          ),
          ProtocolStep(
            type: 'decant',
            operation: 'Decant',
            receiverEndPressureBar: 120,
            resultingPressureBar: 120,
            resultingMix: _mix(21, 0),
            sourceOxygenPercent: 21,
            sourceHeliumPercent: 0,
          ),
        ],
        cylinder: const CylinderInput(initialPressureBar: 50, volumeL: 12),
        physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
        thermal: ThermalInput(
          tankMaterial: 'steel',
          coolingMedium: coolingMedium,
          ambientTemperatureC: 20,
          targetMediumTemperatureC: 20,
          waitMode: 'temperature',
          waitMinutes: 0,
        ),
        booster: const BoosterSettings(otherDecantRateBarPerMin: 5),
      );
      expect(_stepThermal(simulation, 0).temperatureAfterWaitC, equals(20));
    }
  });

  test('equal target medium and ambient produces finite convergence', () {
    final simulation = _thermal(
      steps: [
        ProtocolStep(
          type: 'decant',
          operation: 'Decant',
          receiverEndPressureBar: 100,
          resultingPressureBar: 100,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
        ),
        ProtocolStep(
          type: 'decant',
          operation: 'Decant',
          receiverEndPressureBar: 120,
          resultingPressureBar: 120,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 50, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        targetMediumTemperatureC: 20,
        waitMode: 'temperature',
      ),
      booster: const BoosterSettings(otherDecantRateBarPerMin: 5),
    );
    expect(_stepThermal(simulation, 0).waitMinutes.isFinite, isTrue);
    expect(_stepThermal(simulation, 0).temperatureAfterWaitC, equals(20));
  });

  test(
    'water submersion options are 20% steps up to 80% with a 60% default',
    () {
      expect(waterSubmersionPercentOptions, equals([20, 40, 60, 80]));
      expect(defaultWaterSubmersionPercent, equals(60));
    },
  );

  test('cooling time constant falls strictly between air and full-water values as submersion grows', () {
    for (final material in ['steel', 'aluminum']) {
      final air = coolingTimeConstantMinutes(material, 'air');
      final fullWater = material == 'steel' ? 3.5 : 5.0;
      var previous = air;
      for (final percent in waterSubmersionPercentOptions) {
        final tau = coolingTimeConstantMinutes(material, 'water', percent);
        expect(
          tau,
          lessThan(previous),
          reason: '$material $percent% must cool faster than the previous step',
        );
        expect(
          tau,
          greaterThan(fullWater),
          reason: '$material $percent% must be slower than full submersion',
        );
        previous = tau;
      }
    }
  });

  test(
    'cooling time constant combines wet and dry conductances in parallel',
    () {
      final expected = 1 / (0.6 / 3.5 + 0.4 / 18);
      expect(
        coolingTimeConstantMinutes('steel', 'water', 60),
        closeTo(expected, 1e-12),
      );
    },
  );

  test('submersion percentage never changes the air path', () {
    final percents = <double?>[20, 60, 80, null];
    for (final percent in percents) {
      expect(coolingTimeConstantMinutes('steel', 'air', percent), equals(18));
      expect(
        coolingTimeConstantMinutes('aluminum', 'air', percent),
        equals(25),
      );
    }
    double transfer(String coolingMedium, double? waterSubmersionPercent) =>
        estimateTransferTemperature(
          startTemperatureC: 20,
          addedPressureBar: 100,
          fillTimeMinutes: 10,
          volumeL: 12,
          heliumFraction: 0,
          tankMaterial: 'steel',
          coolingMedium: coolingMedium,
          waterSubmersionPercent: waterSubmersionPercent,
        );
    expect(transfer('air', 20), equals(transfer('air', 80)));
    expect(transfer('air', 20), equals(transfer('air', null)));
  });

  test('lower submersion leaves the tank hotter after a transfer and monotonic in percentage', () {
    double transfer(double? waterSubmersionPercent) =>
        estimateTransferTemperature(
          startTemperatureC: 20,
          addedPressureBar: 150,
          fillTimeMinutes: 10,
          volumeL: 12,
          heliumFraction: 0,
          tankMaterial: 'steel',
          coolingMedium: 'water',
          waterSubmersionPercent: waterSubmersionPercent,
        );
    final air = estimateTransferTemperature(
      startTemperatureC: 20,
      addedPressureBar: 150,
      fillTimeMinutes: 10,
      volumeL: 12,
      heliumFraction: 0,
      tankMaterial: 'steel',
      coolingMedium: 'air',
    );
    var previous = air;
    for (final percent in waterSubmersionPercentOptions) {
      final end = transfer(percent);
      expect(
        end,
        lessThan(previous),
        reason: '$percent% must end cooler than the previous step',
      );
      previous = end;
    }
    expect(transfer(null), equals(transfer(defaultWaterSubmersionPercent)));
  });

  test('final ambient-settle wait lengthens as submersion drops and uses the parallel time constant', () {
    double settle(double waterSubmersionPercent) => _thermal(
      steps: [
        ProtocolStep(
          type: 'boost',
          operation: 'Boost',
          receiverStartPressureBar: 50,
          receiverEndPressureBar: 150,
          resultingPressureBar: 150,
          resultingMix: _mix(21, 0),
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
          sourcePressureBar: 200,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 50, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      thermal: ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'water',
        waterSubmersionPercent: waterSubmersionPercent,
        ambientTemperatureC: 20,
        inletTemperatureC: 20,
        waitMode: 'minutes',
        waitMinutes: 0,
      ),
      booster: const BoosterSettings(otherBoostBpm: 50),
    ).protocolSteps.last.thermal!.waitMinutes;

    expect(settle(60), greaterThan(settle(80)));
    expect(settle(20), greaterThan(settle(60)));
    expect(
      settle(60),
      closeTo(4.6 * coolingTimeConstantMinutes('steel', 'water', 60), 1e-9),
    );
  });

  test('salvage decant cools the working tank at the decant rate as its pressure falls', () {
    final simulation = _thermal(
      steps: [
        ProtocolStep(
          type: 'salvage',
          stage: 'decant',
          operation: 'Salvage Decant',
          receiverStartPressureBar: 20,
          receiverEndPressureBar: 40,
          receiverVolumeL: 50,
          resultingPressureBar: 50,
          resultingMix: _mix(21, 35),
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 35,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 100, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 40),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        inletTemperatureC: 20,
        waitMode: 'minutes',
        waitMinutes: 0,
        targetTemperatureC: 25,
      ),
      booster: const BoosterSettings(otherDecantRateBarPerMin: 5),
    );

    final thermal = _stepThermal(simulation, 0);
    expect(thermal.rateSource, equals('salvage-decant'));
    expect(thermal.rateBarPerMin, equals(5));
    expect(thermal.durationMinutes, equals(4));
    expect(thermal.pressureAtTransferEndHotBar, lessThan(100));
    expect(
      thermal.temperatureAtTransferEndC,
      lessThan(thermal.temperatureStartC),
    );
  });

  test(
    'salvage booster stage uses the booster fill-rate model and cools the tank',
    () {
      final simulation = _thermal(
        steps: [
          ProtocolStep(
            type: 'salvage',
            stage: 'boost',
            operation: 'Salvage Boost',
            receiverStartPressureBar: 40,
            receiverEndPressureBar: 90,
            receiverVolumeL: 20,
            receiverStartMix: _mix(32, 0),
            resultingPressureBar: 80,
            resultingMix: _mix(21, 35),
            sourceOxygenPercent: 21,
            sourceHeliumPercent: 35,
          ),
        ],
        cylinder: const CylinderInput(initialPressureBar: 200, volumeL: 12),
        physics: const PhysicsInput(model: 'ideal', temperatureC: 40),
        thermal: const ThermalInput(
          tankMaterial: 'steel',
          coolingMedium: 'air',
          ambientTemperatureC: 20,
          inletTemperatureC: 20,
          waitMode: 'minutes',
          waitMinutes: 0,
          targetTemperatureC: 25,
        ),
        booster: const BoosterSettings(
          otherBoostBpm: 60,
          cylinderVolumeCm3: 500,
        ),
      );

      final thermal = _stepThermal(simulation, 0);
      expect(thermal.rateSource, equals('salvage-booster'));
      expect(thermal.durationMinutes, greaterThan(0));
      expect(thermal.pressureAtTransferEndHotBar, lessThan(100));
      expect(
        thermal.temperatureAtTransferEndC,
        lessThan(thermal.temperatureStartC),
      );
    },
  );

  test(
    'salvage booster rate averages the bank rise over the integrated duration',
    () {
      final simulation = _thermal(
        steps: [
          ProtocolStep(
            type: 'salvage',
            stage: 'boost',
            operation: 'Salvage Boost',
            receiverStartPressureBar: 40,
            receiverEndPressureBar: 90,
            receiverVolumeL: 20,
            receiverStartMix: _mix(32, 0),
            resultingPressureBar: 80,
            resultingMix: _mix(21, 35),
            sourceOxygenPercent: 21,
            sourceHeliumPercent: 35,
          ),
        ],
        cylinder: const CylinderInput(initialPressureBar: 200, volumeL: 12),
        physics: const PhysicsInput(model: 'ideal', temperatureC: 40),
        thermal: const ThermalInput(
          tankMaterial: 'steel',
          coolingMedium: 'air',
          ambientTemperatureC: 20,
          inletTemperatureC: 20,
          waitMode: 'minutes',
          waitMinutes: 0,
          targetTemperatureC: 25,
        ),
        booster: const BoosterSettings(
          otherBoostBpm: 60,
          cylinderVolumeCm3: 500,
        ),
      );

      final thermal = _stepThermal(simulation, 0);
      expect(thermal.rateSource, equals('salvage-booster'));
      expect(thermal.durationMinutes, greaterThan(0));
      expect(
        thermal.rateBarPerMin! * thermal.durationMinutes,
        closeTo(50, 1e-6),
      );
    },
  );

  test('booster midpoint rate moves within 3.5% of the real-gas receiver moles over a 40-90 bar van der Waals rise', () {
    // The rate is evaluated at midpoint pressures, so the moles check is approximate under van der Waals.
    final rate = calculateBoosterFillRate(
      cylinderVolumeCm3: 500,
      bpm: 60,
      sourcePressureBar: (150 + 100) / 2,
      receiverPressureBar: (40 + 90) / 2,
      sourceOxygenPercent: 21,
      sourceHeliumPercent: 35,
      receiverOxygenPercent: 32,
      receiverHeliumPercent: 0,
      receiverVolumeL: 50,
      temperatureC: 20,
      useVdw: true,
    );
    final durationMinutes = (90 - 40) / rate.fillRateBarPerMin;
    final boosterMoles = rate.molesPerMin * durationMinutes;
    final bankMoles =
        (calcMolarDensity(90, 32, 0, 20, true) -
            calcMolarDensity(40, 32, 0, 20, true)) *
        50;
    expect((boosterMoles / bankMoles - 1).abs(), lessThan(0.035));
  });

  test(
    'a profiled booster transfer reports the integrated duration and rate',
    () {
      final simulation = _profiledBoosterSimulation(sourceStartMoles: 100);
      final step = _stepThermal(simulation, 0);
      expect(step.rateSource, equals('booster'));
      expect(step.durationMinutes, greaterThan(0));
      expect(step.rateBarPerMin! * step.durationMinutes, closeTo(100, 1e-6));
    },
  );

  test('a closed-form decant step keeps dP / rate', () {
    final simulation = _thermal(
      steps: [
        const ProtocolStep(
          type: 'decant',
          operation: 'Decant',
          resultingPressureBar: 150,
          resultingMix: GasMixPercent(oxygenPercent: 21, heliumPercent: 0),
          receiverStartPressureBar: 50,
          receiverEndPressureBar: 150,
          sourceStartPressureBar: 200,
          sourceEndPressureBar: 150,
          sourceOxygenPercent: 21,
          sourceHeliumPercent: 0,
        ),
      ],
      cylinder: const CylinderInput(initialPressureBar: 50, volumeL: 12),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      thermal: const ThermalInput(
        tankMaterial: 'steel',
        coolingMedium: 'air',
        ambientTemperatureC: 20,
        inletTemperatureC: 20,
        waitMode: 'minutes',
        waitMinutes: 0,
        targetTemperatureC: 25,
        tankMassKg: 10,
      ),
    );
    final step = _stepThermal(simulation, 0);
    expect(step.rateSource, equals('decant-rate'));
    expect(step.durationMinutes, closeTo(100 / step.rateBarPerMin!, 1e-9));
  });

  test(
    'a profiled transfer that stalls surfaces TRANSFER_PROFILE_UNSATISFIED',
    () {
      expect(
        () => _profiledBoosterSimulation(sourceStartMoles: 0.0001),
        throwsA(
          isA<TransferProfileException>().having(
            (e) => e.code,
            'code',
            'TRANSFER_PROFILE_UNSATISFIED',
          ),
        ),
      );
    },
  );
}

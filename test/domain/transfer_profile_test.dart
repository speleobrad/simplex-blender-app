import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

/// Booster-type transfer. `currentPressureBar` is the cylinder pressure the
/// step starts from: the receiver for booster steps (JS `startPressureBar`) and
/// the drained tank for salvage-booster steps. The booster source tank is held
/// at 200 bar for the fill rate. Pass `null` for the inventory fields to model
/// a step with no source inventory.
TransferProfileInput profileInput({
  String rateSource = 'booster',
  double currentPressureBar = 50,
  double transferEndPressureBar = 150,
  double pressureIncreaseBar = 100,
  double? sourceVolumeL = 12,
  double? sourceStartMoles = 100,
}) {
  final rate = calculateBoosterFillRate(
    cylinderVolumeCm3: 9,
    bpm: 50,
    sourcePressureBar: 200,
    receiverPressureBar: 50,
    sourceOxygenPercent: 21,
    sourceHeliumPercent: 0,
    receiverOxygenPercent: 21,
    receiverHeliumPercent: 0,
    receiverVolumeL: 12,
    temperatureC: 20,
    useVdw: false,
  );
  return TransferProfileInput(
    step: ProtocolStep(
      type: 'boost',
      operation: 'Boost',
      receiverStartPressureBar: 50,
      receiverEndPressureBar: transferEndPressureBar,
      resultingPressureBar: transferEndPressureBar,
      resultingMix: const GasMixPercent(oxygenPercent: 21, heliumPercent: 0),
      receiverVolumeL: 12,
      sourceOxygenPercent: 21,
      sourceHeliumPercent: 0,
      sourceVolumeL: sourceVolumeL,
      sourceStartMoles: sourceStartMoles,
    ),
    transfer: TransferRate(
      rateSource: rateSource,
      rateBarPerMin: rate.fillRateBarPerMin,
      pressureIncreaseBar: pressureIncreaseBar,
    ),
    currentPressureBar: currentPressureBar,
    currentTemperatureC: 20,
    transferEndPressureBar: transferEndPressureBar,
    currentMix: const GasMixPercent(oxygenPercent: 21, heliumPercent: 0),
    receiverMix: const GasMixPercent(oxygenPercent: 21, heliumPercent: 0),
    cylinder: const CylinderInput(initialPressureBar: 50, volumeL: 12),
    physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
    thermal: const ThermalInput(
      ambientTemperatureC: 20,
      tankMaterial: 'steel',
      coolingMedium: 'air',
      inletTemperatureC: 20,
    ),
    booster: const BoosterSettings(
      cylinderVolumeCm3: 9,
      oxygenBoostBpm: 50,
      otherBoostBpm: 50,
    ),
    inletTemperatureC: 20,
  );
}

void main() {
  test('integrated booster duration reaches the end pressure', () {
    final result = solveTransferProfile(profileInput())!;
    expect(result.reachedEndPressure, isTrue);
    expect(result.converged, isTrue);
    expect(result.profileSamples.last.pressureBar, closeTo(150, 0.5));
  });

  test('profile samples start at zero and never move backward in time', () {
    final samples = solveTransferProfile(profileInput())!.profileSamples;
    expect(samples.first.elapsedMinutes, 0);
    for (var i = 1; i < samples.length; i++) {
      expect(
        samples[i].elapsedMinutes,
        greaterThanOrEqualTo(samples[i - 1].elapsedMinutes),
      );
    }
  });

  test('a source that cannot supply the end pressure throws', () {
    // 0.0001 mol is far below what 150 bar needs, so the booster source runs out early.
    // Same exhaustion path as JS integrateTransferRateProfile: reachedEndPressure is false once the source runs out.
    expect(
      () => solveTransferProfile(profileInput(sourceStartMoles: 0.0001)),
      throwsA(
        isA<TransferProfileException>().having(
          (e) => e.code,
          'code',
          'TRANSFER_PROFILE_UNSATISFIED',
        ),
      ),
    );
  });

  test('a booster step without source inventory returns null', () {
    expect(
      solveTransferProfile(
        profileInput(sourceVolumeL: null, sourceStartMoles: null),
      ),
      isNull,
    );
  });

  test('decant, draining, and salvage-decant return null', () {
    for (final source in ['decant-rate', 'draining-rate', 'salvage-decant']) {
      expect(solveTransferProfile(profileInput(rateSource: source)), isNull);
    }
  });

  test('a repeated solve returns the same duration; errors are not cached', () {
    final first = solveTransferProfile(profileInput())!;
    final second = solveTransferProfile(profileInput())!;
    expect(second.durationMinutes, first.durationMinutes);
    for (var attempt = 0; attempt < 2; attempt++) {
      expect(
        () => solveTransferProfile(profileInput(sourceStartMoles: 0.0001)),
        throwsA(isA<TransferProfileException>()),
      );
    }
  });

  test('salvage-booster profile ends at the planner tank endpoint', () {
    final result = solveTransferProfile(
      profileInput(
        rateSource: 'salvage-booster',
        currentPressureBar: 200,
        transferEndPressureBar: 120,
        pressureIncreaseBar: 100,
      ),
    )!;
    expect(result.reachedEndPressure, isTrue);
    expect(result.profileSamples.last.pressureBar, closeTo(120, 0.5));
  });
}

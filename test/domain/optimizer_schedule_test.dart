import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/optimizer.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

void main() {
  final stallingSteps = <ProtocolStep>[
    const ProtocolStep(
      type: 'salvage',
      stage: 'boost',
      operation: 'Salvage Boost',
      receiverStartPressureBar: 40,
      receiverEndPressureBar: 90,
      receiverVolumeL: 50,
      receiverStartMix: GasMixPercent(oxygenPercent: 32, heliumPercent: 0),
      resultingPressureBar: 80,
      resultingMix: GasMixPercent(oxygenPercent: 21, heliumPercent: 35),
      sourceOxygenPercent: 21,
      sourceHeliumPercent: 35,
    ),
  ];
  const cylinder = <String, Object?>{
    'volumeL': 12,
    'initialPressureBar': 100,
    'workingPressureBar': 200,
  };
  const physics = PhysicsInput(model: 'ideal', temperatureC: 40);
  const thermal = ThermalInput(
    ambientTemperatureC: 20,
    tankMaterial: 'steel',
    coolingMedium: 'air',
    inletTemperatureC: 40,
    targetMediumTemperatureC: 20,
    waitMode: 'minutes',
    waitMinutes: 0,
  );
  const settings = BlendSettings(
    booster: BlendBooster(
      otherBoostBpm: 60,
      cylinderVolumeCm3: 500,
      maxCompressorPressureBar: 232,
    ),
  );

  test('candidate scheduling rejects a transfer profile the source cannot supply instead of throwing', () {
    expect(
      () => scheduleSafeThermalProtocol(
        protocolSteps: stallingSteps,
        thermal: thermal,
        cylinder: cylinder,
        physics: physics,
        settings: settings,
      ),
      throwsA(
        isA<TransferProfileException>().having(
          (error) => error.code,
          'code',
          'TRANSFER_PROFILE_UNSATISFIED',
        ),
      ),
    );

    final scheduled = scheduleCandidateProtocol(
      protocolSteps: stallingSteps,
      thermal: thermal,
      cylinder: cylinder,
      physics: physics,
      settings: settings,
    );
    expect(scheduled['unsafe'], isTrue);
    expect(scheduled['simulation'], isNull);
  });

  test('candidate scheduling rethrows errors that are not transfer profile failures', () {
    const invalidCylinder = <String, Object?>{
      'volumeL': 12,
      'initialPressureBar': 100,
      'workingPressureBar': 200,
      'hotOverfillPercent': 1.2,
    };
    expect(
      () => scheduleCandidateProtocol(
        protocolSteps: const <ProtocolStep>[],
        thermal: thermal,
        cylinder: invalidCylinder,
        physics: physics,
        settings: settings,
      ),
      throwsA(isA<RangeError>()),
    );
  });
}

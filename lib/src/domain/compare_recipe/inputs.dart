part of '../compare_recipe.dart';

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

/// Booster and compressor settings read by Compare. Null fields fall back to
/// the same defaults the JS uses for non-finite values.
class CompareBoosterSettings {
  const CompareBoosterSettings({
    this.minimumSourcePressureBar,
    this.maxCompressorPressureBar,
    this.maxBoosterOutputPressureBar,
    this.oxygenDecantRateBarPerMin,
    this.otherDecantRateBarPerMin,
    this.cylinderVolumeCm3,
    this.oxygenBoostBpm,
    this.otherBoostBpm,
  });

  final double? minimumSourcePressureBar;
  final double? maxCompressorPressureBar;
  final double? maxBoosterOutputPressureBar;
  final double? oxygenDecantRateBarPerMin;
  final double? otherDecantRateBarPerMin;
  final double? cylinderVolumeCm3;
  final double? oxygenBoostBpm;
  final double? otherBoostBpm;
}

class CompareSettings {
  const CompareSettings({this.booster, this.pressureLimitMode});

  final CompareBoosterSettings? booster;
  final String? pressureLimitMode;
}

class CompareCylinder {
  const CompareCylinder({
    required this.volumeL,
    this.workingPressureBar,
    this.initialPressureBar,
    required this.initialOxygenPercent,
    required this.initialHeliumPercent,
  });

  final double volumeL;
  final double? workingPressureBar;
  final double? initialPressureBar;
  final double initialOxygenPercent;
  final double initialHeliumPercent;
}

/// Modeled state of the receiver at the end of a wait row.
class CompareWaitState {
  const CompareWaitState({
    required this.pressureBar,
    this.temperatureC,
    this.totalMoles,
    this.oxygenMoles,
    this.heliumMoles,
    this.mix,
  });

  final double pressureBar;
  final double? temperatureC;
  final double? totalMoles;
  final double? oxygenMoles;
  final double? heliumMoles;
  final GasMixPercent? mix;
}

class CompareRow {
  const CompareRow({
    required this.id,
    required this.type,
    this.bankId,
    this.pressureAddedBar,
    this.targetPressureBar,
    this.pressureInputMode,
    this.waitMode,
    this.waitMinutes,
    this.targetTemperatureC,
    this.sourceBank,
  });

  final String id;
  final String type;
  final String? bankId;
  final double? pressureAddedBar;
  final double? targetPressureBar;
  final String? pressureInputMode;
  final String? waitMode;
  final double? waitMinutes;
  final double? targetTemperatureC;
  final Bank? sourceBank;

  CompareRow copyWith({
    double? pressureAddedBar,
    double? targetPressureBar,
    Bank? sourceBank,
  }) {
    return CompareRow(
      id: id,
      type: type,
      bankId: bankId,
      pressureAddedBar: pressureAddedBar ?? this.pressureAddedBar,
      targetPressureBar: targetPressureBar ?? this.targetPressureBar,
      pressureInputMode: pressureInputMode,
      waitMode: waitMode,
      waitMinutes: waitMinutes,
      targetTemperatureC: targetTemperatureC,
      sourceBank: sourceBank ?? this.sourceBank,
    );
  }
}

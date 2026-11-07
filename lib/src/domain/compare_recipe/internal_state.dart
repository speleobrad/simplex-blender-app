part of '../compare_recipe.dart';

// ---------------------------------------------------------------------------
// Internal state
// ---------------------------------------------------------------------------

class _Limits {
  const _Limits({
    required this.minimumSourcePressureBar,
    required this.maxBoosterOutputPressureBar,
    required this.oxygenDecantRateBarPerMin,
    required this.otherDecantRateBarPerMin,
    required this.cylinderVolumeCm3,
    required this.oxygenBoostBpm,
    required this.otherBoostBpm,
  });

  final double minimumSourcePressureBar;
  final double maxBoosterOutputPressureBar;
  final double oxygenDecantRateBarPerMin;
  final double otherDecantRateBarPerMin;
  final double cylinderVolumeCm3;
  final double oxygenBoostBpm;
  final double otherBoostBpm;
}

class _Receiver {
  const _Receiver({
    required this.totalMoles,
    required this.oxygenMoles,
    required this.heliumMoles,
    required this.mix,
    required this.pressureBar,
    this.temperatureC,
  });

  final double totalMoles;
  final double oxygenMoles;
  final double heliumMoles;
  final GasMixPercent mix;
  final double pressureBar;
  final double? temperatureC;

  _Receiver withPressureBar(double value) {
    return _Receiver(
      totalMoles: totalMoles,
      oxygenMoles: oxygenMoles,
      heliumMoles: heliumMoles,
      mix: mix,
      pressureBar: value,
      temperatureC: temperatureC,
    );
  }
}

class _BankIndex {
  const _BankIndex({required this.byId, required this.duplicateIds});

  final Map<String, Bank> byId;
  final Set<String> duplicateIds;
}

class _BankState {
  _BankState({required this.bank, required this.moles});

  final Bank bank;
  double moles;
}

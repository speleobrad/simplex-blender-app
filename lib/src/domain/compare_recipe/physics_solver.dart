part of '../compare_recipe.dart';

GasMixPercent _mixFromMoles(
  double totalMoles,
  double oxygenMoles,
  double heliumMoles,
) {
  if (totalMoles <= 0) {
    return const GasMixPercent(oxygenPercent: 0, heliumPercent: 0);
  }
  return GasMixPercent(
    oxygenPercent: (oxygenMoles / totalMoles) * 100,
    heliumPercent: (heliumMoles / totalMoles) * 100,
  );
}

CompareTrajectoryPoint _trajectoryPoint({
  required int step,
  required String label,
  required GasMixPercent mix,
  required double pressureBar,
  required double pressureDeltaBar,
  required String color,
}) {
  return CompareTrajectoryPoint(
    step: step,
    label: label,
    oxygenPercent: mix.oxygenPercent,
    heliumPercent: mix.heliumPercent,
    nitrogenPercent: math.max(
      0.0,
      100.0 - mix.oxygenPercent - mix.heliumPercent,
    ),
    pressureBar: pressureBar,
    pressureDeltaBar: pressureDeltaBar,
    color: color,
  );
}

double _receiverTemperature(_Receiver receiver, double temperatureC) {
  final receiverC = receiver.temperatureC;
  return receiverC != null && receiverC.isFinite ? receiverC : temperatureC;
}

_Receiver _receiverAfterAddedMoles(
  _Receiver receiver,
  double addedMoles,
  Bank sourceBank,
  double volumeL,
  double temperatureC,
  bool useVdw,
) {
  final receiverTemperatureC = _receiverTemperature(receiver, temperatureC);
  final totalMoles = receiver.totalMoles + addedMoles;
  final oxygenMoles =
      receiver.oxygenMoles + addedMoles * (sourceBank.oxygenPercent / 100);
  final heliumMoles =
      receiver.heliumMoles + addedMoles * (sourceBank.heliumPercent / 100);
  final mix = _mixFromMoles(totalMoles, oxygenMoles, heliumMoles);
  final pressureBar = calcPressure(
    totalMoles / volumeL,
    mix.oxygenPercent,
    mix.heliumPercent,
    receiverTemperatureC,
    useVdw,
  );
  return _Receiver(
    totalMoles: totalMoles,
    oxygenMoles: oxygenMoles,
    heliumMoles: heliumMoles,
    mix: mix,
    pressureBar: pressureBar,
    temperatureC: receiverTemperatureC,
  );
}

double _pressureForSourceMoles(
  double moles,
  Bank bank,
  double temperatureC,
  bool useVdw,
) {
  return calcPressure(
    math.max(0.0, moles) / bank.volumeL,
    bank.oxygenPercent,
    bank.heliumPercent,
    temperatureC,
    useVdw,
  );
}

double _solveAddedMoles(
  _Receiver receiver,
  double targetPressureBar,
  Bank bank,
  double volumeL,
  double temperatureC,
  bool useVdw,
) {
  if (targetPressureBar <= receiver.pressureBar + PRESSURE_TOLERANCE_BAR) {
    return 0;
  }
  final receiverTemperatureC = _receiverTemperature(receiver, temperatureC);
  var high = math.max(
    1.0,
    calcMolarDensity(
          targetPressureBar,
          bank.oxygenPercent,
          bank.heliumPercent,
          receiverTemperatureC,
          useVdw,
        ) *
        volumeL,
  );
  var highState = _receiverAfterAddedMoles(
    receiver,
    high,
    bank,
    volumeL,
    temperatureC,
    useVdw,
  );
  while (highState.pressureBar < targetPressureBar && high < 1e9) {
    high *= 2;
    highState = _receiverAfterAddedMoles(
      receiver,
      high,
      bank,
      volumeL,
      temperatureC,
      useVdw,
    );
  }
  if (highState.pressureBar < targetPressureBar) {
    throw RangeError(
      'Supply bank transfer cannot reach the requested receiver pressure.',
    );
  }
  var low = 0.0;
  for (var iteration = 0; iteration < 80; iteration++) {
    final middle = (low + high) / 2;
    final pressure = _receiverAfterAddedMoles(
      receiver,
      middle,
      bank,
      volumeL,
      temperatureC,
      useVdw,
    ).pressureBar;
    if (pressure < targetPressureBar) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return (low + high) / 2;
}

double _solveEqualizationMoles(
  _Receiver receiver,
  double sourceMoles,
  double requiredMoles,
  Bank bank,
  double volumeL,
  double temperatureC,
  bool useVdw,
) {
  var low = 0.0;
  var high = requiredMoles;
  for (var iteration = 0; iteration < 80; iteration++) {
    final middle = (low + high) / 2;
    final receiverPressure = _receiverAfterAddedMoles(
      receiver,
      middle,
      bank,
      volumeL,
      temperatureC,
      useVdw,
    ).pressureBar;
    final sourcePressure = _pressureForSourceMoles(
      sourceMoles - middle,
      bank,
      temperatureC,
      useVdw,
    );
    if (sourcePressure > receiverPressure) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return (low + high) / 2;
}

CompareSourceState _sourceState(
  Bank bank,
  double moles,
  double temperatureC,
  bool useVdw,
) {
  return CompareSourceState(
    bankId: bank.id,
    name: bank.name,
    volumeL: bank.volumeL,
    pressureBar: _pressureForSourceMoles(moles, bank, temperatureC, useVdw),
    moles: moles,
    oxygenPercent: bank.oxygenPercent,
    heliumPercent: bank.heliumPercent,
  );
}

CompareSourceSnapshot _sourceSummaryState(CompareSourceState state) {
  return CompareSourceSnapshot(
    pressureBar: state.pressureBar,
    moles: state.moles,
    oxygenPercent: state.oxygenPercent,
    heliumPercent: state.heliumPercent,
  );
}

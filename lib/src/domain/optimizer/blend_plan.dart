part of '../optimizer.dart';

// Port of js/optimizer.js 1008–1290: compressor air, boost ordering, and
// pressure-transfer staging. Helpers for the safety checks live in
// blend_safety.dart.

/// JS `Math.max` with NaN propagation.
double _jsMathMax(double a, double b) {
  if (a.isNaN || b.isNaN) {
    return double.nan;
  }
  return a > b ? a : b;
}

/// JS `Math.min` with NaN propagation.
double _jsMathMin(double a, double b) {
  if (a.isNaN || b.isNaN) {
    return double.nan;
  }
  return a < b ? a : b;
}

/// JS `x || 0` for a number that may be missing or NaN.
double _jsOrZero(double? value) {
  if (value == null || value.isNaN || value == 0) {
    return 0.0;
  }
  return value;
}

/// Approximates JS `localeCompare` for the ids and names this port compares.
int _jsLocaleCompare(String a, String b) {
  return a.compareTo(b);
}

/// JS `boostPriority`: ordering rank of a bank's gas in a boost.
int _boostPriority(Bank bank) {
  if (bank.heliumPercent > 0 && bank.oxygenPercent > 0) {
    return 1;
  }
  if (bank.heliumPercent == 100) {
    return 2;
  }
  if (bank.oxygenPercent == 100) {
    return 3;
  }
  if (bank.oxygenPercent == 21 && bank.heliumPercent == 0) {
    return 4;
  }
  return 2;
}

/// JS `compressorAirBank`: the implicit compressor supply bank.
Bank _compressorAirBank(double maxPressureBar) {
  return Bank(
    id: COMPRESSOR_AIR_ID,
    name: 'Compressor Air',
    volumeL: 1.0,
    pressureBar: maxPressureBar,
    oxygenPercent: 21.0,
    heliumPercent: 0.0,
    enabled: true,
    isCompressor: true,
  );
}

class _ActiveBoost {
  const _ActiveBoost({
    required this.bank,
    required this.addedMoles,
    required this.priority,
    required this.cascade,
    required this.index,
  });

  final Bank bank;
  final double addedMoles;
  final int priority;
  final bool cascade;
  final int index;
}

/// JS `compareActiveBoosts`.
int _compareActiveBoosts(
  _ActiveBoost a,
  _ActiveBoost b, {
  bool airFirst = false,
}) {
  final airOrder = (_isAirBank(a.bank) ? 1 : 0) - (_isAirBank(b.bank) ? 1 : 0);
  final orderedAir = airFirst ? -airOrder : airOrder;
  if (orderedAir != 0) {
    return orderedAir;
  }
  final oxygenOrder = b.bank.oxygenPercent - a.bank.oxygenPercent;
  if (oxygenOrder != 0) {
    return oxygenOrder < 0 ? -1 : 1;
  }
  if (a.priority != b.priority) {
    return a.priority - b.priority;
  }
  final cascadeOrder = (b.cascade ? 1 : 0) - (a.cascade ? 1 : 0);
  if (cascadeOrder != 0) {
    return cascadeOrder;
  }
  final keyOrder = _jsLocaleCompare(
    _cascadeCompositionKey(a.bank),
    _cascadeCompositionKey(b.bank),
  );
  if (keyOrder != 0) {
    return keyOrder;
  }
  if (a.cascade && b.cascade) {
    final pressureOrder = a.bank.pressureBar - b.bank.pressureBar;
    if (pressureOrder != 0) {
      return pressureOrder < 0 ? -1 : 1;
    }
  }
  final molesOrder = b.addedMoles - a.addedMoles;
  if (molesOrder != 0) {
    return molesOrder < 0 ? -1 : 1;
  }
  final idOrder = _jsLocaleCompare(a.bank.id, b.bank.id);
  if (idOrder != 0) {
    return idOrder;
  }
  final nameOrder = _jsLocaleCompare(a.bank.name, b.bank.name);
  if (nameOrder != 0) {
    return nameOrder;
  }
  return a.index - b.index;
}

/// JS `activeBoostsFor`: positive boosts sorted into transfer order.
List<_ActiveBoost> _activeBoostsFor(
  _LinearProgramResult solverResult,
  List<Bank> activeBanks, {
  bool airFirst = false,
}) {
  final boosts = <_ActiveBoost>[];
  final compositionCounts = _cascadeGroups(activeBanks);
  for (var index = 0; index < activeBanks.length; index++) {
    final bank = activeBanks[index];
    final variableName = solverResult.variableNames[index + 1];
    final addedMoles = _jsOrZero(solverResult.solution?[variableName]);
    if (addedMoles <= 1e-9) {
      continue;
    }
    final cascade =
        !_isAirBank(bank) &&
        (compositionCounts[_cascadeCompositionKey(bank)] ?? 0) > 1;
    boosts.add(
      _ActiveBoost(
        bank: bank,
        addedMoles: addedMoles,
        priority: _boostPriority(bank),
        cascade: cascade,
        index: index,
      ),
    );
  }
  boosts.sort((a, b) => _compareActiveBoosts(a, b, airFirst: airFirst));
  return boosts;
}

class _PressureTransferStage {
  const _PressureTransferStage({
    required this.type,
    required this.startFraction,
    required this.endFraction,
    required this.sourceStartPressureBar,
    required this.sourceEndPressureBar,
    required this.receiverStartPressureBar,
    required this.receiverEndPressureBar,
  });

  final String type;
  final double startFraction;
  final double endFraction;
  final double sourceStartPressureBar;
  final double sourceEndPressureBar;
  final double receiverStartPressureBar;
  final double receiverEndPressureBar;
}

/// JS `protocolOperation`: operator-facing label for a transfer stage.
String _protocolOperation(
  _PressureTransferStage stage,
  Bank bank, {
  bool cascade = false,
}) {
  if (_isAirBank(bank)) {
    return 'Top-up';
  }
  final tolerance =
      _jsMathMax(
        1e-9,
        _jsMathMax(
          stage.sourceStartPressureBar,
          _jsMathMax(
            stage.receiverStartPressureBar,
            _jsMathMax(
              stage.sourceEndPressureBar,
              stage.receiverEndPressureBar,
            ),
          ),
        ),
      ) *
      1e-9;
  final startsHigher =
      stage.sourceStartPressureBar > stage.receiverStartPressureBar + tolerance;
  final startsEqual =
      (stage.sourceStartPressureBar - stage.receiverStartPressureBar).abs() <=
      tolerance;
  final endsEqual =
      (stage.sourceEndPressureBar - stage.receiverEndPressureBar).abs() <=
      tolerance;
  if (startsHigher && endsEqual) {
    return cascade ? 'Cascade equalize' : 'Equalize';
  }
  if ((stage.type == 'decant' && startsEqual) ||
      (stage.sourceStartPressureBar >
              stage.receiverStartPressureBar + tolerance &&
          stage.sourceEndPressureBar >=
              stage.receiverEndPressureBar - tolerance)) {
    return 'Decant';
  }
  return cascade ? 'Cascade boost' : 'Boost';
}

/// JS `sourceResidualPressureAfterTransfer`.
double _sourceResidualPressureAfterTransfer(
  Bank bank,
  double addedMoles,
  Map<String, double> bankDensityByBankId,
  double temperatureC,
  bool useVdw,
) {
  if (_isAirBank(bank)) {
    return bank.pressureBar;
  }
  final residualDensity = _jsMathMax(
    0.0,
    (bankDensityByBankId[bank.id] ?? double.nan) - addedMoles / bank.volumeL,
  );
  return calcPressure(
    residualDensity,
    bank.oxygenPercent,
    bank.heliumPercent,
    temperatureC,
    useVdw,
  );
}

/// JS `receiverPressureAfterTransfer`.
double _receiverPressureAfterTransfer({
  required double cumulativeMoles,
  required double cumulativeOxygenMoles,
  required double cumulativeHeliumMoles,
  required double addedMoles,
  required Bank bank,
  required double fraction,
  required double volumeL,
  required double temperatureC,
  required bool useVdw,
}) {
  final transferredMoles = addedMoles * fraction;
  final totalMoles = cumulativeMoles + transferredMoles;
  if (totalMoles <= 1e-12) {
    return 0.0;
  }
  return calcPressure(
    totalMoles / volumeL,
    ((cumulativeOxygenMoles + transferredMoles * (bank.oxygenPercent / 100)) /
            totalMoles) *
        100,
    ((cumulativeHeliumMoles + transferredMoles * (bank.heliumPercent / 100)) /
            totalMoles) *
        100,
    temperatureC,
    useVdw,
  );
}

class _TransferPressures {
  const _TransferPressures({
    required this.sourcePressure,
    required this.receiverPressure,
  });

  final double sourcePressure;
  final double receiverPressure;
}

/// JS `pressureTransferStages`: splits one boost into decant/boost stages.
List<_PressureTransferStage> _pressureTransferStages({
  required double cumulativeMoles,
  required double cumulativeOxygenMoles,
  required double cumulativeHeliumMoles,
  required double addedMoles,
  required Bank bank,
  required Map<String, double> bankDensityByBankId,
  required double volumeL,
  required double temperatureC,
  required bool useVdw,
  bool airTopUp = false,
}) {
  _TransferPressures pressureAt(double fraction) {
    return _TransferPressures(
      sourcePressure: _sourceResidualPressureAfterTransfer(
        bank,
        addedMoles * fraction,
        bankDensityByBankId,
        temperatureC,
        useVdw,
      ),
      receiverPressure: _receiverPressureAfterTransfer(
        cumulativeMoles: cumulativeMoles,
        cumulativeOxygenMoles: cumulativeOxygenMoles,
        cumulativeHeliumMoles: cumulativeHeliumMoles,
        addedMoles: addedMoles,
        bank: bank,
        fraction: fraction,
        volumeL: volumeL,
        temperatureC: temperatureC,
        useVdw: useVdw,
      ),
    );
  }

  if (airTopUp) {
    final start = pressureAt(0.0);
    final end = pressureAt(1.0);
    return <_PressureTransferStage>[
      _PressureTransferStage(
        type: 'boost',
        startFraction: 0.0,
        endFraction: 1.0,
        sourceStartPressureBar: start.sourcePressure,
        sourceEndPressureBar: end.sourcePressure,
        receiverStartPressureBar: start.receiverPressure,
        receiverEndPressureBar: end.receiverPressure,
      ),
    ];
  }

  final start = pressureAt(0.0);
  final end = pressureAt(1.0);
  final pressureTolerance = _jsMathMax(
    1e-9,
    _jsMathMax(
          _jsMathMax(start.sourcePressure, start.receiverPressure),
          _jsMathMax(end.sourcePressure, end.receiverPressure),
        ) *
        1e-9,
  );
  final sourcePressureDifferenceAtStart =
      start.sourcePressure - start.receiverPressure;
  final sourceNotLowerAtStart =
      sourcePressureDifferenceAtStart >= -pressureTolerance;
  final sourceHigherAtStart =
      sourcePressureDifferenceAtStart > pressureTolerance;
  final sourceLowerAtEnd =
      end.sourcePressure - end.receiverPressure < -pressureTolerance;

  if (!sourceHigherAtStart || !sourceLowerAtEnd) {
    return <_PressureTransferStage>[
      _PressureTransferStage(
        type: sourceNotLowerAtStart ? 'decant' : 'boost',
        startFraction: 0.0,
        endFraction: 1.0,
        sourceStartPressureBar: start.sourcePressure,
        sourceEndPressureBar: end.sourcePressure,
        receiverStartPressureBar: start.receiverPressure,
        receiverEndPressureBar: end.receiverPressure,
      ),
    ];
  }

  var lowerFraction = 0.0;
  var upperFraction = 1.0;
  for (var iteration = 0; iteration < 60; iteration++) {
    final middleFraction = (lowerFraction + upperFraction) / 2;
    final middle = pressureAt(middleFraction);
    if (middle.sourcePressure > middle.receiverPressure) {
      lowerFraction = middleFraction;
    } else {
      upperFraction = middleFraction;
    }
  }
  final equilibriumFraction = (lowerFraction + upperFraction) / 2;
  final equilibrium = pressureAt(equilibriumFraction);
  return <_PressureTransferStage>[
    _PressureTransferStage(
      type: 'decant',
      startFraction: 0.0,
      endFraction: equilibriumFraction,
      sourceStartPressureBar: start.sourcePressure,
      sourceEndPressureBar: equilibrium.sourcePressure,
      receiverStartPressureBar: start.receiverPressure,
      receiverEndPressureBar: equilibrium.receiverPressure,
    ),
    _PressureTransferStage(
      type: 'boost',
      startFraction: equilibriumFraction,
      endFraction: 1.0,
      sourceStartPressureBar: equilibrium.sourcePressure,
      sourceEndPressureBar: end.sourcePressure,
      receiverStartPressureBar: equilibrium.receiverPressure,
      receiverEndPressureBar: end.receiverPressure,
    ),
  ];
}

/// JS `transferSafety`: worst 4:1 oxygen-ratio margin across boosts.
({double margin, String? error}) _transferSafety({
  required _LinearProgramResult solverResult,
  required List<Bank> activeBanks,
  required Map<String, double> bankDensityByBankId,
  required double initialOxygenPercent,
  required double initialHeliumPercent,
  required double volumeL,
  required double temperatureC,
  required bool useVdw,
  required double targetPressureBar,
  required double maxCompressorPressureBar,
}) {
  var cumulativeMoles = _jsOrZero(solverResult.solution?['x_cyl']);
  var cumulativeOxygenMoles = cumulativeMoles * (initialOxygenPercent / 100);
  var cumulativeHeliumMoles = cumulativeMoles * (initialHeliumPercent / 100);
  final airFirst = targetPressureBar > maxCompressorPressureBar;
  var worstMargin = double.infinity;
  String? worstError;

  for (final boost in _activeBoostsFor(
    solverResult,
    activeBanks,
    airFirst: airFirst,
  )) {
    final bank = boost.bank;
    final addedMoles = boost.addedMoles;
    cumulativeMoles += addedMoles;
    cumulativeOxygenMoles += addedMoles * (bank.oxygenPercent / 100);
    cumulativeHeliumMoles += addedMoles * (bank.heliumPercent / 100);
    if (bank.oxygenPercent <= 25) {
      continue;
    }

    final receiverPressure = calcPressure(
      cumulativeMoles / volumeL,
      (cumulativeOxygenMoles / cumulativeMoles) * 100,
      (cumulativeHeliumMoles / cumulativeMoles) * 100,
      temperatureC,
      useVdw,
    );
    final sourceResidualPressure = _sourceResidualPressureAfterTransfer(
      bank,
      addedMoles,
      bankDensityByBankId,
      temperatureC,
      useVdw,
    );
    final margin = sourceResidualPressure * 4 - receiverPressure;
    if (margin < worstMargin) {
      worstMargin = margin;
      worstError =
          'Unsafe ${jsNumberString(bank.oxygenPercent)}% O₂ transfer from ${bank.name}: receiving cylinder would reach ${receiverPressure.toStringAsFixed(1)} bar while the source bank would fall to ${sourceResidualPressure.toStringAsFixed(1)} bar, exceeding the 4:1 limit.';
    }
  }

  return (margin: worstMargin, error: worstMargin < -1e-9 ? worstError : null);
}

import 'dart:math' as math;

import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/physics.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

const double salvageHePricePerLitre = 0.075;
const double salvageO2PricePerLitre = 0.007;
const double salvageMinValue = 1.0;
const double salvageAttractivenessGate = -2;

/// Attractiveness changes within this many points of the best are a near tie; a near tie is
/// decided by the number of standard targets the receiving banks can still reach.
const double salvageNearTiePoints = 1.0;

const double _tolerance = 1e-9;
const double _retentionRelativeTolerance = 1e-9;
const int _bisectionSteps = 100;

bool _usesVdw(PhysicsInput physics) => physics.useVdw;

double _molesOf(Bank bank, PhysicsInput physics, [double? pressureBar]) {
  final molarDensity = calcMolarDensity(
    pressureBar ?? bank.pressureBar,
    bank.oxygenPercent,
    bank.heliumPercent,
    physics.temperatureC,
    _usesVdw(physics),
  );
  return molarDensity * bank.volumeL;
}

double _pressureOfMoles(
  double moles,
  double volumeL,
  double oxygenPercent,
  double heliumPercent,
  PhysicsInput physics,
) {
  if (moles <= 0) return 0;
  return calcPressure(
    moles / volumeL,
    oxygenPercent,
    heliumPercent,
    physics.temperatureC,
    _usesVdw(physics),
  );
}

double _freeGasLitres(double moles, PhysicsInput physics) {
  return moles * gasConstant * (physics.temperatureC + 273.15);
}

class _Mix {
  const _Mix({
    required this.moles,
    required this.oxygenPercent,
    required this.heliumPercent,
  });

  final double moles;
  final double oxygenPercent;
  final double heliumPercent;
}

// Gas in `bank` after adding `addedMoles` of gas with the given composition (mixes by moles).
_Mix _mixInto(
  Bank bank,
  double bankMoles,
  double tankOxygenPercent,
  double tankHeliumPercent,
  double addedMoles,
) {
  final totalMoles = bankMoles + addedMoles;
  if (totalMoles <= 0) {
    return _Mix(
      moles: 0,
      oxygenPercent: bank.oxygenPercent,
      heliumPercent: bank.heliumPercent,
    );
  }
  final oxygenMoles =
      bankMoles * bank.oxygenPercent / 100 +
      addedMoles * tankOxygenPercent / 100;
  final heliumMoles =
      bankMoles * bank.heliumPercent / 100 +
      addedMoles * tankHeliumPercent / 100;
  return _Mix(
    moles: totalMoles,
    oxygenPercent: 100 * oxygenMoles / totalMoles,
    heliumPercent: 100 * heliumMoles / totalMoles,
  );
}

// Largest x in [0, hi] for which predicate holds, assuming it holds on a prefix.
double _largestWhere(double hi, bool Function(double) predicate) {
  if (hi <= 0 || !predicate(0)) return 0;
  if (predicate(hi)) return hi;
  var low = 0.0;
  var high = hi;
  for (var step = 0; step < _bisectionSteps; step++) {
    final middle = (low + high) / 2;
    if (predicate(middle)) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return low;
}

double _bankPressureAfter(
  Bank bank,
  double bankMoles,
  Bank tank,
  double addedMoles,
  PhysicsInput physics,
) {
  final mixed = _mixInto(
    bank,
    bankMoles,
    tank.oxygenPercent,
    tank.heliumPercent,
    addedMoles,
  );
  return _pressureOfMoles(
    mixed.moles,
    bank.volumeL,
    mixed.oxygenPercent,
    mixed.heliumPercent,
    physics,
  );
}

// Descending/ascending comparators treating values within tolerance as ties; Infinity ties with Infinity.
int _compareDescending(double a, double b) {
  if (a == b || (a - b).abs() <= _tolerance) return 0;
  return a > b ? -1 : 1;
}

int _compareAscending(double a, double b) {
  if (a == b || (a - b).abs() <= _tolerance) return 0;
  return a < b ? -1 : 1;
}

class _RankEntry<T> {
  const _RankEntry({
    required this.item,
    required this.change,
    required this.reach,
  });

  final T item;
  final double change;
  final double reach;
}

/// Chooses the preferred entry: among entries whose change is within salvageNearTiePoints of the
/// best, the one with the most reachable targets, then the larger change.
_RankEntry<T> _preferredEntry<T>(List<_RankEntry<T>> entries) {
  var bestChange = double.negativeInfinity;
  for (final entry in entries) {
    bestChange = math.max(bestChange, entry.change);
  }
  final nearTie = entries
      .where(
        (entry) =>
            bestChange - entry.change <= salvageNearTiePoints + _tolerance,
      )
      .toList();
  return nearTie.reduce(
    (best, entry) =>
        (entry.reach > best.reach ||
            (entry.reach == best.reach &&
                _compareDescending(entry.change, best.change) < 0)
        ? entry
        : best),
  );
}

/// Whether [bank] can receive salvaged gas.
bool isSalvageReceiver(Bank bank) {
  final max = bank.maxPressureBar;
  return bank.enabled &&
      max != null &&
      max.isFinite &&
      bank.isCompressor != true &&
      bank.oxygenPercent < 100 &&
      bank.heliumPercent < 100;
}

class SalvageTransferResult {
  const SalvageTransferResult({
    required this.movedMoles,
    required this.stage,
    required this.receiverEndPressureBar,
  });

  final double movedMoles;
  final String stage;
  final double receiverEndPressureBar;
}

/// Moles the working tank can move into [bank] in one salvage step.
/// Decant goes up to pressure equalization (and never past the bank maximum);
/// the booster may continue beyond equalization up to the booster output cap.
SalvageTransferResult salvageTransferMoles({
  required Bank bank,
  required Bank tank,
  required double surplusMoles,
  required PhysicsInput physics,
  required double minimumSourcePressureBar,
  required double? maxBoosterOutputPressureBar,
  double retainedMoles = 0,
}) {
  // A missing bank maximum compares false everywhere, as undefined does in the JS source.
  final bankMaxPressure = bank.maxPressureBar ?? double.nan;
  final tankMoles = _molesOf(tank, physics, tank.pressureBar);
  final bankMoles = _molesOf(bank, physics);
  final floorMoles = math.max(
    retainedMoles,
    _molesOf(tank, physics, minimumSourcePressureBar),
  );
  final available = math.max(
    0.0,
    math.min(surplusMoles, tankMoles - floorMoles),
  );

  double roomUnder(double capPressureBar) => _largestWhere(
    tankMoles,
    (addedMoles) =>
        _bankPressureAfter(bank, bankMoles, tank, addedMoles, physics) <=
        capPressureBar,
  );

  final equalizationMoles = _largestWhere(
    tankMoles,
    (addedMoles) =>
        _pressureOfMoles(
              tankMoles - addedMoles,
              tank.volumeL,
              tank.oxygenPercent,
              tank.heliumPercent,
              physics,
            ) -
            _bankPressureAfter(bank, bankMoles, tank, addedMoles, physics) >=
        0,
  );

  final decantMoles = math.min(
    available,
    math.min(equalizationMoles, roomUnder(bankMaxPressure)),
  );

  var movedMoles = decantMoles;
  final boosterMax = maxBoosterOutputPressureBar;
  if (boosterMax != null && boosterMax.isFinite) {
    final boostCap = math.min(bankMaxPressure, boosterMax);
    movedMoles = math.min(
      available,
      math.max(decantMoles, roomUnder(boostCap)),
    );
  }

  final boostMoles = movedMoles - decantMoles;
  var stage = 'decant';
  if (boostMoles > _tolerance) {
    stage = decantMoles > _tolerance ? 'decant+boost' : 'boost';
  }

  return SalvageTransferResult(
    movedMoles: movedMoles,
    stage: stage,
    receiverEndPressureBar: _bankPressureAfter(
      bank,
      bankMoles,
      tank,
      movedMoles,
      physics,
    ),
  );
}

/// Bank state after receiving [movedMoles] of the tank's gas. Volume is unchanged.
Bank applyTransferToBank(
  Bank bank,
  ({double oxygenPercent, double heliumPercent}) tankMix,
  double movedMoles,
  PhysicsInput physics,
) {
  final bankMoles = _molesOf(bank, physics);
  final mixed = _mixInto(
    bank,
    bankMoles,
    tankMix.oxygenPercent,
    tankMix.heliumPercent,
    movedMoles,
  );
  return bank.copyWith(
    pressureBar: _pressureOfMoles(
      mixed.moles,
      bank.volumeL,
      mixed.oxygenPercent,
      mixed.heliumPercent,
      physics,
    ),
    oxygenPercent: mixed.oxygenPercent,
    heliumPercent: mixed.heliumPercent,
  );
}

/// Bank state after the recipe draws [drawnMoles] of its gas. Mix and volume are unchanged.
Bank applyDrawToBank(Bank bank, double drawnMoles, PhysicsInput physics) {
  if (!(drawnMoles > 0)) return bank;
  final remainingMoles = math.max(0.0, _molesOf(bank, physics) - drawnMoles);
  return bank.copyWith(
    pressureBar: _pressureOfMoles(
      remainingMoles,
      bank.volumeL,
      bank.oxygenPercent,
      bank.heliumPercent,
      physics,
    ),
  );
}

/// Price of the He and O2 free-gas litres held in enabled banks.
double netStockValue(List<Bank> banks, PhysicsInput physics) {
  var value = 0.0;
  for (final bank in banks) {
    if (!bank.enabled) continue;
    final litres = _freeGasLitres(_molesOf(bank, physics), physics);
    value += litres * bank.heliumPercent / 100 * salvageHePricePerLitre;
    value += litres * bank.oxygenPercent / 100 * salvageO2PricePerLitre;
  }
  return value;
}

List<double> _attractivenessDeltas(
  List<Bank> baselineBanks,
  List<Bank> variantBanks,
  double Function(Bank) bankScoresOf,
) {
  final variantById = {for (final bank in variantBanks) bank.id: bank};
  final deltas = <double>[];
  for (final baselineBank in baselineBanks) {
    final variantBank = variantById[baselineBank.id];
    if (variantBank == null) continue;
    deltas.add(bankScoresOf(variantBank) - bankScoresOf(baselineBank));
  }
  return deltas;
}

// Mean number of reachable standard targets over the banks this variant changed (the receivers
// and any bank whose draw changed), judged on their final post-recipe state. 0 when none changed.
double _receiverReach(
  List<Bank> baselineBanks,
  List<Bank> variantBanks,
  double Function(Bank) bankReachOf,
) {
  final baselineById = {for (final bank in baselineBanks) bank.id: bank};
  final reaches = <double>[];
  for (final bank in variantBanks) {
    final before = baselineById[bank.id];
    final changed =
        before == null ||
        (bank.pressureBar - before.pressureBar).abs() > _tolerance ||
        (bank.oxygenPercent - before.oxygenPercent).abs() > _tolerance ||
        (bank.heliumPercent - before.heliumPercent).abs() > _tolerance;
    if (changed) reaches.add(bankReachOf(bank));
  }
  if (reaches.isEmpty) return 0;
  return reaches.reduce((sum, reach) => sum + reach) / reaches.length;
}

/// One salvage variant (or the baseline's retained state) as produced by the optimizer.
class SalvageTransferRecord {
  const SalvageTransferRecord({
    required this.receiverId,
    required this.movedMoles,
  });

  final String receiverId;
  final double movedMoles;
}

class SalvageVariant {
  const SalvageVariant({
    required this.id,
    required this.salvagedMoles,
    required this.resolvedSurplusMoles,
    required this.finalBanks,
    required this.transfers,
    this.retainedMoles,
    this.lpCost,
  });

  final String id;
  final double salvagedMoles;
  final double resolvedSurplusMoles;
  final List<Bank> finalBanks;
  final List<SalvageTransferRecord> transfers;

  /// Re-solved cylinder moles; null when not computed (JS `undefined`).
  final double? retainedMoles;

  /// LP cost; null ranks last among otherwise tied variants.
  final double? lpCost;
}

class SalvageBaseline {
  const SalvageBaseline({required this.finalBanks, this.retainedMoles});

  final List<Bank> finalBanks;

  /// Re-solved cylinder moles; null when not computed (JS `undefined`).
  final double? retainedMoles;
}

class SalvageSelectionEntry {
  const SalvageSelectionEntry({
    required this.variant,
    required this.valueKept,
    required this.attractivenessChange,
    required this.reachChange,
  });

  final SalvageVariant variant;
  final double valueKept;
  final double attractivenessChange;
  final double reachChange;
}

/// Picks the salvage variant to apply, or null when none passes the gates.
/// Gates: cylinder retention (re-solved retained moles at least the baseline's, within a
/// relative 1e-9), feasible (re-solved surplus covers the salvaged moles), no bank loses
/// more than |salvageAttractivenessGate| points, and net value kept is at least
/// salvageMinValue. Ranking: value kept, then summed attractiveness change, then LP cost
/// (missing LP cost ranks last). [bankScoresOf] returns that bank's attractiveness score.
SalvageVariant? selectSalvageVariant({
  required SalvageBaseline baseline,
  required List<SalvageVariant> variants,
  required double Function(Bank) bankScoresOf,
  double Function(Bank)? bankReachOf,
  required PhysicsInput physics,
}) {
  final reachOf = bankReachOf ?? (_) => 0;
  final baselineValue = netStockValue(baseline.finalBanks, physics);
  final qualifying = <SalvageSelectionEntry>[];

  for (final variant in variants) {
    final baselineRetained = baseline.retainedMoles;
    final variantRetained = variant.retainedMoles;
    if (baselineRetained != null &&
        variantRetained != null &&
        variantRetained <
            baselineRetained * (1 - _retentionRelativeTolerance)) {
      continue;
    }
    if (variant.resolvedSurplusMoles < variant.salvagedMoles - _tolerance) {
      continue;
    }

    final deltas = _attractivenessDeltas(
      baseline.finalBanks,
      variant.finalBanks,
      bankScoresOf,
    );
    if (deltas.any((delta) => delta < salvageAttractivenessGate - _tolerance)) {
      continue;
    }

    final valueKept =
        netStockValue(variant.finalBanks, physics) - baselineValue;
    if (valueKept < salvageMinValue - _tolerance) continue;

    qualifying.add(
      SalvageSelectionEntry(
        variant: variant,
        valueKept: valueKept,
        attractivenessChange: deltas.fold(0.0, (sum, delta) => sum + delta),
        reachChange: _receiverReach(
          baseline.finalBanks,
          variant.finalBanks,
          reachOf,
        ),
      ),
    );
  }

  qualifying.sort((a, b) {
    final byValue = _compareDescending(a.valueKept, b.valueKept);
    if (byValue != 0) return byValue;
    final byChange = _compareDescending(
      a.attractivenessChange,
      b.attractivenessChange,
    );
    if (byChange != 0) return byChange;
    return _compareAscending(
      a.variant.lpCost ?? double.infinity,
      b.variant.lpCost ?? double.infinity,
    );
  });
  if (qualifying.isEmpty) return null;

  // Near ties in attractiveness (at equal value kept) go to the variant that leaves more targets reachable.
  final topValue = qualifying.first.valueKept;
  final sameValue = qualifying
      .where((entry) => _compareDescending(entry.valueKept, topValue) == 0)
      .map(
        (entry) => _RankEntry<SalvageVariant>(
          item: entry.variant,
          change: entry.attractivenessChange,
          reach: entry.reachChange,
        ),
      )
      .toList();
  return _preferredEntry(sameValue).item;
}

class ReceiverCandidate {
  const ReceiverCandidate({
    required this.id,
    required this.receiver,
    required this.transferredReceiver,
  });

  final String id;
  final Bank receiver;
  final Bank transferredReceiver;
}

/// Sorts receiver candidates best first by how much the receiving bank's attractiveness changes
/// right after the transfer. Changes within salvageNearTiePoints of the best are a near tie,
/// decided by the number of standard targets the receiver can still reach after the transfer
/// ([bankReachOf], default: no preference). Exact ties keep input order.
List<ReceiverCandidate> rankReceivers(
  List<ReceiverCandidate> candidates,
  double Function(Bank) bankScoresOf, [
  double Function(Bank)? bankReachOf,
]) {
  final reachOf = bankReachOf ?? (_) => 0;
  final remaining = [
    for (final candidate in candidates)
      _RankEntry<ReceiverCandidate>(
        item: candidate,
        change:
            bankScoresOf(candidate.transferredReceiver) -
            bankScoresOf(candidate.receiver),
        reach: reachOf(candidate.transferredReceiver),
      ),
  ];
  final ranked = <ReceiverCandidate>[];
  while (remaining.isNotEmpty) {
    final next = _preferredEntry(remaining);
    ranked.add(next.item);
    remaining.remove(next);
  }
  return ranked;
}

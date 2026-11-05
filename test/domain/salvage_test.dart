import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/physics.dart';
import 'package:simplex_blender/src/domain/salvage.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

final PhysicsInput ideal = PhysicsInput(model: 'ideal', temperatureC: 20);
final PhysicsInput vdw = PhysicsInput(model: 'vdw', temperatureC: 20);
final double rt = gasConstant * (20 + 273.15);

// Ideal-gas moles for a pressure in bar and a volume in litres at 20 C.
double molesFor(double pressureBar, double volumeL) =>
    pressureBar * volumeL / rt;

Bank tankAt(double pressureBar, {double volumeL = 10}) => Bank(
  id: 'tank',
  name: 'Tank',
  volumeL: volumeL,
  pressureBar: pressureBar,
  oxygenPercent: 21,
  heliumPercent: 35,
  enabled: true,
);

Bank bankAt(
  double pressureBar, {
  double maxPressureBar = 200,
  double volumeL = 10,
  double oxygenPercent = 18,
  double heliumPercent = 45,
}) => Bank(
  id: 'recv',
  name: 'Receiver',
  volumeL: volumeL,
  pressureBar: pressureBar,
  oxygenPercent: oxygenPercent,
  heliumPercent: heliumPercent,
  enabled: true,
  maxPressureBar: maxPressureBar,
);

Bank gasBank({
  String id = 'gas',
  double volumeL = 10,
  required double pressureBar,
  required double oxygenPercent,
  required double heliumPercent,
  bool enabled = true,
}) => Bank(
  id: id,
  name: id,
  volumeL: volumeL,
  pressureBar: pressureBar,
  oxygenPercent: oxygenPercent,
  heliumPercent: heliumPercent,
  enabled: enabled,
);

// Selection fixtures: the JS fixtures carry score (and reach) on each bank state. Dart banks have
// no such fields, so the test scores are kept in identity-keyed expandos read by scoreOf/reachOf.
final Expando<double> _scoreOfBank = Expando<double>('score');
final Expando<double> _reachOfBank = Expando<double>('reach');

double scoreOf(Bank bank) => _scoreOfBank[bank] ?? 0;
double reachOf(Bank bank) => _reachOfBank[bank] ?? 0;

Bank _scored(Bank bank, double score, {double? reach}) {
  _scoreOfBank[bank] = score;
  if (reach != null) _reachOfBank[bank] = reach;
  return bank;
}

Bank donorAt(double pressureBar, {double score = 50, double? reach}) => _scored(
  Bank(
    id: 'donor',
    name: 'donor',
    enabled: true,
    volumeL: 10,
    pressureBar: pressureBar,
    maxPressureBar: 350,
    oxygenPercent: 0,
    heliumPercent: 100,
  ),
  score,
  reach: reach,
);

Bank receiverAt(double pressureBar, {double score = 60, double? reach}) =>
    _scored(
      bankAt(
        pressureBar,
        maxPressureBar: 200,
        oxygenPercent: 18,
        heliumPercent: 45,
      ),
      score,
      reach: reach,
    );

final SalvageBaseline baseline = SalvageBaseline(
  finalBanks: [donorAt(100), receiverAt(20)],
);

SalvageVariant variant(
  String id, {
  Bank? receiver,
  Bank? donor,
  double salvaged = 5,
  double resolved = 10,
  double? lpCost = 1,
  double? retainedMoles,
  List<SalvageTransferRecord> transfers = const [],
}) => SalvageVariant(
  id: id,
  salvagedMoles: salvaged,
  resolvedSurplusMoles: resolved,
  finalBanks: [donor ?? donorAt(100), receiver ?? receiverAt(30)],
  lpCost: lpCost,
  retainedMoles: retainedMoles,
  transfers: transfers,
);

SalvageVariant? select(List<SalvageVariant> variants) => selectSalvageVariant(
  baseline: baseline,
  variants: variants,
  bankScoresOf: scoreOf,
  physics: ideal,
);

Bank reaching(double reach, double score) =>
    receiverAt(30, score: score, reach: reach);

SalvageVariant? selectWithReach(List<SalvageVariant> variants) =>
    selectSalvageVariant(
      baseline: baseline,
      variants: variants,
      bankScoresOf: scoreOf,
      bankReachOf: reachOf,
      physics: ideal,
    );

void main() {
  group('salvage', () {
    test('constants match the approved prices, gate, and minimum value', () {
      expect(salvageHePricePerLitre, 0.075);
      expect(salvageO2PricePerLitre, 0.007);
      expect(salvageMinValue, 1.0);
      expect(salvageAttractivenessGate, -2);
    });

    test('receiver eligibility truth table', () {
      Bank base({
        double? maxPressureBar = 200,
        double oxygenPercent = 18,
        double heliumPercent = 45,
        bool enabled = true,
        bool? isCompressor,
      }) => Bank(
        id: 'b',
        name: 'b',
        volumeL: 10,
        pressureBar: 100,
        oxygenPercent: oxygenPercent,
        heliumPercent: heliumPercent,
        enabled: enabled,
        maxPressureBar: maxPressureBar,
        isCompressor: isCompressor,
      );

      expect(isSalvageReceiver(base()), isTrue);
      expect(
        isSalvageReceiver(base(oxygenPercent: 21, heliumPercent: 0)),
        isTrue,
        reason: 'air-like gas',
      );
      expect(
        isSalvageReceiver(base(oxygenPercent: 0, heliumPercent: 0)),
        isTrue,
        reason: 'nitrogen balance',
      );
      expect(
        isSalvageReceiver(base(enabled: false)),
        isFalse,
        reason: 'disabled',
      );
      expect(
        isSalvageReceiver(base(maxPressureBar: null)),
        isFalse,
        reason: 'missing max',
      );
      expect(
        isSalvageReceiver(base(maxPressureBar: double.nan)),
        isFalse,
        reason: 'NaN max',
      );
      expect(
        isSalvageReceiver(base(maxPressureBar: double.infinity)),
        isFalse,
        reason: 'infinite max',
      );
      expect(
        isSalvageReceiver(base(oxygenPercent: 100, heliumPercent: 0)),
        isFalse,
        reason: 'pure O2',
      );
      expect(
        isSalvageReceiver(base(oxygenPercent: 0, heliumPercent: 100)),
        isFalse,
        reason: 'pure He',
      );
      expect(
        isSalvageReceiver(
          base(isCompressor: true, oxygenPercent: 21, heliumPercent: 0),
        ),
        isFalse,
        reason: 'compressor',
      );
    });

    test('transfer is capped by the surplus', () {
      final surplus = molesFor(5, 10);
      final result = salvageTransferMoles(
        bank: bankAt(20),
        tank: tankAt(200),
        surplusMoles: surplus,
        physics: ideal,
        minimumSourcePressureBar: 10,
        maxBoosterOutputPressureBar: 200,
        retainedMoles: 0,
      );
      expect((result.movedMoles - surplus).abs(), lessThan(1e-9));
      expect(result.stage, 'decant');
      expect((result.receiverEndPressureBar - 25).abs(), lessThan(1e-6));
    });

    test('transfer is capped by the bank maximum pressure', () {
      final result = salvageTransferMoles(
        bank: bankAt(20, maxPressureBar: 50),
        tank: tankAt(200),
        surplusMoles: molesFor(100, 10),
        physics: ideal,
        minimumSourcePressureBar: 10,
        maxBoosterOutputPressureBar: 200,
        retainedMoles: 0,
      );
      expect((result.movedMoles - molesFor(30, 10)).abs(), lessThan(1e-9));
      expect(result.stage, 'decant');
      expect((result.receiverEndPressureBar - 50).abs(), lessThan(1e-6));
    });

    test('without a booster, decant stops at pressure equalization', () {
      // Equal volumes: equalization moves half the pressure difference, 30 -> 20 bar gives 5 bar-equivalent.
      final result = salvageTransferMoles(
        bank: bankAt(20),
        tank: tankAt(30),
        surplusMoles: molesFor(25, 10),
        physics: ideal,
        minimumSourcePressureBar: 10,
        maxBoosterOutputPressureBar: null,
        retainedMoles: 0,
      );
      expect((result.movedMoles - molesFor(5, 10)).abs(), lessThan(1e-9));
      expect(result.stage, 'decant');
      expect((result.receiverEndPressureBar - 25).abs(), lessThan(1e-6));
    });

    test('with a booster, transfer continues past equalization down to the minimum source pressure', () {
      final result = salvageTransferMoles(
        bank: bankAt(20),
        tank: tankAt(30),
        surplusMoles: molesFor(25, 10),
        physics: ideal,
        minimumSourcePressureBar: 10,
        maxBoosterOutputPressureBar: 200,
        retainedMoles: 0,
      );
      // Tank can give 30 -> 10 bar (20 bar-equivalent); bank 20 -> 40 bar.
      expect((result.movedMoles - molesFor(20, 10)).abs(), lessThan(1e-9));
      expect(result.stage, 'decant+boost');
      expect((result.receiverEndPressureBar - 40).abs(), lessThan(1e-6));
    });

    test(
      'booster minimum source pressure leaves the remainder to be vented',
      () {
        final result = salvageTransferMoles(
          bank: bankAt(0, maxPressureBar: 350),
          tank: tankAt(200),
          surplusMoles: molesFor(190, 10),
          physics: ideal,
          minimumSourcePressureBar: 50,
          maxBoosterOutputPressureBar: 350,
          retainedMoles: 0,
        );
        // Tank keeps 50 bar; 150 bar-equivalent moves; 200 - 150 = 50 remains for the vent step.
        expect((result.movedMoles - molesFor(150, 10)).abs(), lessThan(1e-9));
        expect(result.stage, 'decant+boost');
        expect((result.receiverEndPressureBar - 150).abs(), lessThan(1e-6));
      },
    );

    test('under van der Waals the reported receiver end pressure holds exactly the moved moles', () {
      final bank = bankAt(20, maxPressureBar: 350, volumeL: 10);
      final tank = tankAt(200);
      final result = salvageTransferMoles(
        bank: bank,
        tank: tank,
        surplusMoles: molesFor(190, 10),
        physics: vdw,
        minimumSourcePressureBar: 50,
        maxBoosterOutputPressureBar: 350,
        retainedMoles: 0,
      );
      final bankMoles = calcMolarDensity(20, 18, 45, 20, true) * 10;
      // Moles are conserved: bank before + moved = bank after, at the mixed composition.
      final next = applyTransferToBank(
        bank,
        (oxygenPercent: 21, heliumPercent: 35),
        result.movedMoles,
        vdw,
      );
      final total = bankMoles + result.movedMoles;
      expect(
        (calcMolarDensity(
                      next.pressureBar,
                      next.oxygenPercent,
                      next.heliumPercent,
                      20,
                      true,
                    ) *
                    10 -
                total)
            .abs(),
        lessThan(1e-6),
      );
      expect(
        (next.pressureBar - result.receiverEndPressureBar).abs(),
        lessThan(1e-6),
      );
    });

    test(
      'retained moles raise the tank floor above the minimum source pressure',
      () {
        final result = salvageTransferMoles(
          bank: bankAt(0, maxPressureBar: 350),
          tank: tankAt(200),
          surplusMoles: molesFor(190, 10),
          physics: ideal,
          minimumSourcePressureBar: 10,
          maxBoosterOutputPressureBar: 350,
          retainedMoles: molesFor(120, 10),
        );
        // Tank may only fall to the 120 bar it retains: 80 bar-equivalent moves, all by decant (equalization is 100 bar).
        expect((result.movedMoles - molesFor(80, 10)).abs(), lessThan(1e-9));
        expect(result.stage, 'decant');
        expect((result.receiverEndPressureBar - 80).abs(), lessThan(1e-6));
      },
    );

    test(
      'boost-only transfer when the bank is already above tank pressure',
      () {
        final result = salvageTransferMoles(
          bank: bankAt(120, maxPressureBar: 200),
          tank: tankAt(100),
          surplusMoles: molesFor(90, 10),
          physics: ideal,
          minimumSourcePressureBar: 10,
          maxBoosterOutputPressureBar: 200,
          retainedMoles: 0,
        );
        // Bank room to 200 bar is 80 bar-equivalent; tank can give 90.
        expect((result.movedMoles - molesFor(80, 10)).abs(), lessThan(1e-9));
        expect(result.stage, 'boost');
        expect((result.receiverEndPressureBar - 200).abs(), lessThan(1e-6));
      },
    );

    test('booster output cap does not cut a decant that stops at equalization', () {
      // Bank 10 L at 150 bar (max 300), tank 10 L at 300 bar, booster cap 200.
      // Equalization: (3000 - m) / 10 = (1500 + m) / 10 -> m = 750 bar*L, i.e. 225 bar in both.
      // The cap 200 bar allows only (200 - 150) * 10 = 500 bar*L, but the decant (750) is already past it.
      final result = salvageTransferMoles(
        bank: bankAt(150, maxPressureBar: 300),
        tank: tankAt(300),
        surplusMoles: molesFor(300, 10),
        physics: ideal,
        minimumSourcePressureBar: 10,
        maxBoosterOutputPressureBar: 200,
        retainedMoles: 0,
      );
      expect((result.movedMoles - molesFor(75, 10)).abs(), lessThan(1e-9));
      expect(result.stage, 'decant');
      expect((result.receiverEndPressureBar - 225).abs(), lessThan(1e-6));
    });

    test('booster continues past equalization and stops at its output cap', () {
      // Bank 10 L at 20 bar (max 300); tank 40 L at 100 bar; booster cap 150 bar.
      // Equalization: (4000 - m) / 40 = (200 + m) / 10 -> m = 640 bar*L, i.e. bank 84 bar, tank 84 bar.
      // Moving 1300 bar*L takes the bank to 150 bar; the tank keeps 4000 - 1300 = 2700 bar*L, far above its floor, and the 2000 bar*L surplus is not binding.
      final result = salvageTransferMoles(
        bank: bankAt(20, maxPressureBar: 300),
        tank: tankAt(100, volumeL: 40),
        surplusMoles: molesFor(200, 10),
        physics: ideal,
        minimumSourcePressureBar: 10,
        maxBoosterOutputPressureBar: 150,
        retainedMoles: 0,
      );
      expect((result.movedMoles - molesFor(130, 10)).abs(), lessThan(1e-9));
      expect(result.stage, 'decant+boost');
      expect((result.receiverEndPressureBar - 150).abs(), lessThan(1e-6));
    });

    test('applyTransferToBank mixes composition by moles and keeps volume', () {
      final bank = bankAt(
        20,
        oxygenPercent: 0,
        heliumPercent: 100,
        maxPressureBar: 200,
      );
      final next = applyTransferToBank(
        bank,
        (oxygenPercent: 21, heliumPercent: 35),
        molesFor(30, 10),
        ideal,
      );
      expect(next.volumeL, 10);
      expect((next.pressureBar - 50).abs(), lessThan(1e-6));
      expect((next.heliumPercent - 61).abs(), lessThan(1e-6));
      expect((next.oxygenPercent - 12.6).abs(), lessThan(1e-6));
    });

    test(
      'applyTransferToBank with no moved gas leaves pressure and mix unchanged',
      () {
        final bank = bankAt(20);
        final next = applyTransferToBank(
          bank,
          (oxygenPercent: 21, heliumPercent: 35),
          0,
          ideal,
        );
        expect((next.pressureBar - 20).abs(), lessThan(1e-9));
        expect(next.oxygenPercent, 18);
        expect(next.heliumPercent, 45);
      },
    );

    test('applyTransferToBank under van der Waals mixes by moles and uses the real-gas pressure', () {
      final bank = bankAt(100);
      const tankMix = (oxygenPercent: 21.0, heliumPercent: 35.0);
      final moved = calcMolarDensity(30, 21, 35, 20, true) * 10;
      final next = applyTransferToBank(bank, tankMix, moved, vdw);
      final bankMoles = calcMolarDensity(100, 18, 45, 20, true) * 10;
      final total = bankMoles + moved;
      final oxygen = (bankMoles * 18 + moved * 21) / total;
      final helium = (bankMoles * 45 + moved * 35) / total;
      expect(
        (next.pressureBar - calcPressure(total / 10, oxygen, helium, 20, true))
            .abs(),
        lessThan(1e-6),
      );
      expect((next.oxygenPercent - oxygen).abs(), lessThan(1e-9));
      expect((next.heliumPercent - helium).abs(), lessThan(1e-9));
      // The real-gas result must differ from the ideal-gas one at this pressure, otherwise the vdW branch is not exercised.
      final idealPressure = total * rt / 10;
      expect((next.pressureBar - idealPressure).abs() > 0.1, isTrue);
    });

    test(
      'net stock value prices He and O2 free litres in enabled banks only',
      () {
        final he = gasBank(
          id: 'he',
          pressureBar: 100,
          oxygenPercent: 0,
          heliumPercent: 100,
        );
        final o2 = gasBank(
          id: 'o2',
          pressureBar: 100,
          oxygenPercent: 100,
          heliumPercent: 0,
        );
        final mixed = gasBank(
          id: 'mixed',
          pressureBar: 100,
          oxygenPercent: 18,
          heliumPercent: 45,
        );
        final disabled = gasBank(
          id: 'disabled',
          pressureBar: 100,
          oxygenPercent: 0,
          heliumPercent: 100,
          enabled: false,
        );
        expect((netStockValue([he], ideal) - 75).abs(), lessThan(1e-6));
        expect((netStockValue([o2], ideal) - 7).abs(), lessThan(1e-9));
        expect(
          (netStockValue([mixed], ideal) - (450 * 0.075 + 180 * 0.007)).abs(),
          lessThan(1e-6),
        );
        expect(
          (netStockValue([he, disabled], ideal) - 75).abs(),
          lessThan(1e-6),
        );
      },
    );

    test(
      'net value counts salvage only through stock left after the recipe draws',
      () {
        final donor = gasBank(
          id: 'donor',
          pressureBar: 100,
          oxygenPercent: 0,
          heliumPercent: 100,
        );
        final receiverEmptyAfterDraws = gasBank(
          id: 'recv',
          pressureBar: 0,
          oxygenPercent: 18,
          heliumPercent: 45,
        );
        // Empty receiver holds nothing: only the donor's 1000 bar*L of He (10 L at 100 bar) counts.
        final base = netStockValue([donor, receiverEmptyAfterDraws], ideal);
        expect((base - 75).abs(), lessThan(1e-6));
        // Gas left in the receiver (20 bar, 10 L = 200 bar*L of 18/45) counts at its price.
        final retained = gasBank(
          id: 'recv',
          pressureBar: 20,
          oxygenPercent: 18,
          heliumPercent: 45,
        );
        final delta = netStockValue([donor, retained], ideal) - base;
        expect(
          (delta - (200 * 0.45 * 0.075 + 200 * 0.18 * 0.007)).abs(),
          lessThan(1e-6),
        );
      },
    );

    test('selection drops infeasible variants', () {
      final infeasible = variant(
        'infeasible',
        receiver: receiverAt(40),
        salvaged: 5,
        resolved: 4,
      );
      final feasible = variant('feasible', receiver: receiverAt(30));
      expect(select([infeasible, feasible])?.id, 'feasible');
      expect(select([infeasible]), isNull);
    });

    test('selection drops variants where a bank loses more than two points, keeping an exact -2 change', () {
      final violating = variant(
        'violating',
        receiver: receiverAt(40, score: 57),
      );
      final boundary = variant('boundary', receiver: receiverAt(30, score: 58));
      expect(select([violating]), isNull);
      expect(select([violating, boundary])?.id, 'boundary');
    });

    test(
      'selection drops a variant whose donor bank loses more than two points',
      () {
        final donorDrop = variant(
          'donor-drop',
          donor: donorAt(100, score: 47),
          receiver: receiverAt(40, score: 60),
        );
        final donorOk = variant(
          'donor-ok',
          donor: donorAt(100, score: 50),
          receiver: receiverAt(40, score: 60),
        );
        expect(select([donorDrop]), isNull);
        expect(select([donorDrop, donorOk])?.id, 'donor-ok');
      },
    );

    test('selection rejects a variant with moved gas whose final banks equal the baseline', () {
      final noop = variant(
        'noop',
        receiver: receiverAt(20),
        transfers: const [
          SalvageTransferRecord(receiverId: 'recv', movedMoles: 5),
        ],
      );
      expect(noop.salvagedMoles, 5);
      expect(select([noop]), isNull);
    });

    test('selection drops variants below the minimum value and keeps one exactly at it', () {
      // Pure He donor: 10 L of He at 1 bar is 10 bar*L = 0.75 value, so 4/3 bar is exactly 1.0.
      final exact = variant(
        'exact',
        donor: donorAt(100 + 4 / 3),
        receiver: receiverAt(20),
      );
      final short = variant(
        'short',
        donor: donorAt(100 + 4 / 3 - 0.01),
        receiver: receiverAt(20),
      );
      expect(select([short]), isNull);
      expect(select([short, exact])?.id, 'exact');
    });

    test('selection ranks value kept first, then attractiveness change, then LP cost', () {
      final bigger = variant(
        'bigger',
        receiver: receiverAt(40, score: 60),
        lpCost: 5,
      );
      final smallerButBetterScores = variant(
        'smaller',
        receiver: receiverAt(30, score: 62),
        lpCost: 1,
      );
      expect(select([smallerButBetterScores, bigger])?.id, 'bigger');

      final higherScore = variant(
        'higher-score',
        receiver: receiverAt(40, score: 61),
        lpCost: 9,
      );
      final lowerScore = variant(
        'lower-score',
        receiver: receiverAt(40, score: 60),
        lpCost: 1,
      );
      expect(select([lowerScore, higherScore])?.id, 'higher-score');

      final cheap = variant(
        'cheap',
        receiver: receiverAt(40, score: 60),
        lpCost: 2,
      );
      final expensive = variant(
        'expensive',
        receiver: receiverAt(40, score: 60),
        lpCost: 3,
      );
      expect(select([expensive, cheap])?.id, 'cheap');
    });

    test(
      'selection ranks a missing LP cost last among otherwise tied variants',
      () {
        final costed = variant(
          'costed',
          receiver: receiverAt(40, score: 60),
          lpCost: 3,
        );
        final unknown = variant(
          'unknown',
          receiver: receiverAt(40, score: 60),
          lpCost: null,
        );
        expect(select([unknown, costed])?.id, 'costed');
      },
    );

    test('selection returns null when no variant qualifies', () {
      expect(select([]), isNull);
      expect(select([variant('tiny', receiver: receiverAt(20.01))]), isNull);
    });

    test('rankReceivers sorts by attractiveness change right after transfer, stable for ties', () {
      ReceiverCandidate candidate(String id, double afterScore) =>
          ReceiverCandidate(
            id: id,
            receiver: receiverAt(20, score: 60),
            transferredReceiver: receiverAt(30, score: afterScore),
          );
      final ranked = rankReceivers([
        candidate('down', 58),
        candidate('up', 61),
        candidate('flat-a', 60),
        candidate('flat-b', 60),
      ], scoreOf);
      expect(ranked.map((entry) => entry.id).toList(), [
        'up',
        'flat-a',
        'flat-b',
        'down',
      ]);
    });

    test('selection rejects a variant that lowers the retained cylinder moles, even when value and attractiveness pass', () {
      final retainedBaseline = SalvageBaseline(
        finalBanks: baseline.finalBanks,
        retainedMoles: 10,
      );
      final lowerRetained = variant(
        'lower-retained',
        receiver: receiverAt(40, score: 60),
        retainedMoles: 9.9999,
      );
      final equalRetained = variant(
        'equal-retained',
        receiver: receiverAt(40, score: 60),
        retainedMoles: 10,
      );
      SalvageVariant? selectRetained(List<SalvageVariant> variants) =>
          selectSalvageVariant(
            baseline: retainedBaseline,
            variants: variants,
            bankScoresOf: scoreOf,
            physics: ideal,
          );

      expect(selectRetained([lowerRetained]), isNull);
      expect(
        selectRetained([lowerRetained, equalRetained])?.id,
        'equal-retained',
      );
    });

    test('selection prefers more reachable targets when attractiveness changes are within the near-tie margin', () {
      final fewerTargets = variant('fewer', receiver: reaching(3, 62.0));
      final moreTargets = variant('more', receiver: reaching(5, 61.6));
      expect(selectWithReach([fewerTargets, moreTargets])?.id, 'more');
      expect(selectWithReach([moreTargets, fewerTargets])?.id, 'more');
    });

    test('selection keeps the larger attractiveness change when it leads by more than the near-tie margin', () {
      final fewerTargets = variant('fewer', receiver: reaching(3, 62.0));
      final moreTargets = variant(
        'more',
        receiver: reaching(5, 62.0 - salvageNearTiePoints - 0.5),
      );
      expect(selectWithReach([moreTargets, fewerTargets])?.id, 'fewer');
    });

    test('selection ignores reach when no reach function is given', () {
      final fewerTargets = variant('fewer', receiver: reaching(3, 62.0));
      final moreTargets = variant('more', receiver: reaching(5, 61.6));
      expect(select([moreTargets, fewerTargets])?.id, 'fewer');
    });

    test('selection judges reach on the banks the variant changed, not on untouched banks', () {
      // Both variants leave the donor untouched at reach 5; only the receiver differs.
      final lowReach = variant(
        'low',
        receiver: reaching(2, 62.0),
        donor: donorAt(100, reach: 5),
      );
      final highReach = variant(
        'high',
        receiver: reaching(4, 61.8),
        donor: donorAt(100, reach: 5),
      );
      final baselineWithReach = SalvageBaseline(
        finalBanks: [donorAt(100, reach: 5), receiverAt(20, reach: 1)],
      );
      final chosen = selectSalvageVariant(
        baseline: baselineWithReach,
        variants: [lowReach, highReach],
        bankScoresOf: scoreOf,
        bankReachOf: reachOf,
        physics: ideal,
      );
      expect(chosen?.id, 'high');
    });

    test('rankReceivers puts a near-tie receiver with more reachable targets first, and respects clear leads', () {
      ReceiverCandidate candidate(String id, double afterScore, double reach) =>
          ReceiverCandidate(
            id: id,
            receiver: receiverAt(20, score: 60),
            transferredReceiver: receiverAt(
              30,
              score: afterScore,
              reach: reach,
            ),
          );
      final nearTie = rankReceivers(
        [candidate('shallow', 62.6, 3), candidate('deep', 62.14, 5)],
        scoreOf,
        reachOf,
      );
      expect(nearTie.map((entry) => entry.id).toList(), ['deep', 'shallow']);
      final clearLead = rankReceivers(
        [candidate('shallow', 64.5, 3), candidate('deep', 62.0, 5)],
        scoreOf,
        reachOf,
      );
      expect(clearLead.map((entry) => entry.id).toList(), ['shallow', 'deep']);
      final noReach = rankReceivers([
        candidate('shallow', 62.6, 3),
        candidate('deep', 62.14, 5),
      ], scoreOf);
      expect(noReach.map((entry) => entry.id).toList(), ['shallow', 'deep']);
    });

    test('selection falls through to LP cost when attractiveness and reach both tie', () {
      final cheap = variant('cheap', receiver: reaching(4, 61.0), lpCost: 1);
      final dear = variant('dear', receiver: reaching(4, 61.0), lpCost: 9);
      expect(selectWithReach([dear, cheap])?.id, 'cheap');
      expect(selectWithReach([cheap, dear])?.id, 'cheap');
    });

    test('near-tie reach preference never overrides a higher value kept', () {
      final moreValue = variant(
        'more-value',
        receiver: receiverAt(45, score: 61.0, reach: 2),
      );
      final moreTargets = variant('more-targets', receiver: reaching(5, 61.0));
      expect(selectWithReach([moreTargets, moreValue])?.id, 'more-value');
    });

    test('near-tie reach preference still enforces the retention gate', () {
      final retainedBaseline = SalvageBaseline(
        finalBanks: baseline.finalBanks,
        retainedMoles: 10,
      );
      final lowRetention = variant(
        'low',
        receiver: reaching(5, 61.5),
        retainedMoles: 9,
      );
      final keepsGas = variant(
        'keeps',
        receiver: reaching(3, 61.0),
        retainedMoles: 10,
      );
      final chosen = selectSalvageVariant(
        baseline: retainedBaseline,
        variants: [lowRetention, keepsGas],
        bankScoresOf: scoreOf,
        bankReachOf: reachOf,
        physics: ideal,
      );
      expect(chosen?.id, 'keeps');
    });
  });
}

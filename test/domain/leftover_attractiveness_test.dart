import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/leftover_attractiveness.dart';

// Independent line term: exp(-15 * |3.077 O2 + He - 1| / sqrt(3.077^2 + 1)), fractions.
double lineTerm(double oxygenPercent, double heliumPercent) {
  final residual = (3.077 * (oxygenPercent / 100) + heliumPercent / 100 - 1)
      .abs();
  return math.exp(-15 * residual / math.sqrt(3.077 * 3.077 + 1));
}

// Ideal-gas mix of two same-volume, same-temperature gases: pressures add, mole fractions weight by pressure.
({double pressureBar, double oxygenPercent, double heliumPercent})
mixAtSameVolume(
  ({double pressureBar, double oxygenPercent, double heliumPercent}) bank,
  ({double pressureBar, double oxygenPercent, double heliumPercent}) added,
) {
  final totalBar = bank.pressureBar + added.pressureBar;
  return (
    pressureBar: totalBar,
    oxygenPercent:
        (bank.pressureBar * bank.oxygenPercent +
            added.pressureBar * added.oxygenPercent) /
        totalBar,
    heliumPercent:
        (bank.pressureBar * bank.heliumPercent +
            added.pressureBar * added.heliumPercent) /
        totalBar,
  );
}

void main() {
  group('leftover attractiveness', () {
    test('exposes the five standard targets and the helium reference', () {
      expect(
        standardTargets
            .map((target) => [target.oxygenPercent, target.heliumPercent])
            .toList(),
        [
          [21, 35],
          [18, 45],
          [15, 55],
          [12, 65],
          [10, 70],
        ],
      );
      expect(scoreReferenceHeliumLitres, 1000);
    });

    test('invalid fractions score 0', () {
      double score(double oxygenPercent, double heliumPercent) =>
          leftoverAttractiveness(
            oxygenPercent: oxygenPercent,
            heliumPercent: heliumPercent,
            pressureBar: 100,
            volumeL: 10,
            maxPressureBar: 350,
          );
      expect(score(-1, 40), 0);
      expect(score(60, 50), 0);
      expect(score(double.nan, 40), 0);
    });

    test('heliox built from moles that sums to 100 plus float error is valid, not 0', () {
      // (2/11)*100 + (9/11)*100 = 100.00000000000001 in IEEE doubles.
      final oxygenPercent = (2 / 11) * 100;
      final heliumPercent = (9 / 11) * 100;
      expect(oxygenPercent + heliumPercent > 100, isTrue);
      final score = leftoverAttractiveness(
        oxygenPercent: oxygenPercent,
        heliumPercent: heliumPercent,
        pressureBar: 10,
        volumeL: 10,
        maxPressureBar: 350,
      );
      // All five targets reachable at 10 bar (max ratio 1.818 -> 18 bar <= 350). He energy: 10*10*(9/11) = 81.8 L -> 0.0818.
      final expected =
          100 *
          (0.4 * lineTerm(oxygenPercent, heliumPercent) +
              0.4 * 1 +
              0.2 * (100 * 9 / 11 / 100) * 10 * 10 / 1000);
      expect((score - expected).abs(), lessThan(1e-9));
      // Hand: line term exp(-15*0.37764/3.1) ~ 0.1736 -> 100*(0.0695 + 0.4 + 0.0164) ~ 48.58.
      expect(score > 48.5 && score < 48.7, isTrue);
    });

    test(
      'pure O2 reaches no standard target at 200 bar with a 350 bar max',
      () {
        // Every target needs at least 1/0.21 times the pure-O2 moles: 200 * 4.76 > 350.
        final score = leftoverAttractiveness(
          oxygenPercent: 100,
          heliumPercent: 0,
          pressureBar: 200,
          volumeL: 10,
          maxPressureBar: 350,
        );
        // Only the line term remains: 100 * 0.4 * exp(-15 * 2.077 / sqrt(3.077^2 + 1)).
        expect((score - 100 * 0.4 * lineTerm(100, 0)).abs(), lessThan(1e-9));
      },
    );

    test(
      'pure O2 with a 350 bar max is 5/5 reachable at 35 bar and 0/5 at 74 bar',
      () {
        double at(double pressureBar) => leftoverAttractiveness(
          oxygenPercent: 100,
          heliumPercent: 0,
          pressureBar: pressureBar,
          volumeL: 10,
          maxPressureBar: 350,
        );
        final at35 = at(35);
        final at74 = at(74);
        // Energy is zero (no He); line term is pressure-independent. Versatility 5/5 -> 0/5 is 40 points.
        expect(((at35 - at74) - 40).abs(), lessThan(1e-9));
        expect((at74 - 100 * 0.4 * lineTerm(100, 0)).abs(), lessThan(1e-9));
      },
    );

    test('pure He with a 350 bar max is 5/5 reachable at 122.5 bar and 4/5 just above', () {
      // 21/35 needs He ratio 1/0.35 = 2.857: 122.5 * 2.857 = 350 (inclusive); 122.6 exceeds the max.
      double at(double pressureBar) => leftoverAttractiveness(
        oxygenPercent: 0,
        heliumPercent: 100,
        pressureBar: pressureBar,
        volumeL: 10,
        maxPressureBar: 350,
      );
      final at1225 = at(122.5);
      final at1226 = at(122.6);
      final at122 = at(122);
      // Energy clamps at 1 for both (1220+ bar*L of He), so the only change is 21/35: 0.4 * 100 * 1/5 = 8.
      expect(((at1225 - at1226) - 8).abs(), lessThan(1e-9));
      expect((at122 - at1225).abs(), lessThan(1e-9));
      expect((at122 - 100 * (0.4 + 0.4 + 0.2)).abs(), lessThan(1e-9));
    });

    test(
      '18/45 at low pressure reaches all five targets and scores at least 80',
      () {
        // Energy: ideal free gas = P * V = 100 bar*L, helium 45 bar*L -> 0.045.
        final score = leftoverAttractiveness(
          oxygenPercent: 18,
          heliumPercent: 45,
          pressureBar: 10,
          volumeL: 10,
          maxPressureBar: 350,
        );
        final expected = 100 * (0.4 * lineTerm(18, 45) + 0.4 * 1 + 0.2 * 0.045);
        expect((score - expected).abs(), lessThan(1e-9));
        expect(score >= 80, isTrue);
      },
    );

    test('reachability boundary is inclusive for an exact ratio of 1', () {
      // 21/35 gas: top-up ratio to 21/35 is exactly 1 (every component matches), to 18/45 it is 1.1667.
      // At P = max = 200 only 21/35 is reachable; at max 199.99 it is not, so the score drops by 0.4*100*(1/5) = 8.
      double at(double maxPressureBar) => leftoverAttractiveness(
        oxygenPercent: 21,
        heliumPercent: 35,
        pressureBar: 200,
        volumeL: 10,
        maxPressureBar: maxPressureBar,
      );
      final atBoundary = at(200);
      final justBelow = at(199.99);
      expect(((atBoundary - justBelow) - 8).abs(), lessThan(1e-9));
    });

    test('energy term is zero for helium-free gas', () {
      // 21/0 at 100 bar: reaches 21/35, 18/45, 15/55, 12/65 (N2 ratio 0.79/0.23 * 100 = 343.5 <= 350), not 10/70 (395).
      final score = leftoverAttractiveness(
        oxygenPercent: 21,
        heliumPercent: 0,
        pressureBar: 100,
        volumeL: 10,
        maxPressureBar: 350,
      );
      expect(
        (score - 100 * (0.4 * lineTerm(21, 0) + 0.4 * 0.8)).abs(),
        lessThan(1e-9),
      );
    });

    test(
      'energy term scales with helium litres below 1000 and clamps at 1000',
      () {
        // Pure He at 200 bar: line 1, versatility 2/5, He litres = 200 * V.
        // V = 2 -> 400 bar*L -> 0.4; V = 10 and V = 20 both clamp to 1.
        double at(double volumeL) => leftoverAttractiveness(
          oxygenPercent: 0,
          heliumPercent: 100,
          pressureBar: 200,
          volumeL: volumeL,
          maxPressureBar: 350,
        );
        final small = at(2);
        final tenL = at(10);
        final twentyL = at(20);
        expect(
          (small - 100 * (0.4 + 0.4 * 0.4 + 0.2 * 0.4)).abs(),
          lessThan(1e-9),
        );
        expect((tenL - 100 * (0.4 + 0.4 * 0.4 + 0.2)).abs(), lessThan(1e-9));
        expect(tenL, twentyL);
      },
    );

    test('moving a mix off the line lowers the score at the same state', () {
      double at(double heliumPercent) => leftoverAttractiveness(
        oxygenPercent: 18,
        heliumPercent: heliumPercent,
        pressureBar: 10,
        volumeL: 10,
        maxPressureBar: 350,
      );
      final onLine = at(45);
      final offLine = at(50);
      expect(offLine < onLine, isTrue);
    });

    test('12/65 dump into a 21/35 bank at 100 bar of 200 max lowers the score by about 6 (refused by the -2 gate)', () {
      final bank = (
        pressureBar: 100.0,
        oxygenPercent: 21.0,
        heliumPercent: 35.0,
      );
      final dump = (
        pressureBar: 10.0,
        oxygenPercent: 12.0,
        heliumPercent: 65.0,
      );
      final mixed = mixAtSameVolume(bank, dump);
      final before = leftoverAttractiveness(
        oxygenPercent: bank.oxygenPercent,
        heliumPercent: bank.heliumPercent,
        pressureBar: bank.pressureBar,
        volumeL: 12,
        maxPressureBar: 200,
      );
      final after = leftoverAttractiveness(
        oxygenPercent: mixed.oxygenPercent,
        heliumPercent: mixed.heliumPercent,
        pressureBar: mixed.pressureBar,
        volumeL: 12,
        maxPressureBar: 200,
      );
      // Hand arithmetic: 12/65 becomes unreachable (N2 0.4209 * 110 = 46.3 bar-equivalent ratio -> 201.3 > 200): -8.
      // Helium energy 420 -> 498 bar*L adds +1.56; line term moves +0.39. Net about -6.05.
      final delta = after - before;
      expect(delta > -6.2 && delta < -5.9, isTrue, reason: 'delta $delta');
      expect(delta < -2, isTrue);
    });

    test('the same 21/35 bank at 45 bar of 12/65 at 50 bar raises the score by about 7 (accepted)', () {
      final bank = (
        pressureBar: 45.0,
        oxygenPercent: 21.0,
        heliumPercent: 35.0,
      );
      final dump = (
        pressureBar: 50.0,
        oxygenPercent: 12.0,
        heliumPercent: 65.0,
      );
      final mixed = mixAtSameVolume(bank, dump);
      final before = leftoverAttractiveness(
        oxygenPercent: bank.oxygenPercent,
        heliumPercent: bank.heliumPercent,
        pressureBar: bank.pressureBar,
        volumeL: 12,
        maxPressureBar: 200,
      );
      final after = leftoverAttractiveness(
        oxygenPercent: mixed.oxygenPercent,
        heliumPercent: mixed.heliumPercent,
        pressureBar: mixed.pressureBar,
        volumeL: 12,
        maxPressureBar: 200,
      );
      // Reachability stays 5/5. Helium energy 189 -> 579 L adds +7.8; line term drops about 0.82. Net about +6.98.
      final delta = after - before;
      expect(delta > 6.8 && delta < 7.2, isTrue, reason: 'delta $delta');
    });

    test('reachability counts the standard targets a bank can still be topped up to within its max pressure', () {
      // 21/35 gas at exactly its max pressure reaches only the 21/35 target (ratio 1).
      expect(
        leftoverReachability(
          oxygenPercent: 21,
          heliumPercent: 35,
          pressureBar: 200,
          maxPressureBar: 200,
        ),
        1,
      );
      expect(
        leftoverReachability(
          oxygenPercent: 21,
          heliumPercent: 35,
          pressureBar: 200,
          maxPressureBar: 199.99,
        ),
        0,
      );
      // Pure O2 reaches all five at 35 bar with a 350 bar max, and none at 74 bar.
      expect(
        leftoverReachability(
          oxygenPercent: 100,
          heliumPercent: 0,
          pressureBar: 35,
          maxPressureBar: 350,
        ),
        5,
      );
      expect(
        leftoverReachability(
          oxygenPercent: 100,
          heliumPercent: 0,
          pressureBar: 74,
          maxPressureBar: 350,
        ),
        0,
      );
      // Invalid fractions or pressures reach nothing.
      expect(
        leftoverReachability(
          oxygenPercent: 60,
          heliumPercent: 60,
          pressureBar: 10,
          maxPressureBar: 200,
        ),
        0,
      );
      expect(
        leftoverReachability(
          oxygenPercent: 18,
          heliumPercent: 45,
          pressureBar: -1,
          maxPressureBar: 200,
        ),
        0,
      );
    });
  });
}

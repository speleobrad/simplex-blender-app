import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/physics.dart';
import 'package:simplex_blender/src/domain/pure_prices.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

const double _t = 21;
const PhysicsInput ideal = PhysicsInput(model: 'ideal', temperatureC: _t);
const PhysicsInput vdw = PhysicsInput(model: 'vdw', temperatureC: _t);

Bank bank({
  String id = 'b',
  String name = 'B',
  double volumeL = 10,
  double pressureBar = 100,
  double oxygenPercent = 100,
  double heliumPercent = 0,
  bool enabled = true,
  double? pricePerLitre = 0.02,
}) => Bank(
  id: id,
  name: name,
  volumeL: volumeL,
  pressureBar: pressureBar,
  oxygenPercent: oxygenPercent,
  heliumPercent: heliumPercent,
  enabled: enabled,
  pricePerLitre: pricePerLitre,
);

Bank o2({
  String id = 'b',
  double volumeL = 10,
  double pressureBar = 100,
  double? pricePerLitre = 0.02,
  bool enabled = true,
}) => bank(
  id: id,
  volumeL: volumeL,
  pressureBar: pressureBar,
  oxygenPercent: 100,
  heliumPercent: 0,
  pricePerLitre: pricePerLitre,
  enabled: enabled,
);

Bank he({
  String id = 'b',
  double volumeL = 10,
  double pressureBar = 100,
  double? pricePerLitre = 0.02,
  bool enabled = true,
}) => bank(
  id: id,
  volumeL: volumeL,
  pressureBar: pressureBar,
  oxygenPercent: 0,
  heliumPercent: 100,
  pricePerLitre: pricePerLitre,
  enabled: enabled,
);

void main() {
  // Ideal gas: free-gas litres = (P / (R·T)) × V × (R·T) = P × V, so the weights below are
  // exact: 10 L at 150 bar -> 1500 L, 20 L at 100 bar -> 2000 L.
  test('oxygen price is the free-gas-litre weighted average of priced pure O2 banks', () {
    final prices = pureGasPrices(
      banks: [
        o2(id: 'a', volumeL: 10, pressureBar: 150, pricePerLitre: 0.02),
        o2(id: 'b', volumeL: 20, pressureBar: 100, pricePerLitre: 0.03),
      ],
      physics: ideal,
      inventoryTemperatureC: _t,
    );
    // Litre weighting gives 90 / 3500 = 0.025714; the volume-only average (0.026667) differs by > 5e-4.
    expect(prices.oxygen, closeTo(90 / 3500, 1e-12));
    expect(
      (prices.oxygen! - (10 * 0.02 + 20 * 0.03) / 30).abs() > 5e-4,
      isTrue,
    );
    expect(prices.helium, isNull);
  });

  test(
    'disabled, unpriced and non-pure banks are excluded from the average',
    () {
      final prices = pureGasPrices(
        banks: [
          o2(id: 'a', volumeL: 10, pressureBar: 150, pricePerLitre: 0.02),
          o2(
            id: 'off',
            volumeL: 50,
            pressureBar: 200,
            pricePerLitre: 9,
            enabled: false,
          ),
          o2(id: 'free', volumeL: 30, pressureBar: 200, pricePerLitre: null),
          bank(
            id: 'tx',
            oxygenPercent: 21,
            heliumPercent: 35,
            volumeL: 40,
            pressureBar: 200,
            pricePerLitre: 7,
          ),
          bank(
            id: 'near',
            oxygenPercent: 99,
            heliumPercent: 0,
            volumeL: 40,
            pressureBar: 200,
            pricePerLitre: 7,
          ),
        ],
        physics: ideal,
        inventoryTemperatureC: _t,
      );
      // Only bank a counts: 1500 × 0.02 / 1500
      expect(prices.oxygen, closeTo(0.02, 1e-12));
    },
  );

  test('helium price uses only pure helium banks with the same weighting', () {
    final prices = pureGasPrices(
      banks: [
        he(id: 'h1', volumeL: 5, pressureBar: 200, pricePerLitre: 0.1),
        he(id: 'h2', volumeL: 10, pressureBar: 100, pricePerLitre: 0.2),
      ],
      physics: ideal,
      inventoryTemperatureC: _t,
    );
    // (1000 × 0.1 + 1000 × 0.2) / 2000
    expect(prices.helium, closeTo(0.15, 1e-12));
    expect(prices.oxygen, isNull);
  });

  test('no priced pure bank of a gas gives null for that gas', () {
    final prices = pureGasPrices(
      banks: [
        o2(pricePerLitre: null),
        he(enabled: false),
        bank(oxygenPercent: 21, heliumPercent: 35),
      ],
      physics: ideal,
      inventoryTemperatureC: _t,
    );
    expect(prices, const PureGasPrices(oxygen: null, helium: null));
    expect(
      pureGasPrices(banks: const [], physics: ideal, inventoryTemperatureC: _t),
      const PureGasPrices(oxygen: null, helium: null),
    );
  });

  test(
    'a priced pure bank with no free gas contributes no weight and yields null',
    () {
      final prices = pureGasPrices(
        banks: [o2(pressureBar: 0, pricePerLitre: 0.02)],
        physics: ideal,
        inventoryTemperatureC: _t,
      );
      expect(prices.oxygen, isNull);
    },
  );

  test('vdw physics weights by the vdw free-gas litres at the inventory temperature', () {
    final low = o2(id: 'a', volumeL: 10, pressureBar: 150, pricePerLitre: 0.02);
    final high = o2(
      id: 'b',
      volumeL: 10,
      pressureBar: 300,
      pricePerLitre: 0.04,
    );
    double weightOf(Bank b) =>
        calcMolarDensity(
          b.pressureBar,
          b.oxygenPercent,
          b.heliumPercent,
          15,
          true,
        ) *
        b.volumeL *
        litresPerMole(15);
    final expected =
        (weightOf(low) * 0.02 + weightOf(high) * 0.04) /
        (weightOf(low) + weightOf(high));
    final prices = pureGasPrices(
      banks: [low, high],
      physics: vdw,
      inventoryTemperatureC: 15,
    );
    expect(prices.oxygen, closeTo(expected, 1e-12));
  });

  test('isPureOxygenBank and isPureHeliumBank require an enabled bank at exactly 100/0 or 0/100', () {
    expect(isPureOxygenBank(o2()), isTrue);
    expect(isPureOxygenBank(he()), isFalse);
    expect(isPureOxygenBank(o2(enabled: false)), isFalse);
    expect(
      isPureOxygenBank(bank(oxygenPercent: 99.9, heliumPercent: 0)),
      isFalse,
    );
    expect(isPureHeliumBank(he()), isTrue);
    expect(isPureHeliumBank(o2()), isFalse);
    expect(isPureHeliumBank(he(enabled: false)), isFalse);
    expect(
      isPureHeliumBank(bank(oxygenPercent: 0, heliumPercent: 99.5)),
      isFalse,
    );
  });

  test('isPureBank is true for either pure gas and false for mixes', () {
    expect(isPureBank(o2()), isTrue);
    expect(isPureBank(he()), isTrue);
    expect(isPureBank(bank(oxygenPercent: 21, heliumPercent: 35)), isFalse);
    expect(isPureBank(o2(enabled: false)), isFalse);
  });

  test('isPureComposition ignores enabled and is true only for exact pure O2 or He', () {
    expect(isPureComposition(o2()), isTrue);
    expect(isPureComposition(he()), isTrue);
    expect(isPureComposition(o2(enabled: false)), isTrue);
    expect(
      isPureComposition(bank(oxygenPercent: 21, heliumPercent: 35)),
      isFalse,
    );
    expect(
      isPureComposition(bank(oxygenPercent: 99.9, heliumPercent: 0)),
      isFalse,
    );
  });

  test('bankFreeGasLitres is the free-gas litres a bank holds at the inventory temperature', () {
    expect(
      bankFreeGasLitres(o2(volumeL: 10, pressureBar: 150), ideal, _t),
      closeTo(1500, 1e-9),
    );
    final expected =
        calcMolarDensity(150, 100, 0, 15, true) * 10 * litresPerMole(15);
    expect(
      bankFreeGasLitres(o2(volumeL: 10, pressureBar: 150), vdw, 15),
      closeTo(expected, 1e-9),
    );
    expect(bankFreeGasLitres(o2(pressureBar: 0), ideal, _t), 0);
  });

  test('pricePerLitreFromFullTank divides the tank price by the free-gas litres once', () {
    expect(pricePerLitreFromFullTank(30, 1500), closeTo(0.02, 1e-12));
    expect(pricePerLitreFromFullTank(0, 1500), 0);
    expect(pricePerLitreFromFullTank(30, 0), isNull);
    expect(pricePerLitreFromFullTank(30, -1), isNull);
    expect(pricePerLitreFromFullTank(-1, 1500), isNull);
    expect(pricePerLitreFromFullTank(double.nan, 1500), isNull);
    expect(pricePerLitreFromFullTank(30, double.nan), isNull);
  });

  test('a full-tank price converts at the inventory temperature, not the ambient temperature', () {
    // Real gas: free-gas litres depend on temperature, so the same full-tank price gives a
    // different per-litre price at 5 °C than at 35 °C. Ambient is irrelevant to the conversion.
    final cold = bankFreeGasLitres(o2(volumeL: 10, pressureBar: 150), vdw, 5);
    final warm = bankFreeGasLitres(o2(volumeL: 10, pressureBar: 150), vdw, 35);
    expect(cold > warm, isTrue, reason: 'colder gas holds more free litres');
    final expectedCold =
        calcMolarDensity(150, 100, 0, 5, true) * 10 * litresPerMole(5);
    expect(cold, closeTo(expectedCold, 1e-9));
    expect(
      pricePerLitreFromFullTank(30, cold),
      closeTo(30 / expectedCold, 1e-12),
    );
    expect(
      pricePerLitreFromFullTank(30, cold),
      isNot(pricePerLitreFromFullTank(30, warm)),
    );
  });
}

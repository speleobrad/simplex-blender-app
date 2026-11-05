import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/savings.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

// Ideal physics makes every free-gas litre count exactly P × V, independent of temperature.
const PhysicsInput physics = PhysicsInput(model: 'ideal', temperatureC: 20);
const double inventoryTemperatureC = 20;
const Costs costs = Costs(
  currencySymbol: '',
  leftoverDiscountPercent: 10,
  operationPrices: OperationPrices(boost: 2, decant: 1, topUp: 5),
);

Bank bank({
  String id = 'b',
  String name = 'B',
  double volumeL = 10,
  double pressureBar = 150,
  double oxygenPercent = 32,
  double heliumPercent = 0,
  bool enabled = true,
  double? pricePerLitre,
  bool unpriced = false,
}) => Bank(
  id: id,
  name: name,
  volumeL: volumeL,
  pressureBar: pressureBar,
  oxygenPercent: oxygenPercent,
  heliumPercent: heliumPercent,
  enabled: enabled,
  pricePerLitre: unpriced ? null : pricePerLitre,
);

final Bank pureO2 = bank(
  id: 'o2',
  name: 'O2 bottle',
  oxygenPercent: 100,
  pricePerLitre: 0.02,
);
final Bank pureHe = bank(
  id: 'he',
  name: 'He bottle',
  oxygenPercent: 0,
  heliumPercent: 100,
  pricePerLitre: 0.05,
);
final Bank real = bank(
  id: 'real',
  name: 'EAN32',
  volumeL: 12,
  pricePerLitre: 0.001,
);

final double perMole = litresPerMole(physics.temperatureC);

// A decant from [sourceBankId] that consumed [litres] of free gas.
FillStep decantFrom(String sourceBankId, double litres, {String id = 'op-1'}) =>
    FillStep(
      costOperation: 'decant',
      costOperationId: id,
      sourceBankId: sourceBankId,
      sourceConsumedMoles: litres / perMole,
    );

SavingsResult run({
  required List<Bank> banks,
  List<FillStep> steps = const <FillStep>[],
  double? heliumRetainedLitres = 100,
  bool? feasible,
  double? discountPercent,
}) => computeSavings(
  heliumRetainedLitres: heliumRetainedLitres,
  feasible: feasible,
  protocolSteps: steps,
  banks: banks,
  costs: discountPercent == null
      ? costs
      : Costs(
          currencySymbol: costs.currencySymbol,
          leftoverDiscountPercent: discountPercent,
          operationPrices: costs.operationPrices,
        ),
  settings: DEFAULT_SETTINGS,
  physics: physics,
  inventoryTemperatureC: inventoryTemperatureC,
);

// EAN32 at 150 bar, 12 L, ideal: litres = 1800. Recipe cost = 6 (top-up 5 + decant 1) + 0.02·b·1800,
// with b = 0.32 − 0.21 × 0.68 / 0.79 (O2 needed beyond air). Per litre = 6/1800 + 0.02·b.
final double ean32RecipePerLitre =
    6 / 1800 + 0.02 * (0.32 - 0.21 * 0.68 / 0.79);
const double usedL = 360;
final double ean32Salvage = usedL * ean32RecipePerLitre;

void main() {
  test('reuse value is retained helium litres times the weighted pure helium price', () {
    // Two He banks, weights 10 L × 150 bar = 1500 and 5 L × 150 bar = 750 (ideal litres = P·V).
    // Weighted He = (1500 × 0.05 + 750 × 0.11) / 2250 = 0.07. Saved = 100 × 0.07 = 7.
    final heSmall = bank(
      id: 'he2',
      name: 'He small',
      volumeL: 5,
      oxygenPercent: 0,
      heliumPercent: 100,
      pricePerLitre: 0.11,
    );
    final result = run(banks: [pureO2, pureHe, heSmall]);
    expect(result.savedCost, closeTo(7, 1e-9));
    expect(result.missing, isEmpty);
  });

  test('no helium price with helium retained makes reuse value null and names helium as a pure-price gap', () {
    final result = run(banks: [pureO2, real]);
    expect(result.savedCost, isNull);
    expect(result.missing, [const PurePriceGap(gas: 'helium')]);
  });

  test('no helium retained gives zero reuse value without asking for a helium price', () {
    final result = run(banks: [pureO2, real], heliumRetainedLitres: 0);
    expect(result.savedCost, 0);
    expect(result.missing, isEmpty);
  });

  test('no feasible result gives null savings and no gas prompt', () {
    final result = run(
      banks: [pureO2, real],
      steps: [decantFrom('real', 360)],
      feasible: false,
    );
    expect(result.savedCost, isNull);
    expect(result.salvagedSaving, isNull);
    expect(result.missing, isEmpty);

    final noBlend = computeSavings(
      heliumRetainedLitres: null,
      feasible: null,
      protocolSteps: const <FillStep>[],
      banks: [pureO2, real],
      costs: costs,
      settings: DEFAULT_SETTINGS,
      physics: physics,
      inventoryTemperatureC: inventoryTemperatureC,
    );
    expect(noBlend.savedCost, isNull);
    expect(noBlend.salvagedSaving, isNull);
    expect(noBlend.missing, isEmpty);
  });

  test('salvage is litres used × discount-0 recipe price per litre, with no subtraction of the stored price', () {
    // The stored price 0.001 is not subtracted: the value is the avoided purchase of the same litres.
    final result = run(
      banks: [pureO2, pureHe, real],
      steps: [decantFrom('real', usedL)],
    );
    expect(result.salvagedSaving, closeTo(ean32Salvage, 1e-6));
    expect(result.missing, isEmpty);
  });

  test('salvage does not depend on the leftover discount', () {
    // The avoided purchase is undiscounted: a 0% and a 50% leftover discount give the same result.
    SavingsResult withDiscount(double percent) => run(
      banks: [pureO2, pureHe, real],
      steps: [decantFrom('real', usedL)],
      discountPercent: percent,
    );
    final none = withDiscount(0);
    final half = withDiscount(50);
    expect(none.salvagedSaving, closeTo(ean32Salvage, 1e-6));
    expect(half.salvagedSaving, none.salvagedSaving);
    expect(half.missing, none.missing);
  });

  test('salvage is independent of the stored price of the leftover bank', () {
    // A stored price far above the recipe price (5 vs ~0.0077/L) gives the same avoided purchase.
    final farAbove = bank(
      id: 'real',
      name: 'EAN32',
      volumeL: 12,
      pricePerLitre: 5,
    );
    final result = run(
      banks: [pureO2, pureHe, farAbove],
      steps: [decantFrom('real', usedL)],
    );
    expect(result.salvagedSaving, closeTo(ean32Salvage, 1e-6));
    expect(result.missing, isEmpty);
  });

  test('an unpriced leftover bank is included in salvage and raises no missing entry', () {
    final unpriced = bank(
      id: 'real',
      name: 'EAN32',
      volumeL: 12,
      unpriced: true,
    );
    final result = run(
      banks: [pureO2, pureHe, unpriced],
      steps: [decantFrom('real', usedL)],
    );
    expect(result.salvagedSaving, closeTo(ean32Salvage, 1e-6));
    expect(result.missing, isEmpty);
  });

  test('salvage sums the avoided purchase over every used leftover bank', () {
    final unpriced = bank(
      id: 'real2',
      name: 'EAN32 two',
      volumeL: 12,
      unpriced: true,
    );
    final result = run(
      banks: [pureO2, pureHe, real, unpriced],
      steps: [
        decantFrom('real', usedL, id: 'op-1'),
        decantFrom('real2', 100, id: 'op-2'),
      ],
    );
    expect(
      result.salvagedSaving,
      closeTo(ean32Salvage + 100 * ean32RecipePerLitre, 1e-6),
    );
    expect(result.missing, isEmpty);
  });

  test('a used pure bank is not a salvage source', () {
    final result = run(
      banks: [pureO2, pureHe, real],
      steps: [decantFrom('o2', 100)],
    );
    expect(result.salvagedSaving, 0);
    expect(result.missing, isEmpty);
  });

  test('a missing pure oxygen price makes salvage null and names oxygen as a pure-price gap', () {
    final result = run(
      banks: [pureHe, real],
      steps: [decantFrom('real', usedL)],
    );
    expect(result.salvagedSaving, isNull);
    expect(result.missing, [
      const PurePriceGap(gas: 'oxygen', bankId: 'real', name: 'EAN32'),
    ]);
  });

  test('a bank the recipe cannot price for equipment reasons makes salvage null and names the bank', () {
    final low = bank(
      id: 'real',
      name: 'EAN32',
      volumeL: 12,
      pressureBar: 9.5,
      pricePerLitre: 0.001,
    );
    final result = run(
      banks: [pureO2, pureHe, low],
      steps: [decantFrom('real', usedL)],
    );
    expect(result.salvagedSaving, isNull);
    expect(result.missing, [
      const RecipeUnavailableGap(bankId: 'real', name: 'EAN32'),
    ]);
  });

  test('a gas line whose source bank is not in the inventory is a recipe-unavailable gap, not a throw', () {
    final result = run(
      banks: [pureO2, pureHe],
      steps: [decantFrom('gone', usedL)],
    );
    expect(result.salvagedSaving, isNull);
    expect(result.missing, [
      const RecipeUnavailableGap(bankId: 'gone', name: 'gone'),
    ]);
  });

  test('missing entries are deduplicated', () {
    final low = bank(
      id: 'real',
      name: 'EAN32',
      volumeL: 12,
      pressureBar: 9.5,
      pricePerLitre: 0.001,
    );
    final result = run(
      banks: [pureO2, pureHe, low],
      steps: [
        decantFrom('real', 100, id: 'op-1'),
        decantFrom('real', 100, id: 'op-2'),
      ],
    );
    expect(result.missing, [
      const RecipeUnavailableGap(bankId: 'real', name: 'EAN32'),
    ]);
  });

  test('computeSavings does not mutate the result, banks or costs', () {
    final banks = [pureO2, pureHe, real];
    final steps = [decantFrom('real', 360)];
    final before = [for (final b in banks) (b.id, b.pricePerLitre, b.volumeL)];
    final first = run(banks: banks, steps: steps);
    final second = run(banks: banks, steps: steps);
    expect([for (final b in banks) (b.id, b.pricePerLitre, b.volumeL)], before);
    expect(second.salvagedSaving, first.salvagedSaving);
    expect(second.savedCost, first.savedCost);
    expect(steps.single.sourceBankId, 'real');
    expect(steps.single.sourceConsumedMoles, 360 / perMole);
  });
}

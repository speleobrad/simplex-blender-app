import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/bank_pricing.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/physics.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

const PhysicsInput physics = PhysicsInput(model: 'vdw', temperatureC: 20);
const double inventoryTemperatureC = 20;

Costs costsWith({double leftoverDiscountPercent = 0}) => Costs(
  currencySymbol: '',
  leftoverDiscountPercent: leftoverDiscountPercent,
  operationPrices: const OperationPrices(boost: 2, decant: 1, topUp: 5),
);

Costs zeroCosts() => const Costs(
  currencySymbol: '',
  leftoverDiscountPercent: 0,
  operationPrices: OperationPrices(boost: 0, decant: 0, topUp: 0),
);

Settings settingsWith([
  SettingsBooster Function(SettingsBooster booster)? mutate,
]) {
  final booster = mutate == null
      ? DEFAULT_SETTINGS.booster
      : mutate(DEFAULT_SETTINGS.booster);
  return DEFAULT_SETTINGS.copyWith(costs: costsWith(), booster: booster);
}

/// Field-level copy of [s]. `Settings` has no `==` (JS compares by
/// `JSON.stringify`), so mutation is detected by comparing this snapshot.
Map<String, Object?> settingsSnapshot(Settings s) => <String, Object?>{
  'units': s.units,
  'pressureLimitMode': s.pressureLimitMode,
  'pressureWarningUnlocked': s.pressureWarningUnlocked,
  'interimPressureTolerancePercent': s.interimPressureTolerancePercent,
  'costs.currencySymbol': s.costs.currencySymbol,
  'costs.leftoverDiscountPercent': s.costs.leftoverDiscountPercent,
  'costs.boost': s.costs.operationPrices.boost,
  'costs.decant': s.costs.operationPrices.decant,
  'costs.topUp': s.costs.operationPrices.topUp,
  'physics.model': s.physics.model,
  'gasPresets': s.gasPresets,
  'compressorPresets': s.compressorPresets,
  'boosterPresets': s.boosterPresets,
  'cylinderPresets': s.cylinderPresets,
  'booster': s.booster,
};

Bank makeBank({
  String id = 'real',
  String name = 'Real',
  double volumeL = 12,
  double pressureBar = 150,
  double oxygenPercent = 32,
  double heliumPercent = 0,
  bool enabled = true,
  double? pricePerLitre,
}) {
  return Bank(
    id: id,
    name: name,
    volumeL: volumeL,
    pressureBar: pressureBar,
    oxygenPercent: oxygenPercent,
    heliumPercent: heliumPercent,
    enabled: enabled,
    pricePerLitre: pricePerLitre,
  );
}

// Priced pure banks. Each gas has one bank, so its weighted price is exactly its stored price.
List<Bank> inventory() => <Bank>[
  makeBank(
    id: 'o2',
    name: 'O2',
    volumeL: 10,
    pressureBar: 150,
    oxygenPercent: 100,
    heliumPercent: 0,
    pricePerLitre: 0.02,
  ),
  makeBank(
    id: 'he',
    name: 'He',
    volumeL: 10,
    pressureBar: 150,
    oxygenPercent: 0,
    heliumPercent: 100,
    pricePerLitre: 0.05,
  ),
];

BankPriceResult priceWith({
  Bank? bank,
  Costs? costs,
  Settings? settings,
  PhysicsInput? physicsInput,
  List<Bank>? inventoryBanks,
}) {
  return priceBankByRecipe(
    bank: bank ?? makeBank(),
    costs: costs ?? costsWith(),
    settings: settings ?? settingsWith(),
    physics: physicsInput ?? physics,
    inventoryBanks: inventoryBanks ?? inventory(),
    inventoryTemperatureC: inventoryTemperatureC,
  );
}

BankPriceOk okOf(BankPriceResult result) {
  expect(
    result.ok,
    isTrue,
    reason: result is BankPriceFailure ? result.reason : null,
  );
  return result as BankPriceOk;
}

BankPriceFailure failOf(BankPriceResult result) {
  expect(result.ok, isFalse);
  return result as BankPriceFailure;
}

final double minSourceBar = DEFAULT_SETTINGS.booster.minimumSourcePressureBar;

// Hand-computed virtual source count for one gas, independent of the sizing in bank_pricing.dart:
//   needMoles    = calcMolarDensity(bankP, O2%, He%, 20 C, vdw) × volumeL × (that gas's percent / 100)
//   perBankMoles = (calcMolarDensity(200 bar, pure gas) − calcMolarDensity(minSourceBar, pure gas)) × 200 L
//   count        = ceil(2 × needMoles / perBankMoles), or 0 when needMoles is 0
int gasCount(String gas, Bank b) {
  final pureO2 = gas == 'O2' ? 100.0 : 0.0;
  final pureHe = gas == 'O2' ? 0.0 : 100.0;
  final percent = gas == 'O2' ? b.oxygenPercent : b.heliumPercent;
  final needMoles =
      calcMolarDensity(
        b.pressureBar,
        b.oxygenPercent,
        b.heliumPercent,
        20,
        true,
      ) *
      b.volumeL *
      percent /
      100;
  if (!(needMoles > 0)) {
    return 0;
  }
  final perBankMoles =
      (calcMolarDensity(200, pureO2, pureHe, 20, true) -
          calcMolarDensity(minSourceBar, pureO2, pureHe, 20, true)) *
      200;
  return (2 * needMoles / perBankMoles).ceil();
}

void main() {
  test('virtualBankCount is 0 for an absent gas and 2x margin otherwise', () {
    expect(virtualBankCount(needMoles: 0, perBankMoles: 1000), 0);
    expect(virtualBankCount(needMoles: 100, perBankMoles: 1000), 1);
    expect(virtualBankCount(needMoles: 1000, perBankMoles: 1000), 2);
    expect(virtualBankCount(needMoles: 1001, perBankMoles: 1000), 3);
  });

  test('a pure bank is refused: pure banks have no Calculate price', () {
    final result = failOf(
      priceWith(bank: makeBank(oxygenPercent: 100, heliumPercent: 0)),
    );
    expect(result.reason, contains('Pure banks'));
  });

  test('discount applies once and 100 percent gives zero', () {
    final base = okOf(priceWith());
    expect(base.pricePerLitre, greaterThan(0));
    final half = okOf(priceWith(costs: costsWith(leftoverDiscountPercent: 50)));
    expect(half.pricePerLitre, closeTo(base.pricePerLitre / 2, 1e-12));
    final free = okOf(
      priceWith(costs: costsWith(leftoverDiscountPercent: 100)),
    );
    expect(free.pricePerLitre, 0.0);
  });

  test('EAN32 at 150 bar: O2 litres at the O2 price plus one top-up and one decant', () {
    final result = okOf(priceWith());
    // Hand check, vdw at 20 C, 12 L. M = total moles = calcMolarDensity(150, 32, 0, 20, true) × 12.
    // Air (21% O2, 79% N2) supplies N2 = 0.68·M, so air = 0.68·M / 0.79 and its O2 = 0.21 × 0.68 × M / 0.79.
    // Pure O2 supplies the rest: 0.32·M − 0.21 × 0.68·M / 0.79 = b·M, with b = 0.32 − 0.21 × 0.68 / 0.79.
    // Cost = one top-up (5) + one decant (1) + b·M·litresPerMole(20) × 0.02 (O2 price).
    final perMole = litresPerMole(20);
    final m = calcMolarDensity(150, 32, 0, 20, true) * 12;
    expect(result.litres, closeTo(m * perMole, 1e-9));
    final b = 0.32 - 0.21 * 0.68 / 0.79;
    expect(
      result.recipeCost,
      closeTo(6 + b * m * perMole * 0.02, 1e-6),
      reason: '${result.recipeCost}',
    );
    expect(
      result.pricePerLitre,
      closeTo(result.recipeCost / result.litres, 1e-12),
    );
    expect(result.operationCount['topUp'], 1);
    expect(result.operationCount['decant'], 1);
    expect(result.operationCount['boost'], isNull);
  });

  test('Tx21/35 at 150 bar uses O2 and He sources: one decant per source bank plus one top-up', () {
    final result = okOf(
      priceWith(
        bank: makeBank(oxygenPercent: 21, heliumPercent: 35, pressureBar: 150),
      ),
    );
    // The planner decants O2 and He separately (two distinct costOperationIds), so each is one decant fee.
    expect(result.operationCount['topUp'], 1);
    expect(result.operationCount['decant'], 2);
    expect(result.recipeCost, greaterThanOrEqualTo(5));
  });

  test('ideal and vdw physics give different litres for the same bank', () {
    final vdw = okOf(priceWith());
    final ideal = okOf(
      priceWith(
        physicsInput: const PhysicsInput(model: 'ideal', temperatureC: 20),
      ),
    );
    final idealMoles = calcMolarDensity(150, 32, 0, 20, false) * 12;
    expect(ideal.litres, closeTo(idealMoles * litresPerMole(20), 1e-9));
    expect((vdw.litres - ideal.litres).abs(), greaterThan(1e-6));
  });

  test(
    'compressor ceiling: a top-up within the ceiling is priced with one fee',
    () {
      final result = okOf(
        priceWith(
          settings: settingsWith(
            (b) => b.copyWith(maxCompressorPressureBar: 140),
          ),
        ),
      );
      expect(result.operationCount['topUp'], 1);
    },
  );

  test('compressor ceiling below the target makes the mix unpriceable', () {
    final result = failOf(
      priceWith(
        settings: settingsWith(
          (b) => b.copyWith(maxCompressorPressureBar: 100),
        ),
      ),
    );
    expect(result.reason, matches(RegExp('Compressor Air cannot top up')));
    expect(
      result.missingGas,
      isNull,
      reason: 'an equipment failure names no pure gas',
    );
  });

  test('a bank below 10 bar fails without a price', () {
    final result = failOf(priceWith(bank: makeBank(pressureBar: 9.5)));
    expect(result.reason, matches(RegExp('10 bar')));
  });

  test('a hypoxic mix that air plus pure O2 and He cannot make fails without a price', () {
    final result = failOf(
      priceWith(bank: makeBank(oxygenPercent: 10, heliumPercent: 0)),
    );
    expect(result.reason, matches(RegExp('exact target mix cannot be made')));
  });

  test('more than 6 virtual banks for one gas fails without a price', () {
    final result = failOf(
      priceWith(
        bank: makeBank(
          oxygenPercent: 99.5,
          heliumPercent: 0,
          volumeL: 200,
          pressureBar: 350,
        ),
        settings: settingsWith(
          (b) => b.copyWith(
            minimumSourcePressureBar: 150,
            maxBoosterOutputPressureBar: 350,
          ),
        ),
      ),
    );
    expect(
      result.reason,
      matches(RegExp('more than 6 virtual oxygen sources')),
    );
    expect(
      result.missingGas,
      isNull,
      reason: 'a source-count failure names no pure gas',
    );
  });

  test('zero flat fees with no priced pure bank name the needed oxygen', () {
    final result = failOf(
      priceWith(costs: zeroCosts(), inventoryBanks: const <Bank>[]),
    );
    expect(
      result.reason,
      matches(RegExp('Set a price on a pure oxygen bank first')),
    );
    expect(result.missingGas, 'oxygen');
  });

  test('no fees and no pure price, with no pure gas needed, report that no prices are configured', () {
    // A bank with no oxygen and no helium needs no pure gas, so no gas is named.
    final result = failOf(
      priceWith(
        bank: makeBank(oxygenPercent: 0, heliumPercent: 0),
        costs: zeroCosts(),
        inventoryBanks: const <Bank>[],
      ),
    );
    expect(
      result.reason,
      equals(
        'Nothing is priced yet. Set fees in Settings → Costs and a price on a pure oxygen or helium bank.',
      ),
    );
    expect(result.missingGas, isNull);
  });

  test('zero flat fees still price a bank from the pure-gas prices alone', () {
    final result = okOf(priceWith(costs: zeroCosts()));
    expect(result.recipeCost, greaterThan(0));
    final base = okOf(priceWith());
    // Removing the default fees: one top-up (5) plus one fee per decant.
    expect(
      result.recipeCost,
      equals(base.recipeCost - (5 + (base.operationCount['decant'] ?? 0))),
    );
  });

  test(
    'a needed pure oxygen gas with no priced pure O2 bank fails naming oxygen',
    () {
      final result = failOf(
        priceWith(
          inventoryBanks: inventory().where((b) => b.id != 'o2').toList(),
        ),
      );
      expect(
        result.reason,
        matches(RegExp('Set a price on a pure oxygen bank first')),
      );
      expect(result.missingGas, 'oxygen');
    },
  );

  test(
    'a needed pure helium gas with no priced pure He bank fails naming helium',
    () {
      final result = failOf(
        priceWith(
          bank: makeBank(oxygenPercent: 21, heliumPercent: 35),
          inventoryBanks: inventory().where((b) => b.id != 'he').toList(),
        ),
      );
      expect(
        result.reason,
        matches(RegExp('Set a price on a pure helium bank first')),
      );
      expect(result.missingGas, 'helium');
    },
  );

  test('a disabled pure bank is not a price source and names its gas', () {
    final disabled = inventory()
        .map((b) => b.id == 'o2' ? b.copyWith(enabled: false) : b)
        .toList();
    final result = failOf(priceWith(inventoryBanks: disabled));
    expect(result.reason, matches(RegExp('pure oxygen bank')));
    expect(result.missingGas, 'oxygen');
  });

  test('real banks, inventory and settings are not mutated', () {
    final b = makeBank();
    final s = settingsWith();
    final inv = inventory();
    final bBefore = b.copyWith();
    final sBefore = settingsSnapshot(s);
    final invBefore = inv.map((x) => x.copyWith()).toList();
    priceBankByRecipe(
      bank: b,
      costs: costsWith(),
      settings: s,
      physics: physics,
      inventoryBanks: inv,
      inventoryTemperatureC: inventoryTemperatureC,
    );
    expect(settingsSnapshot(s), equals(sBefore));
    expect(b.volumeL, bBefore.volumeL);
    expect(b.pressureBar, bBefore.pressureBar);
    expect(b.oxygenPercent, bBefore.oxygenPercent);
    expect(b.heliumPercent, bBefore.heliumPercent);
    expect(b.enabled, bBefore.enabled);
    expect(b.pricePerLitre, bBefore.pricePerLitre);
    expect(inv.length, invBefore.length);
    for (var i = 0; i < inv.length; i++) {
      expect(inv[i].id, invBefore[i].id);
      expect(inv[i].pricePerLitre, invBefore[i].pricePerLitre);
      expect(inv[i].enabled, invBefore[i].enabled);
      expect(inv[i].volumeL, invBefore[i].volumeL);
      expect(inv[i].pressureBar, invBefore[i].pressureBar);
    }
  });

  test('200 L at 350 bar: default equipment fails, a 350 bar booster limit prices it with the counted sources', () {
    final big = makeBank(
      oxygenPercent: 10,
      heliumPercent: 60,
      volumeL: 200,
      pressureBar: 350,
    );
    final defaults = failOf(priceWith(bank: big));
    expect(
      defaults.reason,
      matches(RegExp('Maximum safe pressure|Booster output cannot exceed')),
    );
    final raised = okOf(
      priceWith(
        bank: big,
        settings: settingsWith(
          (b) => b.copyWith(maxBoosterOutputPressureBar: 350),
        ),
      ),
    );
    // Hand check: ceil(2 × need / perBank) per gas.
    expect(raised.sourceCount, gasCount('O2', big) + gasCount('He', big));
    expect(
      raised.exhaustedSources,
      lessThan(raised.sourceCount),
      reason: 'supply must not be the binding limit',
    );
  });

  test(
    '12 L O2 99.5% at 150 bar needs one O2 virtual bank and no He banks',
    () {
      final b = makeBank(oxygenPercent: 99.5, heliumPercent: 0);
      final result = okOf(priceWith(bank: b));
      // needMoles ≈ 82.9 mol × 0.995; perBank ≈ 1795 mol at the 5 bar minimum, so ceil(2 × 82.5 / 1795) = 1.
      // A perBank computed with bank.volumeL (12 L) would give ceil(2 × 82.5 / 107.7) = 2.
      expect(result.sourceCount, 1);
      expect(gasCount('He', b), 0);
      expect(result.sourceCount, gasCount('O2', b));
    },
  );

  test('Tx21/35 at 150 bar: sourceCount is the O2 count plus the He count', () {
    final b = makeBank(oxygenPercent: 21, heliumPercent: 35, pressureBar: 150);
    final result = okOf(priceWith(bank: b));
    expect(gasCount('O2', b), greaterThan(0));
    expect(gasCount('He', b), greaterThan(0));
    expect(result.sourceCount, gasCount('O2', b) + gasCount('He', b));
  });
}

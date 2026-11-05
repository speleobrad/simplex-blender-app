// Port of js/bank-pricing.js.

import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/calculator_input.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/optimizer.dart';
import 'package:simplex_blender/src/domain/physics.dart';
import 'package:simplex_blender/src/domain/pure_prices.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

const double virtualBankVolumeL = 200;
const double virtualBankPressureBar = 200;
const int maxVirtualBanksPerGas = 6;
const double _defaultMinimumSourcePressureBar = 20;
const double _safetyMargin = 2;
const int _minTargetPressureBar = 10;

/// Number of virtual pure-gas sources needed for [needMoles], with a 2x safety margin.
int virtualBankCount({
  required double needMoles,
  required double perBankMoles,
}) {
  if (!(needMoles > 1e-12)) return 0;
  return (_safetyMargin * needMoles / perBankMoles).ceil();
}

/// Result of [priceBankByRecipe]. JS `{ok: true, ...}` is [BankPriceOk];
/// JS `{ok: false, ...}` is [BankPriceFailure].
sealed class BankPriceResult {
  const BankPriceResult();

  bool get ok;
}

/// JS `{ok: true, pricePerLitre, recipeCost, litres, exhaustedSources, sourceCount, operationCount}`.
final class BankPriceOk extends BankPriceResult {
  const BankPriceOk({
    required this.pricePerLitre,
    required this.recipeCost,
    required this.litres,
    required this.exhaustedSources,
    required this.sourceCount,
    required this.operationCount,
  });

  final double pricePerLitre;
  final double recipeCost;
  final double litres;
  final int exhaustedSources;
  final int sourceCount;

  /// Keyed by `boost`, `decant`, `topUp`; an absent key means no such operation.
  final Map<String, int> operationCount;

  @override
  bool get ok => true;
}

/// JS `{ok: false, reason, missingGas?}`. [missingGas] is `'oxygen'` or
/// `'helium'` only when a needed pure gas has no weighted price.
final class BankPriceFailure extends BankPriceResult {
  const BankPriceFailure({required this.reason, this.missingGas});

  final String reason;
  final String? missingGas;

  @override
  bool get ok => false;
}

const String _pureBankReason =
    'Pure banks take their price from the pure-gas price. Enter a price manually.';

/// JS `virtualBanks`: [count] virtual sources of one pure gas at the given price.
List<Bank> _virtualBanks({
  required String gasId,
  required double oxygenPercent,
  required double heliumPercent,
  required int count,
  required double? price,
}) {
  return <Bank>[
    for (var index = 0; index < count; index++)
      Bank(
        id: 'virtual-$gasId-${index + 1}',
        name: 'Virtual $gasId ${index + 1}',
        volumeL: virtualBankVolumeL,
        pressureBar: virtualBankPressureBar,
        maxPressureBar: virtualBankPressureBar,
        enabled: true,
        pricePerLitre: price,
        oxygenPercent: oxygenPercent,
        heliumPercent: heliumPercent,
      ),
  ];
}

/// Prices a real (non-pure) bank by planning, with the optimizer, an empty virtual cylinder
/// that reaches the bank's pressure and composition from pure O2/He virtual banks
/// and Compressor Air. Virtual sources carry the volume-weighted pure-gas prices from
/// [inventoryBanks]. Side-effect free: no real bank or setting is modified.
///
/// A failure caused by a needed pure gas without a weighted price carries `missingGas`
/// (`'oxygen'` | `'helium'`). Every other failure leaves it out.
BankPriceResult priceBankByRecipe({
  required Bank bank,
  required Costs costs,
  required Settings? settings,
  required PhysicsInput physics,
  List<Bank> inventoryBanks = const <Bank>[],
  required double inventoryTemperatureC,
}) {
  if (isPureBank(bank)) {
    return const BankPriceFailure(reason: _pureBankReason);
  }
  final pure = pureGasPrices(
    banks: inventoryBanks,
    physics: physics,
    inventoryTemperatureC: inventoryTemperatureC,
  );
  if (bank.pressureBar < _minTargetPressureBar) {
    return BankPriceFailure(
      reason:
          'Banks below $_minTargetPressureBar bar cannot be priced by recipe. Enter a price manually.',
    );
  }
  final useVdw = physics.model == 'vdw';
  final temperatureC = physics.temperatureC;
  final totalMoles =
      calcMolarDensity(
        bank.pressureBar,
        bank.oxygenPercent,
        bank.heliumPercent,
        temperatureC,
        useVdw,
      ) *
      bank.volumeL;
  final boosterMinimum = settings?.booster.minimumSourcePressureBar;
  final minimumPressureBar = boosterMinimum != null && boosterMinimum.isFinite
      ? boosterMinimum
      : _defaultMinimumSourcePressureBar;

  final sources = <Bank>[];
  final needed =
      <
        ({
          String gasId,
          double oxygenPercent,
          double heliumPercent,
          double fraction,
          double? price,
        })
      >[
        (
          gasId: 'oxygen',
          oxygenPercent: 100,
          heliumPercent: 0,
          fraction: bank.oxygenPercent / 100,
          price: pure.oxygen,
        ),
        (
          gasId: 'helium',
          oxygenPercent: 0,
          heliumPercent: 100,
          fraction: bank.heliumPercent / 100,
          price: pure.helium,
        ),
      ];
  for (final gas in needed) {
    final perBankMoles =
        (calcMolarDensity(
              virtualBankPressureBar,
              gas.oxygenPercent,
              gas.heliumPercent,
              temperatureC,
              useVdw,
            ) -
            calcMolarDensity(
              minimumPressureBar,
              gas.oxygenPercent,
              gas.heliumPercent,
              temperatureC,
              useVdw,
            )) *
        virtualBankVolumeL;
    final count = virtualBankCount(
      needMoles: totalMoles * gas.fraction,
      perBankMoles: perBankMoles,
    );
    if (count > maxVirtualBanksPerGas) {
      return BankPriceFailure(
        reason:
            'This bank needs more than $maxVirtualBanksPerGas virtual ${gas.gasId} sources and cannot be priced by recipe. Enter a price manually.',
      );
    }
    if (count > 0 && gas.price == null) {
      return BankPriceFailure(
        reason: 'Set a price on a pure ${gas.gasId} bank first.',
        missingGas: gas.gasId,
      );
    }
    sources.addAll(
      _virtualBanks(
        gasId: gas.gasId,
        oxygenPercent: gas.oxygenPercent,
        heliumPercent: gas.heliumPercent,
        count: count,
        price: gas.price,
      ),
    );
  }

  // Reached only when no needed pure gas is missing, so the gas-specific reasons above take precedence.
  final operationPrices = costs.operationPrices;
  final anyFee =
      operationPrices.boost > 0 ||
      operationPrices.decant > 0 ||
      operationPrices.topUp > 0;
  if (!anyFee && pure.oxygen == null && pure.helium == null) {
    return const BankPriceFailure(
      reason: 'Nothing is priced yet. Set fees in Settings → Costs and a price on a pure oxygen or helium bank.',
    );
  }

  final result = optimizeBlend(<String, Object?>{
    'cylinder': <String, Object?>{
      'volumeL': bank.volumeL,
      'initialPressureBar': 0.0,
      'initialOxygenPercent': 21.0,
      'initialHeliumPercent': 0.0,
      'targetPressureBar': bank.pressureBar,
      'targetOxygenPercent': bank.oxygenPercent,
      'targetHeliumPercent': bank.heliumPercent,
      'workingPressureBar': bank.pressureBar,
    },
    'physics': <String, Object?>{
      'model': physics.model,
      'temperatureC': temperatureC,
    },
    'banks': <Map<String, Object?>>[
      for (final source in sources) optimizerBankJson(source),
    ],
    'settings': settings == null ? null : optimizerSettingsJson(settings),
  });
  final steps = result['protocolSteps'];
  if (result['feasible'] != true || steps is! List<Object?>) {
    return BankPriceFailure(
      reason:
          (result['error'] as String?) ??
          'The optimizer cannot build this mix from pure gases.',
    );
  }
  final protocolSteps = steps.cast<ProtocolStep>();

  final cost = computeFillCost(
    steps: <FillStep>[
      for (final step in protocolSteps)
        FillStep(
          costOperation: step.costOperation,
          costOperationId: step.costOperationId,
          sourceBankId: step.sourceBankId,
          recipeGas: step.recipeGas,
          sourceConsumedMoles: step.sourceConsumedMoles,
        ),
    ],
    banks: sources,
    costs: costs,
    temperatureC: temperatureC,
  );
  final litres = totalMoles * litresPerMole(temperatureC);
  final exhaustedSources = <String?>{
    for (final step in protocolSteps)
      if (step.sourceExhausted == true) step.sourceBankId,
  }.length;
  return BankPriceOk(
    pricePerLitre:
        cost.total * (1 - costs.leftoverDiscountPercent / 100) / litres,
    recipeCost: cost.total,
    litres: litres,
    exhaustedSources: exhaustedSources,
    sourceCount: sources.length,
    operationCount: <String, int>{
      for (final line in cost.operationLines) line.operation: line.count,
    },
  );
}

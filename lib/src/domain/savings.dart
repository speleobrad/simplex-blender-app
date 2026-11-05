// Port of js/savings.js (pure logic only).
//
// The JS module takes the whole optimizer result. The Dart port takes the fields it reads:
// `heliumRetainedLitres` (null when the result has no blend), `feasible`, and `protocolSteps`
// as cost steps. The salvage path calls `priceBankByRecipe`, which lives in bank_pricing.dart
// and runs the optimizer; this module does not call the optimizer directly.

import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/bank_pricing.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/pure_prices.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

const double _retainedToleranceL = 1e-9;

/// A reason a savings number could not be computed (JS `missing` entries).
sealed class SavingsGap {
  const SavingsGap();
}

/// JS `{code: 'pure-price', gas, bankId?, name?}`. With [bankId] it is a salvage gap for that bank.
final class PurePriceGap extends SavingsGap {
  const PurePriceGap({required this.gas, this.bankId, this.name});

  final String gas;
  final String? bankId;
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is PurePriceGap &&
      other.gas == gas &&
      other.bankId == bankId &&
      other.name == name;

  @override
  int get hashCode => Object.hash('pure-price', gas, bankId, name);

  @override
  String toString() => 'PurePriceGap(gas: $gas, bankId: $bankId, name: $name)';
}

/// JS `{code: 'recipe-unavailable', bankId, name}`.
final class RecipeUnavailableGap extends SavingsGap {
  const RecipeUnavailableGap({required this.bankId, required this.name});

  final String? bankId;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is RecipeUnavailableGap &&
      other.bankId == bankId &&
      other.name == name;

  @override
  int get hashCode => Object.hash('recipe-unavailable', bankId, name);

  @override
  String toString() => 'RecipeUnavailableGap(bankId: $bankId, name: $name)';
}

class SavingsResult {
  const SavingsResult({
    required this.savedCost,
    required this.salvagedSaving,
    required this.missing,
  });

  /// Null when helium is retained but has no pure-helium price, or there is no feasible result.
  final double? savedCost;

  /// Null when any used leftover bank is a gap, or there is no feasible result.
  final double? salvagedSaving;

  /// Each gap appears once.
  final List<SavingsGap> missing;

  @override
  bool operator ==(Object other) =>
      other is SavingsResult &&
      other.savedCost == savedCost &&
      other.salvagedSaving == salvagedSaving &&
      _listEquals(other.missing, missing);

  @override
  int get hashCode => Object.hash(savedCost, salvagedSaving, missing.length);

  @override
  String toString() =>
      'SavingsResult(savedCost: $savedCost, salvagedSaving: $salvagedSaving, missing: $missing)';
}

bool _listEquals(List<SavingsGap> a, List<SavingsGap> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Reuse value and salvaged saving for the blending summary. Display-only: never alters a plan.
///
/// [heliumRetainedLitres] is null when the result has no blend. [feasible] false, or a null
/// blend, gives null savings and no gaps. Salvage uses the discount-0 recipe price of each
/// used non-pure bank.
SavingsResult computeSavings({
  required double? heliumRetainedLitres,
  required bool? feasible,
  required List<FillStep> protocolSteps,
  required List<Bank> banks,
  required Costs costs,
  required Settings settings,
  required PhysicsInput physics,
  required double inventoryTemperatureC,
}) {
  if (heliumRetainedLitres == null || feasible == false) {
    return const SavingsResult(
      savedCost: null,
      salvagedSaving: null,
      missing: <SavingsGap>[],
    );
  }

  final missing = <SavingsGap>[];
  void addMissing(SavingsGap entry) {
    if (!missing.contains(entry)) missing.add(entry);
  }

  final pure = pureGasPrices(
    banks: banks,
    physics: physics,
    inventoryTemperatureC: inventoryTemperatureC,
  );
  double? savedCost = 0;
  if (heliumRetainedLitres > _retainedToleranceL) {
    if (pure.helium == null) {
      addMissing(const PurePriceGap(gas: 'helium'));
      savedCost = null;
    } else {
      savedCost = heliumRetainedLitres * pure.helium!;
    }
  }

  final discountFree = Costs(
    currencySymbol: costs.currencySymbol,
    leftoverDiscountPercent: 0,
    operationPrices: costs.operationPrices,
  );
  final cost = computeFillCost(
    steps: protocolSteps,
    banks: banks,
    costs: costs,
    temperatureC: physics.temperatureC,
  );
  double? salvagedSaving = 0;
  for (final line in cost.gasLines) {
    Bank? bank;
    for (final candidate in banks) {
      if (candidate.id == line.sourceBankId) {
        bank = candidate;
        break;
      }
    }
    if (bank != null && isPureBank(bank)) continue;

    final price = bank == null
        ? null
        : priceBankByRecipe(
            bank: bank,
            costs: discountFree,
            settings: settings,
            physics: physics,
            inventoryBanks: banks,
            inventoryTemperatureC: inventoryTemperatureC,
          );
    switch (price) {
      case BankPriceOk():
        if (salvagedSaving != null) {
          salvagedSaving += line.litres * (price.recipeCost / price.litres);
        }
      case BankPriceFailure(:final missingGas):
        salvagedSaving = null;
        addMissing(
          missingGas != null
              ? PurePriceGap(
                  gas: missingGas,
                  bankId: line.sourceBankId,
                  name: line.name,
                )
              : RecipeUnavailableGap(
                  bankId: line.sourceBankId,
                  name: line.name,
                ),
        );
      case null:
        salvagedSaving = null;
        addMissing(
          RecipeUnavailableGap(bankId: line.sourceBankId, name: line.name),
        );
    }
  }

  return SavingsResult(
    savedCost: savedCost,
    salvagedSaving: salvagedSaving,
    missing: missing,
  );
}

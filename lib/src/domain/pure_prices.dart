import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/physics.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

bool _hasPrice(double? value) => value != null && value.isFinite && value >= 0;

bool isPureOxygenBank(Bank? bank) =>
    bank != null &&
    bank.enabled &&
    bank.oxygenPercent == 100 &&
    bank.heliumPercent == 0;

bool isPureHeliumBank(Bank? bank) =>
    bank != null &&
    bank.enabled &&
    bank.oxygenPercent == 0 &&
    bank.heliumPercent == 100;

bool isPureBank(Bank? bank) => isPureOxygenBank(bank) || isPureHeliumBank(bank);

/// Exactly pure O2 or pure He by composition, regardless of whether the bank is enabled.
bool isPureComposition(Bank? bank) =>
    bank != null &&
    ((bank.oxygenPercent == 100 && bank.heliumPercent == 0) ||
        (bank.oxygenPercent == 0 && bank.heliumPercent == 100));

/// Free-gas litres a bank holds now: moles at its pressure and volume under the active
/// physics model, times litres per mole at the inventory gas temperature.
double bankFreeGasLitres(
  Bank bank,
  PhysicsInput physics,
  double inventoryTemperatureC,
) {
  final moles =
      calcMolarDensity(
        bank.pressureBar,
        bank.oxygenPercent,
        bank.heliumPercent,
        inventoryTemperatureC,
        physics.model == 'vdw',
      ) *
      bank.volumeL;
  return moles * litresPerMole(inventoryTemperatureC);
}

/// Per-free-gas-litre price implied by a full-tank price. `null` when the tank price is not a
/// non-negative number or the bank holds no free gas to divide by.
double? pricePerLitreFromFullTank(double? tankPrice, double? freeGasLitres) {
  if (!_hasPrice(tankPrice) ||
      freeGasLitres == null ||
      !(freeGasLitres > 0) ||
      !freeGasLitres.isFinite) {
    return null;
  }
  return tankPrice! / freeGasLitres;
}

double? _weightedPrice(
  List<Bank> banks,
  bool Function(Bank? bank) isPure,
  PhysicsInput physics,
  double inventoryTemperatureC,
) {
  var weightSum = 0.0;
  var costSum = 0.0;
  for (final bank in banks) {
    if (!isPure(bank) || !_hasPrice(bank.pricePerLitre)) continue;
    final weight = bankFreeGasLitres(bank, physics, inventoryTemperatureC);
    if (!(weight > 0)) continue;
    weightSum += weight;
    costSum += weight * bank.pricePerLitre!;
  }
  return weightSum > 0 ? costSum / weightSum : null;
}

class PureGasPrices {
  const PureGasPrices({required this.oxygen, required this.helium});

  final double? oxygen;
  final double? helium;

  @override
  bool operator ==(Object other) =>
      other is PureGasPrices &&
      other.oxygen == oxygen &&
      other.helium == helium;

  @override
  int get hashCode => Object.hash(oxygen, helium);
}

/// Volume-weighted (free-gas-litre) average per-litre price of the enabled, priced pure
/// banks of each gas. `null` when no such bank has free gas to weigh.
PureGasPrices pureGasPrices({
  required List<Bank> banks,
  required PhysicsInput physics,
  required double inventoryTemperatureC,
}) {
  return PureGasPrices(
    oxygen: _weightedPrice(
      banks,
      isPureOxygenBank,
      physics,
      inventoryTemperatureC,
    ),
    helium: _weightedPrice(
      banks,
      isPureHeliumBank,
      physics,
      inventoryTemperatureC,
    ),
  );
}

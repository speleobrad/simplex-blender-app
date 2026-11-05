import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/js_number.dart';
import 'package:simplex_blender/src/domain/physics.dart';

/// Flat operation fees (JS `costs.operationPrices`).
class OperationPrices {
  const OperationPrices({
    required this.boost,
    required this.decant,
    required this.topUp,
  });

  final double boost;
  final double decant;
  final double topUp;
}

/// Cost settings (JS `costs`).
class Costs {
  const Costs({
    required this.currencySymbol,
    required this.leftoverDiscountPercent,
    required this.operationPrices,
  });

  final String currencySymbol;
  final double leftoverDiscountPercent;
  final OperationPrices operationPrices;
}

/// Cost-relevant fields of one protocol step (JS step object).
class FillStep {
  const FillStep({
    this.costOperation,
    this.costOperationId,
    this.sourceBankId,
    this.sourceBankName,
    this.recipeGas,
    this.sourceConsumedMoles,
  });

  final String? costOperation;
  final String? costOperationId;
  final String? sourceBankId;
  final String? sourceBankName;
  final String? recipeGas;
  final double? sourceConsumedMoles;
}

class GasLine {
  const GasLine({
    required this.sourceBankId,
    required this.name,
    required this.litres,
    required this.unitPrice,
    required this.cost,
  });

  final String? sourceBankId;
  final String name;
  final double litres;

  /// Null when the source has no usable price.
  final double? unitPrice;
  final double cost;
}

class OperationLine {
  const OperationLine({
    required this.operation,
    required this.count,
    required this.fee,
    required this.cost,
  });

  final String operation;
  final int count;
  final double fee;
  final double cost;

  @override
  bool operator ==(Object other) =>
      other is OperationLine &&
      other.operation == operation &&
      other.count == count &&
      other.fee == fee &&
      other.cost == cost;

  @override
  int get hashCode => Object.hash(operation, count, fee, cost);

  @override
  String toString() =>
      'OperationLine($operation, count: $count, fee: $fee, cost: $cost)';
}

class UnpricedSource {
  const UnpricedSource({required this.sourceBankId, required this.name});

  final String? sourceBankId;
  final String name;
}

class FillCost {
  const FillCost({
    required this.gasLines,
    required this.operationLines,
    required this.gasTotal,
    required this.operationTotal,
    required this.total,
    required this.unpricedSources,
    required this.incomplete,
    required this.configured,
  });

  final List<GasLine> gasLines;
  final List<OperationLine> operationLines;
  final double gasTotal;
  final double operationTotal;
  final double total;
  final List<UnpricedSource> unpricedSources;
  final bool incomplete;
  final bool configured;
}

const List<String> _operationLineOrder = ['boost', 'decant', 'topUp'];

double litresPerMole(double temperatureC) =>
    gasConstant * (temperatureC + 273.15);

bool _hasPrice(double? value) => value != null && value.isFinite && value >= 0;

/// Bank prices are display-only cost inputs; they never change a plan, so recipe
/// signatures (interim readings, What-if) must ignore them.
List<Bank> withoutBankPrices(List<Bank> banks) => [
  for (final bank in banks) bank.copyWith(pricePerLitre: () => null),
];

double _feeOf(Costs? costs, String key) {
  final prices = costs?.operationPrices;
  final fee = switch (key) {
    'boost' => prices?.boost,
    'decant' => prices?.decant,
    'topUp' => prices?.topUp,
    _ => null,
  };
  return fee != null && fee.isFinite ? fee : 0;
}

String? _feeKeyByOperation(String operation) => switch (operation) {
  'boost' => 'boost',
  'decant' => 'decant',
  'equalize' => 'decant',
  'topUp' => 'topUp',
  _ => null,
};

/// Flat fee model: each distinct `costOperationId` is one operation, charged once at
/// the fee of its class (boost, decant incl. equalize, topUp). Gas is charged per litre
/// of each bank's stored price; compressor air (topUp) has no gas line.
FillCost computeFillCost({
  required List<FillStep> steps,
  required List<Bank> banks,
  required Costs? costs,
  required double temperatureC,
}) {
  final perMole = litresPerMole(temperatureC);
  final bankById = {for (final bank in banks) bank.id: bank};
  final gasKeys = <String?>[];
  final gas = <String?, GasLine>{};
  final operationIds = <String, Set<String?>>{
    'boost': <String?>{},
    'decant': <String?>{},
    'topUp': <String?>{},
  };

  for (final step in steps) {
    final operation = step.costOperation;
    if (operation == null || operation.isEmpty) continue;
    if (operation == 'topUp') {
      operationIds['topUp']!.add(step.costOperationId);
      continue;
    }
    final feeKey = _feeKeyByOperation(operation);
    if (feeKey != null) operationIds[feeKey]!.add(step.costOperationId);
    final consumed = step.sourceConsumedMoles;
    final litres =
        (consumed != null && consumed.isFinite ? consumed : 0.0) * perMole;
    final sourceId = step.sourceBankId;
    final bank = bankById[sourceId];
    final existing = gas[sourceId];
    final unitPrice = _hasPrice(bank?.pricePerLitre)
        ? bank!.pricePerLitre
        : null;
    final name =
        bank?.name ?? step.sourceBankName ?? step.recipeGas ?? sourceId ?? '';
    if (existing == null) gasKeys.add(sourceId);
    gas[sourceId] = GasLine(
      sourceBankId: sourceId,
      name: existing?.name ?? name,
      litres: (existing?.litres ?? 0) + litres,
      unitPrice: existing != null ? existing.unitPrice : unitPrice,
      cost: 0,
    );
  }

  final gasLines = [
    for (final key in gasKeys)
      () {
        final line = gas[key]!;
        final price = line.unitPrice;
        return GasLine(
          sourceBankId: line.sourceBankId,
          name: line.name,
          litres: line.litres,
          unitPrice: price,
          cost: price == null ? 0 : line.litres * price,
        );
      }(),
  ];
  final unpricedSources = [
    for (final line in gasLines)
      if (line.unitPrice == null)
        UnpricedSource(sourceBankId: line.sourceBankId, name: line.name),
  ];

  final operationLines = <OperationLine>[];
  for (final operation in _operationLineOrder) {
    final count = operationIds[operation]!.length;
    if (count == 0) continue;
    final fee = _feeOf(costs, operation);
    operationLines.add(
      OperationLine(
        operation: operation,
        count: count,
        fee: fee,
        cost: count * fee,
      ),
    );
  }

  final gasTotal = gasLines.fold<double>(0, (sum, line) => sum + line.cost);
  final operationTotal = operationLines.fold<double>(
    0,
    (sum, line) => sum + line.cost,
  );
  return FillCost(
    gasLines: gasLines,
    operationLines: operationLines,
    gasTotal: gasTotal,
    operationTotal: operationTotal,
    total: gasTotal + operationTotal,
    unpricedSources: unpricedSources,
    incomplete: unpricedSources.isNotEmpty,
    configured:
        _operationLineOrder.any((key) => _feeOf(costs, key) > 0) ||
        gasLines.any((line) => line.unitPrice != null),
  );
}

/// Parses a typed cost number (a flat operation fee or the leftover discount).
///
/// Fees are money per operation, so they are never unit-converted. Empty or
/// non-numeric text becomes NaN so validation rejects it (JS `parseCostNumber`).
double parseCostNumber(String? text) {
  final trimmed = (text ?? '').trim();
  if (trimmed.isEmpty) {
    return double.nan;
  }
  return parseJsNumber(trimmed);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/cost.dart';

// Fixture fees are per operation: boost 2, decant 1, topUp 5.
Costs costs() => const Costs(
  currencySymbol: '',
  leftoverDiscountPercent: 0,
  operationPrices: OperationPrices(boost: 2, decant: 1, topUp: 5),
);

Costs noFees() => const Costs(
  currencySymbol: '',
  leftoverDiscountPercent: 0,
  operationPrices: OperationPrices(boost: 0, decant: 0, topUp: 0),
);

const double t = 20;
final double perMole = litresPerMole(t);

FillStep step({
  String? costOperation = 'boost',
  String? costOperationId = 'op-1',
  String? sourceBankId = 'a',
  double? sourceConsumedMoles = 1,
}) => FillStep(
  costOperation: costOperation,
  costOperationId: costOperationId,
  sourceBankId: sourceBankId,
  sourceConsumedMoles: sourceConsumedMoles,
);

const List<Bank> banks = [
  Bank(
    id: 'a',
    name: 'A',
    volumeL: 0,
    pressureBar: 0,
    oxygenPercent: 0,
    heliumPercent: 0,
    enabled: true,
    pricePerLitre: 0.01,
  ),
  Bank(
    id: 'b',
    name: 'B',
    volumeL: 0,
    pressureBar: 0,
    oxygenPercent: 0,
    heliumPercent: 0,
    enabled: true,
  ),
];

void main() {
  test('gas lines use stored price and litres from consumed moles', () {
    final cost = computeFillCost(
      steps: [
        step(),
        step(costOperationId: 'op-2'),
      ],
      banks: banks,
      costs: costs(),
      temperatureC: t,
    );
    final line = cost.gasLines.firstWhere((l) => l.sourceBankId == 'a');
    expect(line.litres, closeTo(2 * perMole, 1e-9));
    expect(line.cost, closeTo(2 * perMole * 0.01, 1e-9));
  });

  test('each distinct boost operation id is charged one boost fee', () {
    final cost = computeFillCost(
      steps: [
        step(),
        step(),
        step(costOperationId: 'op-2'),
      ],
      banks: banks,
      costs: costs(),
      temperatureC: t,
    );
    expect(cost.operationLines, [
      const OperationLine(operation: 'boost', count: 2, fee: 2, cost: 4),
    ]);
    expect(cost.operationTotal, 4);
  });

  test('several steps sharing one operation id are one operation', () {
    final cost = computeFillCost(
      steps: [
        step(),
        step(sourceBankId: 'b'),
      ],
      banks: banks,
      costs: costs(),
      temperatureC: t,
    );
    expect(cost.operationLines, [
      const OperationLine(operation: 'boost', count: 1, fee: 2, cost: 2),
    ]);
  });

  test('a decant and an equalize with different ids are two operations at the decant fee', () {
    final cost = computeFillCost(
      steps: [
        step(costOperation: 'decant', costOperationId: 'op-1'),
        step(costOperation: 'equalize', costOperationId: 'op-2'),
      ],
      banks: banks,
      costs: costs(),
      temperatureC: t,
    );
    expect(cost.operationLines, [
      const OperationLine(operation: 'decant', count: 2, fee: 1, cost: 2),
    ]);
  });

  test(
    'a decant and an equalize with the same id count as one decant operation',
    () {
      final cost = computeFillCost(
        steps: [
          step(costOperation: 'decant', costOperationId: 'op-1'),
          step(costOperation: 'equalize', costOperationId: 'op-1'),
        ],
        banks: banks,
        costs: costs(),
        temperatureC: t,
      );
      expect(cost.operationLines, [
        const OperationLine(operation: 'decant', count: 1, fee: 1, cost: 1),
      ]);
    },
  );

  test('top-up fee is charged once per operation id and has no gas line', () {
    final top = step(
      costOperation: 'topUp',
      sourceBankId: 'compressor-air',
      costOperationId: 'op-1',
    );
    final cost = computeFillCost(
      steps: [
        top,
        step(
          costOperation: 'topUp',
          sourceBankId: 'compressor-air',
          costOperationId: 'op-1',
          sourceConsumedMoles: 3,
        ),
      ],
      banks: banks,
      costs: costs(),
      temperatureC: t,
    );
    expect(cost.operationLines, [
      const OperationLine(operation: 'topUp', count: 1, fee: 5, cost: 5),
    ]);
    expect(cost.gasLines, isEmpty);
    final two = computeFillCost(
      steps: [
        top,
        step(
          costOperation: 'topUp',
          sourceBankId: 'compressor-air',
          costOperationId: 'op-2',
        ),
      ],
      banks: banks,
      costs: costs(),
      temperatureC: t,
    );
    expect(two.operationLines, [
      const OperationLine(operation: 'topUp', count: 2, fee: 5, cost: 10),
    ]);
  });

  test('operation lines are ordered boost, decant, topUp and omitted when their count is zero', () {
    final cost = computeFillCost(
      steps: [
        step(
          costOperation: 'topUp',
          sourceBankId: 'compressor-air',
          costOperationId: 'op-3',
          sourceConsumedMoles: 1,
        ),
        step(costOperation: 'decant', costOperationId: 'op-2'),
        step(costOperationId: 'op-1'),
      ],
      banks: banks,
      costs: costs(),
      temperatureC: t,
    );
    expect(cost.operationLines.map((line) => line.operation).toList(), [
      'boost',
      'decant',
      'topUp',
    ]);
    expect(
      computeFillCost(
        steps: [step()],
        banks: banks,
        costs: costs(),
        temperatureC: t,
      ).operationLines.map((line) => line.operation).toList(),
      ['boost'],
    );
  });

  test('operation lines carry exactly operation, count, fee and cost', () {
    final cost = computeFillCost(
      steps: [step()],
      banks: banks,
      costs: costs(),
      temperatureC: t,
    );
    expect(
      cost.operationLines.single,
      const OperationLine(operation: 'boost', count: 1, fee: 2, cost: 2),
    );
  });

  test(
    'unpriced and missing banks are flagged and the total is incomplete',
    () {
      final cost = computeFillCost(
        steps: [
          step(sourceBankId: 'b'),
          step(sourceBankId: 'gone', costOperationId: 'op-2'),
        ],
        banks: banks,
        costs: costs(),
        temperatureC: t,
      );
      expect(cost.incomplete, isTrue);
      expect(cost.unpricedSources.map((s) => s.sourceBankId).toList()..sort(), [
        'b',
        'gone',
      ]);
      expect(cost.gasTotal, 0);
    },
  );

  test('total is gas plus operations', () {
    final cost = computeFillCost(
      steps: [
        step(),
        step(
          costOperation: 'topUp',
          sourceBankId: 'compressor-air',
          costOperationId: 'op-2',
        ),
      ],
      banks: banks,
      costs: costs(),
      temperatureC: t,
    );
    expect(cost.total, closeTo(cost.gasTotal + cost.operationTotal, 1e-12));
    expect(cost.operationTotal, 2 + 5);
  });

  test('configured is false with no fees and no priced used bank', () {
    expect(
      computeFillCost(
        steps: [step(sourceBankId: 'b')],
        banks: banks,
        costs: noFees(),
        temperatureC: t,
      ).configured,
      isFalse,
    );
  });

  test('configured is true with a fee alone or a priced used bank alone', () {
    expect(
      computeFillCost(
        steps: [step()],
        banks: banks,
        costs: costs(),
        temperatureC: t,
      ).configured,
      isTrue,
    );
    expect(
      computeFillCost(
        steps: [step()],
        banks: banks,
        costs: noFees(),
        temperatureC: t,
      ).configured,
      isTrue,
    );
  });

  test('steps without a cost operation are ignored', () {
    final cost = computeFillCost(
      steps: [const FillStep(), const FillStep()],
      banks: banks,
      costs: costs(),
      temperatureC: t,
    );
    expect(cost.total, 0);
    expect(cost.operationLines, isEmpty);
  });

  test('parses typed cost numbers without unit conversion and maps empty or non-numeric text to NaN', () {
    expect(parseCostNumber(' 1.5 '), 1.5);
    expect(parseCostNumber('0.25'), 0.25);
    expect(parseCostNumber('10'), 10);
    expect(parseCostNumber(''), isNaN);
    expect(parseCostNumber('   '), isNaN);
    expect(parseCostNumber('abc'), isNaN);
  });
}

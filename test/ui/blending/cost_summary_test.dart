import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/savings.dart';
import 'package:simplex_blender/src/domain/units.dart';
import 'package:simplex_blender/src/ui/blending/cost_summary.dart';

// Ported from tests/cost-summary.test.js (markup assertions only).

const _gasKey = ValueKey<String>('cost-gas-table');
const _operationKey = ValueKey<String>('cost-operations-table');
const _nbsp = '\u00A0';

const _pricedCost = FillCost(
  gasLines: [
    GasLine(
      sourceBankId: 'bank-o2',
      name: 'Oxygen bank',
      litres: 10,
      unitPrice: 0.025,
      cost: 0.25,
    ),
  ],
  operationLines: [
    OperationLine(operation: 'boost', count: 2, fee: 5, cost: 10),
  ],
  gasTotal: 0.25,
  operationTotal: 10,
  total: 10.25,
  unpricedSources: [],
  incomplete: false,
  configured: true,
);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Widget _summary({
  FillCost? cost = _pricedCost,
  String units = metricUnits,
  String symbol = '€',
}) => _host(CostSummary(cost: cost, units: units, currencySymbol: symbol));

Widget _banner({
  FillCost? cost = _pricedCost,
  SavingsResult? savings,
  String symbol = '€',
}) => _host(
  CostBanner(
    cost: cost,
    savings:
        savings ??
        const SavingsResult(savedCost: null, salvagedSaving: null, missing: []),
    currencySymbol: symbol,
  ),
);

/// Text of each row of [key]'s table; a cell's text is the concatenation of its Text widgets.
List<List<String>> _rows(WidgetTester tester, Key key) {
  final table = tester.widget<Table>(find.byKey(key));
  return [
    for (final row in table.children)
      [
        for (final cell in row.children)
          tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byWidget(cell),
                  matching: find.byType(Text),
                ),
              )
              .map((text) => text.data ?? '')
              .join(),
      ],
  ];
}

void main() {
  testWidgets('renders priced gas, operation and total lines as bare numbers', (
    tester,
  ) async {
    await tester.pumpWidget(_summary());

    expect(find.text(costsNoPlanText), findsNothing);
    expect(find.byKey(_gasKey), findsOneWidget);
    expect(find.byKey(_operationKey), findsOneWidget);
    expect(_rows(tester, _gasKey)[1], [
      'Oxygen bank',
      '10.0',
      '0.025000',
      '0.25',
    ]);
    expect(_rows(tester, _operationKey)[1], ['Boost', '2', '5.00', '10.00']);
    expect(find.text('10.25'), findsOneWidget);
  });

  testWidgets(
    'puts the currency in the headers and keeps table amounts as bare numbers',
    (tester) async {
      await tester.pumpWidget(_summary(symbol: 'CHF'));

      expect(find.text('Price'), findsOneWidget);
      expect(find.text('(CHF/L)'), findsOneWidget);
      expect(find.text('Cost (CHF)'), findsNWidgets(2));
      expect(find.text('Fee (CHF)'), findsOneWidget);
      expect(_rows(tester, _gasKey)[1], [
        'Oxygen bank',
        '10.0',
        '0.025000',
        '0.25',
      ]);
      expect(_rows(tester, _operationKey)[1], ['Boost', '2', '5.00', '10.00']);
      expect(find.text('10.25'), findsOneWidget);
    },
  );

  testWidgets(
    'labels the total incomplete with unpriced source names and marks the gas row unpriced',
    (tester) async {
      const cost = FillCost(
        gasLines: [
          GasLine(
            sourceBankId: 'bank-o2',
            name: 'Oxygen bank',
            litres: 10,
            unitPrice: 0.025,
            cost: 0.25,
          ),
          GasLine(
            sourceBankId: 'bank-he',
            name: 'Helium bank',
            litres: 5,
            unitPrice: null,
            cost: 0,
          ),
        ],
        operationLines: [],
        gasTotal: 0.25,
        operationTotal: 0,
        total: 0.25,
        unpricedSources: [
          UnpricedSource(sourceBankId: 'bank-he', name: 'Helium bank'),
        ],
        incomplete: true,
        configured: true,
      );
      await tester.pumpWidget(_summary(cost: cost));

      expect(_rows(tester, _gasKey)[2], ['Helium bank', '5.0', '—', '—']);
      expect(
        find.text('0.25 (incomplete: Helium bank unpriced)'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'shows top-up as count, fee and cost with compressor air as information only',
    (tester) async {
      const cost = FillCost(
        gasLines: [
          GasLine(
            sourceBankId: 'bank-o2',
            name: 'Oxygen bank',
            litres: 10,
            unitPrice: 0.025,
            cost: 0.25,
          ),
        ],
        operationLines: [
          OperationLine(operation: 'topUp', count: 1, fee: 5, cost: 5),
        ],
        gasTotal: 0.25,
        operationTotal: 5,
        total: 5.25,
        unpricedSources: [],
        incomplete: false,
        configured: true,
      );
      await tester.pumpWidget(_summary(cost: cost));

      expect(_rows(tester, _gasKey)[1], [
        'Oxygen bank',
        '10.0',
        '0.025000',
        '0.25',
      ]);
      expect(_rows(tester, _operationKey)[1], [
        'Top-up includes compressor air',
        '1',
        '5.00',
        '5.00',
      ]);
      expect(find.text('5.25'), findsOneWidget);
    },
  );

  testWidgets(
    'prompts for Settings when nothing is configured and hides the tables',
    (tester) async {
      await tester.pumpWidget(
        _summary(
          cost: const FillCost(
            gasLines: _pricedGasLines,
            operationLines: _pricedOperationLines,
            gasTotal: 0.25,
            operationTotal: 10,
            total: 10.25,
            unpricedSources: [],
            incomplete: false,
            configured: false,
          ),
        ),
      );

      expect(
        find.text(
          'No prices apply to this fill. Set bank prices in Inventory and fees in Settings → Costs.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(_gasKey), findsNothing);
      expect(find.byKey(_operationKey), findsNothing);
      expect(find.text('10.25'), findsNothing);
    },
  );

  testWidgets('shows the empty state when no feasible plan has a cost', (
    tester,
  ) async {
    await tester.pumpWidget(_summary(cost: null));

    expect(
      find.text('Costs appear when a feasible blend is available.'),
      findsOneWidget,
    );
    expect(find.byKey(_gasKey), findsNothing);
    expect(find.byKey(_operationKey), findsNothing);
  });

  testWidgets('converts litres and prices to imperial units', (tester) async {
    await tester.pumpWidget(_summary(units: imperialUnits));

    final row = _rows(tester, _gasKey)[1];
    expect(row[0], 'Oxygen bank');
    expect(row[1], matches(RegExp(r'^\d+\.\d$')));
    expect(row[2], matches(RegExp(r'^\d+\.\d{6}$')));
  });

  testWidgets('labels the gas volume column with the active volume unit', (
    tester,
  ) async {
    await tester.pumpWidget(_summary(units: imperialUnits));

    expect(find.text('Volume (cu ft)'), findsOneWidget);
  });

  testWidgets(
    'labels the gas price column as two lines: Price, then the unit kept whole',
    (tester) async {
      await tester.pumpWidget(_summary());

      expect(find.text('Price'), findsOneWidget);
      expect(find.text('(€/L)'), findsOneWidget);

      await tester.pumpWidget(_summary(units: imperialUnits));

      expect(find.text('Price'), findsOneWidget);
      expect(
        find.text(
          '(€/cu$_nbsp'
          'ft)',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'keeps the unit line unbroken for empty symbols and long non-ASCII symbols',
    (tester) async {
      await tester.pumpWidget(_summary(symbol: ''));
      expect(
        find.text(
          '(per$_nbsp'
          'L)',
        ),
        findsOneWidget,
      );
      expect(find.text('(per L)'), findsNothing);

      await tester.pumpWidget(_summary(units: imperialUnits, symbol: ''));
      expect(
        find.text(
          '(per$_nbsp'
          'cu$_nbsp'
          'ft)',
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(_summary(symbol: 'zł'));
      expect(find.text('(zł/L)'), findsOneWidget);

      await tester.pumpWidget(
        _summary(units: imperialUnits, symbol: 'ABCDEFGH'),
      );
      expect(
        find.text(
          '(ABCDEFGH/cu$_nbsp'
          'ft)',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'shows Total gas cost and Operations cost rows with 2-decimal amounts',
    (tester) async {
      await tester.pumpWidget(_summary());

      final gasRows = _rows(tester, _gasKey);
      final operationRows = _rows(tester, _operationKey);
      expect(gasRows.last, ['Total gas cost', '', '', '0.25']);
      expect(operationRows[operationRows.length - 2], [
        'Operations cost',
        '',
        '',
        '10.00',
      ]);
    },
  );

  testWidgets(
    'headers without a currency symbol read Cost and Fee with no empty parentheses',
    (tester) async {
      await tester.pumpWidget(_summary(symbol: ''));

      expect(find.text('Volume (L)'), findsOneWidget);
      expect(find.text('Cost'), findsNWidgets(2));
      expect(find.text('Fee'), findsOneWidget);
      expect(find.textContaining('()'), findsNothing);
    },
  );

  testWidgets(
    'banner shows total fill cost, reuse value and salvaged saving with 2 decimals',
    (tester) async {
      await tester.pumpWidget(
        _banner(
          savings: const SavingsResult(
            savedCost: 1.5,
            salvagedSaving: 0.333,
            missing: [],
          ),
        ),
      );

      expect(find.text('€10.25'), findsOneWidget);
      expect(find.text('€1.50'), findsOneWidget);
      expect(find.text('€0.33'), findsOneWidget);
    },
  );

  testWidgets(
    'banner marks the total incomplete when a used bank is unpriced',
    (tester) async {
      const cost = FillCost(
        gasLines: _pricedGasLines,
        operationLines: _pricedOperationLines,
        gasTotal: 0.25,
        operationTotal: 10,
        total: 10.25,
        unpricedSources: [
          UnpricedSource(sourceBankId: 'b', name: 'Helium bank'),
        ],
        incomplete: true,
        configured: true,
      );
      await tester.pumpWidget(
        _banner(
          cost: cost,
          savings: const SavingsResult(
            savedCost: 0,
            salvagedSaving: 0,
            missing: [],
          ),
        ),
      );

      expect(find.text('€10.25 (incomplete)'), findsOneWidget);
    },
  );

  testWidgets(
    'banner shows the avoided-purchase salvage as a number when the leftover bank is unpriced',
    (tester) async {
      const cost = FillCost(
        gasLines: _pricedGasLines,
        operationLines: _pricedOperationLines,
        gasTotal: 0.25,
        operationTotal: 10,
        total: 10.25,
        unpricedSources: [UnpricedSource(sourceBankId: 'b', name: 'EAN32')],
        incomplete: true,
        configured: true,
      );
      await tester.pumpWidget(
        _banner(
          cost: cost,
          savings: const SavingsResult(
            savedCost: 0,
            salvagedSaving: 19.76,
            missing: [],
          ),
        ),
      );

      expect(find.text('€19.76'), findsOneWidget);
      expect(find.text('€10.25 (incomplete)'), findsOneWidget);
    },
  );

  testWidgets('banner prompts for a missing pure price instead of a number', (
    tester,
  ) async {
    await tester.pumpWidget(
      _banner(
        savings: const SavingsResult(
          savedCost: null,
          salvagedSaving: null,
          missing: [
            PurePriceGap(gas: 'helium'),
            PurePriceGap(gas: 'oxygen', bankId: 'b', name: 'EAN32'),
          ],
        ),
      ),
    );

    expect(find.text('Price pure helium in Inventory'), findsOneWidget);
    expect(find.text('Price pure oxygen in Inventory'), findsOneWidget);
  });

  testWidgets('banner explains the Saved and Salvaged gaps separately', (
    tester,
  ) async {
    await tester.pumpWidget(
      _banner(
        savings: const SavingsResult(
          savedCost: null,
          salvagedSaving: null,
          missing: [
            PurePriceGap(gas: 'helium'),
            RecipeUnavailableGap(bankId: 'b', name: 'EAN32'),
          ],
        ),
      ),
    );

    expect(find.text('Price pure helium in Inventory'), findsOneWidget);
    expect(find.text('Unavailable for EAN32'), findsOneWidget);
  });

  testWidgets('banner names a bank whose recipe cannot be priced', (
    tester,
  ) async {
    await tester.pumpWidget(
      _banner(
        savings: const SavingsResult(
          savedCost: 0,
          salvagedSaving: null,
          missing: [RecipeUnavailableGap(bankId: 'b1', name: 'Mix bank')],
        ),
      ),
    );

    expect(find.text('€0.00'), findsOneWidget);
    expect(find.text('Unavailable for Mix bank'), findsOneWidget);
  });

  testWidgets('banner shows dashes without a feasible blend', (tester) async {
    await tester.pumpWidget(
      _banner(
        cost: null,
        savings: const SavingsResult(
          savedCost: null,
          salvagedSaving: null,
          missing: [],
        ),
      ),
    );

    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets(
    'the banner labels the retained-helium item Reuse value and no user-visible text uses the old label',
    (tester) async {
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CostSummary(
                cost: _pricedCost,
                units: metricUnits,
                currencySymbol: '€',
              ),
              CostBanner(
                cost: _pricedCost,
                savings: SavingsResult(
                  savedCost: 1.5,
                  salvagedSaving: 0.333,
                  missing: [],
                ),
                currencySymbol: '€',
              ),
            ],
          ),
        ),
      );

      expect(find.text('Reuse value'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data ?? '').toLowerCase().contains('saved cost'),
        ),
        findsNothing,
      );
    },
  );
}

const _pricedGasLines = [
  GasLine(
    sourceBankId: 'bank-o2',
    name: 'Oxygen bank',
    litres: 10,
    unitPrice: 0.025,
    cost: 0.25,
  ),
];

const _pricedOperationLines = [
  OperationLine(operation: 'boost', count: 2, fee: 5, cost: 10),
];

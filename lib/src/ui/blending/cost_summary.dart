import 'package:flutter/material.dart';

import '../../domain/cost.dart';
import '../../domain/currency_format.dart';
import '../../domain/savings.dart';
import '../../domain/units.dart';

/// Shown when a feasible blend exists but no price applies to it.
const String costsNotConfiguredText =
    'No prices apply to this fill. Set bank prices in Inventory and fees in Settings → Costs.';

/// Shown when there is no feasible blend.
const String costsNoPlanText =
    'Costs appear when a feasible blend is available.';

const String _nbsp = '\u00A0';
final RegExp _negativeZero = RegExp(r'^-0(\.0*)?$');

String _numberText(double value, int digits) {
  final text = value.toStringAsFixed(digits);
  return _negativeZero.hasMatch(text) ? text.substring(1) : text;
}

String _keepTogether(String text) => text.replaceAll(' ', _nbsp);

String _unitWord(String quantity, String units) =>
    unitLabel(quantity, units).replaceFirst(RegExp(r'^/'), '');

String _litresText(double litres, String units) =>
    _numberText(convertToDisplay(litres, 'volumeL', units), 1);

String _perVolumeText(double pricePerLitre, String units) =>
    _numberText(convertToDisplay(pricePerLitre, 'pricePerVolumeL', units), 6);

String _currencyHeading(String label, String symbol) =>
    symbol.isEmpty ? label : '$label ($symbol)';

String _totalText(FillCost cost) {
  final text = _numberText(cost.total, 2);
  if (!cost.incomplete) {
    return text;
  }
  final names = cost.unpricedSources.map((source) => source.name).join(', ');
  return '$text (incomplete: $names unpriced)';
}

String _savedText(double? value, List<SavingsGap> missing, String symbol) {
  if (value != null) {
    return formatMoney(value, symbol, 2);
  }
  final gap = missing.any(
    (entry) =>
        entry is PurePriceGap && entry.gas == 'helium' && entry.bankId == null,
  );
  return gap ? 'Price pure helium in Inventory' : '—';
}

String _salvagedText(double? value, List<SavingsGap> missing, String symbol) {
  if (value != null) {
    return formatMoney(value, symbol, 2);
  }
  for (final entry in missing) {
    if (entry is PurePriceGap && entry.bankId != null) {
      return 'Price pure ${entry.gas} in Inventory';
    }
  }
  for (final entry in missing) {
    if (entry is RecipeUnavailableGap) {
      return 'Unavailable for ${entry.name}';
    }
  }
  return '—';
}

/// The Costs section of the Tanks and costs tab: gas and operation tables with totals.
///
/// [cost] is null when no feasible plan exists; `cost.configured` false means no price applies.
class CostSummary extends StatelessWidget {
  const CostSummary({
    super.key,
    required this.cost,
    required this.units,
    required this.currencySymbol,
  });

  /// Null when no feasible plan exists.
  final FillCost? cost;

  /// `metricUnits` or `imperialUnits` from the domain units module.
  final String units;

  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final fill = cost;
    final textTheme = Theme.of(context).textTheme;
    final children = <Widget>[Text('Costs', style: textTheme.titleSmall)];
    if (fill == null) {
      children.add(const Text(costsNoPlanText));
    } else if (!fill.configured) {
      children.add(const Text(costsNotConfiguredText));
    } else {
      children
        ..add(Text('Gas cost', style: textTheme.titleSmall))
        ..add(_gasTable(fill))
        ..add(Text('Operation cost', style: textTheme.titleSmall))
        ..add(_operationTable(fill));
    }
    return Semantics(
      label: 'Costs',
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _gasTable(FillCost fill) {
    final rows = <TableRow>[
      TableRow(
        children: [
          _cell('Source'),
          _cell('Volume (${unitLabel('volumeL', units)})', alignEnd: true),
          _priceHeadingCell(),
          _cell(_currencyHeading('Cost', currencySymbol), alignEnd: true),
        ],
      ),
    ];
    if (fill.gasLines.isEmpty) {
      rows.add(_messageRow('No gas transferred.'));
    } else {
      for (final line in fill.gasLines) {
        rows.add(_gasRow(line));
      }
    }
    rows.add(
      TableRow(
        children: [
          _cell('Total gas cost', bold: true),
          _cell(''),
          _cell(''),
          _cell(_numberText(fill.gasTotal, 2), alignEnd: true, bold: true),
        ],
      ),
    );
    return _scrollingTable(const ValueKey('cost-gas-table'), rows);
  }

  TableRow _gasRow(GasLine line) {
    final unitPrice = line.unitPrice;
    return TableRow(
      children: [
        _cell(line.name),
        _cell(_litresText(line.litres, units), alignEnd: true),
        _cell(
          unitPrice == null ? '—' : _perVolumeText(unitPrice, units),
          alignEnd: true,
        ),
        _cell(
          unitPrice == null ? '—' : _numberText(line.cost, 2),
          alignEnd: true,
        ),
      ],
    );
  }

  Widget _operationTable(FillCost fill) {
    final rows = <TableRow>[
      TableRow(
        children: [
          _cell('Operation'),
          _cell('Count', alignEnd: true),
          _cell(_currencyHeading('Fee', currencySymbol), alignEnd: true),
          _cell(_currencyHeading('Cost', currencySymbol), alignEnd: true),
        ],
      ),
    ];
    if (fill.operationLines.isEmpty) {
      rows.add(_messageRow('No operations.'));
    } else {
      for (final line in fill.operationLines) {
        rows.add(_operationRow(line));
      }
    }
    rows
      ..add(
        TableRow(
          children: [
            _cell('Operations cost', bold: true),
            _cell(''),
            _cell(''),
            _cell(
              _numberText(fill.operationTotal, 2),
              alignEnd: true,
              bold: true,
            ),
          ],
        ),
      )
      ..add(
        TableRow(
          children: [
            _cell('Total cost', bold: true),
            _cell(''),
            _cell(''),
            _cell(_totalText(fill), alignEnd: true, bold: true),
          ],
        ),
      );
    return _scrollingTable(const ValueKey('cost-operations-table'), rows);
  }

  TableRow _operationRow(OperationLine line) {
    final label = switch (line.operation) {
      'boost' => 'Boost',
      'decant' => 'Decant',
      'topUp' => 'Top-up',
      _ => line.operation,
    };
    final text = line.operation == 'topUp'
        ? '$label includes compressor air'
        : label;
    return TableRow(
      children: [
        _cell(text),
        _cell('${line.count}', alignEnd: true),
        _cell(_numberText(line.fee, 2), alignEnd: true),
        _cell(_numberText(line.cost, 2), alignEnd: true),
      ],
    );
  }

  Widget _priceHeadingCell() {
    final unit = _unitWord('pricePerVolumeL', units);
    final detail = currencySymbol.isEmpty
        ? '(per $unit)'
        : '($currencySymbol/$unit)';
    return _cellWidget(
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Price'),
          Text(_keepTogether(detail), softWrap: false),
        ],
      ),
      alignEnd: true,
    );
  }

  TableRow _messageRow(String text) => TableRow(
    children: [
      _cell(text),
      const SizedBox.shrink(),
      const SizedBox.shrink(),
      const SizedBox.shrink(),
    ],
  );

  Widget _scrollingTable(Key key, List<TableRow> rows) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Table(
      key: key,
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: rows,
    ),
  );

  Widget _cell(String text, {bool alignEnd = false, bool bold = false}) =>
      _cellWidget(
        Text(
          text,
          style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
        alignEnd: alignEnd,
      );

  Widget _cellWidget(Widget child, {bool alignEnd = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    ),
  );
}

/// The Total cost of fill, Reuse value and Salvaged saving items of the Blending summary banner.
///
/// [cost] is null without a feasible blend; [savings] is the result of `computeSavings`.
class CostBanner extends StatelessWidget {
  const CostBanner({
    super.key,
    required this.cost,
    required this.savings,
    required this.currencySymbol,
  });

  final FillCost? cost;
  final SavingsResult? savings;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final fill = cost;
    final result = savings;
    final fillTotal = fill != null && fill.configured
        ? '${formatMoney(fill.total, currencySymbol, 2)}${fill.incomplete ? ' (incomplete)' : ''}'
        : '—';
    final saved = result == null
        ? '—'
        : _savedText(result.savedCost, result.missing, currencySymbol);
    final salvaged = result == null
        ? '—'
        : _salvagedText(result.salvagedSaving, result.missing, currencySymbol);
    return Semantics(
      label: 'Fill costs',
      container: true,
      explicitChildNodes: true,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 24,
        runSpacing: 12,
        children: [
          _BannerItem(label: 'Total cost of fill', value: fillTotal),
          _BannerItem(label: 'Reuse value', value: saved),
          _BannerItem(
            label: 'Salvaged saving',
            value: salvaged,
            tooltip: 'Pure-gas cost avoided by using leftover mixes',
          ),
        ],
      ),
    );
  }
}

class _BannerItem extends StatelessWidget {
  const _BannerItem({required this.label, required this.value, this.tooltip});

  final String label;
  final String value;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final item = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: textTheme.labelSmall),
        Text(value, style: textTheme.titleMedium),
      ],
    );
    final tip = tooltip;
    return tip == null ? item : Tooltip(message: tip, child: item);
  }
}

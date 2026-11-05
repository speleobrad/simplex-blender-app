import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/currency_format.dart';
import 'package:simplex_blender/src/domain/js_number.dart';
import 'package:simplex_blender/src/domain/units.dart';

/// Inventory price-suggestion state for one bank (JS suggestion `status`).
sealed class BankPriceSuggestion {
  const BankPriceSuggestion();
}

/// JS `status: 'calculating'`.
final class BankPriceSuggestionCalculating extends BankPriceSuggestion {
  const BankPriceSuggestionCalculating();
}

/// JS `status: 'failed'`; [reason] is shown verbatim.
final class BankPriceSuggestionFailed extends BankPriceSuggestion {
  const BankPriceSuggestionFailed({required this.reason});

  final String reason;
}

/// JS `status: 'ok'`. [pricePerLitre] and [recipeCost] are stored (metric) values; [litres] is in litres.
final class BankPriceSuggestionOk extends BankPriceSuggestion {
  const BankPriceSuggestionOk({
    required this.pricePerLitre,
    required this.recipeCost,
    required this.litres,
  });

  final double pricePerLitre;
  final double recipeCost;
  final double litres;
}

/// Stored per-litre price as the text shown in the inventory price input, to 6 decimals; empty when unpriced.
String formatBankPrice(double? pricePerLitre, String? units) {
  if (pricePerLitre == null) {
    return '';
  }
  return convertToDisplay(
    pricePerLitre,
    'pricePerVolumeL',
    units,
  ).toStringAsFixed(6);
}

/// Indicative-price note under a bank's price input; the Calculating and failed states return their own text.
String formatSuggestionNote(
  Bank bank,
  BankPriceSuggestion suggestion,
  String? units,
  String? currencySymbol, [
  double leftoverDiscountPercent = 0,
]) {
  return switch (suggestion) {
    BankPriceSuggestionCalculating() => 'Calculating…',
    BankPriceSuggestionFailed(:final reason) => reason,
    BankPriceSuggestionOk ok => _formatOkNote(
      bank,
      ok,
      units,
      currencySymbol,
      leftoverDiscountPercent,
    ),
  };
}

String _formatOkNote(
  Bank bank,
  BankPriceSuggestionOk suggestion,
  String? units,
  String? currencySymbol,
  double leftoverDiscountPercent,
) {
  final perVolume = unitLabel('volumeL', units);
  final litres = _formatAmount(
    convertToDisplay(suggestion.litres, 'volumeL', units),
  );
  final discountNote = leftoverDiscountPercent > 0
      ? ' after ${jsNumberString(leftoverDiscountPercent)}% leftover discount'
      : '';
  var text =
      'Indicative price '
      '${_priceText(suggestion.pricePerLitre, units, currencySymbol, perVolume)}'
      '$discountNote '
      '(recipe cost ${formatMoney(suggestion.recipeCost, currencySymbol, 2)} '
      'for $litres $perVolume).';
  final currentPrice = bank.pricePerLitre;
  if (currentPrice != null) {
    text +=
        ' Current price '
        '${_priceText(currentPrice, units, currencySymbol, perVolume)}.';
  }
  return text;
}

String _priceText(
  double pricePerLitre,
  String? units,
  String? currencySymbol,
  String perVolume,
) {
  final displayed = convertToDisplay(pricePerLitre, 'pricePerVolumeL', units);
  return '${formatMoney(displayed, currencySymbol, 6)} per $perVolume';
}

/// Litre amount to 6 significant digits, printed the way JS `String(Number(x.toPrecision(6)))` does.
String _formatAmount(double value) =>
    jsNumberString(double.parse(value.toStringAsPrecision(6)));

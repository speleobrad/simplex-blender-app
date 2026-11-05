/// Prefix for a currency symbol: alphanumeric symbols get a following space ("CHF 12.40"); punctuation stays attached ("€12.40").
String currencyPrefix(String? symbol) {
  if (symbol == null || symbol.isEmpty) return '';
  return RegExp(r'[\p{L}\p{N}]$', unicode: true).hasMatch(symbol)
      ? '$symbol '
      : symbol;
}

/// Format a money amount with a fixed number of decimal digits and the configured currency prefix. A negative amount gets its sign before the prefix ("-€1.20"); an amount that rounds to zero has no sign.
String formatMoney(double amount, String? symbol, int digits) {
  final negative = double.parse(amount.toStringAsFixed(digits)) < 0;
  return '${negative ? '-' : ''}${currencyPrefix(symbol)}${amount.abs().toStringAsFixed(digits)}';
}

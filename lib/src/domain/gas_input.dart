/// Port of `js/gas-input.js`.
library;

final RegExp _decimalNumberPattern = RegExp(
  r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$',
);

/// JS `{ oxygenText, heliumText }`.
class GasInputSplit {
  const GasInputSplit({required this.oxygenText, required this.heliumText});

  final String oxygenText;
  final String heliumText;
}

/// Splits a slash-delimited O2/He entry. Returns null when there is no `/`.
GasInputSplit? splitGasInput(String value) {
  final separator = value.indexOf('/');
  if (separator < 0) return null;
  return GasInputSplit(
    oxygenText: value.substring(0, separator).trim(),
    heliumText: value.substring(separator + 1).trim(),
  );
}

/// `null` stands for JS `undefined`/non-number values, which are never finite.
bool isValidGasComposition(double? oxygenPercent, double? heliumPercent) {
  if (oxygenPercent == null || heliumPercent == null) return false;
  final oxygen = oxygenPercent;
  final helium = heliumPercent;
  return oxygen.isFinite &&
      helium.isFinite &&
      oxygen >= 0 &&
      oxygen <= 100 &&
      helium >= 0 &&
      helium <= 100 &&
      oxygen + helium <= 100;
}

/// Strict decimal parse; returns NaN for blank, malformed, or non-finite text.
double parseNumericInput(String value) {
  final input = value.trim();
  if (!_decimalNumberPattern.hasMatch(input)) return double.nan;
  final parsed = double.tryParse(input);
  if (parsed == null || !parsed.isFinite) return double.nan;
  return parsed;
}

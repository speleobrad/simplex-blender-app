/// Parses user-typed text as a finite number: surrounding whitespace is
/// ignored, then the text must be a number that is not NaN or infinite.
/// Returns null for blank, malformed, or non-finite input.
double? parseFiniteNumber(String text) {
  final value = double.tryParse(text.trim());
  return value != null && value.isFinite ? value : null;
}

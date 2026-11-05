/// Mirrors JS `String(n)` as used by template literals (`${n}`).
///
/// Finite integral values below 1e21 print without a fraction (`3`, not `3.0`).
/// Other values use Dart's shortest round-trip text, which matches JS for
/// fractions, `NaN`, `Infinity`, `-Infinity`, and exponent notation.
String jsNumberString(double value) {
  if (value.isFinite &&
      value == value.truncateToDouble() &&
      value.abs() < 1e21) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// Mirrors JS `Number(text)` for a string that is already trimmed.
///
/// Accepts decimal literals, `Infinity`, `+Infinity`, `-Infinity`, and
/// `0x`/`0o`/`0b` integer prefixes. Anything else is `NaN`, as in JS.
double parseJsNumber(String text) {
  final prefixed = RegExp(r'^0([xob])([0-9a-fA-F]+)$').firstMatch(text);
  if (prefixed != null) {
    final radix = switch (prefixed.group(1)) {
      'x' => 16,
      'o' => 8,
      _ => 2,
    };
    final digits = prefixed.group(2)!;
    final value = int.tryParse(digits, radix: radix);
    return value == null ? double.nan : value.toDouble();
  }
  if (text == 'Infinity' || text == '+Infinity') {
    return double.infinity;
  }
  if (text == '-Infinity') {
    return double.negativeInfinity;
  }
  if (!RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$').hasMatch(text)) {
    return double.nan;
  }
  return double.tryParse(text) ?? double.nan;
}

part of '../settings_screen.dart';

/// Number text field: parses with `parseFloat` semantics (NaN for blank or
/// non-numeric text, which validation rejects).
class _NumberField extends StatelessWidget {
  const _NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.display,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String Function(double)? display;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: (display ?? _formatSettingNumber)(value),
      decoration: InputDecoration(labelText: label, isDense: true),
      keyboardType: signedDecimalKeyboard,
      onChanged: (text) => onChanged(_parseNumber(text)),
    );
  }
}

double _parseNumber(String text) => double.tryParse(text.trim()) ?? double.nan;

String _formatSettingNumber(double value) =>
    value.isFinite ? value.toStringAsFixed(2) : '—';

String _formatFee(double value) =>
    value.isFinite ? value.toStringAsFixed(2) : '';

String _formatDimension(double value) =>
    value.isFinite ? value.toStringAsFixed(1) : '';

/// JS `Math.round(value * 100) / 100` for flat operation fees.
double _roundFee(double value) =>
    value.isFinite ? (value * 100 + 0.5).floorToDouble() / 100 : value;

import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/currency_format.dart';

void main() {
  test(
    'currencyPrefix spaces alphanumeric symbols and leaves symbols bare',
    () {
      expect(currencyPrefix(''), '');
      expect(currencyPrefix(null), '');
      expect(currencyPrefix('€'), '€');
      expect(currencyPrefix('\$'), '\$');
      expect(currencyPrefix('CHF'), 'CHF ');
      expect(currencyPrefix('kr.'), 'kr.');
      expect(currencyPrefix('Kč'), 'Kč ');
      expect(currencyPrefix('zł'), 'zł ');
    },
  );

  test('formatMoney prefixes the fixed-precision amount', () {
    expect(formatMoney(12.4, '€', 2), '€12.40');
    expect(formatMoney(12.4, 'CHF', 2), 'CHF 12.40');
    expect(formatMoney(0.025, '', 4), '0.0250');
    expect(formatMoney(0, '\$', 2), '\$0.00');
  });

  test('formatMoney puts the sign before the currency prefix', () {
    expect(formatMoney(-1.2, '€', 2), '-€1.20');
    expect(formatMoney(-1.2, 'CHF', 2), '-CHF 1.20');
    expect(formatMoney(-0.023, '€', 6), '-€0.023000');
  });

  test('formatMoney prints no minus for an amount that rounds to zero', () {
    expect(formatMoney(-0.001, '€', 2), '€0.00');
    expect(formatMoney(-0.0, '€', 2), '€0.00');
  });
}

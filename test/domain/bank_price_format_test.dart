import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/bank_price_format.dart';

void main() {
  group('bank price formatting', () {
    test('formats stored prices for the inventory input in the display unit to 6 decimals', () {
      // JS undefined and null both map to Dart null.
      expect(formatBankPrice(null, 'metric'), '');
      expect(formatBankPrice(0.02, 'metric'), '0.020000');
      expect(formatBankPrice(0.0123456789, 'metric'), '0.012346');
      expect(formatBankPrice(0.02, 'imperial'), '0.566337');
    });
  });
}

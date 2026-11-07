import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/finite_number.dart';

void main() {
  test('parses finite numbers and ignores surrounding whitespace', () {
    expect(parseFiniteNumber('12.5'), 12.5);
    expect(parseFiniteNumber('  -3 '), -3);
  });

  test('blank and malformed text give null', () {
    expect(parseFiniteNumber(''), isNull);
    expect(parseFiniteNumber('   '), isNull);
    expect(parseFiniteNumber('12abc'), isNull);
  });

  test('NaN and infinity, which tryParse accepts, give null', () {
    expect(parseFiniteNumber('NaN'), isNull);
    expect(parseFiniteNumber('Infinity'), isNull);
    expect(parseFiniteNumber('-Infinity'), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/gas_input.dart';

void main() {
  test(
    'slash-delimited O2/He input separates both values and trims whitespace',
    () {
      final split = splitGasInput(' 21 / 35 ');
      expect(split, isNotNull);
      expect(split!.oxygenText, '21');
      expect(split.heliumText, '35');
    },
  );

  test('ordinary O2 input does not split', () {
    expect(splitGasInput('21'), isNull);
  });

  test(
    'numeric inputs do not turn blank or malformed text into a fallback value',
    () {
      expect(parseNumericInput(' 21.5 '), 21.5);
      expect(parseNumericInput('1.5e1'), 15);
      expect(parseNumericInput('').isNaN, isTrue);
      expect(parseNumericInput('not a number').isNaN, isTrue);
      expect(parseNumericInput('0x15').isNaN, isTrue);
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/theme.dart';

void main() {
  test('missing or unknown theme preference uses the light default', () {
    expect(themeOrDefault(null), DEFAULT_THEME);
    expect(themeOrDefault('system'), 'light');
  });

  test('light and dark theme preferences survive save/load', () {
    expect(themeOrDefault(themeToStore('light')), 'light');
    expect(themeOrDefault(themeToStore('dark')), 'dark');
  });

  test(
    'invalid theme values are rejected before replacing a saved preference',
    () {
      final saved = themeToStore('light');
      expect(() => themeToStore('system'), throwsRangeError);
      expect(themeOrDefault(saved), 'light');
    },
  );
}

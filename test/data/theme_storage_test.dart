import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/data/key_value_storage.dart';
import 'package:simplex_blender/src/data/theme_storage.dart';
import 'package:simplex_blender/src/domain/theme.dart';

import '../support/memory_storage.dart';

/// Storage whose reads always fail, mirroring `storage.getItem` throwing.
class _UnreadableStorage implements KeyValueStorage {
  @override
  String? getItem(String key) => throw StateError('storage unavailable');

  @override
  void setItem(String key, String value) {}

  @override
  void clear() {}
}

void main() {
  group('theme storage', () {
    test('missing or unknown theme preference uses the light default', () {
      final storage = MemoryStorage();
      expect(loadThemePreference(storage), DEFAULT_THEME);
      storage.setItem('simplex-gas-remixer-theme', 'system');
      expect(loadThemePreference(storage), 'light');
    });

    test('light and dark theme preferences survive save/load', () {
      final storage = MemoryStorage();
      saveThemePreference('light', storage);
      expect(loadThemePreference(storage), 'light');
      saveThemePreference('dark', storage);
      expect(loadThemePreference(storage), 'dark');
    });

    test(
      'invalid theme values are rejected before replacing a saved preference',
      () {
        final storage = MemoryStorage(<String, String>{
          'simplex-gas-remixer-theme': 'light',
        });
        expect(
          () => saveThemePreference('system', storage),
          throwsA(isA<RangeError>()),
        );
        expect(storage.getItem('simplex-gas-remixer-theme'), 'light');
      },
    );

    test('theme load falls back to light when storage cannot be read', () {
      expect(loadThemePreference(_UnreadableStorage()), 'light');
    });
  });
}

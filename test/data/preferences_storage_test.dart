import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simplex_blender/src/data/preferences_storage.dart';

const String _themeKey = 'simplex-gas-remixer-theme';
const String _banksKey = 'simplex-gas-remixer-banks';

/// String entries as the platform store holds them. `reload()` re-reads the
/// platform store, bypassing the in-memory cache that `setItem` updates.
Future<Map<String, String>> _persistedStrings() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final values = <String, String>{};
  for (final key in preferences.getKeys()) {
    final value = preferences.get(key);
    if (value is String) {
      values[key] = value;
    }
  }
  return values;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('preferences key/value storage', () {
    test('existing string values load into getItem', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _themeKey: 'dark',
        _banksKey: '[]',
        'numeric-entry': 7,
      });

      final storage = await PreferencesKeyValueStorage.open();

      expect(storage.getItem(_themeKey), 'dark');
      expect(storage.getItem(_banksKey), '[]');
      expect(storage.getItem('missing-key'), isNull);
      expect(storage.getItem('numeric-entry'), isNull);
    });

    test('setItem is visible at once and persists after the write', () async {
      final storage = await PreferencesKeyValueStorage.open();

      storage.setItem(_themeKey, 'dark');
      expect(storage.getItem(_themeKey), 'dark');

      await storage.pendingWrites;
      expect(await _persistedStrings(), <String, String>{_themeKey: 'dark'});

      final reopened = await PreferencesKeyValueStorage.open();
      expect(reopened.getItem(_themeKey), 'dark');
    });

    test('later writes to a key replace earlier ones on disk', () async {
      final storage = await PreferencesKeyValueStorage.open();

      storage.setItem(_themeKey, 'light');
      storage.setItem(_themeKey, 'dark');
      await storage.pendingWrites;

      expect(storage.getItem(_themeKey), 'dark');
      expect(await _persistedStrings(), <String, String>{_themeKey: 'dark'});
    });

    test('clear empties memory and the persisted store', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _themeKey: 'dark',
        _banksKey: '[]',
      });
      final storage = await PreferencesKeyValueStorage.open();

      storage.clear();
      expect(storage.getItem(_themeKey), isNull);
      expect(storage.getItem(_banksKey), isNull);

      await storage.pendingWrites;
      expect(await _persistedStrings(), isEmpty);
    });

    test('a write issued after clear survives the clear', () async {
      final storage = await PreferencesKeyValueStorage.open();

      storage.setItem(_themeKey, 'dark');
      storage.clear();
      storage.setItem(_banksKey, '[]');
      await storage.pendingWrites;

      expect(storage.getItem(_themeKey), isNull);
      expect(await _persistedStrings(), <String, String>{_banksKey: '[]'});
    });
  });
}

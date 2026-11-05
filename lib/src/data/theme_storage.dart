import 'package:simplex_blender/src/data/key_value_storage.dart';
import 'package:simplex_blender/src/domain/theme.dart';

/// Port of JS `loadTheme`. Any read failure or unknown stored value yields
/// [DEFAULT_THEME]; the failure is not reported.
String loadThemePreference(KeyValueStorage storage) {
  try {
    return themeOrDefault(storage.getItem(THEME_STORAGE_KEY));
  } catch (_) {
    return DEFAULT_THEME;
  }
}

/// Port of JS `saveTheme`. Invalid values throw [RangeError] before the stored
/// preference is replaced.
void saveThemePreference(String theme, KeyValueStorage storage) {
  storage.setItem(THEME_STORAGE_KEY, themeToStore(theme));
}

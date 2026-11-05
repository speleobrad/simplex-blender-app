// ignore_for_file: constant_identifier_names

/// Port of the pure part of `js/theme.js`.
///
/// Reading and writing the preference through the platform store is in
/// `lib/src/data/theme_storage.dart`; this file only validates and normalizes
/// theme values.
library;

/// Key used by the web app's localStorage and by `theme_storage.dart`.
const String THEME_STORAGE_KEY = 'simplex-gas-remixer-theme';

const String DEFAULT_THEME = 'light';

const String _invalidThemeMessage = 'Theme must be light or dark.';

bool isThemePreference(String? value) => value == 'light' || value == 'dark';

/// Mirrors the pure half of JS `loadTheme`: unknown or missing values become
/// the light default.
String themeOrDefault(String? stored) =>
    isThemePreference(stored) ? stored! : DEFAULT_THEME;

/// Mirrors the pure half of JS `saveTheme`: returns the value to persist, or
/// throws [RangeError] before anything is replaced.
String themeToStore(String theme) {
  if (!isThemePreference(theme)) throw RangeError(_invalidThemeMessage);
  return theme;
}

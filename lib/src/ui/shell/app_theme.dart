import 'package:flutter/material.dart';

/// Palette roles taken from `css/app.css`. Typography and layout are not
/// matched yet (plan Step 5); only colours follow the web theme.
class _Palette {
  const _Palette({
    required this.background,
    required this.surface,
    required this.surfaceLow,
    required this.surfaceContainer,
    required this.surfaceHigh,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.error,
    required this.onError,
  });

  final Color background;
  final Color surface;
  final Color surfaceLow;
  final Color surfaceContainer;
  final Color surfaceHigh;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color error;
  final Color onError;
}

// Dark: `--ocean-*` 950/900/850/800/700, `--slate-100/400`, `--cyan-300/400`,
// `--rose-300`.
const _Palette _darkPalette = _Palette(
  background: Color(0xFF030812),
  surface: Color(0xFF071224),
  surfaceLow: Color(0xFF0B1B36),
  surfaceContainer: Color(0xFF0F2448),
  surfaceHigh: Color(0xFF17366B),
  border: Color(0xFF17366B),
  text: Color(0xFFF1F5F9),
  textMuted: Color(0xFF94A3B8),
  primary: Color(0xFF67E8F9),
  onPrimary: Color(0xFF030812),
  secondary: Color(0xFF22D3EE),
  error: Color(0xFFFDA4AF),
  onError: Color(0xFF030812),
);

// Light: `--ocean-950/900/850/800/700`, `--slate-100/400`, `--cyan-300/500`,
// `--rose-300`.
const _Palette _lightPalette = _Palette(
  background: Color(0xFFF8FAFC),
  surface: Color(0xFFFFFFFF),
  surfaceLow: Color(0xFFF1F5F9),
  surfaceContainer: Color(0xFFE2E8F0),
  surfaceHigh: Color(0xFFCBD5E1),
  border: Color(0xFFCBD5E1),
  text: Color(0xFF0F172A),
  textMuted: Color(0xFF475569),
  primary: Color(0xFF0E7490),
  onPrimary: Color(0xFFFFFFFF),
  secondary: Color(0xFF0891B2),
  error: Color(0xFFBE123C),
  onError: Color(0xFFFFFFFF),
);

/// Builds the Material theme for [brightness] from the web palette.
ThemeData buildAppTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark ? _darkPalette : _lightPalette;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: palette.primary,
    onPrimary: palette.onPrimary,
    secondary: palette.secondary,
    onSecondary: palette.onPrimary,
    error: palette.error,
    onError: palette.onError,
    surface: palette.surface,
    onSurface: palette.text,
    onSurfaceVariant: palette.textMuted,
    surfaceContainerLowest: palette.background,
    surfaceContainerLow: palette.surfaceLow,
    surfaceContainer: palette.surfaceContainer,
    surfaceContainerHigh: palette.surfaceHigh,
    outline: palette.border,
    outlineVariant: palette.border,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.background,
    dividerColor: palette.border,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.surface,
      foregroundColor: palette.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: palette.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.border),
      ),
    ),
  );
}

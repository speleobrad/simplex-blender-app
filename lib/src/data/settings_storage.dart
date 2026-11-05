import 'dart:convert';

import 'package:simplex_blender/src/data/key_value_storage.dart';
import 'package:simplex_blender/src/data/settings_migrations.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/settings_json.dart';

// ignore: constant_identifier_names
const String SETTINGS_STORAGE_KEY = 'simplex-gas-remixer-settings';

/// Port of JS `loadSettings`.
///
/// Returns defaults when nothing is stored. Unreadable or invalid saved data
/// also returns defaults and reports the reason through [onFallback], which
/// the app uses to set its storage warning.
Settings loadSettings(
  KeyValueStorage storage, {
  void Function(Object error)? onFallback,
}) {
  final String? raw;
  try {
    raw = storage.getItem(SETTINGS_STORAGE_KEY);
  } on Object catch (error) {
    onFallback?.call(error);
    return copySettings(DEFAULT_SETTINGS);
  }
  if (raw == null) {
    return copySettings(DEFAULT_SETTINGS);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (error) {
    onFallback?.call(error);
    return copySettings(DEFAULT_SETTINGS);
  }
  final saved = asJsonObject(decoded) ?? <String, Object?>{};
  final normalized = normalizeSettingsJson(saved);
  final errors = validateSettingsJson(normalized);
  if (errors.isNotEmpty) {
    onFallback?.call(RangeError(errors.join(' ')));
    return copySettings(DEFAULT_SETTINGS);
  }
  return copySettings(settingsFromJson(normalized));
}

/// Port of JS `saveSettings`. Invalid settings throw a [RangeError] before
/// anything is written, so the stored value is never replaced by bad data.
void saveSettings(Settings settings, KeyValueStorage storage) {
  final normalized = normalizeSettingsJson(settingsToJson(settings));
  final errors = validateSettingsJson(normalized);
  if (errors.isNotEmpty) {
    throw RangeError(errors.join(' '));
  }
  final stored = settingsToJson(copySettings(settingsFromJson(normalized)));
  storage.setItem(SETTINGS_STORAGE_KEY, jsonEncode(stored));
}

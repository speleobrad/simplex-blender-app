import 'dart:convert';

import 'package:simplex_blender/src/data/key_value_storage.dart';

/// Storage key for the analytics on/off preference. Value shape: `{"enabled":
/// bool}`. Kept apart from the settings record so the settings JSON shape is
/// unchanged.
const String analyticsStorageKey = 'simplex-gas-remixer-analytics';

/// Analytics is on until the user turns it off. Missing, unreadable, or
/// malformed stored values fall back to on.
bool loadAnalyticsEnabled(KeyValueStorage storage) {
  try {
    final raw = storage.getItem(analyticsStorageKey);
    if (raw == null) {
      return true;
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, Object?> && decoded['enabled'] is bool) {
      return decoded['enabled']! as bool;
    }
    return true;
  } on Object {
    return true;
  }
}

void saveAnalyticsEnabled(bool enabled, KeyValueStorage storage) {
  storage.setItem(
    analyticsStorageKey,
    jsonEncode(<String, Object>{'enabled': enabled}),
  );
}

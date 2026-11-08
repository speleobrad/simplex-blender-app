import 'dart:convert';

import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/settings_json.dart';

/// Saved settings JSON, as written before cylinder dimensions existed: default
/// settings whose cylinder presets are a custom aluminium 5.5 L preset and a
/// 12 L steel preset, both without the `diameterMm` and `lengthMm` keys.
String legacyCylinderSettingsJson() => jsonEncode(<String, Object?>{
  ...settingsToJson(DEFAULT_SETTINGS),
  'cylinderPresets': <Object?>[
    <String, Object?>{
      'name': 'Alu 5.5',
      'volumeL': 5.5,
      'material': 'aluminum',
      'massKg': 7,
      'workingPressureBar': 207,
      'hotOverfillPercent': 2,
    },
    <String, Object?>{
      'name': 'Steel 12',
      'volumeL': 12,
      'material': 'steel',
      'massKg': 14,
      'workingPressureBar': 232,
      'hotOverfillPercent': 2,
    },
  ],
});

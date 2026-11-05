import 'package:simplex_blender/src/domain/settings.dart';

/// JS `compressorPresetMatchesActiveFields`: true when every preset field equals
/// the active compressor setting.
bool compressorPresetMatchesActiveFields(
  SettingsBooster compressor,
  CompressorPreset preset,
) {
  return preset.inletFlowLPerMin == compressor.compressorInletFlowLPerMin &&
      preset.maxPressureBar == compressor.maxCompressorPressureBar &&
      preset.temperatureModifierC == compressor.compressorTemperatureModifierC;
}

/// JS `boosterPresetMatchesActiveFields`: true when every preset field equals
/// the active booster setting.
bool boosterPresetMatchesActiveFields(
  SettingsBooster booster,
  BoosterPreset preset,
) {
  return preset.minimumSourcePressureBar == booster.minimumSourcePressureBar &&
      preset.cylinderVolumeCm3 == booster.cylinderVolumeCm3 &&
      preset.oxygenBoostBpm == booster.oxygenBoostBpm &&
      preset.otherBoostBpm == booster.otherBoostBpm &&
      preset.oxygenDecantRateBarPerMin == booster.oxygenDecantRateBarPerMin &&
      preset.otherDecantRateBarPerMin == booster.otherDecantRateBarPerMin &&
      preset.maxOutputPressureBar == booster.maxBoosterOutputPressureBar &&
      preset.temperatureModifierC == booster.boosterTemperatureModifierC &&
      preset.drainingRateBarPerMin == booster.drainingRateBarPerMin;
}

/// Name shown for the active compressor: the first matching preset, else
/// `Custom compressor` (JS `renderEquipmentSummary`).
String compressorDisplayName(
  SettingsBooster active,
  List<CompressorPreset> presets,
) {
  for (final preset in presets) {
    if (compressorPresetMatchesActiveFields(active, preset)) {
      return preset.name;
    }
  }
  return 'Custom compressor';
}

/// Name shown for the active booster: the first matching preset, else
/// `Custom booster` (JS `renderEquipmentSummary`).
String boosterDisplayName(SettingsBooster active, List<BoosterPreset> presets) {
  for (final preset in presets) {
    if (boosterPresetMatchesActiveFields(active, preset)) {
      return preset.name;
    }
  }
  return 'Custom booster';
}

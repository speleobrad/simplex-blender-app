import 'package:simplex_blender/src/domain/settings.dart';

/// Name of the cylinder preset selected on first launch (JS
/// `DEFAULT_CYLINDER_PRESET_NAME` in `js/main.js`).
const String defaultCylinderPresetName = 'Catalina S80';

/// Built-in Blending form values (JS `index.html` input defaults) in internal
/// metric units. The Blending form, the root shell, and any other consumer
/// obtain their initial values from [defaultBlendInputs]; no other copy exists.
class BlendInputDefaults {
  const BlendInputDefaults({
    required this.cylinderPreset,
    required this.initialPressureBar,
    required this.initialOxygenPercent,
    required this.initialHeliumPercent,
    required this.targetPressureBar,
    required this.targetOxygenPercent,
    required this.targetHeliumPercent,
    required this.ambientTemperatureC,
    required this.targetInWaterTemperatureC,
    required this.waitTargetTemperatureC,
    required this.inletTemperatureC,
    required this.coolingMedium,
    required this.waterSubmersionPercent,
    required this.waitMode,
    required this.waitMinutes,
  });

  final CylinderPreset cylinderPreset;
  final double initialPressureBar;
  final double initialOxygenPercent;
  final double initialHeliumPercent;
  final double targetPressureBar;
  final double targetOxygenPercent;
  final double targetHeliumPercent;
  final double ambientTemperatureC;
  final double targetInWaterTemperatureC;
  final double waitTargetTemperatureC;
  final double inletTemperatureC;
  final String coolingMedium;
  final double waterSubmersionPercent;
  final String waitMode;
  final double waitMinutes;
}

/// Returns the built-in Blending defaults.
///
/// The initial cylinder is the preset named [defaultCylinderPresetName] when
/// [cylinderPresets] contains it, otherwise the first preset (JS
/// `selectedCylinderPreset` in `js/main.js`, with the default name rendered
/// as the selected option).
BlendInputDefaults defaultBlendInputs({List<CylinderPreset>? cylinderPresets}) {
  final preset = _defaultCylinderPreset(
    cylinderPresets ?? DEFAULT_SETTINGS.cylinderPresets,
  );
  return BlendInputDefaults(
    cylinderPreset: preset,
    initialPressureBar: 45,
    initialOxygenPercent: 21,
    initialHeliumPercent: 0,
    targetPressureBar: 195,
    targetOxygenPercent: 18,
    targetHeliumPercent: 45,
    ambientTemperatureC: 21,
    targetInWaterTemperatureC: 10,
    waitTargetTemperatureC: 25,
    inletTemperatureC: 21,
    coolingMedium: 'air',
    waterSubmersionPercent: 60,
    waitMode: 'minutes',
    waitMinutes: 5,
  );
}

CylinderPreset _defaultCylinderPreset(List<CylinderPreset> presets) {
  for (final preset in presets) {
    if (preset.name == defaultCylinderPresetName) {
      return preset;
    }
  }
  if (presets.isEmpty) {
    throw StateError('No cylinder presets are available.');
  }
  return presets.first;
}

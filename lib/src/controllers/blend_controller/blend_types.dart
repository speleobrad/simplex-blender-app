part of '../blend_controller.dart';

/// Blending screen form values (JS `readInput`), in internal metric units.
/// [inletTemperatureC] is the effective inlet temperature (JS
/// `effectiveInletTemperatureC()`), already resolved by the caller.
class BlendInputs {
  const BlendInputs({
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

  BlendInputs copyWith({
    CylinderPreset? cylinderPreset,
    double? initialPressureBar,
    double? initialOxygenPercent,
    double? initialHeliumPercent,
    double? targetPressureBar,
    double? targetOxygenPercent,
    double? targetHeliumPercent,
    double? ambientTemperatureC,
    double? targetInWaterTemperatureC,
    double? waitTargetTemperatureC,
    double? inletTemperatureC,
    String? coolingMedium,
    double? waterSubmersionPercent,
    String? waitMode,
    double? waitMinutes,
  }) {
    return BlendInputs(
      cylinderPreset: cylinderPreset ?? this.cylinderPreset,
      initialPressureBar: initialPressureBar ?? this.initialPressureBar,
      initialOxygenPercent: initialOxygenPercent ?? this.initialOxygenPercent,
      initialHeliumPercent: initialHeliumPercent ?? this.initialHeliumPercent,
      targetPressureBar: targetPressureBar ?? this.targetPressureBar,
      targetOxygenPercent: targetOxygenPercent ?? this.targetOxygenPercent,
      targetHeliumPercent: targetHeliumPercent ?? this.targetHeliumPercent,
      ambientTemperatureC: ambientTemperatureC ?? this.ambientTemperatureC,
      targetInWaterTemperatureC:
          targetInWaterTemperatureC ?? this.targetInWaterTemperatureC,
      waitTargetTemperatureC:
          waitTargetTemperatureC ?? this.waitTargetTemperatureC,
      inletTemperatureC: inletTemperatureC ?? this.inletTemperatureC,
      coolingMedium: coolingMedium ?? this.coolingMedium,
      waterSubmersionPercent:
          waterSubmersionPercent ?? this.waterSubmersionPercent,
      waitMode: waitMode ?? this.waitMode,
      waitMinutes: waitMinutes ?? this.waitMinutes,
    );
  }

  /// Builds the initial Blending form values from [defaultBlendInputs].
  factory BlendInputs.fromDefaults(BlendInputDefaults defaults) {
    return BlendInputs(
      cylinderPreset: defaults.cylinderPreset,
      initialPressureBar: defaults.initialPressureBar,
      initialOxygenPercent: defaults.initialOxygenPercent,
      initialHeliumPercent: defaults.initialHeliumPercent,
      targetPressureBar: defaults.targetPressureBar,
      targetOxygenPercent: defaults.targetOxygenPercent,
      targetHeliumPercent: defaults.targetHeliumPercent,
      ambientTemperatureC: defaults.ambientTemperatureC,
      targetInWaterTemperatureC: defaults.targetInWaterTemperatureC,
      waitTargetTemperatureC: defaults.waitTargetTemperatureC,
      inletTemperatureC: defaults.inletTemperatureC,
      coolingMedium: defaults.coolingMedium,
      waterSubmersionPercent: defaults.waterSubmersionPercent,
      waitMode: defaults.waitMode,
      waitMinutes: defaults.waitMinutes,
    );
  }
}

/// Steps and temperature that the Costs section is derived from (JS
/// `blendingCostSource()`).
typedef BlendCostSource = ({List<ProtocolStep> steps, double temperatureC});

/// Bank price suggestion with the pricing signature it was computed for
/// (JS `state.bankSuggestions[bank.id]`).
class BankPriceEntry {
  const BankPriceEntry({required this.signature, required this.result});

  final String signature;
  final BankPriceResult result;
}

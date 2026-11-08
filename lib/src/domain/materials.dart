import 'package:simplex_blender/src/domain/domain_error.dart';

/// Thermal parameter set for one cylinder material.
class MaterialThermal {
  const MaterialThermal({
    required this.defaultTankMassKg,
    required this.specificHeatJPerKgK,
    required this.airTauMinutes,
    required this.waterTauMinutes,
  });

  final double defaultTankMassKg;
  final double specificHeatJPerKgK;
  final double airTauMinutes;
  final double waterTauMinutes;

  @override
  bool operator ==(Object other) =>
      other is MaterialThermal &&
      other.defaultTankMassKg == defaultTankMassKg &&
      other.specificHeatJPerKgK == specificHeatJPerKgK &&
      other.airTauMinutes == airTauMinutes &&
      other.waterTauMinutes == waterTauMinutes;

  @override
  int get hashCode => Object.hash(
    defaultTankMassKg,
    specificHeatJPerKgK,
    airTauMinutes,
    waterTauMinutes,
  );
}

class MaterialDefinition {
  const MaterialDefinition({
    required this.label,
    this.labelImperial,
    required this.thermal,
  });

  final String label;
  final String? labelImperial;
  final MaterialThermal thermal;
}

// `carbon-wrapped-steel` (shown as "Fero-carbon") covers steel-lined, carbon-fibre
// hoop-wrapped cylinders such as the Worthington Carbondive. Its thermal parameters are
// deliberately UNCALIBRATED and borrowed from steel: the liner carries most of the mass,
// and no measured fill or cool-down data exists for the wrap's effect (it may slow
// cool-down in water). Aluminium-lined and polymer-lined (Type 3/4) composites are not
// modelled and must not be mapped onto these values.
//
// Steel and aluminium cooling time constants (`airTauMinutes`, `waterTauMinutes`) have NO
// recorded provenance: no source, measurement, or calibration run is referenced in this
// repository, and they are NOT calibrated. Do not describe them as calibrated. The water
// values are also not consistent with `heatTransferWaterWPerM2K`. A lumped-capacitance
// estimate tau = m*c / (h*A) with h = 250 W/m2K gives about 1.0 min (steel) and 1.8 min
// (aluminium), while the tabulated values imply h of about 73 and 89 W/m2K. Until the
// original JS source or cool-down measurements are located, treat both the water time
// constants and the water heat-transfer coefficient as open questions. Do not change either
// value without that data.

const MaterialThermal _steelThermal = MaterialThermal(
  defaultTankMassKg: 14,
  specificHeatJPerKgK: 490,
  airTauMinutes: 18,
  waterTauMinutes: 3.5,
);

/// Single source of truth for cylinder materials.
const Map<String, MaterialDefinition> materials = {
  'steel': MaterialDefinition(label: 'Steel', thermal: _steelThermal),
  'aluminum': MaterialDefinition(
    label: 'Aluminium',
    labelImperial: 'Aluminum',
    thermal: MaterialThermal(
      defaultTankMassKg: 14.2,
      specificHeatJPerKgK: 900,
      airTauMinutes: 25,
      waterTauMinutes: 5,
    ),
  ),
  'carbon-wrapped-steel': MaterialDefinition(
    label: 'Fero-carbon',
    thermal: _steelThermal,
  ),
};

final List<String> materialValues = List.unmodifiable(materials.keys);

bool isValidMaterial(Object? material) =>
    material is String && materials.containsKey(material);

String materialListText() {
  final labels = [
    for (final definition in materials.values) definition.label.toLowerCase(),
  ];
  return '${labels.sublist(0, labels.length - 1).join(', ')} or ${labels.last}';
}

/// An absent material keeps the historical steel default; an unknown one is an error
/// rather than silently inheriting steel behaviour.
MaterialThermal materialThermal(String? material) {
  if (material == null) return _steelThermal;
  final definition = materials[material];
  if (definition == null) {
    throw DomainError('Unknown cylinder material: $material');
  }
  return definition.thermal;
}

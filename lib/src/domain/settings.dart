import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/cylinder_geometry.dart';
import 'package:simplex_blender/src/domain/domain_error.dart';
import 'package:simplex_blender/src/domain/input_validation.dart';
import 'package:simplex_blender/src/domain/preset_validation.dart';

// ignore: constant_identifier_names
const String PRESSURE_WARNING_UNLOCK_PHRASE = "I KNOW WHAT I'M DOING";

/// Mirrors JS `normalizePresetName`: trimmed, lower-cased name used for
/// duplicate detection.
String normalizePresetName(String name) => name.trim().toLowerCase();

/// Mirrors JS `matchesPressureWarningUnlockPhrase`. ASCII letters are
/// upper-cased and backtick/double-quote are folded to an apostrophe before
/// comparing with [PRESSURE_WARNING_UNLOCK_PHRASE].
bool matchesPressureWarningUnlockPhrase(Object? value) {
  if (value is! String) {
    return false;
  }
  final upper = value.replaceAllMapped(
    RegExp('[a-z]'),
    (match) => match[0]!.toUpperCase(),
  );
  return upper.replaceAll(RegExp('[`"]'), "'") ==
      PRESSURE_WARNING_UNLOCK_PHRASE;
}

/// Equipment collections that the Settings editor and the optimizer share.
enum EquipmentCategory { compressor, booster }

/// A gas preset (JS `gasPresets` entry).
class GasPreset {
  const GasPreset({
    required this.name,
    required this.oxygenPercent,
    required this.heliumPercent,
  });

  final String name;
  final double oxygenPercent;
  final double heliumPercent;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'oxygenPercent': oxygenPercent,
    'heliumPercent': heliumPercent,
  };

  GasPreset copyWith({
    String? name,
    double? oxygenPercent,
    double? heliumPercent,
  }) {
    return GasPreset(
      name: name ?? this.name,
      oxygenPercent: oxygenPercent ?? this.oxygenPercent,
      heliumPercent: heliumPercent ?? this.heliumPercent,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GasPreset &&
      other.name == name &&
      other.oxygenPercent == oxygenPercent &&
      other.heliumPercent == heliumPercent;

  @override
  int get hashCode => Object.hash(name, oxygenPercent, heliumPercent);
}

/// A cylinder preset (JS `cylinderPresets` entry). `diameterMm` and
/// `lengthMm` (body without valve) are Flutter-only additions; null means
/// unknown, which makes the preset incomplete.
class CylinderPreset {
  const CylinderPreset({
    required this.name,
    required this.volumeL,
    required this.material,
    required this.massKg,
    required this.workingPressureBar,
    required this.hotOverfillPercent,
    this.diameterMm,
    this.lengthMm,
  });

  final String name;
  final double volumeL;
  final String material;
  final double massKg;
  final double workingPressureBar;
  final double hotOverfillPercent;
  final double? diameterMm;
  final double? lengthMm;

  /// True only when both dimensions are finite and greater than zero.
  bool get isComplete =>
      _validDimension(diameterMm) && _validDimension(lengthMm);

  /// Heat-transfer surface in m². Throws when the preset is incomplete.
  double get surfaceAreaM2 {
    if (!isComplete) {
      throw DomainError(incompleteCylinderMessage(name));
    }
    return tankSurfaceAreaM2(diameterMm: diameterMm!, lengthMm: lengthMm!);
  }

  static bool _validDimension(double? value) =>
      value != null && value.isFinite && value > 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'volumeL': volumeL,
    'material': material,
    'massKg': massKg,
    'workingPressureBar': workingPressureBar,
    'hotOverfillPercent': hotOverfillPercent,
    'diameterMm': diameterMm,
    'lengthMm': lengthMm,
  };

  /// A null argument keeps the current value. The editor passes `double.nan`
  /// to represent a cleared dimension field, which validation rejects.
  CylinderPreset copyWith({
    String? name,
    double? volumeL,
    String? material,
    double? massKg,
    double? workingPressureBar,
    double? hotOverfillPercent,
    double? diameterMm,
    double? lengthMm,
  }) {
    return CylinderPreset(
      name: name ?? this.name,
      volumeL: volumeL ?? this.volumeL,
      material: material ?? this.material,
      massKg: massKg ?? this.massKg,
      workingPressureBar: workingPressureBar ?? this.workingPressureBar,
      hotOverfillPercent: hotOverfillPercent ?? this.hotOverfillPercent,
      diameterMm: diameterMm ?? this.diameterMm,
      lengthMm: lengthMm ?? this.lengthMm,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CylinderPreset &&
      other.name == name &&
      other.volumeL == volumeL &&
      other.material == material &&
      other.massKg == massKg &&
      other.workingPressureBar == workingPressureBar &&
      other.hotOverfillPercent == hotOverfillPercent &&
      other.diameterMm == diameterMm &&
      other.lengthMm == lengthMm;

  @override
  int get hashCode => Object.hash(
    name,
    volumeL,
    material,
    massKg,
    workingPressureBar,
    hotOverfillPercent,
    diameterMm,
    lengthMm,
  );
}

/// A compressor preset (JS `compressorPresets` entry).
class CompressorPreset {
  const CompressorPreset({
    required this.name,
    required this.inletFlowLPerMin,
    required this.maxPressureBar,
    required this.temperatureModifierC,
  });

  final String name;
  final double inletFlowLPerMin;
  final double maxPressureBar;
  final double temperatureModifierC;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'inletFlowLPerMin': inletFlowLPerMin,
    'maxPressureBar': maxPressureBar,
    'temperatureModifierC': temperatureModifierC,
  };

  CompressorPreset copyWith({
    String? name,
    double? inletFlowLPerMin,
    double? maxPressureBar,
    double? temperatureModifierC,
  }) {
    return CompressorPreset(
      name: name ?? this.name,
      inletFlowLPerMin: inletFlowLPerMin ?? this.inletFlowLPerMin,
      maxPressureBar: maxPressureBar ?? this.maxPressureBar,
      temperatureModifierC: temperatureModifierC ?? this.temperatureModifierC,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CompressorPreset &&
      other.name == name &&
      other.inletFlowLPerMin == inletFlowLPerMin &&
      other.maxPressureBar == maxPressureBar &&
      other.temperatureModifierC == temperatureModifierC;

  @override
  int get hashCode =>
      Object.hash(name, inletFlowLPerMin, maxPressureBar, temperatureModifierC);
}

/// A booster preset (JS `boosterPresets` entry).
class BoosterPreset {
  const BoosterPreset({
    required this.name,
    required this.minimumSourcePressureBar,
    required this.cylinderVolumeCm3,
    required this.oxygenBoostBpm,
    required this.otherBoostBpm,
    required this.oxygenDecantRateBarPerMin,
    required this.otherDecantRateBarPerMin,
    required this.maxOutputPressureBar,
    required this.temperatureModifierC,
    required this.drainingRateBarPerMin,
  });

  final String name;
  final double minimumSourcePressureBar;
  final double cylinderVolumeCm3;
  final double oxygenBoostBpm;
  final double otherBoostBpm;
  final double oxygenDecantRateBarPerMin;
  final double otherDecantRateBarPerMin;
  final double maxOutputPressureBar;
  final double temperatureModifierC;
  final double drainingRateBarPerMin;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'minimumSourcePressureBar': minimumSourcePressureBar,
    'cylinderVolumeCm3': cylinderVolumeCm3,
    'oxygenBoostBpm': oxygenBoostBpm,
    'otherBoostBpm': otherBoostBpm,
    'oxygenDecantRateBarPerMin': oxygenDecantRateBarPerMin,
    'otherDecantRateBarPerMin': otherDecantRateBarPerMin,
    'maxOutputPressureBar': maxOutputPressureBar,
    'temperatureModifierC': temperatureModifierC,
    'drainingRateBarPerMin': drainingRateBarPerMin,
  };

  BoosterPreset copyWith({
    String? name,
    double? minimumSourcePressureBar,
    double? cylinderVolumeCm3,
    double? oxygenBoostBpm,
    double? otherBoostBpm,
    double? oxygenDecantRateBarPerMin,
    double? otherDecantRateBarPerMin,
    double? maxOutputPressureBar,
    double? temperatureModifierC,
    double? drainingRateBarPerMin,
  }) {
    return BoosterPreset(
      name: name ?? this.name,
      minimumSourcePressureBar:
          minimumSourcePressureBar ?? this.minimumSourcePressureBar,
      cylinderVolumeCm3: cylinderVolumeCm3 ?? this.cylinderVolumeCm3,
      oxygenBoostBpm: oxygenBoostBpm ?? this.oxygenBoostBpm,
      otherBoostBpm: otherBoostBpm ?? this.otherBoostBpm,
      oxygenDecantRateBarPerMin:
          oxygenDecantRateBarPerMin ?? this.oxygenDecantRateBarPerMin,
      otherDecantRateBarPerMin:
          otherDecantRateBarPerMin ?? this.otherDecantRateBarPerMin,
      maxOutputPressureBar: maxOutputPressureBar ?? this.maxOutputPressureBar,
      temperatureModifierC: temperatureModifierC ?? this.temperatureModifierC,
      drainingRateBarPerMin:
          drainingRateBarPerMin ?? this.drainingRateBarPerMin,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BoosterPreset &&
      other.name == name &&
      other.minimumSourcePressureBar == minimumSourcePressureBar &&
      other.cylinderVolumeCm3 == cylinderVolumeCm3 &&
      other.oxygenBoostBpm == oxygenBoostBpm &&
      other.otherBoostBpm == otherBoostBpm &&
      other.oxygenDecantRateBarPerMin == oxygenDecantRateBarPerMin &&
      other.otherDecantRateBarPerMin == otherDecantRateBarPerMin &&
      other.maxOutputPressureBar == maxOutputPressureBar &&
      other.temperatureModifierC == temperatureModifierC &&
      other.drainingRateBarPerMin == drainingRateBarPerMin;

  @override
  int get hashCode => Object.hash(
    name,
    minimumSourcePressureBar,
    cylinderVolumeCm3,
    oxygenBoostBpm,
    otherBoostBpm,
    oxygenDecantRateBarPerMin,
    otherDecantRateBarPerMin,
    maxOutputPressureBar,
    temperatureModifierC,
    drainingRateBarPerMin,
  );
}

/// JS `settings.booster`: the active booster and compressor values. Named
/// `SettingsBooster` because `thermodynamics.dart` already owns `BoosterSettings`
/// for the thermal input (nullable fields, different shape).
class SettingsBooster {
  const SettingsBooster({
    required this.minimumSourcePressureBar,
    required this.cylinderVolumeCm3,
    required this.oxygenBoostBpm,
    required this.otherBoostBpm,
    required this.oxygenDecantRateBarPerMin,
    required this.otherDecantRateBarPerMin,
    required this.drainingRateBarPerMin,
    required this.compressorInletFlowLPerMin,
    required this.maxCompressorPressureBar,
    required this.maxBoosterOutputPressureBar,
    required this.boosterTemperatureModifierC,
    required this.compressorTemperatureModifierC,
  });

  final double minimumSourcePressureBar;
  final double cylinderVolumeCm3;
  final double oxygenBoostBpm;
  final double otherBoostBpm;
  final double oxygenDecantRateBarPerMin;
  final double otherDecantRateBarPerMin;
  final double drainingRateBarPerMin;
  final double compressorInletFlowLPerMin;
  final double maxCompressorPressureBar;
  final double maxBoosterOutputPressureBar;
  final double boosterTemperatureModifierC;
  final double compressorTemperatureModifierC;

  SettingsBooster copyWith({
    double? minimumSourcePressureBar,
    double? cylinderVolumeCm3,
    double? oxygenBoostBpm,
    double? otherBoostBpm,
    double? oxygenDecantRateBarPerMin,
    double? otherDecantRateBarPerMin,
    double? drainingRateBarPerMin,
    double? compressorInletFlowLPerMin,
    double? maxCompressorPressureBar,
    double? maxBoosterOutputPressureBar,
    double? boosterTemperatureModifierC,
    double? compressorTemperatureModifierC,
  }) {
    return SettingsBooster(
      minimumSourcePressureBar:
          minimumSourcePressureBar ?? this.minimumSourcePressureBar,
      cylinderVolumeCm3: cylinderVolumeCm3 ?? this.cylinderVolumeCm3,
      oxygenBoostBpm: oxygenBoostBpm ?? this.oxygenBoostBpm,
      otherBoostBpm: otherBoostBpm ?? this.otherBoostBpm,
      oxygenDecantRateBarPerMin:
          oxygenDecantRateBarPerMin ?? this.oxygenDecantRateBarPerMin,
      otherDecantRateBarPerMin:
          otherDecantRateBarPerMin ?? this.otherDecantRateBarPerMin,
      drainingRateBarPerMin:
          drainingRateBarPerMin ?? this.drainingRateBarPerMin,
      compressorInletFlowLPerMin:
          compressorInletFlowLPerMin ?? this.compressorInletFlowLPerMin,
      maxCompressorPressureBar:
          maxCompressorPressureBar ?? this.maxCompressorPressureBar,
      maxBoosterOutputPressureBar:
          maxBoosterOutputPressureBar ?? this.maxBoosterOutputPressureBar,
      boosterTemperatureModifierC:
          boosterTemperatureModifierC ?? this.boosterTemperatureModifierC,
      compressorTemperatureModifierC:
          compressorTemperatureModifierC ?? this.compressorTemperatureModifierC,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SettingsBooster &&
      other.minimumSourcePressureBar == minimumSourcePressureBar &&
      other.cylinderVolumeCm3 == cylinderVolumeCm3 &&
      other.oxygenBoostBpm == oxygenBoostBpm &&
      other.otherBoostBpm == otherBoostBpm &&
      other.oxygenDecantRateBarPerMin == oxygenDecantRateBarPerMin &&
      other.otherDecantRateBarPerMin == otherDecantRateBarPerMin &&
      other.drainingRateBarPerMin == drainingRateBarPerMin &&
      other.compressorInletFlowLPerMin == compressorInletFlowLPerMin &&
      other.maxCompressorPressureBar == maxCompressorPressureBar &&
      other.maxBoosterOutputPressureBar == maxBoosterOutputPressureBar &&
      other.boosterTemperatureModifierC == boosterTemperatureModifierC &&
      other.compressorTemperatureModifierC == compressorTemperatureModifierC;

  @override
  int get hashCode => Object.hash(
    minimumSourcePressureBar,
    cylinderVolumeCm3,
    oxygenBoostBpm,
    otherBoostBpm,
    oxygenDecantRateBarPerMin,
    otherDecantRateBarPerMin,
    drainingRateBarPerMin,
    compressorInletFlowLPerMin,
    maxCompressorPressureBar,
    maxBoosterOutputPressureBar,
    boosterTemperatureModifierC,
    compressorTemperatureModifierC,
  );
}

/// JS `settings.physics`.
class PhysicsSettings {
  const PhysicsSettings({required this.model});

  /// Either `ideal` or `vdw`.
  final String model;

  @override
  bool operator ==(Object other) =>
      other is PhysicsSettings && other.model == model;

  @override
  int get hashCode => model.hashCode;
}

/// Full settings object (JS `DEFAULT_SETTINGS` shape). The stored form and the
/// migrations are in `lib/src/data/settings_storage.dart`.
class Settings {
  const Settings({
    required this.units,
    required this.pressureLimitMode,
    required this.pressureWarningUnlocked,
    required this.interimPressureTolerancePercent,
    required this.costs,
    required this.physics,
    required this.gasPresets,
    required this.compressorPresets,
    required this.boosterPresets,
    required this.cylinderPresets,
    required this.booster,
  });

  /// Either `metric` or `imperial` (validated, not typed, to match JS).
  final String units;

  /// Either `hard-stop` or `warning` (validated, not typed, to match JS).
  final String pressureLimitMode;
  final bool pressureWarningUnlocked;
  final double interimPressureTolerancePercent;
  final Costs costs;
  final PhysicsSettings physics;
  final List<GasPreset> gasPresets;
  final List<CompressorPreset> compressorPresets;
  final List<BoosterPreset> boosterPresets;
  final List<CylinderPreset> cylinderPresets;
  final SettingsBooster booster;

  Settings copyWith({
    String? units,
    String? pressureLimitMode,
    bool? pressureWarningUnlocked,
    double? interimPressureTolerancePercent,
    Costs? costs,
    PhysicsSettings? physics,
    List<GasPreset>? gasPresets,
    List<CompressorPreset>? compressorPresets,
    List<BoosterPreset>? boosterPresets,
    List<CylinderPreset>? cylinderPresets,
    SettingsBooster? booster,
  }) {
    return Settings(
      units: units ?? this.units,
      pressureLimitMode: pressureLimitMode ?? this.pressureLimitMode,
      pressureWarningUnlocked:
          pressureWarningUnlocked ?? this.pressureWarningUnlocked,
      interimPressureTolerancePercent:
          interimPressureTolerancePercent ??
          this.interimPressureTolerancePercent,
      costs: costs ?? this.costs,
      physics: physics ?? this.physics,
      gasPresets: gasPresets ?? this.gasPresets,
      compressorPresets: compressorPresets ?? this.compressorPresets,
      boosterPresets: boosterPresets ?? this.boosterPresets,
      cylinderPresets: cylinderPresets ?? this.cylinderPresets,
      booster: booster ?? this.booster,
    );
  }
}

// ignore: constant_identifier_names
const Settings DEFAULT_SETTINGS = Settings(
  units: 'metric',
  pressureLimitMode: 'hard-stop',
  pressureWarningUnlocked: false,
  interimPressureTolerancePercent: 3,
  costs: Costs(
    currencySymbol: '',
    leftoverDiscountPercent: 0,
    operationPrices: OperationPrices(boost: 0, decant: 0, topUp: 0),
  ),
  physics: PhysicsSettings(model: 'vdw'),
  gasPresets: <GasPreset>[
    GasPreset(name: 'Air', oxygenPercent: 21, heliumPercent: 0),
    GasPreset(name: 'EAN 32', oxygenPercent: 32, heliumPercent: 0),
    GasPreset(name: 'EAN 50', oxygenPercent: 50, heliumPercent: 0),
    GasPreset(name: 'Oxygen', oxygenPercent: 100, heliumPercent: 0),
    GasPreset(name: 'Helium', oxygenPercent: 0, heliumPercent: 100),
    GasPreset(name: 'Tx 21/35', oxygenPercent: 21, heliumPercent: 35),
    GasPreset(name: 'Tx 18/45', oxygenPercent: 18, heliumPercent: 45),
    GasPreset(name: 'Tx 15/55', oxygenPercent: 15, heliumPercent: 55),
    GasPreset(name: 'Tx 12/65', oxygenPercent: 12, heliumPercent: 65),
    GasPreset(name: 'Tx 50/20', oxygenPercent: 50, heliumPercent: 20),
  ],
  compressorPresets: <CompressorPreset>[
    CompressorPreset(
      name: 'Bauer Junior 2 200bar',
      inletFlowLPerMin: 100,
      maxPressureBar: 232,
      temperatureModifierC: 5,
    ),
    CompressorPreset(
      name: 'Bauer Oceanus 300bar',
      inletFlowLPerMin: 140,
      maxPressureBar: 300,
      temperatureModifierC: 7,
    ),
    CompressorPreset(
      name: 'Bauer Junior 2 225 bar',
      inletFlowLPerMin: 100,
      maxPressureBar: 225,
      temperatureModifierC: 5,
    ),
    CompressorPreset(
      name: 'Bauer Junior 2 330 bar',
      inletFlowLPerMin: 100,
      maxPressureBar: 330,
      temperatureModifierC: 5,
    ),
    CompressorPreset(
      name: 'Bauer Oceanus 230 bar',
      inletFlowLPerMin: 140,
      maxPressureBar: 230,
      temperatureModifierC: 7,
    ),
    CompressorPreset(
      name: 'Coltri MCH 6 232 bar',
      inletFlowLPerMin: 100,
      maxPressureBar: 232,
      temperatureModifierC: 5,
    ),
    CompressorPreset(
      name: 'Coltri MCH 13 225 bar',
      inletFlowLPerMin: 235,
      maxPressureBar: 225,
      temperatureModifierC: 5,
    ),
    CompressorPreset(
      name: 'Coltri MCH 13 330 bar',
      inletFlowLPerMin: 235,
      maxPressureBar: 330,
      temperatureModifierC: 5,
    ),
  ],
  boosterPresets: <BoosterPreset>[
    BoosterPreset(
      name: 'MPS C1 Sport light',
      minimumSourcePressureBar: 5,
      cylinderVolumeCm3: 9,
      oxygenBoostBpm: 35,
      otherBoostBpm: 50,
      oxygenDecantRateBarPerMin: 5,
      otherDecantRateBarPerMin: 10,
      maxOutputPressureBar: 230,
      temperatureModifierC: 10,
      drainingRateBarPerMin: 15,
    ),
    BoosterPreset(
      name: 'Maximator ROB22',
      minimumSourcePressureBar: 50,
      cylinderVolumeCm3: 4.6,
      oxygenBoostBpm: 30,
      otherBoostBpm: 50,
      oxygenDecantRateBarPerMin: 5,
      otherDecantRateBarPerMin: 10,
      maxOutputPressureBar: 280,
      temperatureModifierC: 0,
      drainingRateBarPerMin: 15,
    ),
    BoosterPreset(
      name: 'Maximator ROB 32D',
      minimumSourcePressureBar: 50,
      cylinderVolumeCm3: 11.6,
      oxygenBoostBpm: 45,
      otherBoostBpm: 70,
      oxygenDecantRateBarPerMin: 6,
      otherDecantRateBarPerMin: 12,
      maxOutputPressureBar: 300,
      temperatureModifierC: 0,
      drainingRateBarPerMin: 15,
    ),
    BoosterPreset(
      name: 'Haskel AG-15',
      minimumSourcePressureBar: 3.5,
      cylinderVolumeCm3: 101.6,
      oxygenBoostBpm: 30,
      otherBoostBpm: 45,
      oxygenDecantRateBarPerMin: 5,
      otherDecantRateBarPerMin: 10,
      maxOutputPressureBar: 155,
      temperatureModifierC: 0,
      drainingRateBarPerMin: 15,
    ),
  ],
  cylinderPresets: <CylinderPreset>[
    CylinderPreset(
      name: 'Faber 3L',
      volumeL: 3,
      material: 'steel',
      massKg: 4.4,
      workingPressureBar: 232,
      hotOverfillPercent: DEFAULT_HOT_OVERFILL_PERCENT,
      diameterMm: 100.1,
      lengthMm: 495.3,
    ),
    CylinderPreset(
      name: 'Catalina S13',
      volumeL: 1.9,
      material: 'aluminum',
      massKg: 2.6,
      workingPressureBar: 207,
      hotOverfillPercent: DEFAULT_HOT_OVERFILL_PERCENT,
      diameterMm: 111.3,
      lengthMm: 325,
    ),
    CylinderPreset(
      name: 'Luxfer S40',
      volumeL: 5.7,
      material: 'aluminum',
      massKg: 7.2,
      workingPressureBar: 207,
      hotOverfillPercent: DEFAULT_HOT_OVERFILL_PERCENT,
      diameterMm: 133,
      lengthMm: 625,
    ),
    CylinderPreset(
      name: 'Luxfer S80',
      volumeL: 11.1,
      material: 'aluminum',
      massKg: 13.7,
      workingPressureBar: 217,
      hotOverfillPercent: DEFAULT_HOT_OVERFILL_PERCENT,
      diameterMm: 184,
      lengthMm: 662,
    ),
    CylinderPreset(
      name: 'Catalina S80',
      volumeL: 11.1,
      material: 'aluminum',
      massKg: 14.3,
      workingPressureBar: 207,
      hotOverfillPercent: DEFAULT_HOT_OVERFILL_PERCENT,
      diameterMm: 184.2,
      lengthMm: 658,
    ),
  ],
  booster: SettingsBooster(
    minimumSourcePressureBar: 5,
    cylinderVolumeCm3: 9,
    oxygenBoostBpm: 35,
    otherBoostBpm: 50,
    oxygenDecantRateBarPerMin: 5,
    otherDecantRateBarPerMin: 10,
    drainingRateBarPerMin: 15,
    compressorInletFlowLPerMin: 100,
    maxCompressorPressureBar: 232,
    maxBoosterOutputPressureBar: 230,
    boosterTemperatureModifierC: 10,
    compressorTemperatureModifierC: 5,
  ),
);

/// Mirrors JS `copySettings`: `units` falls back to `metric`, `costs` are
/// copied with a trimmed currency symbol, and every list is copied.
Settings copySettings(Settings settings) {
  return Settings(
    units: settings.units == 'imperial' ? 'imperial' : 'metric',
    pressureLimitMode: settings.pressureLimitMode,
    pressureWarningUnlocked: settings.pressureWarningUnlocked,
    interimPressureTolerancePercent: settings.interimPressureTolerancePercent,
    costs: _copyCosts(settings.costs),
    physics: PhysicsSettings(model: settings.physics.model),
    gasPresets: List<GasPreset>.unmodifiable(settings.gasPresets),
    compressorPresets: List<CompressorPreset>.unmodifiable(
      settings.compressorPresets,
    ),
    boosterPresets: List<BoosterPreset>.unmodifiable(settings.boosterPresets),
    cylinderPresets: List<CylinderPreset>.unmodifiable(
      settings.cylinderPresets,
    ),
    booster: settings.booster.copyWith(),
  );
}

Costs _copyCosts(Costs costs) {
  return Costs(
    currencySymbol: costs.currencySymbol.trim(),
    leftoverDiscountPercent: costs.leftoverDiscountPercent,
    operationPrices: costs.operationPrices,
  );
}

const List<String> _unitValues = <String>['metric', 'imperial'];
const List<String> _pressureModeValues = <String>['hard-stop', 'warning'];
const List<String> _gasModelValues = <String>['ideal', 'vdw'];

final RegExp _needsNamePattern = RegExp('needs a name');

bool _finiteIn(double value, num minimum, num maximum) {
  return value.isFinite && value >= minimum && value <= maximum;
}

/// Mirrors JS `validateSettings`: returns every user-facing error, in the JS
/// order, and an empty list when the settings are valid.
List<String> validateSettings(Settings settings) {
  final errors = <String>[];
  if (settings.gasPresets.isEmpty) {
    errors.add('At least one gas preset is required.');
  }
  if (!_unitValues.contains(settings.units)) {
    errors.add('Units must be either metric or imperial.');
  }
  if (!_pressureModeValues.contains(settings.pressureLimitMode)) {
    errors.add('Pressure limit mode must be either hard-stop or warning.');
  }
  if (settings.pressureLimitMode == 'warning' &&
      !settings.pressureWarningUnlocked) {
    errors.add('Pressure warning mode requires an unlock.');
  }
  if (!_finiteIn(settings.interimPressureTolerancePercent, 0.5, 10)) {
    errors.add('Interim pressure tolerance must be between 0.5 and 10%.');
  }
  if (settings.cylinderPresets.isEmpty) {
    errors.add('At least one cylinder preset is required.');
  }
  if (!_gasModelValues.contains(settings.physics.model)) {
    errors.add('Gas model must be either ideal or vdw.');
  }

  final booster = settings.booster;
  if (!_finiteIn(booster.minimumSourcePressureBar, 0, 100)) {
    errors.add(
      'Booster minimum source pressure must be between 0 and 100 bar.',
    );
  }
  if (!_finiteIn(booster.cylinderVolumeCm3, 0.1, 1000)) {
    errors.add('Booster cylinder volume must be between 0.1 and 1000 cm³.');
  }
  if (!_finiteIn(booster.oxygenBoostBpm, 1, 1000)) {
    errors.add('Oxygen booster speed must be between 1 and 1000 BPM.');
  }
  if (!_finiteIn(booster.otherBoostBpm, 1, 1000)) {
    errors.add('Other-gas booster speed must be between 1 and 1000 BPM.');
  }
  if (!_finiteIn(booster.oxygenDecantRateBarPerMin, 0.01, 1000)) {
    errors.add(
      'Oxygen manual decant rate must be between 0.01 and 1000 bar/min.',
    );
  }
  if (!_finiteIn(booster.otherDecantRateBarPerMin, 0.01, 1000)) {
    errors.add(
      'Other-gas manual decant rate must be between 0.01 and 1000 bar/min.',
    );
  }
  if (!_finiteIn(booster.drainingRateBarPerMin, 0.01, 1000)) {
    errors.add('Draining rate must be between 0.01 and 1000 bar/min.');
  }
  if (!_finiteIn(booster.compressorInletFlowLPerMin, 0.1, 10000)) {
    errors.add('Compressor inlet flow must be between 0.1 and 10000 L/min.');
  }
  if (!_finiteIn(booster.maxCompressorPressureBar, 10, 350)) {
    errors.add('Maximum compressor pressure must be between 10 and 350 bar.');
  }
  if (!_finiteIn(booster.maxBoosterOutputPressureBar, 10, 350)) {
    errors.add(
      'Maximum booster output pressure must be between 10 and 350 bar.',
    );
  }
  if (!_finiteIn(booster.boosterTemperatureModifierC, -100, 100)) {
    errors.add('Booster temperature modifier must be between -100 and 100°C.');
  }
  if (!_finiteIn(booster.compressorTemperatureModifierC, -100, 100)) {
    errors.add(
      'Compressor temperature modifier must be between -100 and 100°C.',
    );
  }

  errors.addAll(
    _validatePresetCollection(
      settings.compressorPresets
          .map((preset) => preset.toJson())
          .toList(growable: false),
      'compressor',
      validateCompressorPreset,
    ),
  );
  errors.addAll(
    _validatePresetCollection(
      settings.boosterPresets
          .map((preset) => preset.toJson())
          .toList(growable: false),
      'booster',
      validateBoosterPreset,
    ),
  );
  errors.addAll(
    _namedPresetErrors(
      settings.gasPresets
          .map((preset) => preset.toJson())
          .toList(growable: false),
      'gas',
      validateGasPreset,
    ),
  );
  errors.addAll(
    _namedPresetErrors(
      settings.cylinderPresets
          .map((preset) => preset.toJson())
          .toList(growable: false),
      'cylinder',
      validateCylinderPreset,
    ),
  );
  errors.addAll(validateCostSettings(_costsToJson(settings.costs)));
  return errors;
}

Map<String, Object?> _costsToJson(Costs costs) => <String, Object?>{
  'currencySymbol': costs.currencySymbol,
  'leftoverDiscountPercent': costs.leftoverDiscountPercent,
  'operationPrices': <String, Object?>{
    'boost': costs.operationPrices.boost,
    'decant': costs.operationPrices.decant,
    'topUp': costs.operationPrices.topUp,
  },
};

/// Mirrors JS `validatePresetCollection`: a non-empty list is required, then
/// the per-preset checks of [_namedPresetErrors] run.
List<String> _validatePresetCollection(
  List<Map<String, Object?>> presets,
  String category,
  PresetValidator validator,
) {
  if (presets.isEmpty) {
    return <String>['At least one $category preset is required.'];
  }
  return _namedPresetErrors(presets, category, validator);
}

/// Per-preset checks shared by every collection: a blank or non-string name
/// keeps only the validator's "needs a name" errors; a duplicate normalized
/// name adds the uniqueness error; then the validator's errors are added.
List<String> _namedPresetErrors(
  List<Map<String, Object?>> presets,
  String category,
  PresetValidator validator,
) {
  final errors = <String>[];
  final names = <String>{};
  final heading = '${category[0].toUpperCase()}${category.substring(1)}';
  for (final preset in presets) {
    final presetErrors = validator(preset);
    final name = preset['name'];
    if (name is! String || name.trim().isEmpty) {
      errors.addAll(presetErrors.where(_needsNamePattern.hasMatch));
      continue;
    }
    final normalizedName = normalizePresetName(name);
    if (names.contains(normalizedName)) {
      errors.add('$heading preset names must be unique.');
    }
    names.add(normalizedName);
    errors.addAll(presetErrors);
  }
  return errors;
}

CompressorPreset createCompressorPreset(Settings settings, String name) {
  return CompressorPreset(
    name: name,
    inletFlowLPerMin: settings.booster.compressorInletFlowLPerMin,
    maxPressureBar: settings.booster.maxCompressorPressureBar,
    temperatureModifierC: settings.booster.compressorTemperatureModifierC,
  );
}

BoosterPreset createBoosterPreset(Settings settings, String name) {
  return BoosterPreset(
    name: name,
    minimumSourcePressureBar: settings.booster.minimumSourcePressureBar,
    cylinderVolumeCm3: settings.booster.cylinderVolumeCm3,
    oxygenBoostBpm: settings.booster.oxygenBoostBpm,
    otherBoostBpm: settings.booster.otherBoostBpm,
    oxygenDecantRateBarPerMin: settings.booster.oxygenDecantRateBarPerMin,
    otherDecantRateBarPerMin: settings.booster.otherDecantRateBarPerMin,
    maxOutputPressureBar: settings.booster.maxBoosterOutputPressureBar,
    temperatureModifierC: settings.booster.boosterTemperatureModifierC,
    drainingRateBarPerMin: settings.booster.drainingRateBarPerMin,
  );
}

/// Copies [settings] and sets only the compressor fields from [preset].
Settings applyCompressorPresetToSettings(
  Settings settings,
  CompressorPreset preset,
) {
  final copied = copySettings(settings);
  return copied.copyWith(
    booster: copied.booster.copyWith(
      compressorInletFlowLPerMin: preset.inletFlowLPerMin,
      maxCompressorPressureBar: preset.maxPressureBar,
      compressorTemperatureModifierC: preset.temperatureModifierC,
    ),
  );
}

/// Copies [settings] and sets only the booster fields from [preset].
Settings applyBoosterPresetToSettings(Settings settings, BoosterPreset preset) {
  final copied = copySettings(settings);
  return copied.copyWith(
    booster: copied.booster.copyWith(
      minimumSourcePressureBar: preset.minimumSourcePressureBar,
      cylinderVolumeCm3: preset.cylinderVolumeCm3,
      oxygenBoostBpm: preset.oxygenBoostBpm,
      otherBoostBpm: preset.otherBoostBpm,
      oxygenDecantRateBarPerMin: preset.oxygenDecantRateBarPerMin,
      otherDecantRateBarPerMin: preset.otherDecantRateBarPerMin,
      maxBoosterOutputPressureBar: preset.maxOutputPressureBar,
      boosterTemperatureModifierC: preset.temperatureModifierC,
      drainingRateBarPerMin: preset.drainingRateBarPerMin,
    ),
  );
}

/// Mirrors JS `createUniquePresetName`: appends ` 2`, ` 3`, ... to [baseName]
/// until its normalized form is not among [presetNames].
String createUniquePresetName(String baseName, Iterable<String> presetNames) {
  final names = <String>{
    for (final name in presetNames) normalizePresetName(name),
  };
  var name = baseName;
  var suffix = 2;
  while (names.contains(normalizePresetName(name))) {
    name = '$baseName ${suffix++}';
  }
  return name;
}

/// Mirrors JS `addEquipmentPresetToDraft` without mutation: returns the draft
/// with one new active-setting preset appended to [category], and its name.
({Settings settings, String name}) addEquipmentPresetToDraft(
  Settings draft,
  EquipmentCategory category,
  String baseName,
) {
  if (category == EquipmentCategory.compressor) {
    final name = createUniquePresetName(
      baseName,
      draft.compressorPresets.map((preset) => preset.name),
    );
    return (
      settings: draft.copyWith(
        compressorPresets: List<CompressorPreset>.unmodifiable(
          <CompressorPreset>[
            ...draft.compressorPresets,
            createCompressorPreset(draft, name),
          ],
        ),
      ),
      name: name,
    );
  }
  final name = createUniquePresetName(
    baseName,
    draft.boosterPresets.map((preset) => preset.name),
  );
  return (
    settings: draft.copyWith(
      boosterPresets: List<BoosterPreset>.unmodifiable(<BoosterPreset>[
        ...draft.boosterPresets,
        createBoosterPreset(draft, name),
      ]),
    ),
    name: name,
  );
}

/// Mirrors JS `selectEquipmentPreset`: applies the first preset in [category]
/// whose exact name is [presetName], or returns null when none matches.
Settings? selectEquipmentPreset(
  Settings settings,
  EquipmentCategory category,
  String presetName,
) {
  if (category == EquipmentCategory.compressor) {
    for (final preset in settings.compressorPresets) {
      if (preset.name == presetName) {
        return applyCompressorPresetToSettings(settings, preset);
      }
    }
    return null;
  }
  for (final preset in settings.boosterPresets) {
    if (preset.name == presetName) {
      return applyBoosterPresetToSettings(settings, preset);
    }
  }
  return null;
}

/// Mirrors JS `applyGasPresetToBank`: only name and gas composition change.
Bank applyGasPresetToBank(Bank bank, GasPreset preset) {
  return bank.copyWith(
    name: preset.name,
    oxygenPercent: preset.oxygenPercent,
    heliumPercent: preset.heliumPercent,
  );
}

/// Mirrors JS `getSelectedGasPreset`. Composition comparison uses a 1e-9
/// tolerance on both percentages. The link is read from [Bank.gasPresetLink].
GasPreset? getSelectedGasPreset(Bank bank, List<GasPreset> gasPresets) {
  bool matchesComposition(GasPreset preset) {
    return (preset.oxygenPercent - bank.oxygenPercent).abs() < 1e-9 &&
        (preset.heliumPercent - bank.heliumPercent).abs() < 1e-9;
  }

  return switch (bank.gasPresetLink) {
    CustomMixLink() => null,
    UnnamedPresetLink() => _firstWhereOrNull(gasPresets, matchesComposition),
    NamedPresetLink(:final name) => _firstWhereOrNull(
      gasPresets,
      (preset) => preset.name == name && matchesComposition(preset),
    ),
  };
}

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) {
      return item;
    }
  }
  return null;
}

/// An item of a sorted preset list plus its position in the original list.
typedef PresetEntry<T> = ({T preset, int index});

/// Numeric comparison that treats `NaN` as a tie, like JS `a - b || ...`.
int _compareKeys(double left, double right) {
  if (left < right) {
    return -1;
  }
  if (left > right) {
    return 1;
  }
  return 0;
}

List<PresetEntry<T>> _sortPresetEntries<T>(
  List<T> presets,
  double Function(T) keyOf,
) {
  final entries = <PresetEntry<T>>[
    for (var index = 0; index < presets.length; index++)
      (preset: presets[index], index: index),
  ];
  entries.sort((left, right) {
    final byKey = _compareKeys(keyOf(left.preset), keyOf(right.preset));
    if (byKey != 0) {
      return byKey;
    }
    return left.index.compareTo(right.index);
  });
  return entries;
}

/// Mirrors JS `sortGasPresetEntries`: by helium percent, ties keep list order.
List<PresetEntry<GasPreset>> sortGasPresetEntries(List<GasPreset> presets) {
  return _sortPresetEntries(presets, (preset) => preset.heliumPercent);
}

/// Mirrors JS `sortCylinderPresetEntries`: by volume, ties keep list order.
List<PresetEntry<CylinderPreset>> sortCylinderPresetEntries(
  List<CylinderPreset> presets,
) {
  return _sortPresetEntries(presets, (preset) => preset.volumeL);
}

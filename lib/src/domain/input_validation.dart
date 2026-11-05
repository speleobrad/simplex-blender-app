/// Port of `js/input-validation.js`.
///
/// Calculator inputs are typed; JS `undefined` and `null` both map to Dart
/// `null` (absent). Cost settings, supply banks, and presets arrive as decoded
/// JSON, so they are checked at runtime with `Object?`.
library;

import 'package:simplex_blender/src/domain/gas_input.dart';
import 'package:simplex_blender/src/domain/js_number.dart';
import 'package:simplex_blender/src/domain/materials.dart';
import 'package:simplex_blender/src/domain/pressure_limits.dart';
import 'package:simplex_blender/src/domain/preset_validation.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

const double _maxCostPrice = 1000000;

/// Calculator cylinder fields read by validation.
class CalculatorCylinder {
  const CalculatorCylinder({
    this.volumeL,
    this.initialPressureBar,
    this.targetPressureBar,
    this.workingPressureBar,
    this.hotOverfillPercent,
  });

  final double? volumeL;
  final double? initialPressureBar;
  final double? targetPressureBar;
  final double? workingPressureBar;
  final double? hotOverfillPercent;

  CalculatorCylinder copyWith({
    double? volumeL,
    double? initialPressureBar,
    double? targetPressureBar,
    double? workingPressureBar,
    double? hotOverfillPercent,
  }) {
    return CalculatorCylinder(
      volumeL: volumeL ?? this.volumeL,
      initialPressureBar: initialPressureBar ?? this.initialPressureBar,
      targetPressureBar: targetPressureBar ?? this.targetPressureBar,
      workingPressureBar: workingPressureBar ?? this.workingPressureBar,
      hotOverfillPercent: hotOverfillPercent ?? this.hotOverfillPercent,
    );
  }
}

/// Calculator physics fields read by validation.
class CalculatorPhysics {
  const CalculatorPhysics({this.temperatureC});

  final double? temperatureC;

  CalculatorPhysics copyWith({double? temperatureC}) {
    return CalculatorPhysics(temperatureC: temperatureC ?? this.temperatureC);
  }
}

/// Calculator thermal fields read by validation.
class CalculatorThermal {
  const CalculatorThermal({
    this.ambientTemperatureC,
    this.tankMaterial,
    this.coolingMedium,
    this.waterSubmersionPercent,
    this.inletTemperatureC,
    this.targetMediumTemperatureC,
    this.targetTemperatureC,
    this.targetInWaterTemperatureC,
    this.settledTemperatureC,
    this.waitMode,
    this.waitMinutes,
    this.interimMeasurements,
  });

  final double? ambientTemperatureC;
  final String? tankMaterial;
  final String? coolingMedium;
  final double? waterSubmersionPercent;
  final double? inletTemperatureC;
  final double? targetMediumTemperatureC;
  final double? targetTemperatureC;
  final double? targetInWaterTemperatureC;
  final double? settledTemperatureC;
  final String? waitMode;
  final double? waitMinutes;
  final List<InterimMeasurement?>? interimMeasurements;

  CalculatorThermal copyWith({
    double? ambientTemperatureC,
    String? tankMaterial,
    String? coolingMedium,
    double? waterSubmersionPercent,
    double? inletTemperatureC,
    double? targetMediumTemperatureC,
    double? targetTemperatureC,
    double? targetInWaterTemperatureC,
    double? settledTemperatureC,
    String? waitMode,
    double? waitMinutes,
    List<InterimMeasurement?>? interimMeasurements,
  }) {
    return CalculatorThermal(
      ambientTemperatureC: ambientTemperatureC ?? this.ambientTemperatureC,
      tankMaterial: tankMaterial ?? this.tankMaterial,
      coolingMedium: coolingMedium ?? this.coolingMedium,
      waterSubmersionPercent:
          waterSubmersionPercent ?? this.waterSubmersionPercent,
      inletTemperatureC: inletTemperatureC ?? this.inletTemperatureC,
      targetMediumTemperatureC:
          targetMediumTemperatureC ?? this.targetMediumTemperatureC,
      targetTemperatureC: targetTemperatureC ?? this.targetTemperatureC,
      targetInWaterTemperatureC:
          targetInWaterTemperatureC ?? this.targetInWaterTemperatureC,
      settledTemperatureC: settledTemperatureC ?? this.settledTemperatureC,
      waitMode: waitMode ?? this.waitMode,
      waitMinutes: waitMinutes ?? this.waitMinutes,
      interimMeasurements: interimMeasurements ?? this.interimMeasurements,
    );
  }
}

/// `Number.isFinite` on a decoded JSON value: only `num` qualifies.
double? _num(Object? value) => value is num ? value.toDouble() : null;

Map<String, Object?>? _asMap(Object? value) =>
    value is Map<String, Object?> ? value : null;

/// True when the value is a finite number within `[minimum, maximum]`.
bool _finiteIn(double? value, num minimum, num maximum) {
  return value != null &&
      value.isFinite &&
      value >= minimum &&
      value <= maximum;
}

bool _priceOk(Object? value) => _finiteIn(_num(value), 0, _maxCostPrice);

CylinderPressureSpec _pressureSpec(CalculatorCylinder cylinder) {
  return CylinderPressureSpec(
    workingPressureBar: cylinder.workingPressureBar,
    hotOverfillPercent: cylinder.hotOverfillPercent,
  );
}

List<String> validateCostSettings(Object? costs) {
  final map = _asMap(costs);
  if (map == null) return <String>['Cost settings are missing.'];
  final errors = <String>[];
  final currencySymbol = map['currencySymbol'];
  if (currencySymbol is! String || currencySymbol.trim().length > 8) {
    errors.add('Currency symbol must be text of at most 8 characters.');
  }
  final operationPrices = _asMap(map['operationPrices']);
  final fees = <Object?>[
    operationPrices?['boost'],
    operationPrices?['decant'],
    operationPrices?['topUp'],
  ];
  if (!fees.every(_priceOk)) {
    errors.add('Prices must be numbers from 0 to 1,000,000.');
  }
  if (!_finiteIn(_num(map['leftoverDiscountPercent']), 0, 100)) {
    errors.add('Leftover discount must be between 0 and 100%.');
  }
  return errors;
}

List<String> validateCalculatorInputs(
  CalculatorCylinder? cylinder,
  CalculatorPhysics? physics,
  CalculatorThermal? thermal, {
  String? pressureLimitMode,
}) {
  final mode = pressureLimitMode ?? 'hard-stop';
  final errors = <String>[];
  final cyl = cylinder;

  final volume = cyl?.volumeL;
  if (volume == null || !volume.isFinite || volume < 0.1) {
    errors.add('Cylinder capacity must be at least 0.1 L.');
  }
  if (!_finiteIn(cyl?.initialPressureBar, 0, 350)) {
    errors.add('Initial pressure must be between 0 and 350 bar.');
  }
  if (!_finiteIn(cyl?.targetPressureBar, 10, 350)) {
    errors.add('Target pressure must be between 10 and 350 bar.');
  }
  final working = cyl?.workingPressureBar;
  if (cyl != null && working != null) {
    if (!working.isFinite || working < 10 || working > 350) {
      errors.add('Cylinder working pressure must be between 10 and 350 bar.');
    } else {
      final initialExceedance = getCylinderPressureExceedance(
        pressureBar: cyl.initialPressureBar,
        cylinder: _pressureSpec(cyl),
        toleranceBar: 0,
      );
      if (mode != 'warning' && initialExceedance != null) {
        errors.add(
          'Initial pressure cannot exceed the selected cylinder working pressure of ${jsNumberString(initialExceedance.limitBar)} bar.',
        );
      }
      final targetExceedance = getCylinderPressureExceedance(
        pressureBar: cyl.targetPressureBar,
        cylinder: _pressureSpec(cyl),
        toleranceBar: 0,
      );
      if (mode != 'warning' && targetExceedance != null) {
        errors.add(
          'Target pressure cannot exceed the selected cylinder working pressure of ${jsNumberString(targetExceedance.limitBar)} bar.',
        );
      }
    }
  }
  final hotOverfill = cyl?.hotOverfillPercent;
  if (hotOverfill != null && !isValidHotOverfillPercent(hotOverfill)) {
    errors.add('Cylinder hot overfill must be between 0 and 5% in 0.5% steps.');
  }
  if (!_finiteIn(physics?.temperatureC, 5, 40)) {
    errors.add('Temperature must be between 5 and 40°C.');
  }
  if (thermal == null) return errors;

  if (!isValidMaterial(thermal.tankMaterial)) {
    errors.add('Thermal tank material must be ${materialListText()}.');
  }
  final coolingMedium = thermal.coolingMedium;
  if (coolingMedium != 'air' && coolingMedium != 'water') {
    errors.add('Thermal cooling medium must be air or water.');
  }
  final waitMode = thermal.waitMode;
  final waitMinutes = thermal.waitMinutes;
  if (waitMode != null && waitMode != 'minutes' && waitMode != 'temperature') {
    errors.add('Thermal wait mode must be minutes or temperature.');
  } else if (waitMode != 'temperature' &&
      waitMinutes != null &&
      !_finiteIn(waitMinutes, 0, 1440)) {
    errors.add('Thermal wait must be between 0 and 1440 minutes.');
  }
  final submersion = thermal.waterSubmersionPercent;
  if (coolingMedium == 'water' &&
      submersion != null &&
      !waterSubmersionPercentOptions.contains(submersion)) {
    errors.add('Thermal water submersion must be 20, 40, 60, or 80%.');
  }

  final legacy =
      thermal.targetInWaterTemperatureC == null &&
      thermal.targetMediumTemperatureC == null;
  final ambient = thermal.ambientTemperatureC;
  final targetMedium =
      thermal.targetMediumTemperatureC ?? thermal.targetTemperatureC;
  final targetInWater =
      thermal.targetInWaterTemperatureC ??
      thermal.settledTemperatureC ??
      (legacy ? ambient : null);
  if (!_finiteIn(ambient, 5, 40)) {
    errors.add('Thermal ambient temperature must be between 5 and 40°C.');
  }
  final inlet = thermal.inletTemperatureC ?? (legacy ? ambient : null);
  if (!_finiteIn(inlet, 5, 40)) {
    errors.add('Thermal inlet gas temperature must be between 5 and 40°C.');
  }
  if (!_finiteIn(targetMedium, 5, 40)) {
    errors.add('Thermal target-medium temperature must be between 5 and 40°C.');
  } else if (ambient != null && ambient.isFinite && targetMedium! < ambient) {
    errors.add(
      'Thermal target-medium temperature cannot be below ambient temperature.',
    );
  }
  if (!_finiteIn(targetInWater, 1, 30)) {
    errors.add(
      'Thermal target in-water temperature must be between 1 and 30°C.',
    );
  }

  final readings = thermal.interimMeasurements;
  if (readings != null) {
    for (final measurement in readings) {
      if (measurement == null) continue;
      final pressure = measurement.pressureBar;
      final temperature = measurement.temperatureC;
      if (!_finiteIn(pressure, 0, 350)) {
        errors.add('Measured pressure must be between 0 and 350 bar.');
      } else if (working != null && working.isFinite) {
        final isTransientHot =
            ambient != null &&
            ambient.isFinite &&
            temperature != null &&
            temperature.isFinite &&
            temperature > ambient;
        final diagnosticOverfill =
            isTransientHot && !isValidHotOverfillPercent(hotOverfill)
            ? DEFAULT_HOT_OVERFILL_PERCENT
            : hotOverfill;
        final exceedance = getCylinderPressureExceedance(
          pressureBar: pressure,
          cylinder: CylinderPressureSpec(
            workingPressureBar: working,
            hotOverfillPercent: diagnosticOverfill,
          ),
          isTransientHot: isTransientHot,
          toleranceBar: 0,
        );
        if (mode != 'warning' && exceedance != null) {
          errors.add(
            exceedance.kind == hotOverfillKind
                ? 'Measured pressure cannot exceed the selected cylinder hot overfill limit of ${jsNumberString(exceedance.limitBar)} bar.'
                : 'Measured pressure cannot exceed the selected cylinder working pressure of ${jsNumberString(exceedance.limitBar)} bar.',
          );
        }
      }
      if (!_finiteIn(temperature, -20, 100)) {
        errors.add('Measured temperature must be between -20 and 100°C.');
      }
    }
  }

  return errors;
}

List<String> validateSupplyBankInput(Object? bank) {
  final map = _asMap(bank);
  if (map == null) return <String>['Supply bank is invalid.'];
  final id = map['id'];
  if (id is! String || id.isEmpty) {
    return <String>['Supply bank ID must be non-empty text.'];
  }
  final name = map['name'];
  final enabled = map['enabled'];
  if (name is! String || name.trim().isEmpty || enabled is! bool) {
    return <String>[
      'Supply bank names must be non-empty text and enabled states must be boolean.',
    ];
  }
  final oxygen = _num(map['oxygenPercent']);
  final helium = _num(map['heliumPercent']);
  if (oxygen == 21 && helium == 0) {
    return <String>[
      'Air is supplied by the implicit compressor and cannot be a finite supply bank.',
    ];
  }

  final volume = _num(map['volumeL']);
  final pressure = _num(map['pressureBar']);
  for (final (value, minimum, maximum) in <(double?, num, num)>[
    (volume, 1, 200),
    (pressure, 1, 350),
  ]) {
    if (value == null || !value.isFinite) {
      return <String>['Supply bank values must be finite numbers.'];
    }
    if (value < minimum || value > maximum) {
      return <String>[
        'Supply bank volume must be 1–200 L; pressure 1–350 bar.',
      ];
    }
  }
  final maxPressure = _num(map['maxPressureBar']);
  if (maxPressure == null ||
      !maxPressure.isFinite ||
      maxPressure < 1 ||
      maxPressure > 350 ||
      maxPressure < pressure!) {
    return <String>[
      'Supply bank maximum pressure must be 1–350 bar and at least the current pressure.',
    ];
  }
  if (!isValidGasComposition(oxygen, helium)) {
    return <String>['$name gas composition must total at most 100% O₂ and He.'];
  }
  final gasPresetName = map['gasPresetName'];
  if (gasPresetName != null && gasPresetName is! String) {
    return <String>['Supply bank preset names must be text.'];
  }
  final price = map['pricePerLitre'];
  if (price != null && !_priceOk(price)) {
    return <String>['Supply bank price must be a number from 0 to 1,000,000.'];
  }
  return <String>[];
}

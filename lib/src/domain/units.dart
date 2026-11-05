import 'package:simplex_blender/src/domain/materials.dart';

const String metricUnits = 'metric';
const String imperialUnits = 'imperial';

const double _litresPerCubicFoot = 28.316846592;
const double _psiPerBar = 14.5037738;
const double _poundsPerKilogram = 2.20462262185;
const double _cubicInchesPerCubicCentimetre = 0.0610237441;

typedef _Convert = double Function(double value);

double _identity(double value) => value;

class _UnitVariant {
  const _UnitVariant(this.label, this.toDisplay, this.fromDisplay);

  final String label;
  final _Convert toDisplay;
  final _Convert fromDisplay;
}

final Map<String, Map<String, _UnitVariant>> _unitDefinitions = {
  'pressureBar': {
    metricUnits: _UnitVariant('bar', _identity, _identity),
    imperialUnits: _UnitVariant(
      'psi',
      (value) => value * _psiPerBar,
      (value) => value / _psiPerBar,
    ),
  },
  'pressureBarPerMin': {
    metricUnits: _UnitVariant('bar/min', _identity, _identity),
    imperialUnits: _UnitVariant(
      'psi/min',
      (value) => value * _psiPerBar,
      (value) => value / _psiPerBar,
    ),
  },
  'volumeL': {
    metricUnits: _UnitVariant('L', _identity, _identity),
    imperialUnits: _UnitVariant(
      'cu ft',
      (value) => value / _litresPerCubicFoot,
      (value) => value * _litresPerCubicFoot,
    ),
  },
  'pricePerVolumeL': {
    metricUnits: _UnitVariant('/L', _identity, _identity),
    imperialUnits: _UnitVariant(
      '/cu ft',
      (value) => value * _litresPerCubicFoot,
      (value) => value / _litresPerCubicFoot,
    ),
  },
  'massKg': {
    metricUnits: _UnitVariant('kg', _identity, _identity),
    imperialUnits: _UnitVariant(
      'lb',
      (value) => value * _poundsPerKilogram,
      (value) => value / _poundsPerKilogram,
    ),
  },
  'temperatureC': {
    metricUnits: _UnitVariant('°C', _identity, _identity),
    imperialUnits: _UnitVariant(
      '°F',
      (value) => value * 9 / 5 + 32,
      (value) => (value - 32) * 5 / 9,
    ),
  },
  'temperatureDeltaC': {
    metricUnits: _UnitVariant('°C', _identity, _identity),
    imperialUnits: _UnitVariant(
      '°F',
      (value) => value * 9 / 5,
      (value) => value * 5 / 9,
    ),
  },
  'flowLPerMin': {
    metricUnits: _UnitVariant('L/min', _identity, _identity),
    imperialUnits: _UnitVariant(
      'cu ft/min',
      (value) => value / _litresPerCubicFoot,
      (value) => value * _litresPerCubicFoot,
    ),
  },
  'volumeCm3': {
    metricUnits: _UnitVariant('cm³', _identity, _identity),
    imperialUnits: _UnitVariant(
      'in³',
      (value) => value * _cubicInchesPerCubicCentimetre,
      (value) => value / _cubicInchesPerCubicCentimetre,
    ),
  },
};

const Map<String, String> _quantityAliases = {
  'pressure': 'pressureBar',
  'volume': 'volumeL',
  'mass': 'massKg',
  'temperature': 'temperatureC',
  'flow': 'flowLPerMin',
  'volumeCm': 'volumeCm3',
};

String _canonicalQuantity(String quantity) =>
    _quantityAliases[quantity] ?? quantity;

String normalizeUnits(String? units) =>
    units == imperialUnits ? imperialUnits : metricUnits;

_UnitVariant? _variant(String quantity, String? units) =>
    _unitDefinitions[_canonicalQuantity(quantity)]?[normalizeUnits(units)];

String unitLabel(String quantity, String? units) =>
    _variant(quantity, units)?.label ?? '';

String materialLabel(String material, String? units) {
  final definition = materials[material];
  if (definition == null) return material;
  final imperialLabel = definition.labelImperial;
  if (units == imperialUnits && imperialLabel != null) return imperialLabel;
  return definition.label;
}

/// JS alias of [unitLabel].
String getUnitLabel(String quantity, String? units) =>
    unitLabel(quantity, units);

double convertToDisplay(double value, String quantity, String? units) =>
    _variant(quantity, units)?.toDisplay(value) ?? value;

double convertFromDisplay(double value, String quantity, String? units) =>
    _variant(quantity, units)?.fromDisplay(value) ?? value;

String formatUnitValue(
  double value,
  String quantity,
  String? units, [
  int digits = 1,
]) {
  return '${convertToDisplay(value, quantity, units).toStringAsFixed(digits)} '
      '${unitLabel(quantity, units)}';
}

double displayStep(double value, String quantity, String? units) =>
    convertToDisplay(value, quantity, units);

String formatInputValue(
  double value,
  String quantity,
  String? units, [
  int? digitsOverride,
]) {
  final normalizedUnits = normalizeUnits(units);
  final digits =
      digitsOverride ??
      (quantity == 'pressureBar' && normalizedUnits == imperialUnits
          ? 1
          : quantity == 'temperatureC'
          ? 1
          : 0);
  return convertToDisplay(
    value,
    quantity,
    normalizedUnits,
  ).toStringAsFixed(digits);
}

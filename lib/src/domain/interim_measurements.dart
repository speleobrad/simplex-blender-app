import 'dart:convert';

import 'thermodynamics.dart';

/// Calculator input as a JSON-shaped map (JS plain object). Values must be
/// JSON-encodable; a key whose value is removed is JS `undefined`.
typedef CalculatorInput = Map<String, Object?>;

Map<String, Object?> _copyWithout(
  Map<String, Object?> source,
  List<String> keys,
) {
  final copy = Map<String, Object?>.of(source);
  for (final key in keys) {
    copy.remove(key);
  }
  return copy;
}

// Mirrors JS `withoutBankPrices` for JSON-shaped banks. The typed
// `withoutBankPrices` in cost.dart works on `Bank` objects and cannot apply here.
Object? _withoutBankPrices(Object? banks) {
  if (banks is! List<Object?>) {
    return banks;
  }
  return [
    for (final bank in banks)
      bank is Map<String, Object?> && bank.containsKey('pricePerLitre')
          ? _copyWithout(bank, const ['pricePerLitre'])
          : bank,
  ];
}

// Cost prices and display units (settings.costs, bank pricePerLitre, settings.units) never change a plan,
// so they are excluded: editing them keeps interim readings.
String calculatorInputSignature(CalculatorInput input) {
  final result = Map<String, Object?>.of(input);
  final thermal = input['thermal'];
  if (thermal is Map<String, Object?>) {
    result['thermal'] = _copyWithout(thermal, const ['interimMeasurements']);
  }
  final settings = input['settings'];
  if (settings is Map<String, Object?>) {
    result['settings'] = _copyWithout(settings, const ['costs', 'units']);
  }
  if (input.containsKey('banks')) {
    result['banks'] = _withoutBankPrices(input['banks']);
  }
  return jsonEncode(result);
}

String? signatureAfterClearingMeasurement(CalculatorInput input, int index) {
  final thermal = input['thermal'];
  final measurements = thermal is Map<String, Object?>
      ? thermal['interimMeasurements']
      : null;
  if (measurements is! List<Object?>) {
    return null;
  }
  var hasRemainingMeasurement = false;
  for (
    var measurementIndex = 0;
    measurementIndex < measurements.length;
    measurementIndex++
  ) {
    if (measurementIndex != index && measurements[measurementIndex] != null) {
      hasRemainingMeasurement = true;
      break;
    }
  }
  return hasRemainingMeasurement ? calculatorInputSignature(input) : null;
}

int latestInterimMeasurementIndex(List<InterimMeasurement?>? measurements) {
  if (measurements == null) {
    return -1;
  }
  for (var index = measurements.length - 1; index >= 0; index -= 1) {
    if (measurements[index] != null) {
      return index;
    }
  }
  return -1;
}

// Earlier readings are locked. Only the latest reading may be replaced or cleared,
// and a new reading may only be recorded at or after the latest one.
String? interimMeasurementLockMessage(
  List<InterimMeasurement?>? measurements,
  int index,
  String action,
) {
  final latest = latestInterimMeasurementIndex(measurements);
  final allowed = action == 'clear' ? index == latest : index >= latest;
  if (allowed) {
    return null;
  }
  return 'Step ${index + 1} is locked. Only the latest reading (step ${latest + 1}) can be changed or cleared.';
}

final RegExp _stepTitlePattern = RegExp(
  r'^Step[ ]+([0-9]+)',
  caseSensitive: false,
);

// The "Step N" number shown for a protocol step: the number in its plan title, else
// the fallback index + 1. Shared so the results panel and the reading check agree.
int protocolStepNumber(ProtocolStep? step, int fallbackIndex) {
  final match = _stepTitlePattern.firstMatch(step?.title ?? '');
  return match != null ? int.parse(match.group(1)!) : fallbackIndex + 1;
}

bool interimPressureWithinTolerance({
  required double measuredBar,
  required double plannedBar,
  required double tolerancePercent,
}) {
  return (measuredBar - plannedBar).abs() <=
      (tolerancePercent / 100) * plannedBar;
}

// Gas can only sit below ambient after a pressure-lowering transfer out of the working
// tank: a drain, or a salvage decant or booster. Waits and keeps carry that state
// forward; any other step (boost, decant, top-up, equalize) clears it.
// ignore: constant_identifier_names
const COOLING_RATE_SOURCES = {
  'draining-rate',
  'salvage-decant',
  'salvage-booster',
};

bool gasCanBeBelowAmbient(List<ProtocolStep?> protocolSteps, int stepIndex) {
  var belowAmbient = false;
  for (final step in protocolSteps.take(stepIndex)) {
    final rateSource = step?.thermal?.rateSource;
    if (rateSource != null && COOLING_RATE_SOURCES.contains(rateSource)) {
      belowAmbient = true;
    } else if (step?.type == 'wait' ||
        step?.type == 'keep' ||
        (step?.type == 'drain' && rateSource == 'none')) {
      continue;
    } else {
      belowAmbient = false;
    }
  }
  return belowAmbient;
}

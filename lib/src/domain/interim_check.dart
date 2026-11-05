/// Port of `js/interim-check.js`.
///
/// The calculator input stays a JSON-shaped `Map<String, Object?>` with the JS
/// key names (same convention as `interim_measurements.dart`). The plan result
/// is read through its typed `protocolSteps` (`ProtocolStep`).
library;

import 'interim_measurements.dart';
import 'js_number.dart';
import 'plan_with_readings.dart';
import 'thermodynamics.dart';
import 'units.dart';

/// A reading as the user enters it: pressure (bar) and gas temperature (°C).
typedef InterimReading = ({double pressureBar, double temperatureC});

/// Result of [verifyInterimMeasurement]: JS `{ ok: true }` or `{ ok: false, error }`.
class InterimCheckResult {
  const InterimCheckResult._(this.ok, this.error);

  const InterimCheckResult.accepted() : this._(true, null);

  const InterimCheckResult.rejected(String message) : this._(false, message);

  final bool ok;
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is InterimCheckResult && other.ok == ok && other.error == error;

  @override
  int get hashCode => Object.hash(ok, error);

  @override
  String toString() => ok
      ? 'InterimCheckResult.accepted'
      : 'InterimCheckResult.rejected($error)';
}

Map<String, Object?> _mapOf(Object? value) => value as Map<String, Object?>;

double _doubleOf(Object? value) => (value as num).toDouble();

List<ProtocolStep?> _stepsIn(Object? value) => value is List<Object?>
    ? [for (final step in value) step as ProtocolStep?]
    : const [];

// JS `protocolStepsOf`: the result's own steps, else the maximum-pressure steps.
List<ProtocolStep?> _protocolStepsOf(Map<String, Object?> result) {
  final direct = _stepsIn(result['protocolSteps']);
  if (direct.isNotEmpty) {
    return direct;
  }
  final maximum = result['maximumPressure'];
  return maximum is Map<String, Object?>
      ? _stepsIn(maximum['protocolSteps'])
      : const [];
}

/// Checks a candidate reading for step [index] against the recipe that
/// planWithReadings produces from the readings before it.
InterimCheckResult verifyInterimMeasurement(
  Map<String, Object?> input,
  int index,
  InterimReading measurement, {
  required double tolerancePercent,
  String units = metricUnits,
}) {
  final thermal = _mapOf(input['thermal']);
  final measurements =
      thermal['interimMeasurements'] as List<Object?>? ?? const [];
  final priorMeasurements = measurements.take(index).toList();
  final reference = planWithReadings({
    ...input,
    'thermal': {...thermal, 'interimMeasurements': priorMeasurements},
  });
  if (reference['feasible'] == false) {
    final reason = reference['error'] as String? ?? 'unknown error';
    return InterimCheckResult.rejected(
      'This reading cannot be checked because the plan from the earlier readings is infeasible: $reason.',
    );
  }
  final protocolSteps = _protocolStepsOf(reference);
  final stepIndex = protocolSteps.indexWhere(
    (step) => step?.measurementIndex == index,
  );
  final plannedStep = stepIndex < 0 ? null : protocolSteps[stepIndex];
  final planned = plannedStep?.thermal;
  if (planned == null) {
    return const InterimCheckResult.rejected(
      'This reading cannot be checked because the plan has no matching step.',
    );
  }
  final stepNumber = protocolStepNumber(plannedStep, index);

  final ambientC = _doubleOf(thermal['ambientTemperatureC']);
  if (measurement.temperatureC < ambientC &&
      !gasCanBeBelowAmbient(protocolSteps, stepIndex)) {
    return InterimCheckResult.rejected(
      'Measured temperature ${formatUnitValue(measurement.temperatureC, 'temperatureC', units)} is below ambient ${formatUnitValue(ambientC, 'temperatureC', units)}, but this gas state did not come from a pressure-lowering drain or a salvage transfer out of the working tank. Stop, recheck the starting cylinder, and retry from the actual measured state.',
    );
  }

  final receiverStartMix = planned.receiverStartMix!;
  final physics = _mapOf(input['physics']);
  final expectedBar = calculatePressureAtTemperature(
    pressureBar: planned.pressureStartBar,
    oxygenPercent: receiverStartMix.oxygenPercent,
    heliumPercent: receiverStartMix.heliumPercent,
    fromTemperatureC: planned.temperatureStartC,
    toTemperatureC: measurement.temperatureC,
    volumeL: _doubleOf(_mapOf(input['cylinder'])['volumeL']),
    useVdw: physics['model'] == 'vdw',
  );
  if (!interimPressureWithinTolerance(
    measuredBar: measurement.pressureBar,
    plannedBar: expectedBar,
    tolerancePercent: tolerancePercent,
  )) {
    final tolerance = jsNumberString(tolerancePercent);
    return InterimCheckResult.rejected(
      'Measured pressure ${formatUnitValue(measurement.pressureBar, 'pressureBar', units)} is outside ±$tolerance% of the planned ${formatUnitValue(expectedBar, 'pressureBar', units)} for step $stepNumber at ${formatUnitValue(measurement.temperatureC, 'temperatureC', units)}. Stop, recheck the starting cylinder, and retry from the actual measured state.',
    );
  }
  return const InterimCheckResult.accepted();
}

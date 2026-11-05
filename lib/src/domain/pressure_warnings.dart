/// Port of the pressure-warning observation builders and mode gate in
/// `js/main.js` (`addPressureWarningObservation`,
/// `addTemperaturePressureWarningObservation`,
/// `pressureWarningObservationsForOptimize`,
/// `pressureWarningObservationsForCompare`,
/// `pressureWarningObservationsForWhatIf`, `collectPressureWarnings`).
///
/// The per-protocol-step classification lives in `pressure_limits.dart`
/// (`collectThermalPressureWarningObservations`); this module only assembles
/// the observations for each result and applies the `warning` mode gate.
library;

import 'interim_measurements.dart';
import 'pressure_limits.dart';
import 'thermodynamics.dart';

double? _finiteOrNull(double? value) =>
    value != null && value.isFinite ? value : null;

double? _numberOrNull(Object? value) {
  if (value is num) {
    final number = value.toDouble();
    return number.isFinite ? number : null;
  }
  return null;
}

Map<String, Object?> _mapOf(Object? value) =>
    value is Map<String, Object?> ? value : const <String, Object?>{};

Map<String, Object?>? _mapOrNull(Object? value) =>
    value is Map<String, Object?> ? value : null;

List<ProtocolStep> _protocolStepsOf(Object? value) => value is List<Object?>
    ? value.whereType<ProtocolStep>().toList(growable: false)
    : const <ProtocolStep>[];

/// JS `addPressureWarningObservation`: a non-finite pressure is skipped.
void _addObservation(
  List<PressureObservation> observations,
  double? pressureBar, {
  required String source,
  String? stepIdentifier,
  bool isTransientHot = false,
}) {
  final finite = _finiteOrNull(pressureBar);
  if (finite == null) {
    return;
  }
  observations.add(
    PressureObservation(
      pressureBar: finite,
      source: source,
      stepIdentifier: stepIdentifier,
      stepIndex: null,
      isTransientHot: isTransientHot,
    ),
  );
}

bool _isAboveAmbient(double? temperatureC, double? ambientTemperatureC) {
  final temperature = _finiteOrNull(temperatureC);
  final ambient = _finiteOrNull(ambientTemperatureC);
  return temperature != null && ambient != null && temperature > ambient;
}

/// JS `addTemperaturePressureWarningObservation`: the observation is hot when
/// the measured temperature is above ambient.
void _addTemperatureObservation(
  List<PressureObservation> observations,
  double? pressureBar,
  double? temperatureC,
  double? ambientTemperatureC, {
  required String source,
  String? stepIdentifier,
}) {
  _addObservation(
    observations,
    pressureBar,
    source: source,
    stepIdentifier: stepIdentifier,
    isTransientHot: _isAboveAmbient(temperatureC, ambientTemperatureC),
  );
}

/// Step identifier for a step index. A missing step (JS `undefined`) has an
/// empty title, so it takes the `Step N` fallback.
String _stepIdentifierAt(List<ProtocolStep> steps, int index) {
  if (index < steps.length) {
    return pressureWarningStepIdentifier(steps[index], index);
  }
  return 'Step ${index + 1}';
}

/// JS `pressureWarningObservationsForOptimize(input, result)`.
///
/// [input] is the Optimize calculator input map (`buildCalculatorInput`) and
/// [result] is the planner result. Observation order: initial, target,
/// interim readings, protocol thermal observations, final in-water target.
List<PressureObservation> pressureWarningObservationsForOptimize(
  CalculatorInput input,
  Map<String, Object?> result,
) {
  final observations = <PressureObservation>[];
  final cylinder = _mapOf(input['cylinder']);
  final thermal = _mapOf(input['thermal']);
  final maximumPressure = _mapOrNull(result['maximumPressure']);
  final resultSteps = _protocolStepsOf(result['protocolSteps']);
  final protocolSteps = resultSteps.isNotEmpty
      ? resultSteps
      : _protocolStepsOf(maximumPressure?['protocolSteps']);
  final ambientTemperatureC = _numberOrNull(thermal['ambientTemperatureC']);

  _addObservation(
    observations,
    _numberOrNull(cylinder['initialPressureBar']),
    source: 'initial',
  );
  _addObservation(
    observations,
    _numberOrNull(cylinder['targetPressureBar']),
    source: 'target',
  );

  final measurements = thermal['interimMeasurements'];
  if (measurements is List<Object?>) {
    for (var index = 0; index < measurements.length; index++) {
      final measurement = measurements[index];
      if (measurement is! Map<String, Object?>) {
        continue;
      }
      final protocolIndex = protocolSteps.indexWhere(
        (step) => step.measurementIndex == index,
      );
      final stepIndex = protocolIndex >= 0 ? protocolIndex : index;
      _addTemperatureObservation(
        observations,
        _numberOrNull(measurement['pressureBar']),
        _numberOrNull(measurement['temperatureC']),
        ambientTemperatureC,
        source: 'interim',
        stepIdentifier: _stepIdentifierAt(protocolSteps, stepIndex),
      );
    }
  }

  final waitModeRaw = thermal['waitMode'];
  observations.addAll(
    collectThermalPressureWarningObservations(
      protocolSteps: protocolSteps,
      ambientTemperatureC: ambientTemperatureC,
      waitMode: waitModeRaw is String ? waitModeRaw : null,
    ),
  );

  final thermalResult =
      _mapOrNull(result['thermal']) ?? _mapOrNull(maximumPressure?['thermal']);
  _addObservation(
    observations,
    _numberOrNull(thermalResult?['finalInWaterPressureBar']),
    source: 'target',
    stepIdentifier: 'Target temperature',
  );
  return observations;
}

/// JS `pressureWarningObservationsForCompare(input, compare)`.
///
/// Observation order: initial, thermal, settled.
List<PressureObservation> pressureWarningObservationsForCompare({
  required double? initialPressureBar,
  required double? ambientTemperatureC,
  required ThermalCompareResult compare,
}) {
  final observations = <PressureObservation>[];
  _addObservation(observations, initialPressureBar, source: 'initial');
  observations.addAll(
    collectThermalPressureWarningObservations(
      protocolSteps: compare.protocolSteps,
      ambientTemperatureC: ambientTemperatureC,
    ),
  );
  _addObservation(
    observations,
    compare.finalSummary.ambientSettled.pressureBar,
    source: 'settled',
    stepIdentifier: 'Settled result',
  );
  return observations;
}

/// JS `pressureWarningObservationsForWhatIf(input, compare)`.
///
/// The Compare observations followed by the cooling observation from the
/// in-water projection. Observation order: initial, thermal, settled, cooling.
List<PressureObservation> pressureWarningObservationsForWhatIf({
  required double? initialPressureBar,
  required double? ambientTemperatureC,
  required ThermalCompareResult compare,
  required double? inWaterPressureBar,
}) {
  final observations = pressureWarningObservationsForCompare(
    initialPressureBar: initialPressureBar,
    ambientTemperatureC: ambientTemperatureC,
    compare: compare,
  );
  _addObservation(
    observations,
    inWaterPressureBar,
    source: 'cooling',
    stepIdentifier: 'In-water projection',
  );
  return observations;
}

/// JS `collectPressureWarnings(input, observations)`. Returns no warnings
/// unless [pressureLimitMode] is `warning`.
List<CylinderPressureWarning> collectPressureWarnings({
  required String pressureLimitMode,
  required CylinderPressureSpec? cylinder,
  required List<PressureObservation> observations,
}) {
  if (pressureLimitMode != 'warning') {
    return const <CylinderPressureWarning>[];
  }
  return collectCylinderPressureWarnings(
    cylinder: cylinder,
    observations: observations,
  );
}

/// Cylinder spec of a calculator input map (JS `input.cylinder`).
CylinderPressureSpec cylinderPressureSpecOfInput(CalculatorInput input) {
  final cylinder = _mapOf(input['cylinder']);
  return CylinderPressureSpec(
    workingPressureBar: _numberOrNull(cylinder['workingPressureBar']),
    hotOverfillPercent: _numberOrNull(cylinder['hotOverfillPercent']),
  );
}

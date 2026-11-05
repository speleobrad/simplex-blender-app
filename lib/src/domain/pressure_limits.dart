import 'dart:convert';

import 'preset_validation.dart';
import 'thermodynamics.dart';

/// Port of `js/pressure-limits.js`.
const double _defaultToleranceBar = 1e-9;

const String workingPressureKind = 'working-pressure';
const String hotOverfillKind = 'hot-overfill';

const String _invalidHotOverfillMessage =
    'Cylinder hot overfill must be between 0 and 5% in 0.5% steps.';

/// Cylinder fields read by the pressure limit checks (JS cylinder preset).
class CylinderPressureSpec {
  const CylinderPressureSpec({
    required this.workingPressureBar,
    this.hotOverfillPercent,
  });

  final double? workingPressureBar;

  /// `null` stands for both an absent and a null JS `hotOverfillPercent`;
  /// both fall back to [defaultHotOverfillPercent].
  final double? hotOverfillPercent;
}

/// JS limit object returned by [getCylinderPressureLimit].
class CylinderPressureLimit {
  const CylinderPressureLimit({required this.kind, required this.limitBar});

  final String kind;
  final double limitBar;
}

/// JS exceedance object returned by [getCylinderPressureExceedance].
class CylinderPressureExceedance {
  const CylinderPressureExceedance({
    required this.kind,
    required this.limitBar,
    required this.pressureBar,
  });

  final String kind;
  final double limitBar;
  final double pressureBar;
}

/// One pressure observation fed to [collectCylinderPressureWarnings].
class PressureObservation {
  const PressureObservation({
    required this.pressureBar,
    required this.source,
    required this.stepIdentifier,
    required this.stepIndex,
    this.isTransientHot = false,
  });

  final double pressureBar;
  final String source;
  final String? stepIdentifier;
  final int? stepIndex;
  final bool isTransientHot;
}

/// JS warning object returned by [collectCylinderPressureWarnings].
class CylinderPressureWarning {
  const CylinderPressureWarning({
    required this.kind,
    required this.limitBar,
    required this.pressureBar,
    required this.source,
    required this.stepIdentifier,
    required this.stepIndex,
  });

  final String kind;
  final double limitBar;
  final double pressureBar;
  final String source;
  final String? stepIdentifier;
  final int? stepIndex;
}

double _hotOverfillPercent(CylinderPressureSpec? cylinder) {
  final value = cylinder?.hotOverfillPercent;
  if (value == null) return defaultHotOverfillPercent;
  if (!isValidHotOverfillPercent(value)) {
    throw RangeError(_invalidHotOverfillMessage);
  }
  return value;
}

CylinderPressureLimit? getCylinderPressureLimit({
  CylinderPressureSpec? cylinder,
  bool isTransientHot = false,
}) {
  final workingPressureBar = cylinder?.workingPressureBar;
  if (workingPressureBar == null || !workingPressureBar.isFinite) return null;
  if (!isTransientHot) {
    return CylinderPressureLimit(
      kind: workingPressureKind,
      limitBar: workingPressureBar,
    );
  }
  return CylinderPressureLimit(
    kind: hotOverfillKind,
    limitBar: workingPressureBar * (1 + _hotOverfillPercent(cylinder) / 100),
  );
}

CylinderPressureExceedance? getCylinderPressureExceedance({
  double? pressureBar,
  CylinderPressureSpec? cylinder,
  bool isTransientHot = false,
  double toleranceBar = _defaultToleranceBar,
}) {
  final limit = getCylinderPressureLimit(
    cylinder: cylinder,
    isTransientHot: isTransientHot,
  );
  if (limit == null ||
      pressureBar == null ||
      !pressureBar.isFinite ||
      pressureBar <= limit.limitBar + toleranceBar) {
    return null;
  }
  return CylinderPressureExceedance(
    kind: limit.kind,
    limitBar: limit.limitBar,
    pressureBar: pressureBar,
  );
}

/// Keeps the highest exceedance per (source, step identifier, step index,
/// kind), in first-seen key order.
List<CylinderPressureWarning> collectCylinderPressureWarnings({
  CylinderPressureSpec? cylinder,
  List<PressureObservation> observations = const [],
  double toleranceBar = _defaultToleranceBar,
}) {
  final highest = <String, CylinderPressureWarning>{};
  for (final observation in observations) {
    final exceedance = getCylinderPressureExceedance(
      pressureBar: observation.pressureBar,
      cylinder: cylinder,
      isTransientHot: observation.isTransientHot,
      toleranceBar: toleranceBar,
    );
    if (exceedance == null) continue;
    final key = jsonEncode([
      observation.source,
      observation.stepIdentifier,
      observation.stepIndex,
      exceedance.kind,
    ]);
    final warning = CylinderPressureWarning(
      kind: exceedance.kind,
      limitBar: exceedance.limitBar,
      pressureBar: exceedance.pressureBar,
      source: observation.source,
      stepIdentifier: observation.stepIdentifier,
      stepIndex: observation.stepIndex,
    );
    final previous = highest[key];
    if (previous == null || warning.pressureBar > previous.pressureBar) {
      highest[key] = warning;
    }
  }
  return highest.values.toList(growable: false);
}

final RegExp _stepNumberPrefix = RegExp(
  r'^Step[ ]+[0-9]+[ ]*:[ ]*',
  caseSensitive: false,
);

String pressureWarningStepIdentifier(ProtocolStep step, int index) {
  final title = (step.title ?? step.operation ?? '')
      .replaceFirst(_stepNumberPrefix, '')
      .trim();
  return title.isEmpty ? 'Step ${index + 1}' : title;
}

bool _isAboveAmbientTemperature(
  double? temperatureC,
  double? ambientTemperatureC,
) {
  return temperatureC != null &&
      temperatureC.isFinite &&
      ambientTemperatureC != null &&
      ambientTemperatureC.isFinite &&
      temperatureC > ambientTemperatureC;
}

/// Builds the pressure observations of a simulated protocol. Mirrors the JS
/// classification of start, ambient, transfer, wait, and sampled pressures.
List<PressureObservation> collectThermalPressureWarningObservations({
  List<ProtocolStep> protocolSteps = const [],
  double? ambientTemperatureC,
  String? waitMode,
}) {
  final observations = <PressureObservation>[];
  var previousStepEndsAtTargetWait = false;
  int? currentStepIndex;

  void addObservation(
    double? pressureBar,
    String source,
    String? stepIdentifier, {
    bool isTransientHot = false,
    int? stepIndex,
  }) {
    if (pressureBar == null || !pressureBar.isFinite) return;
    observations.add(
      PressureObservation(
        pressureBar: pressureBar,
        source: source,
        stepIdentifier: stepIdentifier,
        stepIndex: stepIndex ?? currentStepIndex,
        isTransientHot: isTransientHot,
      ),
    );
  }

  for (var index = 0; index < protocolSteps.length; index++) {
    final step = protocolSteps[index];
    currentStepIndex = index;
    final thermal = step.thermal;
    if (thermal == null) {
      previousStepEndsAtTargetWait = false;
      continue;
    }
    final isFinalStep = index == protocolSteps.length - 1;
    final skipsInitialKeepWait =
        !isFinalStep && index == 0 && step.type == 'keep';
    final endsAtTargetWait =
        step.waitMode == 'target' ||
        (waitMode == 'temperature' && !isFinalStep && !skipsInitialKeepWait);
    final stepIdentifier = pressureWarningStepIdentifier(step, index);
    final waitEndMinutes = thermal.durationMinutes + thermal.waitMinutes;
    bool isTargetWaitEndpoint(ThermalSample sample) =>
        endsAtTargetWait &&
        sample.elapsedMinutes.isFinite &&
        waitEndMinutes.isFinite &&
        sample.elapsedMinutes >= waitEndMinutes - 1e-9;
    final startIsTransientHot = thermal.measurementApplied == true
        ? _isAboveAmbientTemperature(
            thermal.temperatureStartC,
            ambientTemperatureC,
          )
        : !previousStepEndsAtTargetWait &&
              _isAboveAmbientTemperature(
                thermal.temperatureStartC,
                ambientTemperatureC,
              );

    addObservation(
      thermal.pressureStartBar,
      'start',
      stepIdentifier,
      isTransientHot: startIsTransientHot,
      stepIndex: index,
    );
    if (thermal.rateSource != 'none') {
      addObservation(
        thermal.pressureAtTransferEndAmbientBar,
        'ambient',
        stepIdentifier,
        stepIndex: index,
      );
    }
    addObservation(
      thermal.pressureAtTransferEndHotBar,
      'transfer',
      stepIdentifier,
      isTransientHot: _isAboveAmbientTemperature(
        thermal.temperatureAtTransferEndC,
        ambientTemperatureC,
      ),
      stepIndex: index,
    );

    final waitIsTransientHot =
        !endsAtTargetWait &&
        _isAboveAmbientTemperature(
          thermal.temperatureAfterWaitC,
          ambientTemperatureC,
        );
    addObservation(
      thermal.pressureAfterWaitBar,
      waitIsTransientHot ? 'cooling' : 'settled',
      stepIdentifier,
      isTransientHot: waitIsTransientHot,
      stepIndex: index,
    );

    for (final sample in thermal.samples) {
      final temperatureC = sample.temperatureC;
      final isTargetWaitStart =
          previousStepEndsAtTargetWait &&
          thermal.measurementApplied != true &&
          sample.elapsedMinutes.isFinite &&
          sample.elapsedMinutes <= 1e-9;
      final sampleIsTransientHot =
          !isTargetWaitEndpoint(sample) &&
          !isTargetWaitStart &&
          _isAboveAmbientTemperature(temperatureC, ambientTemperatureC);
      addObservation(
        sample.projectedPressureBar ?? sample.pressureBar,
        sampleIsTransientHot ? 'cooling' : 'settled',
        stepIdentifier,
        isTransientHot: sampleIsTransientHot,
        stepIndex: index,
      );
    }
    previousStepEndsAtTargetWait = endsAtTargetWait;
  }
  return observations;
}

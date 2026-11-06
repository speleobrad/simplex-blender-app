// Pure Dart port of the DOM-free exports of js/ui/thermal-charts.js
// (lines 1-335). Rendering, hover, and DOM helpers are intentionally absent.
//
// Null handling: JS `undefined`/`null`/non-finite numbers in loosely typed
// inputs are modelled as nullable `double?` fields. Every value the series
// builder consumes is passed through `_finiteOrNull`, which mirrors JS
// `Number.isFinite` (null, NaN and infinities all become null).

import 'dart:math' as math;

import 'package:simplex_blender/src/domain/js_number.dart';

const double _chartMarginTop = 28;

// ---------------------------------------------------------------------------
// Input shapes
// ---------------------------------------------------------------------------

/// One raw minute sample supplied by the optimizer (`thermal.samples[i]`).
///
/// [projectedPressureBar] is the temperature-adjusted pressure the thermal
/// trajectory follows; the chart prefers it and falls back to the reference
/// [pressureBar] when it is absent.
class ThermalInputSample {
  const ThermalInputSample({
    this.elapsedMinutes,
    this.pressureBar,
    this.projectedPressureBar,
    this.temperatureC,
    this.rateBarPerMin,
  });

  final double? elapsedMinutes;
  final double? pressureBar;
  final double? projectedPressureBar;
  final double? temperatureC;
  final double? rateBarPerMin;
}

/// The `thermal` object of a protocol step.
class ThermalStepThermal {
  const ThermalStepThermal({
    this.durationMinutes,
    this.waitMinutes,
    this.measuredStartPressureBar,
    this.measuredStartTemperatureC,
    this.measuredWaitMinutes,
    this.temperatureStartC,
    this.temperatureAtTransferEndC,
    this.pressureAtTransferEndBar,
    this.temperatureAfterWaitC,
    this.pressureAfterWaitBar,
    this.samples,
  });

  final double? durationMinutes;
  final double? waitMinutes;
  final double? measuredStartPressureBar;
  final double? measuredStartTemperatureC;
  final double? measuredWaitMinutes;
  final double? temperatureStartC;
  final double? temperatureAtTransferEndC;
  final double? pressureAtTransferEndBar;
  final double? temperatureAfterWaitC;
  final double? pressureAfterWaitBar;

  /// JS `Array.isArray(thermal.samples) && length > 0`; null or empty means
  /// the three key points are used as the sample list.
  final List<ThermalInputSample>? samples;
}

/// One entry of `protocolSteps`. `type == 'keep'` steps are skipped.
/// A null [thermal] makes the whole series empty (JS `if (!thermal)`).
class ThermalProtocolStep {
  const ThermalProtocolStep({
    this.type,
    this.title,
    this.recipeLabel,
    this.recipeAction,
    this.recipeGas,
    this.receiverStartPressureBar,
    this.resultingPressureBar,
    this.thermal,
  });

  final String? type;
  final String? title;
  final String? recipeLabel;
  final String? recipeAction;
  final String? recipeGas;
  final double? receiverStartPressureBar;
  final double? resultingPressureBar;
  final ThermalStepThermal? thermal;
}

/// JS `initial` argument (`{}` by default).
class ThermalInitialState {
  const ThermalInitialState({
    this.initialPressureBar,
    this.initialTemperatureC,
  });

  final double? initialPressureBar;
  final double? initialTemperatureC;
}

/// JS `terminalProjection` argument. `null` in JS maps to a null Dart value.
class ThermalTerminalProjection {
  const ThermalTerminalProjection({
    this.mode,
    this.pressureBar,
    this.temperatureC,
    this.durationMinutes,
    this.inWaterPressureBar,
    this.inWaterTemperatureC,
  });

  final String? mode;
  final double? pressureBar;
  final double? temperatureC;
  final double? durationMinutes;
  final double? inWaterPressureBar;
  final double? inWaterTemperatureC;
}

// ---------------------------------------------------------------------------
// Output shapes (mirror the JS object field names)
// ---------------------------------------------------------------------------

/// Mirrors JS `point(...)`.
class ThermalSeriesPoint {
  const ThermalSeriesPoint({
    required this.step,
    required this.phase,
    required this.title,
    required this.label,
    required this.pressureBar,
    required this.temperatureC,
    required this.elapsedMinutes,
    required this.timeLabel,
    this.recipeAction,
    this.recipeGas,
  });

  final int step;
  final String phase;
  final String title;
  final String label;
  final String? recipeAction;
  final String? recipeGas;
  final double pressureBar;
  final double temperatureC;
  final double elapsedMinutes;
  final String timeLabel;
}

/// A plotted sample. `step` and `title` are null for samples that do not
/// belong to a protocol step (the terminal start used when no step exists,
/// and interpolated samples), matching the JS objects that lack those keys.
class ThermalSeriesSample {
  const ThermalSeriesSample({
    required this.elapsedMinutes,
    required this.pressureBar,
    required this.temperatureC,
    this.step,
    this.title,
    this.rateBarPerMin,
  });

  final int? step;
  final String? title;
  final double elapsedMinutes;
  final double pressureBar;
  final double temperatureC;
  final double? rateBarPerMin;
}

class ThermalSeriesBand {
  const ThermalSeriesBand({
    required this.step,
    required this.title,
    required this.startMinute,
    required this.endMinute,
    required this.labelRow,
  });

  final int step;
  final String title;
  final double startMinute;
  final double endMinute;
  final int labelRow;
}

enum ThermalSegmentStyle { observed, estimated }

class ThermalSeriesSegment {
  const ThermalSeriesSegment({required this.style, required this.samples});

  final ThermalSegmentStyle style;
  final List<ThermalSeriesSample> samples;
}

class ThermalSeries {
  const ThermalSeries({
    required this.points,
    required this.samples,
    required this.bands,
    required this.segments,
    required this.finalPoint,
  });

  final List<ThermalSeriesPoint> points;
  final List<ThermalSeriesSample> samples;
  final List<ThermalSeriesBand> bands;
  final List<ThermalSeriesSegment> segments;
  final ThermalSeriesPoint? finalPoint;
}

/// Key selector for [buildChartPath] (JS `sample[key]`).
enum ThermalSampleKey { pressureBar, temperatureC }

class ThermalChartDomain {
  const ThermalChartDomain({required this.min, required this.max});

  final double min;
  final double max;
}

/// Presentation of a thermal curve (JS `thermalCurveAttributes`).
/// `strokeDasharray` is null for observed (solid) curves.
class ThermalCurveStyle {
  const ThermalCurveStyle({
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.strokeDasharray,
    required this.strokeLinecap,
    required this.strokeLinejoin,
  });

  final String fill;
  final String stroke;
  final double strokeWidth;
  final String? strokeDasharray;
  final String strokeLinecap;
  final String strokeLinejoin;
}

/// Presentation of a key point marker (JS `thermalPointMarkerAttributes`).
class ThermalPointMarkerStyle {
  const ThermalPointMarkerStyle({
    required this.r,
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
  });

  final double r;
  final String fill;
  final String stroke;
  final double strokeWidth;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// JS `Number.isFinite` on a possibly-missing number.
double? _finiteOrNull(double? value) =>
    value != null && value.isFinite ? value : null;

/// JS truthiness for a string (`'' || fallback` falls through).
String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

ThermalSeriesPoint _point({
  required int step,
  required String phase,
  required String title,
  required String label,
  String? recipeAction,
  String? recipeGas,
  required double pressureBar,
  required double temperatureC,
  required double elapsedMinutes,
  String? timeLabel,
}) {
  return ThermalSeriesPoint(
    step: step,
    phase: phase,
    title: title,
    label: label,
    recipeAction: recipeAction,
    recipeGas: recipeGas,
    pressureBar: pressureBar,
    temperatureC: temperatureC,
    elapsedMinutes: elapsedMinutes,
    timeLabel: timeLabel ?? '${elapsedMinutes.toStringAsFixed(1)} min',
  );
}

String _phaseLabel(String phase) {
  if (phase == 'transfer-end') return 'transfer end';
  if (phase == 'settled') return 'ambient settled';
  if (phase == 'ambient-settled') return 'ambient-settled projection';
  if (phase == 'in-water-projection') return 'explicit in-water projection';
  if (phase == 'in-water-target') return 'in-water target projection';
  if (phase == 'measured-start') return 'measured start';
  return 'step start';
}

ThermalSeries _emptySeries() {
  return const ThermalSeries(
    points: [],
    samples: [],
    bands: [],
    segments: [],
    finalPoint: null,
  );
}

/// Mutable working segment; `transferEndMinute` is only used while building.
class _SegmentDraft {
  _SegmentDraft({
    required this.style,
    required this.transferEndMinute,
    required this.samples,
  });

  final ThermalSegmentStyle style;
  final double? transferEndMinute;
  final List<ThermalSeriesSample> samples;
}

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

bool isThermalTerminalProjection(String phase) {
  return phase == 'ambient-settled' ||
      phase == 'in-water-target' ||
      phase == 'in-water-projection';
}

ThermalCurveStyle thermalCurveAttributes(
  String color, [
  ThermalSegmentStyle style = ThermalSegmentStyle.estimated,
]) {
  return ThermalCurveStyle(
    fill: 'none',
    stroke: color,
    strokeWidth: 2.5,
    strokeDasharray: style == ThermalSegmentStyle.estimated ? '2 4' : null,
    strokeLinecap: 'round',
    strokeLinejoin: 'round',
  );
}

ThermalPointMarkerStyle thermalPointMarkerAttributes(
  ThermalSeriesPoint pointValue,
  String color,
) {
  final measured = pointValue.phase == 'measured-start';
  return ThermalPointMarkerStyle(
    r: measured ? 5 : 4,
    fill: measured ? 'var(--chart-badge)' : color,
    stroke: measured ? color : 'var(--chart-point-outline)',
    strokeWidth: measured ? 2 : 1.5,
  );
}

String thermalChartAriaLabel(String title) {
  return '$title during blending steps over time; solid curves show the current/observed path; dotted curves indicate estimated values';
}

ThermalSeries buildThermalSeries(
  List<ThermalProtocolStep> protocolSteps, {
  ThermalInitialState initial = const ThermalInitialState(),
  ThermalTerminalProjection? terminalProjection,
}) {
  if (protocolSteps.isEmpty) {
    return _emptySeries();
  }

  double? previousPressureBar = _finiteOrNull(initial.initialPressureBar);
  double? previousTemperatureC = _finiteOrNull(initial.initialTemperatureC);
  var elapsedMinutes = 0.0;
  var previousWaitMinutes = 0.0;
  final points = <ThermalSeriesPoint>[];
  final samples = <ThermalSeriesSample>[];
  final bands = <ThermalSeriesBand>[];
  final lineSegments = <_SegmentDraft>[];

  for (final step in protocolSteps) {
    if (step.type == 'keep') {
      continue;
    }
    final thermal = step.thermal;
    if (thermal == null) {
      return _emptySeries();
    }

    final durationMinutes = _finiteOrNull(thermal.durationMinutes);
    final waitMinutes = _finiteOrNull(thermal.waitMinutes);
    if (durationMinutes == null ||
        durationMinutes < 0 ||
        waitMinutes == null ||
        waitMinutes < 0) {
      return _emptySeries();
    }

    final measuredPressureBar = _finiteOrNull(thermal.measuredStartPressureBar);
    final measuredTemperatureC = _finiteOrNull(
      thermal.measuredStartTemperatureC,
    );
    final hasMeasuredStart =
        measuredPressureBar != null || measuredTemperatureC != null;
    final startPressureBar = _finiteOrNull(
      measuredPressureBar ??
          previousPressureBar ??
          _finiteOrNull(step.receiverStartPressureBar) ??
          step.resultingPressureBar,
    );
    final startTemperatureC = _finiteOrNull(
      measuredTemperatureC ?? previousTemperatureC ?? thermal.temperatureStartC,
    );
    final transferPressureBar = _finiteOrNull(thermal.pressureAtTransferEndBar);
    final transferTemperatureC = _finiteOrNull(
      thermal.temperatureAtTransferEndC,
    );
    final settledPressureBar = _finiteOrNull(thermal.pressureAfterWaitBar);
    final settledTemperatureC = _finiteOrNull(thermal.temperatureAfterWaitC);
    if (startPressureBar == null ||
        startTemperatureC == null ||
        transferPressureBar == null ||
        transferTemperatureC == null ||
        settledPressureBar == null ||
        settledTemperatureC == null) {
      return _emptySeries();
    }

    final stepNumber = points.length ~/ 3 + 1;
    final title =
        _nonEmpty(step.recipeLabel) ??
        _nonEmpty(step.title) ??
        'Step $stepNumber';
    final measuredWaitMinutes = _finiteOrNull(thermal.measuredWaitMinutes);
    final stepStartMinutes = hasMeasuredStart && measuredWaitMinutes != null
        ? elapsedMinutes - previousWaitMinutes + measuredWaitMinutes
        : elapsedMinutes;
    final transferEndMinutes = stepStartMinutes + durationMinutes;
    final settledMinutes = transferEndMinutes + waitMinutes;
    final startPhase = hasMeasuredStart ? 'measured-start' : 'start';
    final String? startTimeLabel = hasMeasuredStart
        ? (measuredWaitMinutes != null
              ? '~${stepStartMinutes.toStringAsFixed(1)} min'
              : '? min')
        : null;
    points.addAll([
      _point(
        step: stepNumber,
        phase: startPhase,
        title: title,
        label: '$title · ${_phaseLabel(startPhase)}',
        recipeAction: step.recipeAction,
        recipeGas: step.recipeGas,
        pressureBar: startPressureBar,
        temperatureC: startTemperatureC,
        elapsedMinutes: stepStartMinutes,
        timeLabel: startTimeLabel,
      ),
      _point(
        step: stepNumber,
        phase: 'transfer-end',
        title: title,
        label: '$title · ${_phaseLabel('transfer-end')}',
        recipeAction: step.recipeAction,
        recipeGas: step.recipeGas,
        pressureBar: transferPressureBar,
        temperatureC: transferTemperatureC,
        elapsedMinutes: transferEndMinutes,
      ),
      _point(
        step: stepNumber,
        phase: 'settled',
        title: title,
        label: '$title · ${_phaseLabel('settled')}',
        recipeAction: step.recipeAction,
        recipeGas: step.recipeGas,
        pressureBar: settledPressureBar,
        temperatureC: settledTemperatureC,
        elapsedMinutes: settledMinutes,
      ),
    ]);

    final providedSamples = thermal.samples;
    final inputSamples = providedSamples != null && providedSamples.isNotEmpty
        ? providedSamples
        : [
            ThermalInputSample(
              elapsedMinutes: 0,
              pressureBar: startPressureBar,
              temperatureC: startTemperatureC,
            ),
            ThermalInputSample(
              elapsedMinutes: durationMinutes,
              pressureBar: transferPressureBar,
              temperatureC: transferTemperatureC,
            ),
            ThermalInputSample(
              elapsedMinutes: durationMinutes + waitMinutes,
              pressureBar: settledPressureBar,
              temperatureC: settledTemperatureC,
            ),
          ];
    final mappedSamples = <ThermalSeriesSample>[];
    for (final sample in inputSamples) {
      final sampleElapsed = _finiteOrNull(sample.elapsedMinutes);
      final samplePressure =
          _finiteOrNull(sample.projectedPressureBar) ??
          _finiteOrNull(sample.pressureBar);
      final sampleTemperature = _finiteOrNull(sample.temperatureC);
      if (sampleElapsed == null ||
          samplePressure == null ||
          sampleTemperature == null) {
        return _emptySeries();
      }
      mappedSamples.add(
        ThermalSeriesSample(
          step: stepNumber,
          title: title,
          elapsedMinutes: stepStartMinutes + sampleElapsed,
          pressureBar: samplePressure,
          temperatureC: sampleTemperature,
          rateBarPerMin: _finiteOrNull(sample.rateBarPerMin),
        ),
      );
    }
    samples.addAll(mappedSamples);

    final stepSegment = _SegmentDraft(
      style: ThermalSegmentStyle.observed,
      transferEndMinute: transferEndMinutes,
      samples: mappedSamples,
    );
    if (hasMeasuredStart) {
      final previousSegment = lineSegments.isEmpty ? null : lineSegments.last;
      final previousTransferEnd = previousSegment?.transferEndMinute;
      if (previousSegment != null && previousTransferEnd != null) {
        final transferEndIndex = previousSegment.samples.indexWhere(
          (sample) =>
              (sample.elapsedMinutes - previousTransferEnd).abs() < 1e-9,
        );
        if (transferEndIndex >= 0) {
          final transferSamples = previousSegment.samples.sublist(
            0,
            transferEndIndex + 1,
          );
          final estimatedSamples = previousSegment.samples.sublist(
            transferEndIndex,
          );
          lineSegments
            ..removeLast()
            ..add(
              _SegmentDraft(
                style: ThermalSegmentStyle.observed,
                transferEndMinute: null,
                samples: transferSamples,
              ),
            )
            ..add(
              _SegmentDraft(
                style: ThermalSegmentStyle.estimated,
                transferEndMinute: null,
                samples: estimatedSamples,
              ),
            )
            ..add(
              _SegmentDraft(
                style: ThermalSegmentStyle.observed,
                transferEndMinute: null,
                samples: [estimatedSamples.first, mappedSamples.first],
              ),
            );
        }
      }
    }
    lineSegments.add(stepSegment);

    bands.add(
      ThermalSeriesBand(
        step: stepNumber,
        title: title,
        startMinute: stepStartMinutes,
        endMinute: settledMinutes,
        labelRow: bands.length % 2,
      ),
    );
    elapsedMinutes = settledMinutes;
    previousWaitMinutes = waitMinutes;
    previousPressureBar = settledPressureBar;
    previousTemperatureC = settledTemperatureC;
  }

  ThermalSeriesPoint? ambientSettledPoint;
  final ThermalSeriesSample? terminalStart;
  if (points.isNotEmpty) {
    terminalStart = samples.last;
  } else if (previousPressureBar != null && previousTemperatureC != null) {
    terminalStart = ThermalSeriesSample(
      elapsedMinutes: 0,
      pressureBar: previousPressureBar,
      temperatureC: previousTemperatureC,
    );
  } else {
    terminalStart = null;
  }

  final terminalPressure = _finiteOrNull(terminalProjection?.pressureBar);
  final terminalTemperature = _finiteOrNull(terminalProjection?.temperatureC);
  final terminalDuration = _finiteOrNull(terminalProjection?.durationMinutes);
  if (terminalStart != null &&
      terminalPressure != null &&
      terminalTemperature != null &&
      terminalDuration != null &&
      terminalDuration >= 0) {
    final terminalElapsedMinutes = elapsedMinutes + terminalDuration;
    final terminalPoint = _point(
      step: points.isEmpty ? 0 : points.last.step,
      phase: 'ambient-settled',
      title: 'Ambient-settled projection',
      label: 'Ambient-settled projection',
      pressureBar: terminalPressure,
      temperatureC: terminalTemperature,
      elapsedMinutes: terminalElapsedMinutes,
    );
    final terminalSample = ThermalSeriesSample(
      step: terminalPoint.step,
      title: terminalPoint.title,
      elapsedMinutes: terminalElapsedMinutes,
      pressureBar: terminalPressure,
      temperatureC: terminalTemperature,
    );
    final repeatsLastSample =
        points.isNotEmpty &&
        (samples.last.elapsedMinutes - terminalElapsedMinutes).abs() < 1e-6 &&
        (samples.last.pressureBar - terminalPressure).abs() < 1e-6 &&
        (samples.last.temperatureC - terminalTemperature).abs() < 1e-6;
    ambientSettledPoint = terminalPoint;
    if (!repeatsLastSample) {
      if (points.isEmpty) {
        samples.add(terminalStart);
      }
      points.add(terminalPoint);
      samples.add(terminalSample);
      lineSegments.add(
        _SegmentDraft(
          style: ThermalSegmentStyle.estimated,
          transferEndMinute: null,
          samples: [terminalStart, terminalSample],
        ),
      );
    }

    final inWaterPressure = _finiteOrNull(
      terminalProjection?.inWaterPressureBar,
    );
    final inWaterTemperature = _finiteOrNull(
      terminalProjection?.inWaterTemperatureC,
    );
    if (inWaterPressure != null && inWaterTemperature != null) {
      final explicitInWater = terminalProjection?.mode == 'what-if';
      final inWaterPhase = explicitInWater
          ? 'in-water-projection'
          : 'in-water-target';
      final inWaterLabel = explicitInWater
          ? 'In-water projection'
          : 'In-water target projection';
      final inWaterPoint = _point(
        step: terminalPoint.step,
        phase: inWaterPhase,
        title: inWaterLabel,
        label: inWaterLabel,
        pressureBar: inWaterPressure,
        temperatureC: inWaterTemperature,
        elapsedMinutes: terminalElapsedMinutes,
      );
      points.add(inWaterPoint);
      samples.add(
        ThermalSeriesSample(
          step: inWaterPoint.step,
          title: inWaterPoint.title,
          elapsedMinutes: terminalElapsedMinutes,
          pressureBar: inWaterPoint.pressureBar,
          temperatureC: inWaterPoint.temperatureC,
        ),
      );
    }
  }

  ThermalSeriesPoint? finalPoint = ambientSettledPoint;
  if (finalPoint == null) {
    for (final pointValue in points.reversed) {
      if (pointValue.phase == 'ambient-settled') {
        finalPoint = pointValue;
        break;
      }
    }
  }
  finalPoint ??= points.isEmpty ? null : points.last;

  return ThermalSeries(
    points: points,
    samples: samples,
    bands: bands,
    segments: [
      for (final segment in lineSegments)
        ThermalSeriesSegment(style: segment.style, samples: segment.samples),
    ],
    finalPoint: finalPoint,
  );
}

/// SVG path string: `M x y L x y ...` (JS `buildChartPath`).
String buildChartPath(
  List<ThermalSeriesSample> samples,
  ThermalSampleKey key,
  double Function(double elapsedMinutes) xForTime,
  double Function(double value) yFor,
) {
  final parts = <String>[];
  for (var index = 0; index < samples.length; index++) {
    final sample = samples[index];
    final value = key == ThermalSampleKey.pressureBar
        ? sample.pressureBar
        : sample.temperatureC;
    parts.add(
      '${index == 0 ? 'M' : 'L'} ${jsNumberString(xForTime(sample.elapsedMinutes))} ${jsNumberString(yFor(value))}',
    );
  }
  return parts.join(' ');
}

/// Linear interpolation at [elapsedMinutes] (JS `interpolateThermalSample`).
/// Returns null only when [samples] is empty.
ThermalSeriesSample? interpolateThermalSample(
  List<ThermalSeriesSample> samples,
  double elapsedMinutes,
) {
  if (samples.isEmpty) {
    return null;
  }
  if (elapsedMinutes <= samples.first.elapsedMinutes) {
    return samples.first;
  }
  final last = samples.last;
  if (elapsedMinutes >= last.elapsedMinutes) {
    return last;
  }

  for (var index = 1; index < samples.length; index++) {
    final upper = samples[index];
    if (elapsedMinutes > upper.elapsedMinutes) {
      continue;
    }
    final lower = samples[index - 1];
    final duration = upper.elapsedMinutes - lower.elapsedMinutes;
    if (duration <= 0) {
      return upper;
    }
    final fraction = (elapsedMinutes - lower.elapsedMinutes) / duration;
    return ThermalSeriesSample(
      elapsedMinutes: elapsedMinutes,
      temperatureC:
          lower.temperatureC +
          (upper.temperatureC - lower.temperatureC) * fraction,
      pressureBar:
          lower.pressureBar +
          (upper.pressureBar - lower.pressureBar) * fraction,
    );
  }
  return last;
}

/// Axis domain with padding (JS `calculateChartDomain`). `bar` axes start at 0.
ThermalChartDomain calculateChartDomain(List<double> values, String unit) {
  var rawMin = double.infinity;
  var rawMax = double.negativeInfinity;
  for (final value in values) {
    rawMin = math.min(rawMin, value);
    rawMax = math.max(rawMax, value);
  }
  final range = rawMax - rawMin;
  final padding = math.max(range * 0.1, unit == '°C' ? 1.0 : 2.0);
  return ThermalChartDomain(
    min: unit == 'bar' ? 0 : rawMin - padding,
    max: rawMax + padding,
  );
}

/// Y coordinate of a reference value (JS `calculateReferenceLineY`).
double calculateReferenceLineY(
  double value,
  double minimum,
  double maximum,
  double plotHeight,
) {
  return _chartMarginTop +
      (1 - (value - minimum) / (maximum - minimum)) * plotHeight;
}

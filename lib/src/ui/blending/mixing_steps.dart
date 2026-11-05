import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/interim_measurements.dart';
import 'package:simplex_blender/src/domain/pressure_limits.dart';
import 'package:simplex_blender/src/domain/preset_validation.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/domain/units.dart';
import 'package:simplex_blender/src/ui/shell/tour_targets.dart';

// Source of truth: js/ui/results.js `renderProtocol` (step cards and interim
// index rule), `renderThermalDetails` (365-478), the interim measurement
// control (480-575), and the measurement lookup (613-621, 655-658).
// index.html 600-606 holds the `#mixing-steps-section` markup.

/// JS `SUMMARY_TOLERANCE` tolerance for the colour thresholds.
const double _summaryTolerance = 1e-9;

/// Recipe tab step-by-step protocol (JS `#mixing-steps-section`).
class MixingSteps extends StatelessWidget {
  const MixingSteps({super.key, required this.controller, required this.app});

  final BlendController controller;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[controller, app]),
      builder: (context, _) {
        final result = controller.lastResult;
        if (result == null || controller.lastInput == null) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        final units = app.settings.units;
        final pressureLimitMode = app.settings.pressureLimitMode;
        final feasible = result['feasible'] == true;
        final maximumValue = result['maximumPressure'];
        final maximum = maximumValue is Map<String, Object?>
            ? maximumValue
            : null;
        final steps = feasible
            ? _stepsOf(result['protocolSteps'])
            : _stepsOf(maximum?['protocolSteps']);
        final preset = controller.inputs.cylinderPreset;
        final cylinderSpec = CylinderPressureSpec(
          workingPressureBar: preset.workingPressureBar,
          hotOverfillPercent: preset.hotOverfillPercent,
        );
        final measurements = controller.interimMeasurements;

        return Column(
          key: TourTargetsScope.of(context).keyFor('mixing-steps-section'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Mixing steps',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            for (var index = 0; index < steps.length; index++)
              _StepCard(
                key: ValueKey<String>('step-$index'),
                controller: controller,
                steps: steps,
                index: index,
                measurements: measurements,
                units: units,
                cylinderSpec: cylinderSpec,
                cylinderPreset: preset,
                pressureLimitMode: pressureLimitMode,
              ),
          ],
        );
      },
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    super.key,
    required this.controller,
    required this.steps,
    required this.index,
    required this.measurements,
    required this.units,
    required this.cylinderSpec,
    required this.cylinderPreset,
    required this.pressureLimitMode,
  });

  final BlendController controller;
  final List<ProtocolStep> steps;
  final int index;
  final List<InterimMeasurement?> measurements;
  final String units;
  final CylinderPressureSpec cylinderSpec;
  final CylinderPreset cylinderPreset;
  final String pressureLimitMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final step = steps[index];
    final thermal = step.thermal;
    final isLast = index == steps.length - 1;
    final interimIndex = _interimIndexOf(step, index);
    final storedReading = _measurementFor(interimIndex, measurements);
    final showInterim =
        index > 0 &&
        step.type != 'keep' &&
        step.type != 'salvage' &&
        (step.type != 'drain' || storedReading != null) &&
        interimIndex != null;
    final resultingPressure =
        thermal != null && thermal.pressureAtTransferEndBar.isFinite
        ? thermal.pressureAtTransferEndBar
        : step.resultingPressureBar;
    final wait = step.automaticWaitMetadata;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (showInterim)
                  _InterimControl(
                    key: ValueKey<String>(
                      'interim-$interimIndex-${controller.interimMeasurementSignature}',
                    ),
                    controller: controller,
                    stepIndex: interimIndex,
                    nextStep: step,
                    stepNumber: protocolStepNumber(step, index),
                    measurement: storedReading,
                    measurements: measurements,
                    cylinderPreset: cylinderPreset,
                    pressureLimitMode: pressureLimitMode,
                    units: units,
                  ),
                Text(
                  _displayStepTitle(step, index, units),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (wait != null)
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: scheme.tertiary.withValues(alpha: 0.4),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _automaticWaitWarning(wait, thermal, units, step.title),
                        style: TextStyle(color: scheme.tertiary),
                      ),
                    ),
                  ),
                if (thermal != null)
                  _ThermalDetails(
                    thermal: thermal,
                    isFinalStep: isLast,
                    step: step,
                    units: units,
                    cylinderSpec: cylinderSpec,
                    measurement: _measurementFor(
                      thermal.measurementIndex,
                      measurements,
                    ),
                  ),
                if (step.type == 'salvage')
                  _SalvageDetails(step: step, units: units),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text('Result', style: TextStyle(color: scheme.onSurfaceVariant)),
              Text(
                formatUnitValue(
                  resultingPressure ?? double.nan,
                  'pressureBar',
                  units,
                ),
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// JS `renderProtocol` interim index: `thermal.measurementIndex` when the
/// thermal object is present, else the step's own `measurementIndex`, else the
/// step index (`results.js` 613-621).
int? _interimIndexOf(ProtocolStep step, int index) {
  final thermal = step.thermal;
  if (thermal != null) {
    return thermal.measurementIndex;
  }
  if (step.measurementIndexExplicitNull) {
    return null;
  }
  return step.measurementIndex ?? index;
}

/// JS measurement lookup (`results.js` 655-658).
InterimMeasurement? _measurementFor(
  int? index,
  List<InterimMeasurement?> measurements,
) {
  if (index == null || index < 0 || index >= measurements.length) {
    return null;
  }
  return measurements[index];
}

String _displayStepTitle(ProtocolStep step, int index, String units) {
  var title = (step.title ?? '').replaceFirst(
    RegExp(r'^Step\s+[0-9]+\s*:\s*', caseSensitive: false),
    '',
  );
  final settledPressureBar = step.thermal?.pressureAfterWaitBar;
  final sourceEnd = step.sourceEndPressureBar;
  if (step.type == 'equalize' &&
      sourceEnd != null &&
      sourceEnd.isFinite &&
      settledPressureBar != null &&
      settledPressureBar.isFinite &&
      sourceEnd < settledPressureBar - 1e-6) {
    title = title.replaceFirst(
      RegExp(r'^Equalize\b', caseSensitive: false),
      'Boost',
    );
  }
  final transferPressureBar = step.type == 'salvage'
      ? step.receiverEndPressureBar
      : step.thermal?.pressureAtTransferEndBar;
  if (transferPressureBar != null && transferPressureBar.isFinite) {
    title = title.replaceFirstMapped(
      RegExp(r'to [0-9]+(?:\.[0-9]+)? bar$', caseSensitive: false),
      (_) => 'to ${formatUnitValue(transferPressureBar, 'pressureBar', units)}',
    );
  }
  if (step.type == 'salvage') {
    return title;
  }
  return 'Step ${protocolStepNumber(step, index)}: $title';
}

String _automaticWaitWarning(
  Map<String, Object?> metadata,
  ThermalStep? thermal,
  String units,
  String? stepTitle,
) {
  final actual = _doubleOrNull(metadata['actualWaitMinutes']);
  final valueText = actual != null && actual.isFinite
      ? '${actual.toStringAsFixed(1)} min'
      : '—';
  final afterWait = thermal?.temperatureAfterWaitC;
  final temperature = afterWait != null && afterWait.isFinite
      ? ' or until temperature lower than ${formatUnitValue(afterWait, 'temperatureC', units)} is reached'
      : '';
  final identifier = metadata['stepIdentifier'] ?? stepTitle ?? 'step';
  return '⚠️ Adjusted cooloff: cylinder pressure limit reached ($identifier);\nWaiting time extended to $valueText$temperature.';
}

class _SalvageDetails extends StatelessWidget {
  const _SalvageDetails({required this.step, required this.units});

  final ProtocolStep step;
  final String units;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String pressure(double? value) => value != null && value.isFinite
        ? formatUnitValue(value, 'pressureBar', units)
        : '—';
    String mix(GasMixPercent? value) => value == null
        ? '—'
        : 'Tx ${_toFixed(value.oxygenPercent, 1)}/${_toFixed(value.heliumPercent, 1)}';
    final moved = step.movedHeliumLitres;
    final rows = <(String, String)>[
      ('Receiver', step.receiverBankName ?? '—'),
      (
        'Helium moved',
        moved != null && moved.isFinite
            ? formatUnitValue(moved, 'volumeL', units, 0)
            : '—',
      ),
      (
        'Receiver before',
        '${pressure(step.receiverStartPressureBar)} · ${mix(step.receiverStartMix)}',
      ),
      (
        'Receiver after',
        '${pressure(step.receiverEndPressureBar)} · ${mix(step.receiverEndMix)}',
      ),
    ];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final row in rows)
            Row(
              children: <Widget>[
                Expanded(child: Text(row.$1)),
                Text(row.$2),
              ],
            ),
        ],
      ),
    );
  }
}

/// JS `renderThermalDetails` (`results.js` 365-478).
class _ThermalDetails extends StatelessWidget {
  const _ThermalDetails({
    required this.thermal,
    required this.isFinalStep,
    required this.step,
    required this.units,
    required this.cylinderSpec,
    required this.measurement,
  });

  final ThermalStep thermal;
  final bool isFinalStep;
  final ProtocolStep step;
  final String units;
  final CylinderPressureSpec cylinderSpec;
  final InterimMeasurement? measurement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = thermal;
    final measuredPressure = measurement?.pressureBar;
    final measuredTemperature = measurement?.temperatureC;
    final hasManual =
        measurement != null &&
        ((measuredPressure != null && measuredPressure.isFinite) ||
            (measuredTemperature != null && measuredTemperature.isFinite));

    String pressure(double? value) => value != null && value.isFinite
        ? formatUnitValue(value, 'pressureBar', units)
        : '—';
    String temperature(double? value) => value != null && value.isFinite
        ? formatUnitValue(value, 'temperatureC', units)
        : '—';

    final addedWait = _doubleOrNull(
      step.automaticWaitMetadata?['addedWaitMinutes'],
    );
    final isExtendedWait = addedWait != null && addedWait > 0;
    final extendedColor = isExtendedWait
        ? scheme.tertiary
        : scheme.onSurfaceVariant;
    final isWaitOnly =
        step.type == 'wait' && t.rateSource == 'none' && t.waitMinutes > 0;
    final waitLabel = isFinalStep
        ? 'Final cool-off to ${temperature(t.temperatureAfterWaitC)} (${_formatThermalValue(t.waitMinutes)} min)'
        : '${_formatThermalValue(t.waitMinutes)} min';

    final manualRows = <_DetailRow>[
      if (hasManual && measuredPressure != null && measuredPressure.isFinite)
        _DetailRow(
          label: 'Start pressure',
          value: _ManualReading(
            planned: pressure(t.plannedStartPressureBar ?? t.pressureStartBar),
            actual: pressure(measuredPressure),
          ),
        ),
      if (hasManual &&
          measuredTemperature != null &&
          measuredTemperature.isFinite)
        _DetailRow(
          label: 'Start temperature',
          value: _ManualReading(
            planned: temperature(
              t.plannedStartTemperatureC ?? t.temperatureStartC,
            ),
            actual: temperature(measuredTemperature),
          ),
        ),
    ];

    final sourceEnd = step.sourceEndPressureBar;
    final sourceEndFinite = sourceEnd != null && sourceEnd.isFinite;
    final resultingMix = step.resultingMix;

    if (isWaitOnly) {
      final rows = <_DetailRow>[
        _DetailRow(
          label: 'Cooloff period',
          value: _PlainValue('${_formatThermalValue(t.waitMinutes)} min'),
          color: extendedColor,
        ),
        _DetailRow(
          label: 'Pressure after cooloff',
          value: _PlainValue(pressure(t.pressureAfterWaitBar)),
          color: _technicalPressureColor(
            scheme,
            t.pressureAfterWaitBar,
            cylinderSpec,
            false,
          ),
        ),
        _DetailRow(
          label: 'Temperature after cooloff',
          value: _PlainValue(temperature(t.temperatureAfterWaitC)),
        ),
        if (resultingMix != null)
          _DetailRow(
            label: 'Interim mix',
            value: _PlainValue(_mixText(resultingMix)),
          ),
        if (sourceEnd != null && sourceEnd.isFinite)
          _DetailRow(
            label: 'Source leftover pressure',
            value: _PlainValue(pressure(sourceEnd)),
            color: _sourceMinimumColor(scheme, step),
          ),
        ...manualRows,
      ];
      return _DetailGrid(rows: rows);
    }

    final rate = t.rateBarPerMin;
    final leftRows = <_DetailRow>[
      _DetailRow(
        label: 'Rate',
        value: _PlainValue(
          '${t.rateSource} · ${rate != null && rate.isFinite ? '${_toFixed(rate, 1)}/min' : '—'}',
        ),
      ),
      _DetailRow(
        label: 'Duration',
        value: _PlainValue('${_formatThermalValue(t.durationMinutes)} min'),
      ),
      _DetailRow(
        label: 'Pressure at transfer end',
        value: _PlainValue(pressure(t.pressureAtTransferEndBar)),
        color: _technicalPressureColor(
          scheme,
          t.pressureAtTransferEndBar,
          cylinderSpec,
          true,
        ),
      ),
      _DetailRow(
        label: 'Temperature at transfer end',
        value: _PlainValue(temperature(t.temperatureAtTransferEndC)),
      ),
    ];
    final rightRows = <_DetailRow>[
      if (sourceEndFinite)
        _DetailRow(
          label: 'Source leftover pressure',
          value: _PlainValue(pressure(sourceEnd)),
          color: _sourceMinimumColor(scheme, step),
        )
      else
        const _DetailRow.empty(),
      _DetailRow(
        label: 'Cooloff period',
        value: _PlainValue(waitLabel),
        color: extendedColor,
      ),
      _DetailRow(
        label: 'Pressure after cooloff',
        value: _PlainValue(pressure(t.pressureAfterWaitBar)),
        color: _technicalPressureColor(
          scheme,
          t.pressureAfterWaitBar,
          cylinderSpec,
          false,
        ),
      ),
      _DetailRow(
        label: 'Temperature after cooloff',
        value: _PlainValue(temperature(t.temperatureAfterWaitC)),
      ),
    ];
    final ratio = step.oxygenCompressionRatio;
    if (ratio != null && ratio.isFinite) {
      leftRows.add(
        _DetailRow(
          label: 'O₂ boost ratio',
          value: _PlainValue('${_toFixed(ratio, 2)}:1'),
          color: _oxygenCompressionRatioColor(scheme, ratio),
        ),
      );
      rightRows.add(const _DetailRow.empty());
    }
    if (resultingMix != null) {
      leftRows.add(
        _DetailRow(
          label: 'Interim mix',
          value: _PlainValue(_mixText(resultingMix)),
        ),
      );
      rightRows.add(const _DetailRow.empty());
    }
    if (manualRows.isNotEmpty) {
      leftRows.addAll(manualRows);
      rightRows.addAll(manualRows.map((_) => const _DetailRow.empty()));
    }
    final rows = <_DetailRow>[];
    for (var i = 0; i < leftRows.length; i++) {
      rows.add(leftRows[i]);
      rows.add(rightRows[i]);
    }
    return _DetailGrid(rows: rows);
  }
}

String _mixText(GasMixPercent mix) =>
    'Tx ${_toFixed(mix.oxygenPercent, 1)}/${_toFixed(mix.heliumPercent, 1)}';

String _formatThermalValue(double value) =>
    value.isFinite ? _toFixed(value, 1) : '—';

Color _technicalPressureColor(
  ColorScheme scheme,
  double pressureBar,
  CylinderPressureSpec? cylinder,
  bool isTransientHot,
) {
  final working = cylinder?.workingPressureBar;
  final limit = getCylinderPressureLimit(
    cylinder: cylinder,
    isTransientHot: isTransientHot,
  );
  if (!pressureBar.isFinite ||
      working == null ||
      !working.isFinite ||
      limit == null) {
    return scheme.onSurface;
  }
  if (pressureBar > limit.limitBar + _summaryTolerance) {
    return scheme.error;
  }
  if (pressureBar > working + _summaryTolerance) {
    return scheme.tertiary;
  }
  return scheme.onSurface;
}

Color _sourceMinimumColor(ColorScheme scheme, ProtocolStep step) {
  if (step.sourceExhausted == true) {
    return scheme.tertiary;
  }
  final sourceEnd = step.sourceEndPressureBar;
  final minimum = step.minimumSourcePressureBar;
  if (sourceEnd == null ||
      !sourceEnd.isFinite ||
      minimum == null ||
      !minimum.isFinite) {
    return scheme.onSurface;
  }
  return (sourceEnd - minimum).abs() <= _summaryTolerance
      ? scheme.tertiary
      : scheme.onSurface;
}

Color _oxygenCompressionRatioColor(ColorScheme scheme, double ratio) {
  if (ratio > 3.8) {
    return scheme.error;
  }
  if (ratio > 3.5) {
    return scheme.tertiary;
  }
  return scheme.onSurface;
}

sealed class _RowValue {
  const _RowValue();
}

class _PlainValue extends _RowValue {
  const _PlainValue(this.text);

  final String text;
}

class _ManualReading extends _RowValue {
  const _ManualReading({required this.planned, required this.actual});

  final String planned;
  final String actual;
}

class _DetailRow {
  const _DetailRow({required this.label, required this.value, this.color});

  const _DetailRow.empty()
    : label = '',
      value = const _PlainValue(''),
      color = null;

  final String label;
  final _RowValue value;
  final Color? color;
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.rows});

  final List<_DetailRow> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final row in rows)
            if (_isVisible(row))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        row.label,
                        style: TextStyle(
                          color: row.color ?? scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    switch (row.value) {
                      _PlainValue(:final text) => Text(
                        text,
                        style: TextStyle(color: row.color ?? scheme.onSurface),
                      ),
                      _ManualReading(:final planned, :final actual) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            planned,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          Text(' → ', style: TextStyle(color: scheme.tertiary)),
                          Text(
                            actual,
                            style: TextStyle(color: scheme.tertiary),
                          ),
                        ],
                      ),
                    },
                  ],
                ),
              ),
        ],
      ),
    );
  }

  static bool _isVisible(_DetailRow row) {
    if (row.label.isNotEmpty) {
      return true;
    }
    final value = row.value;
    return value is _PlainValue && value.text.isNotEmpty;
  }
}

// JS `renderInterimMeasurementControl` (results.js 480-575).
class _InterimControl extends StatefulWidget {
  const _InterimControl({
    super.key,
    required this.controller,
    required this.stepIndex,
    required this.nextStep,
    required this.stepNumber,
    required this.measurement,
    required this.measurements,
    required this.cylinderPreset,
    required this.pressureLimitMode,
    required this.units,
  });

  final BlendController controller;
  final int stepIndex;
  final ProtocolStep nextStep;
  final int stepNumber;
  final InterimMeasurement? measurement;
  final List<InterimMeasurement?> measurements;
  final CylinderPreset cylinderPreset;
  final String pressureLimitMode;
  final String units;

  @override
  State<_InterimControl> createState() => _InterimControlState();
}

class _InterimControlState extends State<_InterimControl> {
  late final TextEditingController _pressure;
  late final TextEditingController _temperature;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pressure = TextEditingController(text: _initialPressureText());
    _temperature = TextEditingController(text: _initialTemperatureText());
    _pressure.addListener(_onChanged);
    _temperature.addListener(_onChanged);
  }

  @override
  void dispose() {
    _pressure.dispose();
    _temperature.dispose();
    super.dispose();
  }

  void _onChanged() {
    setState(() {});
  }

  String _initialPressureText() {
    final value = widget.measurement?.pressureBar;
    return value == null
        ? ''
        : _displayText(convertToDisplay(value, 'pressureBar', widget.units));
  }

  String _initialTemperatureText() {
    final value = widget.measurement?.temperatureC;
    return value == null
        ? ''
        : _displayText(convertToDisplay(value, 'temperatureC', widget.units));
  }

  /// Upper pressure bound of the input (JS `pressureMaximumBar`).
  double get _pressureMaximumBar {
    if (widget.pressureLimitMode == 'warning') {
      return 350;
    }
    final working = widget.cylinderPreset.workingPressureBar;
    final hot = widget.cylinderPreset.hotOverfillPercent;
    final overfill = isValidHotOverfillPercent(hot)
        ? hot
        : defaultHotOverfillPercent;
    if (!working.isFinite) {
      return 350;
    }
    return math.min(350, working * (1 + overfill / 100));
  }

  /// Parsed value in internal units, or null when the field is empty,
  /// non-numeric, or outside [minBar, maxBar] (JS native validation).
  double? _parsed(
    TextEditingController field,
    String quantity,
    double minBar,
    double maxBar,
  ) {
    final text = field.text.trim();
    if (text.isEmpty) {
      return null;
    }
    final value = double.tryParse(text);
    if (value == null || !value.isFinite) {
      return null;
    }
    final internal = convertFromDisplay(value, quantity, widget.units);
    if (internal < minBar || internal > maxBar) {
      return null;
    }
    return internal;
  }

  double? get _pressureBar =>
      _parsed(_pressure, 'pressureBar', 0, _pressureMaximumBar);

  double? get _temperatureC => _parsed(_temperature, 'temperatureC', -20, 100);

  void _apply() {
    final pressure = _pressureBar;
    final temperature = _temperatureC;
    if (pressure == null || temperature == null) {
      return;
    }
    final message = widget.controller.applyInterimMeasurement(
      widget.stepIndex,
      (pressureBar: pressure, temperatureC: temperature),
    );
    setState(() {
      _error = message;
    });
  }

  void _clear() {
    final message = widget.controller.clearInterimMeasurement(widget.stepIndex);
    setState(() {
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final units = widget.units;
    final measurement = widget.measurement;
    final lockMessage = interimMeasurementLockMessage(
      widget.measurements,
      widget.stepIndex,
      'apply',
    );
    final recordedText = measurement == null
        ? null
        : 'Measured start for step ${widget.stepNumber}: ${formatUnitValue(measurement.pressureBar ?? double.nan, 'pressureBar', units)} · ${formatUnitValue(measurement.temperatureC ?? double.nan, 'temperatureC', units)}';
    if (lockMessage != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              recordedText ??
                  'No reading recorded before Step ${widget.stepNumber}',
            ),
            const Text(
              'Locked: only the latest reading can be changed or cleared.',
            ),
          ],
        ),
      );
    }
    final isLatest =
        measurement != null &&
        widget.stepIndex == latestInterimMeasurementIndex(widget.measurements);
    final pressureLabel = 'Pressure before “${widget.nextStep.title ?? ''}”';
    final temperatureLabel =
        'Temperature before “${widget.nextStep.title ?? ''}”';
    final canApply = _pressureBar != null && _temperatureC != null;
    final error = _error;
    return ExpansionTile(
      title: Text(
        recordedText ??
            'Record actual readings before Step ${widget.stepNumber}',
        style: TextStyle(color: scheme.primary),
      ),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 140,
              child: Semantics(
                label: pressureLabel,
                child: TextField(
                  controller: _pressure,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Pressure',
                    suffixText: unitLabel('pressureBar', units),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 140,
              child: Semantics(
                label: temperatureLabel,
                child: TextField(
                  controller: _temperature,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Temperature',
                    suffixText: unitLabel('temperatureC', units),
                  ),
                ),
              ),
            ),
            FilledButton.tonal(
              onPressed: canApply ? _apply : null,
              child: Text(measurement != null ? 'Update' : 'Apply'),
            ),
            if (isLatest)
              OutlinedButton(onPressed: _clear, child: const Text('Clear')),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(error, style: TextStyle(color: scheme.error)),
          ),
      ],
    );
  }
}

String _displayText(double value) => value.toString();

double? _doubleOrNull(Object? value) => value is double ? value : null;

String _toFixed(double value, int digits) =>
    value.isFinite ? value.toStringAsFixed(digits) : '—';

List<ProtocolStep> _stepsOf(Object? value) => value is List<Object?>
    ? value.whereType<ProtocolStep>().toList()
    : const <ProtocolStep>[];

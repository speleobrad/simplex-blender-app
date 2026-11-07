import 'package:flutter/material.dart';

import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/pressure_limits.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/domain/units.dart';
import 'package:simplex_blender/src/ui/blending/mixing_steps.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_format.dart';

/// JS `SUMMARY_TOLERANCE` (`results.js` line 52).
const double _summaryTolerance = 1e-9;

/// JS `SUMMARY_COLORS` (`results.js` lines 23-28), mapped to scheme roles.
enum _Tone { neutral, benefit, warning, problem }

Color _toneColor(ColorScheme scheme, _Tone tone) {
  return switch (tone) {
    _Tone.neutral => scheme.onSurface,
    _Tone.benefit => scheme.primary,
    _Tone.warning => scheme.tertiary,
    _Tone.problem => scheme.error,
  };
}

/// JS `INFEASIBILITY_SUMMARIES` (`results.js` lines 29-34).
const Map<String, String> _infeasibilitySummaries = <String, String>{
  'oxygen-boost-ratio': 'No feasible blend — the requested mix cannot be made safely with the available oxygen sources.',
  'working-pressure': 'No feasible blend — the requested mix exceeds the cylinder working-pressure limit.',
  'equipment-pressure-limit': 'No feasible blend — the requested mix exceeds an equipment pressure limit.',
  'insufficient-source-gas': 'No feasible blend — the combination and availability of source gases in the inventory does not allow this mix to be made in any quantity.',
};

/// JS `renderInfeasible` reason suffixes (`results.js` lines 223-228).
const Map<String, String> _reasonSuffixes = <String, String>{
  'oxygen-boost-ratio': 'due to unsafe oxygen boost ratio (maximum 4:1).',
  'working-pressure': 'due to exceeding the working pressure of the cylinder.',
  'equipment-pressure-limit': 'due to exceeding an equipment pressure limit.',
  'insufficient-source-gas': 'due to insufficient source gas.',
};

// ---------------------------------------------------------------------------
// Result-map helpers
// ---------------------------------------------------------------------------

Map<String, Object?>? _mapOrNull(Object? value) {
  return value is Map<String, Object?> ? value : null;
}

double? _num(Object? value) {
  return value is num ? value.toDouble() : null;
}

List<ProtocolStep> _stepsOf(Object? value) {
  return value is List<Object?>
      ? value.whereType<ProtocolStep>().toList(growable: false)
      : const <ProtocolStep>[];
}

List<CylinderPressureWarning> _warningsOf(Map<String, Object?> result) {
  final warnings = result['pressureLimitWarnings'];
  return warnings is List<Object?>
      ? warnings.whereType<CylinderPressureWarning>().toList(growable: false)
      : const <CylinderPressureWarning>[];
}

bool _finite(double? value) => value != null && value.isFinite;

String _pressureText(double? value, String units) =>
    formatUnitValueOrDash(value, 'pressureBar', units);

String _temperatureText(double? value, String units) =>
    formatUnitValueOrDash(value, 'temperatureC', units);

String _volumeText(double? value, String units) =>
    formatUnitValueOrDash(value, 'volumeL', units, 0);

String _fixedText(double? value, int digits) {
  return _finite(value) ? value!.toStringAsFixed(digits) : '—';
}

/// JS template-literal number formatting (`${value}`).
String _jsNumber(double? value) {
  if (value == null) {
    return 'undefined';
  }
  if (!value.isFinite) {
    return value.toString();
  }
  return value == value.truncateToDouble()
      ? value.toInt().toString()
      : value.toString();
}

// ---------------------------------------------------------------------------
// Tone rules (JS `results.js` 54-99)
// ---------------------------------------------------------------------------

/// JS `retainedGasColor`.
_Tone _retainedTone(double retainedPercent) {
  if (!retainedPercent.isFinite ||
      (retainedPercent > _summaryTolerance &&
          retainedPercent < 100 - _summaryTolerance)) {
    return _Tone.neutral;
  }
  return retainedPercent <= _summaryTolerance ? _Tone.problem : _Tone.benefit;
}

/// JS `ventedGasColor`.
_Tone _ventedTone(double retainedPercent) {
  if (!retainedPercent.isFinite) {
    return _Tone.neutral;
  }
  final ventedPercent = 100 - retainedPercent;
  if (ventedPercent <= _summaryTolerance) {
    return _Tone.benefit;
  }
  return ventedPercent >= 100 - _summaryTolerance
      ? _Tone.problem
      : _Tone.warning;
}

/// JS `pressureColor`.
_Tone _pressureTone(double? pressureBar, double? workingPressureBar) {
  if (_finite(pressureBar) &&
      _finite(workingPressureBar) &&
      pressureBar! > workingPressureBar! + _summaryTolerance) {
    return _Tone.problem;
  }
  return _Tone.neutral;
}

/// JS `inWaterPressureColor`.
_Tone _inWaterTone(
  double? pressureBar,
  double? targetPressureBar,
  double? workingPressureBar,
) {
  if (_pressureTone(pressureBar, workingPressureBar) == _Tone.problem) {
    return _Tone.problem;
  }
  if (!_finite(pressureBar) || !_finite(targetPressureBar)) {
    return _Tone.neutral;
  }
  return (pressureBar! - targetPressureBar!).abs() <= _summaryTolerance
      ? _Tone.benefit
      : _Tone.problem;
}

/// JS `renderBlendSummary` final-mix colour (`results.js` 703-711).
_Tone _mixTone({
  required double finalOxygenPercent,
  required double finalHeliumPercent,
  required double? targetOxygenPercent,
  required double? targetHeliumPercent,
}) {
  if (!_finite(targetOxygenPercent) || !_finite(targetHeliumPercent)) {
    return _Tone.neutral;
  }
  final matches =
      (finalOxygenPercent - targetOxygenPercent!).abs() <= _summaryTolerance &&
      (finalHeliumPercent - targetHeliumPercent!).abs() <= _summaryTolerance;
  return matches ? _Tone.benefit : _Tone.warning;
}

// ---------------------------------------------------------------------------
// Status text (JS `renderBlendStatus`, `results.js` 763-783)
// ---------------------------------------------------------------------------

/// JS `formatMaximumPressure` (`results.js` 163-183).
String _formatMaximumPressure(Map<String, Object?> maximum, String units) {
  final thermal = _mapOrNull(maximum['thermal']);
  final projected = _num(thermal?['finalInWaterPressureBar']);
  final pressureBar = _finite(projected)
      ? projected
      : _num(maximum['pressureBar']);
  if (!_finite(pressureBar)) {
    return '';
  }
  final temperatureC =
      _num(thermal?['requestedInWaterTemperatureC']) ??
      _num(thermal?['finalInWaterTemperatureC']);
  final temperature = _finite(temperatureC)
      ? ' at ${formatUnitValue(temperatureC!, 'temperatureC', units)}'
      : '';
  return '${formatUnitValue(pressureBar!, 'pressureBar', units)}$temperature';
}

// ---------------------------------------------------------------------------
// BlendStatusBox
// ---------------------------------------------------------------------------

/// Status box above the result tabs (JS `renderBlendStatus`,
/// `results.js` 763-783).
class BlendStatusBox extends StatelessWidget {
  const BlendStatusBox({
    super.key,
    required this.controller,
    required this.app,
  });

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
        final mode = app.settings.pressureLimitMode;
        final feasible = result['feasible'] == true;
        final maximum = _mapOrNull(result['maximumPressure']);

        final String statusText;
        final Color statusColor;
        if (feasible) {
          statusText = 'Feasible blend · target pressure is achievable with the current supply.';
          statusColor = scheme.primary;
        } else if (maximum != null) {
          final qualifier = mode == 'warning'
              ? 'maximum under active non-cylinder constraints is'
              : 'maximum safely achievable pressure is';
          statusText =
              'Target pressure limited · $qualifier ${_formatMaximumPressure(maximum, units)}.';
          statusColor = scheme.tertiary;
        } else {
          statusText =
              _infeasibilitySummaries[result['reasonCode'] as String?] ??
              'No feasible blend · review the target and enabled gas supply.';
          statusColor = scheme.error;
        }

        final warningLines = <String>[
          if (mode == 'warning')
            'Warning mode: cylinder limits are not enforced.',
          if (mode == 'warning')
            for (final warning in _warningsOf(result))
              pressureWarningText(warning, units),
        ];

        return Semantics(
          liveRegion: true,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  statusText,
                  style: TextStyle(color: statusColor, fontSize: 12),
                ),
                for (final line in warningLines)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      line,
                      style: TextStyle(
                        color: scheme.tertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// RecipePane
// ---------------------------------------------------------------------------

/// Recipe tab content: summary cards, infeasible message, then the mixing
/// steps (JS `renderResults`, `results.js` 999-1087, and `renderBlendSummary`,
/// `renderThermalSummary`).
class RecipePane extends StatelessWidget {
  const RecipePane({super.key, required this.controller, required this.app});

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
        final inputs = controller.inputs;
        final workingPressureBar = inputs.cylinderPreset.workingPressureBar;
        final feasible = result['feasible'] == true;
        final maximum = _mapOrNull(result['maximumPressure']);
        final gas = _mapOrNull(result['gas']);
        final diagnostics = _mapOrNull(result['diagnostics']);

        // JS `renderResults`: infeasible results summarise the maximum
        // pressure blend and steps when one exists.
        final blend = feasible
            ? _mapOrNull(result['blend'])
            : _mapOrNull(maximum?['blend']);
        final thermal = feasible
            ? _mapOrNull(result['thermal'])
            : _mapOrNull(result['thermal']) ?? _mapOrNull(maximum?['thermal']);
        final steps = feasible
            ? _stepsOf(result['protocolSteps'])
            : _stepsOf(maximum?['protocolSteps']);
        final targetInWaterFallback = feasible
            ? inputs.targetPressureBar
            : _num(gas?['targetPressureBar']);

        final cards = <Widget>[
          ..._blendCards(
            blend,
            units,
            scheme,
            inputs.targetOxygenPercent,
            inputs.targetHeliumPercent,
          ),
          ..._thermalCards(
            thermal,
            steps,
            units,
            scheme,
            workingPressureBar,
            targetInWaterFallback,
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(spacing: 12, runSpacing: 12, children: cards),
            if (!feasible) ...<Widget>[
              const SizedBox(height: 12),
              _InfeasibleMessage(
                text: _infeasibleText(
                  error: result['error'] as String?,
                  maximum: maximum,
                  requestedPressureBar: _num(gas?['targetPressureBar']),
                  oxygenPercent: _num(
                    _mapOrNull(maximum?['blend'])?['finalOxygenPercent'],
                  ),
                  heliumPercent: _num(
                    _mapOrNull(maximum?['blend'])?['finalHeliumPercent'],
                  ),
                  diagnostics: diagnostics,
                  thermal: thermal,
                  units: units,
                  pressureLimitMode: app.settings.pressureLimitMode,
                  reasonCode: result['reasonCode'] as String?,
                ),
                isMaximum: maximum != null,
              ),
            ],
            const SizedBox(height: 12),
            MixingSteps(controller: controller, app: app),
          ],
        );
      },
    );
  }
}

/// JS `renderBlendSummary` (`results.js` 688-712).
List<Widget> _blendCards(
  Map<String, Object?>? blend,
  String units,
  ColorScheme scheme,
  double targetOxygenPercent,
  double targetHeliumPercent,
) {
  final retainedPercent = _num(blend?['retainedPercent']) ?? double.nan;
  final retainedTone = blend == null
      ? _Tone.neutral
      : _retainedTone(retainedPercent);
  final ventedTone = blend == null
      ? _Tone.neutral
      : _ventedTone(retainedPercent);
  final heliumVented = _num(blend?['heliumVentedLitres']);
  final heliumSalvaged = _num(blend?['heliumSalvagedLitres']);
  final finalOxygen = _num(blend?['finalOxygenPercent']) ?? double.nan;
  final finalHelium = _num(blend?['finalHeliumPercent']) ?? double.nan;
  final mixTone = blend == null
      ? _Tone.neutral
      : _mixTone(
          finalOxygenPercent: finalOxygen,
          finalHeliumPercent: finalHelium,
          targetOxygenPercent: targetOxygenPercent,
          targetHeliumPercent: targetHeliumPercent,
        );
  return <Widget>[
    _SummaryCard(
      label: 'Retained gas',
      value: blend == null
          ? '—'
          : _pressureText(_num(blend['retainedPressureBar']), units),
      tone: retainedTone,
      detail: blend == null ? '—' : '${_fixedText(retainedPercent, 0)}% kept',
      detailTone: retainedTone,
    ),
    _SummaryCard(
      label: 'Helium vented',
      value: blend == null ? '—' : _volumeText(heliumVented, units),
      tone: ventedTone,
      detail: blend == null
          ? '—'
          : 'of ${_pressureText(_num(blend['ventedPressureBar']), units)}',
      detailTone: ventedTone,
    ),
    _SummaryCard(
      label: 'Helium salvaged',
      value: blend == null ? '—' : _volumeText(heliumSalvaged, units),
      tone:
          blend != null &&
              _finite(heliumSalvaged) &&
              heliumSalvaged! > _summaryTolerance
          ? _Tone.benefit
          : _Tone.neutral,
    ),
    _SummaryCard(
      label: 'Achieved mix',
      value: blend == null
          ? '—'
          : '${_fixedText(finalOxygen, 1)}/${_fixedText(finalHelium, 1)}',
      tone: mixTone,
    ),
  ];
}

/// JS `renderThermalSummary` (`results.js` 714-761).
List<Widget> _thermalCards(
  Map<String, Object?>? thermal,
  List<ProtocolStep> steps,
  String units,
  ColorScheme scheme,
  double workingPressureBar,
  double? targetInWaterFallback,
) {
  final thermalSteps = <ThermalStep>[
    for (final step in steps)
      if (step.thermal != null) step.thermal!,
  ];
  final temperatures = <double>[
    for (final state in thermalSteps) ...<double>[
      state.temperatureStartC,
      state.temperatureAtTransferEndC,
      state.temperatureAfterWaitC,
    ],
  ].where((value) => value.isFinite).toList(growable: false);
  var duration = 0.0;
  for (final state in thermalSteps) {
    duration += state.durationMinutes;
  }
  final waitedSteps = thermalSteps.isEmpty
      ? const <ThermalStep>[]
      : thermalSteps.take(thermalSteps.length - 1);
  for (final state in waitedSteps) {
    duration += state.waitMinutes;
  }
  final durationText = thermalSteps.isEmpty
      ? '—'
      : '${duration.toStringAsFixed(1)} min';
  final maxTemperatureText = temperatures.isEmpty
      ? '—'
      : formatUnitValue(
          temperatures.reduce((a, b) => a > b ? a : b),
          'temperatureC',
          units,
        );

  if (thermal == null) {
    return <Widget>[
      _SummaryCard(
        label: 'Fill duration',
        value: durationText,
        tone: _Tone.neutral,
      ),
      _SummaryCard(
        label: 'Max temperature',
        value: maxTemperatureText,
        tone: temperatures.isEmpty ? _Tone.neutral : _Tone.problem,
      ),
      const _SummaryCard(label: 'Hot mix', value: '—', tone: _Tone.neutral),
      const _SummaryCard(
        label: 'Ambient settled',
        value: '—',
        tone: _Tone.neutral,
      ),
      const _SummaryCard(label: 'In-water', value: '—', tone: _Tone.neutral),
    ];
  }

  final hotPressure = _num(thermal['finalTransferEndPressureBar']);
  final ambientPressure = _num(thermal['finalAmbientPressureBar']);
  final inWaterPressure =
      _num(thermal['finalInWaterPressureBar']) ??
      _num(thermal['requestedInWaterPressureBar']);
  final targetInWater =
      _num(thermal['requestedInWaterPressureBar']) ?? targetInWaterFallback;
  return <Widget>[
    _SummaryCard(
      label: 'Fill duration',
      value: durationText,
      tone: _Tone.neutral,
    ),
    _SummaryCard(
      label: 'Max temperature',
      value: maxTemperatureText,
      tone: temperatures.isEmpty ? _Tone.neutral : _Tone.problem,
    ),
    _SummaryCard(
      label: 'Hot mix',
      value: _pressureText(hotPressure, units),
      tone: _pressureTone(hotPressure, workingPressureBar),
      detail: _temperatureText(
        _num(thermal['finalTransferEndTemperatureC']),
        units,
      ),
      detailTone: _Tone.neutral,
    ),
    _SummaryCard(
      label: 'Ambient settled',
      value: _pressureText(ambientPressure, units),
      tone: _pressureTone(ambientPressure, workingPressureBar),
      detail: _temperatureText(
        _num(thermal['finalAmbientTemperatureC']),
        units,
      ),
      detailTone: _Tone.neutral,
    ),
    _SummaryCard(
      label: 'In-water',
      value: _pressureText(inWaterPressure, units),
      tone: _inWaterTone(inWaterPressure, targetInWater, workingPressureBar),
      detail: _temperatureText(
        _num(thermal['finalInWaterTemperatureC']),
        units,
      ),
      detailTone: _Tone.neutral,
    ),
  ];
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.tone,
    this.detail,
    this.detailTone = _Tone.neutral,
  });

  final String label;
  final String value;
  final _Tone tone;
  final String? detail;
  final _Tone detailTone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: textTheme.titleMedium?.copyWith(
              color: _toneColor(scheme, tone),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              style: textTheme.bodySmall?.copyWith(
                color: _toneColor(scheme, detailTone),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfeasibleMessage extends StatelessWidget {
  const _InfeasibleMessage({required this.text, required this.isMaximum});

  final String text;
  final bool isMaximum;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heading = isMaximum
        ? 'Requested Mix Is Unavailable'
        : 'No Feasible Blend';
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.1),
          border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              heading,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
        ),
      ),
    );
  }
}

/// Port of JS `renderInfeasible` description text (`results.js` 186-247),
/// including the diagnostic details (JS `renderDiagnosticDetails`).
String _infeasibleText({
  required String? error,
  required Map<String, Object?>? maximum,
  required double? requestedPressureBar,
  required double? oxygenPercent,
  required double? heliumPercent,
  required Map<String, Object?>? diagnostics,
  required Map<String, Object?>? thermal,
  required String units,
  required String pressureLimitMode,
  required String? reasonCode,
}) {
  final diagnosticDetails = _diagnosticDetails(diagnostics, units);
  final structuredReason =
      reasonCode ??
      ((error ?? '').contains('4:1') ? 'oxygen-boost-ratio' : null);
  final noPositiveQuantitySummary =
      _infeasibilitySummaries[structuredReason] ?? '';
  final safetyReason = (error ?? '').contains('4:1')
      ? (error!.split(' Maximum safe pressure')[0]).trim()
      : '';
  final targetTemperatureC = _num(thermal?['requestedInWaterTemperatureC']);
  final targetTemperature = _finite(targetTemperatureC)
      ? ' at target ${formatUnitValue(targetTemperatureC!, 'temperatureC', units)}'
      : '';
  final requestedMix =
      'The target mix (${_jsNumber(oxygenPercent)}/${_jsNumber(heliumPercent)})';
  final pressure =
      '${_pressureText(requestedPressureBar, units)}$targetTemperature';
  final reasonSuffix = _reasonSuffixes[structuredReason];
  final requestedPressureReason = reasonSuffix != null
      ? '$requestedMix cannot safely reach $pressure $reasonSuffix'
      : safetyReason.isNotEmpty
      ? '$requestedMix cannot safely reach $pressure.'
      : '$requestedMix cannot reach $pressure.';
  final maximumPressureDescription = maximum != null
      ? 'The maximum ${pressureLimitMode == 'warning' ? 'pressure under active non-cylinder constraints' : 'safely achievable pressure'} is ${_formatMaximumPressure(maximum, units)}.'
      : '';
  final settledPressure = _num(thermal?['finalAmbientPressureBar']);
  final settledEstimate = _finite(settledPressure)
      ? 'Predicted settled pressure is ${_pressureText(settledPressure, units)} at ${_temperatureText(_num(thermal?['finalAmbientTemperatureC']), units)}.'
      : '';
  final lines = maximum != null
      ? <String>[
          requestedPressureReason,
          diagnosticDetails,
          maximumPressureDescription,
          (structuredReason ?? '').isNotEmpty ? '' : safetyReason,
          settledEstimate,
        ]
      : <String>[
          noPositiveQuantitySummary.isNotEmpty
              ? noPositiveQuantitySummary
              : (error != null && error.isNotEmpty)
              ? error
              : 'The available gas banks cannot satisfy both the target pressure and exact gas fractions.',
          diagnosticDetails,
          settledEstimate,
        ];
  return lines.where((line) => line.isNotEmpty).join('\n');
}

/// Port of JS `renderDiagnosticDetails` (`results.js` 142-161).
String _diagnosticDetails(Map<String, Object?>? diagnostics, String units) {
  if (diagnostics == null) {
    return '';
  }
  final explainedBanks = <Object?>{};
  final details = <String>[];
  final shortfalls = diagnostics['componentShortfalls'];
  if (shortfalls is List<Object?>) {
    for (final raw in shortfalls) {
      final shortfall = _mapOrNull(raw);
      if (shortfall == null) {
        continue;
      }
      final component = shortfall['component'] as String? ?? '';
      final bank = _mapOrNull(shortfall['sourceBank']);
      if (bank == null) {
        details.add(
          'No enabled source bank can add ${component.toLowerCase()}.',
        );
        continue;
      }
      explainedBanks.add(bank['id']);
      final name = bank['name'] as String? ?? '';
      final volumeL = _jsNumber(_num(bank['volumeL']));
      final current = _pressureText(_num(bank['currentPressureBar']), units);
      final minimum = _pressureText(
        _num(bank['minimumSourcePressureBar']),
        units,
      );
      if (bank['pressureEstimateOutOfRange'] == true) {
        details.add(
          '$component shortfall: the pressure needed in $name ($volumeL L) is outside the supported real-gas density range. It is currently at $current ($minimum booster minimum).',
        );
      } else {
        final required = _pressureText(
          _num(bank['requiredPressureBar']),
          units,
        );
        final increase = _pressureText(
          _num(bank['pressureIncreaseBar']),
          units,
        );
        details.add(
          '$component shortfall: $name ($volumeL L) would need to be at $required to supply the missing gas. It is currently at $current ($minimum booster minimum), a $increase increase.',
        );
      }
    }
  }
  final exhausted = diagnostics['exhaustedBanks'];
  if (exhausted is List<Object?>) {
    for (final raw in exhausted) {
      final bank = _mapOrNull(raw);
      if (bank == null || explainedBanks.contains(bank['id'])) {
        continue;
      }
      details.add(
        '${bank['name'] as String? ?? ''} is fully drawn from ${_pressureText(_num(bank['currentPressureBar']), units)} to the ${_pressureText(_num(bank['minimumSourcePressureBar']), units)} booster minimum.',
      );
    }
  }
  return details.join('\n');
}

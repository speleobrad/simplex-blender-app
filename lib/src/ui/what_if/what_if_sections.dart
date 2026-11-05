import 'package:flutter/material.dart';
import 'package:simplex_blender/src/controllers/what_if_controller.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/thermal_chart_series.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/domain/ternary_geometry.dart';
import 'package:simplex_blender/src/domain/units.dart';
import 'package:simplex_blender/src/ui/blending/cost_summary.dart';
import 'package:simplex_blender/src/ui/results/ternary_diagram.dart';
import 'package:simplex_blender/src/ui/results/thermal_charts.dart';
import 'package:simplex_blender/src/ui/results/water_pressure_pane.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_format.dart';
import 'package:simplex_blender/src/domain/interim_measurements.dart';

/// Visible What-if result sections built from one successful [WhatIfRun]
/// (JS `renderWhatIfResults` and `renderWhatIfScenarioSummary`).
class WhatIfSections extends StatelessWidget {
  const WhatIfSections({super.key, required this.run, required this.units});

  final WhatIfRun run;
  final String units;

  @override
  Widget build(BuildContext context) {
    final effectiveUnits = units;
    final summary = run.simulation.finalSummary;
    final steps = run.simulation.protocolSteps;
    final input = run.input;
    final fillCost = computeFillCost(
      steps: <FillStep>[
        for (final step in steps)
          FillStep(
            costOperation: step.costOperation,
            costOperationId: step.costOperationId,
            sourceBankId: step.sourceBankId,
            recipeGas: step.recipeGas,
            sourceConsumedMoles: step.sourceConsumedMoles,
          ),
      ],
      banks: input.banks,
      costs: input.settings.costs,
      temperatureC: input.physicsTemperatureC ?? 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Section(
          title: 'Scenario summary',
          child: _ScenarioSummary(run: run, units: effectiveUnits),
        ),
        _Section(
          title: 'Recipe',
          child: _RecipeSteps(run: run, units: effectiveUnits),
        ),
        _Section(
          title: 'Thermal',
          child: ThermalCharts(
            series: buildThermalSeries(
              <ThermalProtocolStep>[
                for (final step in steps) _thermalStepOf(step),
              ],
              initial: ThermalInitialState(
                initialPressureBar: input.initialPressureBar,
                initialTemperatureC: input.physicsTemperatureC,
              ),
              terminalProjection: ThermalTerminalProjection(
                mode: 'what-if',
                pressureBar: summary.ambientSettled.pressureBar,
                temperatureC: summary.ambientSettled.temperatureC,
                durationMinutes: summary.ambientSettledDurationMinutes,
                inWaterPressureBar: summary.inWater?.pressureBar,
                inWaterTemperatureC: summary.inWater?.temperatureC,
              ),
            ),
            units: effectiveUnits,
            mode: 'what-if',
            ambientTemperatureC: input.ambientTemperatureC,
          ),
        ),
        _Section(
          title: 'Tanks and costs',
          child: CostSummary(
            cost: fillCost,
            units: effectiveUnits,
            currencySymbol: input.settings.costs.currencySymbol,
          ),
        ),
        _Section(
          title: 'Diagram',
          child: TernaryDiagram(
            banks: <TernaryBank>[
              for (final bank in input.banks)
                TernaryBank(
                  id: bank.id,
                  name: bank.name,
                  enabled: bank.enabled,
                  oxygenPercent: bank.oxygenPercent,
                  heliumPercent: bank.heliumPercent,
                  pressureBar: bank.pressureBar,
                ),
            ],
            trajectory: <TernaryTrajectoryPoint>[
              for (final point in run.protocol.trajectory)
                TernaryTrajectoryPoint(
                  label: point.label,
                  oxygenPercent: point.oxygenPercent,
                  heliumPercent: point.heliumPercent,
                  nitrogenPercent: point.nitrogenPercent,
                  step: point.step,
                  pressureBar: point.pressureBar,
                ),
            ],
          ),
        ),
        _Section(
          title: 'Water pressure',
          child: WaterPressurePane(
            pressureBar: summary.ambientSettled.pressureBar,
            oxygenPercent: summary.recipeEnd.oxygenPercent,
            heliumPercent: summary.recipeEnd.heliumPercent,
            fromTemperatureC: summary.ambientSettled.temperatureC,
            volumeL: input.cylinderPreset?.volumeL,
            workingPressureBar: input.cylinderPreset?.workingPressureBar,
            units: effectiveUnits,
            useVdw: input.physicsModel == 'vdw',
          ),
        ),
      ],
    );
  }
}

ThermalProtocolStep _thermalStepOf(ProtocolStep step) {
  final thermal = step.thermal;
  return ThermalProtocolStep(
    type: step.type,
    title: step.title,
    recipeLabel: step.recipeLabel,
    recipeAction: step.recipeAction,
    recipeGas: step.recipeGas,
    receiverStartPressureBar: step.receiverStartPressureBar,
    resultingPressureBar: step.resultingPressureBar,
    thermal: thermal == null
        ? null
        : ThermalStepThermal(
            durationMinutes: thermal.durationMinutes,
            waitMinutes: thermal.waitMinutes,
            measuredStartPressureBar: thermal.measuredStartPressureBar,
            measuredStartTemperatureC: thermal.measuredStartTemperatureC,
            measuredWaitMinutes: thermal.measuredWaitMinutes,
            temperatureStartC: thermal.temperatureStartC,
            temperatureAtTransferEndC: thermal.temperatureAtTransferEndC,
            pressureAtTransferEndBar: thermal.pressureAtTransferEndBar,
            temperatureAfterWaitC: thermal.temperatureAfterWaitC,
            pressureAfterWaitBar: thermal.pressureAfterWaitBar,
            samples: <ThermalInputSample>[
              for (final sample in thermal.samples)
                ThermalInputSample(
                  elapsedMinutes: sample.elapsedMinutes,
                  pressureBar: sample.pressureBar,
                  temperatureC: sample.temperatureC,
                ),
            ],
          ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// JS `formatCompareState`: pressure, optional temperature, and the mix.
String formatWhatIfState({
  required double pressureBar,
  required double? temperatureC,
  required double oxygenPercent,
  required double heliumPercent,
  required String units,
}) {
  final temperature = temperatureC != null && temperatureC.isFinite
      ? ' at ${formatUnitValue(temperatureC, 'temperatureC', units)}'
      : '';
  return '${formatUnitValue(pressureBar, 'pressureBar', units)}$temperature · '
      'Tx ${oxygenPercent.toStringAsFixed(1)}/${heliumPercent.toStringAsFixed(1)}';
}

class _ScenarioSummary extends StatelessWidget {
  const _ScenarioSummary({required this.run, required this.units});

  final WhatIfRun run;
  final String units;

  @override
  Widget build(BuildContext context) {
    final input = run.input;
    final start = run.protocol.initialMix;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Scenario start: ${formatWhatIfState(pressureBar: input.initialPressureBar ?? 0, temperatureC: input.physicsTemperatureC, oxygenPercent: start.oxygenPercent, heliumPercent: start.heliumPercent, units: units)}',
          key: const Key('what-if-scenario-start'),
        ),
        for (final warning in run.pressureLimitWarnings)
          Text(
            pressureWarningText(warning, units),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

class _RecipeSteps extends StatelessWidget {
  const _RecipeSteps({required this.run, required this.units});

  final WhatIfRun run;
  final String units;

  @override
  Widget build(BuildContext context) {
    final steps = run.simulation.protocolSteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < steps.length; index += 1)
          Card(
            key: Key('what-if-step-$index'),
            child: ListTile(
              title: Text(_stepTitle(steps[index], index, units)),
              subtitle: steps[index].recipeLabel == null
                  ? null
                  : Text(steps[index].recipeLabel!),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('Result'),
                  Text(
                    formatUnitValue(
                      _resultingPressure(steps[index]),
                      'pressureBar',
                      units,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

double _resultingPressure(ProtocolStep step) {
  final transfer = step.thermal?.pressureAtTransferEndBar;
  if (transfer != null && transfer.isFinite) {
    return transfer;
  }
  return step.resultingPressureBar ?? 0;
}

/// JS `displayStepTitle`: strips the stored `Step N:` prefix, renames a
/// boost-like equalize, rewrites the target pressure, and numbers the step.
String _stepTitle(ProtocolStep step, int index, String units) {
  var title = (step.title ?? '').replaceFirst(
    RegExp(r'^Step[ ]+[0-9]+[ ]*:[ ]*', caseSensitive: false),
    '',
  );
  final settled = step.thermal?.pressureAfterWaitBar;
  final source = step.sourceEndPressureBar;
  if (step.type == 'equalize' &&
      source != null &&
      source.isFinite &&
      settled != null &&
      settled.isFinite &&
      source < settled - 1e-6) {
    title = title.replaceFirst(
      RegExp(r'^Equalize\b', caseSensitive: false),
      'Boost',
    );
  }
  final transfer = step.type == 'salvage'
      ? step.receiverEndPressureBar
      : step.thermal?.pressureAtTransferEndBar;
  if (transfer != null && transfer.isFinite) {
    title = title.replaceFirst(
      RegExp(r'to [0-9]+(?:\.[0-9]+)? bar$', caseSensitive: false),
      'to ${formatUnitValue(transfer, 'pressureBar', units)}',
    );
  }
  if (step.type == 'salvage') {
    return title;
  }
  return 'Step ${protocolStepNumber(step, index)}: $title';
}

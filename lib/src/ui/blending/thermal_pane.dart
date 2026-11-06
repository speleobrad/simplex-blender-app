import 'package:flutter/material.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/thermal_chart_series.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/ui/results/thermal_charts.dart';

/// Blending thermal history pane (JS `renderThermalCharts`,
/// `js/ui/thermal-charts.js` lines 757-841, called from `js/main.js` with the
/// blending result).
class ThermalPane extends StatelessWidget {
  const ThermalPane({super.key, required this.controller, required this.app});

  final BlendController controller;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[controller, app]),
      builder: (context, _) {
        final result = controller.lastResult;
        final input = controller.lastInput;
        if (result == null || input == null) {
          return const SizedBox.shrink();
        }
        final thermal = _mapOrNull(result['thermal']);
        final cylinder = _mapOrNull(input['cylinder']);
        final physics = _mapOrNull(input['physics']);
        final inputThermal = _mapOrNull(input['thermal']);
        final gas = _mapOrNull(result['gas']);

        // JS `terminalProjection` (thermal-charts.js 774-780). Blending has no
        // mode, so the projection keeps the default null mode.
        final series = buildThermalSeries(
          <ThermalProtocolStep>[
            for (final step in _protocolStepsFor(result)) _thermalStepOf(step),
          ],
          initial: ThermalInitialState(
            initialPressureBar:
                _doubleOrNull(cylinder?['initialPressureBar']) ??
                _doubleOrNull(gas?['initialPressureBar']),
            initialTemperatureC: _doubleOrNull(physics?['temperatureC']),
          ),
          terminalProjection: ThermalTerminalProjection(
            pressureBar: _doubleOrNull(thermal?['finalAmbientPressureBar']),
            temperatureC: _doubleOrNull(thermal?['finalAmbientTemperatureC']),
            durationMinutes:
                _doubleOrNull(thermal?['finalAmbientCoolOffMinutes']) ?? 0,
            inWaterPressureBar: _doubleOrNull(
              thermal?['finalInWaterPressureBar'],
            ),
            inWaterTemperatureC: _doubleOrNull(
              thermal?['finalInWaterTemperatureC'],
            ),
          ),
        );

        // JS `input.thermal?.ambientTemperatureC ?? input.physics?.temperatureC`.
        final ambientTemperatureC =
            _doubleOrNull(inputThermal?['ambientTemperatureC']) ??
            _doubleOrNull(physics?['temperatureC']);

        return ThermalCharts(
          series: series,
          units: app.settings.units,
          mode: 'blending',
          ambientTemperatureC: ambientTemperatureC,
        );
      },
    );
  }
}

/// JS `protocolForResult` (thermal-charts.js 751-755) for a blending result:
/// feasible results use their own steps; otherwise the maximum-pressure steps,
/// falling back to the result's steps when the maximum has none.
List<ProtocolStep> _protocolStepsFor(Map<String, Object?> result) {
  if (result['feasible'] == true) {
    return _stepsOf(result['protocolSteps']);
  }
  final maximumSteps = _mapOrNull(result['maximumPressure'])?['protocolSteps'];
  if (maximumSteps is List<Object?>) {
    return _stepsOf(maximumSteps);
  }
  return _stepsOf(result['protocolSteps']);
}

List<ProtocolStep> _stepsOf(Object? value) {
  if (value is! List<Object?>) {
    return const <ProtocolStep>[];
  }
  return value.whereType<ProtocolStep>().toList(growable: false);
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
                  projectedPressureBar: sample.projectedPressureBar,
                  temperatureC: sample.temperatureC,
                  rateBarPerMin: sample.rateBarPerMin,
                ),
            ],
          ),
  );
}

Map<String, Object?>? _mapOrNull(Object? value) {
  return value is Map<String, Object?> ? value : null;
}

double? _doubleOrNull(Object? value) {
  return value is num ? value.toDouble() : null;
}

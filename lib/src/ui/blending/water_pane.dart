import 'package:flutter/material.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/ui/results/water_pressure_pane.dart';

/// In-water pressure pane (JS `renderWaterPressurePane` call sites in
/// `js/ui/results.js` lines 1016-1023 and 1102-1109).
///
/// Data comes from the result's thermal and blend maps; infeasible results use
/// the maximum-pressure blend (JS line 1016-1018). Cylinder and physics values
/// come from the calculator input, as JS `calculation.cylinder` and
/// `calculation.physics`.
class WaterPane extends StatelessWidget {
  const WaterPane({super.key, required this.controller, required this.app});

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
        final feasible = result['feasible'] == true;
        final maximum = _mapOrNull(result['maximumPressure']);
        final thermal = feasible
            ? _mapOrNull(result['thermal'])
            : _mapOrNull(result['thermal']) ?? _mapOrNull(maximum?['thermal']);
        final blend = feasible
            ? _mapOrNull(result['blend'])
            : _mapOrNull(maximum?['blend']);
        final cylinder = _mapOrNull(input['cylinder']);
        final physics = _mapOrNull(input['physics']);

        return WaterPressurePane(
          pressureBar: _doubleOrNull(thermal?['finalAmbientPressureBar']),
          oxygenPercent: _doubleOrNull(blend?['finalOxygenPercent']),
          heliumPercent: _doubleOrNull(blend?['finalHeliumPercent']),
          fromTemperatureC: _doubleOrNull(thermal?['finalAmbientTemperatureC']),
          volumeL: _doubleOrNull(cylinder?['volumeL']),
          workingPressureBar: _doubleOrNull(cylinder?['workingPressureBar']),
          units: app.settings.units,
          useVdw: physics?['model'] == 'vdw',
        );
      },
    );
  }
}

Map<String, Object?>? _mapOrNull(Object? value) {
  return value is Map<String, Object?> ? value : null;
}

double? _doubleOrNull(Object? value) {
  return value is num ? value.toDouble() : null;
}

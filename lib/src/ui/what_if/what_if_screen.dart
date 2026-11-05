import 'package:flutter/material.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/controllers/what_if_controller.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_results.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_rows.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_start_fields.dart';

/// What-if screen (JS `renderWhatIfScenarioEditor` and the What-if branch of
/// `renderCompareRecipe`). Edits the scenario through [WhatIfController] and
/// copies its starting state from [BlendController] inputs.
class WhatIfScreen extends StatelessWidget {
  const WhatIfScreen({
    super.key,
    required this.controller,
    required this.blend,
    required this.app,
  });

  final WhatIfController controller;
  final BlendController blend;
  final AppController app;

  void _copyFromBlending() {
    final inputs = blend.inputs;
    controller.copyFromBlending(
      initialPressureBar: inputs.initialPressureBar,
      initialOxygenPercent: inputs.initialOxygenPercent,
      initialHeliumPercent: inputs.initialHeliumPercent,
      ambientTemperatureC: inputs.ambientTemperatureC,
      coolingMedium: inputs.coolingMedium,
      waterSubmersionPercent: inputs.waterSubmersionPercent,
      targetInWaterTemperatureC: inputs.targetInWaterTemperatureC,
      cylinderPresetName: inputs.cylinderPreset.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[controller, app]),
      builder: (context, _) {
        final settings = app.settings;
        final status = controller.status;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              WhatIfStartFields(
                controller: controller,
                settings: settings,
                onCopyFromBlending: _copyFromBlending,
              ),
              const SizedBox(height: 16),
              WhatIfStepEditor(
                controller: controller,
                banks: app.banks,
                units: settings.units,
              ),
              if (status.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(status, key: const Key('what-if-status')),
                ),
              ],
              const SizedBox(height: 16),
              WhatIfResults(controller: controller, units: settings.units),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../../controllers/blend_controller.dart';
import '../../domain/ternary_geometry.dart';
import '../results/ternary_diagram.dart';
import 'ternary_data.dart';

/// The Simplex diagram tab of the Optimize result (JS `tab-pane-ternary`,
/// `js/main.js` 1397-1406 and `js/ui/ternary.js` 492-511, 613-633).
///
/// With no recipe, the diagram shows "No feasible blend" (JS
/// `clearTernaryDiagram`). With invalid composition data, the canvas is replaced
/// by the JS unavailable text.
class TernaryPane extends StatelessWidget {
  const TernaryPane({super.key, required this.controller, required this.app});

  final BlendController controller;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[controller, app]),
      builder: (context, _) {
        final inputs = blendingTernaryInputsOf(controller, app);
        if (inputs == null) {
          return const TernaryDiagram(
            banks: <TernaryBank>[],
            trajectory: <TernaryTrajectoryPoint>[],
            noFeasible: true,
          );
        }
        if (!inputs.valid) {
          return Text(
            invalidTernaryDataText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
        }
        return TernaryDiagram(
          banks: inputs.banks,
          trajectory: inputs.trajectory,
        );
      },
    );
  }
}

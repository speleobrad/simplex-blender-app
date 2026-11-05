import 'package:flutter/material.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/ui/blending/blending_form.dart';
import 'package:simplex_blender/src/ui/blending/blending_result_panel.dart';
import 'package:simplex_blender/src/ui/blending/transfer_conditions.dart';

/// Blending screen (JS `index.html` Blending column and results column).
///
/// Working tank inputs, transfer conditions, and the Optimize result panel.
/// There is no run button: JS recalculates on every input change
/// (`data-recalculate="input"`), and [BlendController] recalculates in
/// `setInputs`. The Compare path is not part of this screen.
class BlendingScreen extends StatelessWidget {
  const BlendingScreen({
    super.key,
    required this.controller,
    required this.app,
  });

  final BlendController controller;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          BlendingForm(controller: controller, app: app),
          const SizedBox(height: 16),
          TransferConditions(controller: controller, app: app),
          const SizedBox(height: 16),
          BlendingResultPanel(controller: controller, app: app),
        ],
      ),
    );
  }
}

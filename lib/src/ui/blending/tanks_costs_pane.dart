import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../../controllers/blend_controller.dart';
import 'cost_summary.dart';
import 'ternary_data.dart';
import 'ternary_data_tables.dart';

/// The Tanks and costs tab of the Optimize result (JS `tab-pane-summary`).
///
/// Order follows the JS markup: heading, accessible ternary tables, then costs
/// (`index.html` 666-748). Costs come from `controller.blendingCost()` (JS
/// `deriveFillCost(blendingCostSource())`) and `controller.blendingSavings()`
/// (JS `blendingSavings()`). Only the Optimize source is shown; the JS compare
/// branch of `blendingCostSource` is unreachable in Blending.
class TanksCostsPane extends StatelessWidget {
  const TanksCostsPane({
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
        if (controller.lastResult == null || controller.lastInput == null) {
          return const SizedBox.shrink();
        }
        final settings = app.settings;
        final symbol = settings.costs.currencySymbol;
        final cost = controller.blendingCost();
        final tables = blendingTernaryTablesOf(controller, app);
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Tanks and costs', style: theme.textTheme.titleSmall),
            TernaryDataTables(tables: tables),
            const SizedBox(height: 16),
            CostBanner(
              cost: cost,
              savings: controller.blendingSavings(),
              currencySymbol: symbol,
            ),
            const SizedBox(height: 16),
            CostSummary(
              cost: cost,
              units: settings.units,
              currencySymbol: symbol,
            ),
          ],
        );
      },
    );
  }
}

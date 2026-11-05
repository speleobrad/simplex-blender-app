import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../../controllers/blend_controller.dart';
import '../shell/tour_targets.dart';
import 'recipe_pane.dart';
import 'tanks_costs_pane.dart';
import 'ternary_pane.dart';
import 'thermal_pane.dart';
import 'water_pane.dart';

/// Result tab labels in JS order (`index.html` 493-507).
const List<String> _tabLabels = <String>[
  'Recipe',
  'Thermal Graph',
  'In-water pressure',
  'Tanks and costs',
  'Simplex diagram',
];

/// The Optimize result region of Blending (JS `result-panel-template`,
/// `index.html` 487-508). Renders nothing until a run exists.
class BlendingResultPanel extends StatelessWidget {
  const BlendingResultPanel({
    super.key,
    required this.controller,
    required this.app,
  });

  final BlendController controller;
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final result = controller.lastResult;
        if (result == null || controller.lastInput == null) {
          return const SizedBox.shrink();
        }
        final interimReadings = result['interimReadings'];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            BlendStatusBox(controller: controller, app: app),
            if (interimReadings is Map<String, Object?>)
              _InterimNotice(
                error: interimReadings['error'] is String
                    ? interimReadings['error'] as String
                    : null,
              ),
            const SizedBox(height: 8),
            _ResultTabs(controller: controller, app: app),
          ],
        );
      },
    );
  }
}

/// JS `renderInterimNotice` (`js/ui/results.js` 928-943).
class _InterimNotice extends StatelessWidget {
  const _InterimNotice({required this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failure = error;
    final text = failure != null
        ? 'Your reading is recorded, but the recipe could not be recalculated from it, so the planned steps are shown: $failure'
        : 'This recipe is a mix of planned steps and your interim manual readings.';
    return Semantics(
      container: true,
      label: 'Interim readings',
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: TextStyle(
            color: failure != null ? scheme.tertiary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Tab strip and the selected pane. Only the selected pane is built, which
/// keeps the scrolling page at its natural height.
class _ResultTabs extends StatefulWidget {
  const _ResultTabs({required this.controller, required this.app});

  final BlendController controller;
  final AppController app;

  @override
  State<_ResultTabs> createState() => _ResultTabsState();
}

class _ResultTabsState extends State<_ResultTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: _tabLabels.length,
    vsync: this,
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targets = TourTargetsScope.of(context);
    final controller = widget.controller;
    final app = widget.app;
    final panes = <Widget>[
      RecipePane(controller: controller, app: app),
      ThermalPane(controller: controller, app: app),
      WaterPane(controller: controller, app: app),
      TanksCostsPane(controller: controller, app: app),
      TernaryPane(controller: controller, app: app),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TabBar(
          key: targets.keyFor('results-tablist'),
          controller: _tabs,
          isScrollable: true,
          tabs: <Widget>[for (final label in _tabLabels) Tab(text: label)],
        ),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: _tabs,
          builder: (context, _) => panes[_tabs.index],
        ),
      ],
    );
  }
}

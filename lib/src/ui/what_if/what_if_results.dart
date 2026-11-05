import 'package:flutter/material.dart';
import 'package:simplex_blender/src/controllers/what_if_controller.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_sections.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_rows.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_start_fields.dart';

/// Result area of the What-if screen: stale notices, the result sections for
/// the last successful run, and errors that have no visible control.
class WhatIfResults extends StatelessWidget {
  const WhatIfResults({
    super.key,
    required this.controller,
    required this.units,
  });

  final WhatIfController controller;
  final String units;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final run = controller.lastRun;

    final children = <Widget>[];

    if (controller.isStale) {
      final String status = controller.sharedInputChanged
          ? 'Out of date — shared inputs changed. Update the scenario inputs.'
          : 'Out of date — scenario draft changed. Update the scenario inputs.';
      children.add(
        Container(
          key: const Key('what-if-stale-status'),
          padding: const EdgeInsets.all(8),
          color: colors.tertiaryContainer,
          child: Text(
            status,
            style: TextStyle(color: colors.onTertiaryContainer),
          ),
        ),
      );
      children.add(
        Container(
          key: const Key('what-if-stale-banner'),
          padding: const EdgeInsets.all(8),
          color: colors.tertiaryContainer,
          child: Text(
            'Scenario result is out of date. Update the scenario inputs.',
            style: TextStyle(color: colors.onTertiaryContainer),
          ),
        ),
      );
    }

    if (!controller.hasRun) {
      children.add(
        const Text(
          'Run the sequence to see the modeled result.',
          key: Key('what-if-empty-state'),
        ),
      );
    }

    for (final error in controller.fieldErrors) {
      final field = error.field;
      final isControlError =
          (error.rowId == null &&
              field != null &&
              whatIfStartErrorFields.contains(field)) ||
          (error.rowId != null &&
              field != null &&
              whatIfRowErrorFields.contains(field));
      if (isControlError) {
        continue;
      }
      children.add(Text(error.message, style: TextStyle(color: colors.error)));
    }

    if (run != null) {
      children.add(WhatIfSections(run: run, units: units));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final child in children) ...<Widget>[
          child,
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

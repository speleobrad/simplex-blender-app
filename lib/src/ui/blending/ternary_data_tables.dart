import 'package:flutter/material.dart';

import 'package:simplex_blender/src/domain/ternary_geometry.dart';
import 'package:simplex_blender/src/ui/blending/ternary_data.dart';

/// Status line and the two accessible tables under Tanks and costs (JS
/// `index.html` 668-693). Headers and captions stay visible when the bodies
/// are cleared, matching the JS markup.
class TernaryDataTables extends StatelessWidget {
  const TernaryDataTables({super.key, required this.tables});

  final BlendingTernaryTables tables;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mixRows = tables.data?.mixRows ?? const <TernaryMixRow>[];
    final trajectoryRows =
        tables.data?.trajectoryRows ?? const <TernaryTrajectoryRow>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            tables.status,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DataTable(
                caption: 'Reference mixes in Tanks and costs',
                headers: const <String>[
                  'Mix',
                  'O₂/He',
                  'Start pressure',
                  'End pressure',
                ],
                rows: <List<String>>[
                  for (final row in mixRows)
                    <String>[
                      row.label,
                      formatGasMix(
                        row.mix.oxygenPercent,
                        row.mix.heliumPercent,
                      ),
                      _pressureText(row.startPressureBar),
                      _pressureText(row.endPressureBar),
                    ],
                ],
              ),
              const SizedBox(height: 16),
              _DataTable(
                caption: 'Blend trajectory',
                headers: const <String>['Stage', 'O₂/He', 'Pressure'],
                rows: <List<String>>[
                  for (final row in trajectoryRows)
                    <String>[
                      row.label,
                      formatGasMix(
                        row.mix.oxygenPercent,
                        row.mix.heliumPercent,
                      ),
                      _pressureText(row.pressureBar),
                    ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// JS `chartDataRow` / `trajectoryDataRow` pressure cell (`js/ui/ternary.js`
/// 387, 410): `Number.isFinite` gates `toFixed(1)` plus " bar", else a dash.
String _pressureText(double? pressureBar) {
  return pressureBar == null || !pressureBar.isFinite
      ? '—'
      : '${pressureBar.toStringAsFixed(1)} bar';
}

class _DataTable extends StatelessWidget {
  const _DataTable({
    required this.caption,
    required this.headers,
    required this.rows,
  });

  final String caption;
  final List<String> headers;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final cellStyle = theme.textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(caption, style: theme.textTheme.bodyMedium),
        ),
        Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            TableRow(
              children: [
                for (final header in headers)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(header, style: headerStyle),
                  ),
              ],
            ),
            for (final row in rows)
              TableRow(
                children: [
                  for (final cell in row)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(cell, style: cellStyle),
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

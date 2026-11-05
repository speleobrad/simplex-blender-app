import 'package:flutter/material.dart';
import 'package:simplex_blender/src/domain/units.dart';
import 'package:simplex_blender/src/domain/water_pressure.dart';

/// In-water pressure pane (JS `renderWaterPressurePane`, `js/ui/water-pressure.js`).
///
/// Shows the heading and description, then the water and car temperature
/// pressure tables when the inputs yield projection data. With null or invalid
/// inputs only the heading and description are shown (the JS container is empty).
class WaterPressurePane extends StatelessWidget {
  const WaterPressurePane({
    super.key,
    required this.pressureBar,
    required this.oxygenPercent,
    required this.heliumPercent,
    required this.fromTemperatureC,
    required this.volumeL,
    required this.workingPressureBar,
    required this.units,
    this.useVdw = false,
  });

  /// JS `thermal.finalAmbientPressureBar`.
  final double? pressureBar;

  /// JS `blend.finalOxygenPercent`.
  final double? oxygenPercent;

  /// JS `blend.finalHeliumPercent`.
  final double? heliumPercent;

  /// JS `thermal.finalAmbientTemperatureC`.
  final double? fromTemperatureC;

  /// JS `calculation.cylinder.volumeL`.
  final double? volumeL;

  /// JS `calculation.cylinder.workingPressureBar`.
  final double? workingPressureBar;

  /// `'metric'` or `'imperial'`.
  final String units;

  /// JS `calculation.physics.model === 'vdw'`.
  final bool useVdw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = buildPressureProjectionData(
      pressureBar: pressureBar,
      oxygenPercent: oxygenPercent,
      heliumPercent: heliumPercent,
      fromTemperatureC: fromTemperatureC,
      volumeL: volumeL,
      workingPressureBar: workingPressureBar,
      useVdw: useVdw,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('In water pressure', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          'Estimated pressure-gauge readings after the cylinder equilibrates at each water temperature.',
          style: theme.textTheme.bodySmall,
        ),
        if (data != null) ...[
          const SizedBox(height: 16),
          _PressureSection(
            heading: 'Water temperatures',
            title: 'Water temperature',
            rows: data.water,
            workingPressureBar: workingPressureBar,
            units: units,
          ),
          const SizedBox(height: 16),
          _PressureSection(
            heading: 'Car temperatures',
            title: 'Car temperatures',
            rows: data.car,
            workingPressureBar: workingPressureBar,
            units: units,
          ),
        ],
      ],
    );
  }
}

class _PressureSection extends StatelessWidget {
  const _PressureSection({
    required this.heading,
    required this.title,
    required this.rows,
    required this.workingPressureBar,
    required this.units,
  });

  final String heading;
  final String title;
  final List<PressureProjectionRow> rows;
  final double? workingPressureBar;
  final String units;

  @override
  Widget build(BuildContext context) {
    final (first, second) = splitPressureProjections(rows);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PressureTable(
                title: '$title (1 of 2)',
                rows: first,
                workingPressureBar: workingPressureBar,
                units: units,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PressureTable(
                title: '$title (2 of 2)',
                rows: second,
                workingPressureBar: workingPressureBar,
                units: units,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PressureTable extends StatelessWidget {
  const _PressureTable({
    required this.title,
    required this.rows,
    required this.workingPressureBar,
    required this.units,
  });

  final String title;
  final List<PressureProjectionRow> rows;
  final double? workingPressureBar;
  final String units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final headerStyle = theme.textTheme.labelSmall;
    final temperatureUnit = unitLabel('temperature', units);
    final pressureUnit = unitLabel('pressure', units);
    final working = workingPressureBar;

    return Semantics(
      label: '$title pressure estimates',
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Expanded(child: Text('Temperature', style: headerStyle)),
                Expanded(
                  child: Text(
                    'Gauge pressure',
                    style: headerStyle,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          for (final row in rows)
            Builder(
              builder: (context) {
                final temperatureText =
                    '${convertToDisplay(row.temperatureC, 'temperature', units).toStringAsFixed(0)} $temperatureUnit';
                final pressureText =
                    '${convertToDisplay(row.pressureBar, 'pressure', units).toStringAsFixed(1)} $pressureUnit';
                final exceeds = row.exceedsWorkingPressure;
                final valueColor = exceeds ? colors.error : colors.primary;
                final warningText = exceeds && working != null
                    ? 'Exceeds cylinder working pressure of ${convertToDisplay(working, 'pressure', units).toStringAsFixed(1)} $pressureUnit'
                    : null;
                return Semantics(
                  label: '$temperatureText, $pressureText',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            temperatureText,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (warningText != null) ...[
                                Tooltip(
                                  message: warningText,
                                  child: Icon(
                                    Icons.warning_amber_rounded,
                                    size: 14,
                                    color: colors.error,
                                    semanticLabel: warningText,
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                pressureText,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: valueColor,
                                  fontWeight: exceeds
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

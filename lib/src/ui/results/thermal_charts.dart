// Thermal Graph pane: port of js/ui/thermal-charts.js (renderThermalCharts,
// renderChart, renderDataTable and the hover/focus interactions). The series is
// built by the caller with buildThermalSeries; this file converts units for
// display, draws the two charts and handles hover and focus.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:simplex_blender/src/domain/thermal_chart_series.dart';
import 'package:simplex_blender/src/domain/units.dart';

const double _chartWidth = 720;
const double _chartHeight = 300;
const double _marginTop = 28;
const double _marginRight = 18;
const double _marginBottom = 48;
const double _marginLeft = 58;
const double _plotWidth = _chartWidth - _marginLeft - _marginRight;
const double _plotHeight = _chartHeight - _marginTop - _marginBottom;
const double _pointHitSize = 16;

const String _headingText = 'Blending thermal history';
const String _emptyStatusText =
    'Chart data appears when a completed blend protocol is available.';
const String _hoverDefaultText =
    'Hover either graph to inspect time, temperature, and pressure.';
const String _emptyChartText =
    'Chart data appears when a blend protocol is available.';
const String _tableCaption = 'Temperature and pressure chart data';
const String _temperatureChartLabel = 'Temperature history chart';
const String _pressureChartLabel = 'Pressure history chart';
const String _temperatureToken = 'var(--chart-feasible)';
const String _pressureToken = 'var(--chart-helium)';
const String _inkToken = 'currentColor';
const String _gridToken = 'var(--chart-grid)';
const String _oddBandToken = 'rgb(var(--ocean-850))';
const String _labelToken = 'var(--chart-label)';
const String _markerOutlineToken = 'var(--chart-marker-outline)';
const List<String> _inWaterTitles = [
  'In-water target projection',
  'In-water projection',
];
const List<String> _tableHeaders = [
  'Time',
  'Step',
  'Phase',
  'Temperature',
  'Pressure',
];

/// Thermal Graph pane body.
///
/// [series] comes from `buildThermalSeries`. [units] is `'metric'` or
/// `'imperial'`. [mode] mirrors JS `result.mode` (`'blending'`, `'compare'` or
/// `'what-if'`) and only selects the status wording. [ambientTemperatureC] is
/// JS `input.thermal?.ambientTemperatureC ?? input.physics?.temperatureC` in
/// metric °C and draws the dashed ambient reference line on the temperature
/// chart when finite.
class ThermalCharts extends StatelessWidget {
  const ThermalCharts({
    super.key,
    required this.series,
    required this.units,
    this.mode = 'blending',
    this.ambientTemperatureC,
  });

  final ThermalSeries series;
  final String units;
  final String mode;
  final double? ambientTemperatureC;

  @override
  Widget build(BuildContext context) {
    return _ThermalChartsView(
      series: series,
      units: units,
      mode: mode,
      ambientTemperatureC: ambientTemperatureC,
    );
  }
}

class _ThermalChartsView extends StatefulWidget {
  const _ThermalChartsView({
    required this.series,
    required this.units,
    required this.mode,
    required this.ambientTemperatureC,
  });

  final ThermalSeries series;
  final String units;
  final String mode;
  final double? ambientTemperatureC;

  @override
  State<_ThermalChartsView> createState() => _ThermalChartsViewState();
}

class _ThermalChartsViewState extends State<_ThermalChartsView> {
  /// Hover reading in display units. Null shows the default readout text.
  ThermalSeriesSample? _reading;

  /// Index of the point highlighted by pointer or focus (JS
  /// `.thermal-point-active`), shared by both charts and the table.
  int? _activePoint;

  @override
  void didUpdateWidget(_ThermalChartsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // JS renderThermalCharts calls clearThermalHover on every render.
    if (oldWidget.series != widget.series || oldWidget.units != widget.units) {
      _reading = null;
      _activePoint = null;
    }
  }

  void _clearReading() {
    if (_reading == null) {
      return;
    }
    setState(() => _reading = null);
  }

  void _enterPoint(_DisplaySeries display, int index) {
    setState(() {
      _activePoint = index;
      _reading = display.points[index].reading;
    });
  }

  void _leavePoint(int index) {
    if (_activePoint != index) {
      return;
    }
    setState(() => _activePoint = null);
  }

  /// JS handleChartMove: map the pointer x to minutes and interpolate the series.
  void _moveOverChart(_DisplaySeries display, Offset view) {
    final inside =
        view.dy >= _marginTop && view.dy <= _chartHeight - _marginBottom;
    if (!inside || display.hoverSamples.isEmpty) {
      _clearReading();
      return;
    }
    final fraction = math.min(
      1.0,
      math.max(0.0, (view.dx - _marginLeft) / _plotWidth),
    );
    final sample = interpolateThermalSample(
      display.hoverSamples,
      fraction * display.maximumTime,
    );
    if (sample == null) {
      _clearReading();
      return;
    }
    setState(() => _reading = display.toDisplay(sample));
  }

  String _statusText(_DisplaySeries display) {
    final finalPoint = display.finalPoint;
    if (finalPoint == null) {
      return _emptyStatusText;
    }
    final whatIf = widget.mode == 'what-if';
    final inWaterPhase = whatIf ? 'in-water-projection' : 'in-water-target';
    _DisplayPoint? inWater;
    for (final point in display.points) {
      if (point.source.phase == inWaterPhase) {
        inWater = point;
        break;
      }
    }
    final projection = inWater == null
        ? ''
        : ' ${whatIf ? 'Explicit in-water projection' : 'In-water target projection'}: '
              '${_fixed1(inWater.reading.pressureBar)} ${display.pressureUnit} at '
              '${_fixed1(inWater.reading.temperatureC)} ${display.temperatureUnit}.';
    final modeWord = whatIf
        ? 'What-if'
        : widget.mode == 'compare'
        ? 'compare recipe'
        : 'blending';
    final step = finalPoint.source.step;
    final reading = finalPoint.reading;
    return '$step $modeWord step${step == 1 ? '' : 's'} shown over '
        '${_fixed1(reading.elapsedMinutes)} minutes; final point is the '
        'ambient-settled tank state at ${_fixed1(reading.pressureBar)} '
        '${display.pressureUnit} and ${_fixed1(reading.temperatureC)} '
        '${display.temperatureUnit}.$projection';
  }

  String _readoutText(_DisplaySeries display) {
    final reading = _reading;
    if (reading == null) {
      return _hoverDefaultText;
    }
    return 'Time: ${_fixed1(reading.elapsedMinutes)} min · '
        'Temperature: ${_fixed1(reading.temperatureC)} ${display.temperatureUnit} · '
        'Pressure: ${_fixed1(reading.pressureBar)} ${display.pressureUnit}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final display = _DisplaySeries(widget.series, widget.units);
    final hasPoints = display.points.isNotEmpty;

    final ambient = widget.ambientTemperatureC;
    _ReferenceLine? ambientLine;
    if (ambient != null && ambient.isFinite) {
      final ambientDisplay = convertToDisplay(
        ambient,
        'temperature',
        widget.units,
      );
      ambientLine = _ReferenceLine(
        value: ambientDisplay,
        label: 'Ambient ${_fixed1(ambientDisplay)} ${display.temperatureUnit}',
      );
    }

    final temperatureSpec = hasPoints
        ? _ChartSpec(
            title: 'Temperature',
            unit: display.temperatureUnit,
            key: ThermalSampleKey.temperatureC,
            colorToken: _temperatureToken,
            domain: calculateChartDomain(
              _domainValues(display, ThermalSampleKey.temperatureC),
              display.temperatureUnit,
            ),
            referenceLine: ambientLine,
          )
        : null;
    final pressureSpec = hasPoints
        ? _ChartSpec(
            title: 'Pressure',
            unit: display.pressureUnit,
            key: ThermalSampleKey.pressureBar,
            colorToken: _pressureToken,
            domain: calculateChartDomain(
              _domainValues(display, ThermalSampleKey.pressureBar),
              display.pressureUnit,
            ),
            referenceLine: null,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _headingText,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            _statusText(display),
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ),
        Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _readoutText(display),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: colors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _frame(
          colors,
          label: _temperatureChartLabel,
          child: temperatureSpec == null
              ? _emptyChartBody(colors)
              : _ThermalChartView(
                  spec: temperatureSpec,
                  display: display,
                  reading: _reading,
                  activePoint: _activePoint,
                  onMove: (view) => _moveOverChart(display, view),
                  onExit: _clearReading,
                  onPointEnter: (index) => _enterPoint(display, index),
                  onPointExit: _leavePoint,
                ),
        ),
        const SizedBox(height: 16),
        _frame(
          colors,
          label: _pressureChartLabel,
          child: pressureSpec == null
              ? _emptyChartBody(colors)
              : _ThermalChartView(
                  spec: pressureSpec,
                  display: display,
                  reading: _reading,
                  activePoint: _activePoint,
                  onMove: (view) => _moveOverChart(display, view),
                  onExit: _clearReading,
                  onPointEnter: (index) => _enterPoint(display, index),
                  onPointExit: _leavePoint,
                ),
        ),
        const SizedBox(height: 16),
        _frame(
          colors,
          child: hasPoints
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _dataTable(display, colors),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// JS renderDataTable. Non-terminal steps span three rows: the step cell is
  /// shown on the first row only (Flutter tables have no rowSpan). Rows of odd
  /// steps carry the band tint (JS `thermal-band-odd`), and every row is
  /// focusable with its own description.
  Widget _dataTable(_DisplaySeries display, ColorScheme colors) {
    final headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: colors.onSurfaceVariant,
    );
    final rows = <TableRow>[
      TableRow(
        children: [
          for (final header in _tableHeaders)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(header, style: headerStyle),
            ),
        ],
      ),
    ];
    final points = display.points;
    var index = 0;
    while (index < points.length) {
      final point = points[index];
      rows.add(
        _pointRow(display, colors, index, _stepContent(point.source, colors)),
      );
      if (isThermalTerminalProjection(point.source.phase)) {
        index += 1;
        continue;
      }
      for (
        var offset = 1;
        offset < 3 && index + offset < points.length;
        offset++
      ) {
        rows.add(_pointRow(display, colors, index + offset, null));
      }
      index += 3;
    }
    return Semantics(
      container: true,
      label: _tableCaption,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder(
          horizontalInside: BorderSide(color: colors.outlineVariant),
        ),
        children: rows,
      ),
    );
  }

  TableRow _pointRow(
    _DisplaySeries display,
    ColorScheme colors,
    int index,
    Widget? stepContent,
  ) {
    final point = display.points[index];
    final source = point.source;
    final description = _pointDescription(point, display);
    final cellStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      color: colors.onSurface,
    );

    Widget cell(Widget child, {bool focusable = false}) {
      Widget wrapped = MouseRegion(
        onEnter: (_) => _enterPoint(display, index),
        onExit: (_) => _leavePoint(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: child,
        ),
      );
      if (focusable) {
        wrapped = Focus(
          onFocusChange: (focused) {
            if (focused) {
              _enterPoint(display, index);
            } else {
              _leavePoint(index);
            }
          },
          child: Semantics(label: description, child: wrapped),
        );
      }
      return wrapped;
    }

    return TableRow(
      decoration: _activePoint == index
          ? BoxDecoration(color: colors.primary.withValues(alpha: 0.15))
          : _bandColor(source.step, colors) == null
          ? null
          : BoxDecoration(color: _bandColor(source.step, colors)),
      children: [
        cell(
          Align(
            alignment: Alignment.centerRight,
            child: Text(source.timeLabel, style: cellStyle),
          ),
          focusable: true,
        ),
        cell(stepContent ?? const SizedBox.shrink()),
        cell(Text(_phaseLabel(source.phase), style: cellStyle)),
        cell(
          Text(
            '${_fixed1(point.reading.temperatureC)} ${display.temperatureUnit}',
            style: cellStyle,
          ),
        ),
        cell(
          Text(
            '${_fixed1(point.reading.pressureBar)} ${display.pressureUnit}',
            style: cellStyle,
          ),
        ),
      ],
    );
  }
}

/// One chart: title, unit, plotted quantity, colour token, domain and the
/// optional ambient reference line.
class _ChartSpec {
  const _ChartSpec({
    required this.title,
    required this.unit,
    required this.key,
    required this.colorToken,
    required this.domain,
    required this.referenceLine,
  });

  final String title;
  final String unit;
  final ThermalSampleKey key;
  final String colorToken;
  final ThermalChartDomain domain;
  final _ReferenceLine? referenceLine;
}

class _ReferenceLine {
  const _ReferenceLine({required this.value, required this.label});

  final double value;
  final String label;
}

class _DisplayPoint {
  const _DisplayPoint({required this.source, required this.reading});

  final ThermalSeriesPoint source;

  /// The point's values in display units.
  final ThermalSeriesSample reading;
}

class _DisplaySegment {
  const _DisplaySegment({required this.style, required this.samples});

  final ThermalSegmentStyle style;

  /// Samples in display units.
  final List<ThermalSeriesSample> samples;
}

/// JS `displaySeries`: the domain series converted to display units.
class _DisplaySeries {
  _DisplaySeries._({
    required this.units,
    required this.pressureUnit,
    required this.temperatureUnit,
    required this.points,
    required this.samples,
    required this.segments,
    required this.bands,
    required this.finalPoint,
    required this.hoverSamples,
    required this.maximumTime,
  });

  factory _DisplaySeries(ThermalSeries series, String units) {
    final finalSource = series.finalPoint;
    return _DisplaySeries._(
      units: units,
      pressureUnit: unitLabel('pressure', units),
      temperatureUnit: unitLabel('temperature', units),
      points: [
        for (final point in series.points)
          _DisplayPoint(
            source: point,
            reading: _displayAt(
              point.elapsedMinutes,
              point.temperatureC,
              point.pressureBar,
              units,
            ),
          ),
      ],
      samples: [
        for (final sample in series.samples)
          _displayAt(
            sample.elapsedMinutes,
            sample.temperatureC,
            sample.pressureBar,
            units,
          ),
      ],
      segments: [
        for (final segment in series.segments)
          _DisplaySegment(
            style: segment.style,
            samples: [
              for (final sample in segment.samples)
                _displayAt(
                  sample.elapsedMinutes,
                  sample.temperatureC,
                  sample.pressureBar,
                  units,
                ),
            ],
          ),
      ],
      bands: series.bands,
      finalPoint: finalSource == null
          ? null
          : _DisplayPoint(
              source: finalSource,
              reading: _displayAt(
                finalSource.elapsedMinutes,
                finalSource.temperatureC,
                finalSource.pressureBar,
                units,
              ),
            ),
      // JS state.samples: in-water projection samples are excluded from hover.
      hoverSamples: [
        for (final sample in series.samples)
          if (!_inWaterTitles.contains(sample.title)) sample,
      ],
      maximumTime: series.points.isEmpty
          ? 1.0
          : math.max(1.0, series.points.last.elapsedMinutes),
    );
  }

  final String units;
  final String pressureUnit;
  final String temperatureUnit;
  final List<_DisplayPoint> points;
  final List<ThermalSeriesSample> samples;
  final List<_DisplaySegment> segments;
  final List<ThermalSeriesBand> bands;
  final _DisplayPoint? finalPoint;

  /// Raw domain samples in metric units; the hover interpolates these and then
  /// converts the result, as JS interpolates before display.
  final List<ThermalSeriesSample> hoverSamples;
  final double maximumTime;

  ThermalSeriesSample toDisplay(ThermalSeriesSample sample) => _displayAt(
    sample.elapsedMinutes,
    sample.temperatureC,
    sample.pressureBar,
    units,
  );

  /// Curves to draw. Falls back to one observed curve through the samples (or
  /// the points when there are no samples), as JS renderChart does.
  List<_DisplaySegment> get curves {
    if (segments.isNotEmpty) {
      return segments;
    }
    final fallback = samples.isNotEmpty
        ? samples
        : [for (final point in points) point.reading];
    return [
      _DisplaySegment(style: ThermalSegmentStyle.observed, samples: fallback),
    ];
  }
}

ThermalSeriesSample _displayAt(
  double elapsedMinutes,
  double temperatureC,
  double pressureBar,
  String units,
) {
  return ThermalSeriesSample(
    elapsedMinutes: elapsedMinutes,
    temperatureC: convertToDisplay(temperatureC, 'temperature', units),
    pressureBar: convertToDisplay(pressureBar, 'pressure', units),
  );
}

List<double> _domainValues(_DisplaySeries display, ThermalSampleKey key) {
  final readings = display.samples.isNotEmpty
      ? display.samples
      : [for (final point in display.points) point.reading];
  return [for (final reading in readings) _valueOf(reading, key)];
}

double _valueOf(ThermalSeriesSample sample, ThermalSampleKey key) =>
    key == ThermalSampleKey.pressureBar
    ? sample.pressureBar
    : sample.temperatureC;

double _xFor(double minutes, double maximumTime) =>
    _marginLeft + (minutes / maximumTime) * _plotWidth;

double _yFor(double value, ThermalChartDomain domain) =>
    calculateReferenceLineY(value, domain.min, domain.max, _plotHeight);

Offset _toView(Offset local, Size size) => Offset(
  local.dx * _chartWidth / size.width,
  local.dy * _chartHeight / size.height,
);

Offset _toPixel(Offset view, Size size) => Offset(
  view.dx * size.width / _chartWidth,
  view.dy * size.height / _chartHeight,
);

String _fixed1(double value) => value.toStringAsFixed(1);

/// JS formatValue: integers as-is, everything else to one decimal.
String _formatValue(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

/// JS phaseLabel (private in the domain file, so mirrored for the table).
String _phaseLabel(String phase) {
  return switch (phase) {
    'transfer-end' => 'transfer end',
    'settled' => 'ambient settled',
    'ambient-settled' => 'ambient-settled projection',
    'in-water-projection' => 'explicit in-water projection',
    'in-water-target' => 'in-water target projection',
    'measured-start' => 'measured start',
    _ => 'step start',
  };
}

/// JS pointDescription.
String _pointDescription(_DisplayPoint point, _DisplaySeries display) {
  final source = point.source;
  final label = source.label.isNotEmpty ? source.label : source.title;
  return '$label, ${_phaseLabel(source.phase)}, '
      '${_fixed1(point.reading.elapsedMinutes)} minutes, '
      '${_fixed1(point.reading.temperatureC)} ${display.temperatureUnit}, '
      '${_fixed1(point.reading.pressureBar)} ${display.pressureUnit}';
}

/// JS `thermal-band-even|odd` by `(step - 1) % 2`; even bands are untinted.
Color? _bandColor(int step, ColorScheme colors) {
  if ((step - 1) % 2 == 0) {
    return null;
  }
  return colors.surfaceContainerHighest.withValues(alpha: 0.5);
}

Widget _stepContent(ThermalSeriesPoint source, ColorScheme colors) {
  final style = TextStyle(fontSize: 12, color: colors.onSurface);
  final action = source.recipeAction;
  final gas = source.recipeGas;
  if (action != null && action.isNotEmpty && gas != null && gas.isNotEmpty) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(action, style: style),
        Text(gas, style: style),
      ],
    );
  }
  return Text(source.title, style: style);
}

Widget _emptyChartBody(ColorScheme colors) => Padding(
  padding: const EdgeInsets.all(16),
  child: Text(
    _emptyChartText,
    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
  ),
);

Widget _frame(ColorScheme colors, {String? label, required Widget child}) {
  return Semantics(
    container: true,
    label: label,
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    ),
  );
}

/// One chart (JS renderChart). Pointer events are routed to the parent state;
/// point markers are focusable targets positioned over the paint.
class _ThermalChartView extends StatelessWidget {
  const _ThermalChartView({
    required this.spec,
    required this.display,
    required this.reading,
    required this.activePoint,
    required this.onMove,
    required this.onExit,
    required this.onPointEnter,
    required this.onPointExit,
  });

  final _ChartSpec spec;
  final _DisplaySeries display;
  final ThermalSeriesSample? reading;
  final int? activePoint;
  final ValueChanged<Offset> onMove;
  final VoidCallback onExit;
  final ValueChanged<int> onPointEnter;
  final ValueChanged<int> onPointExit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      label: thermalChartAriaLabel(spec.title),
      child: AspectRatio(
        aspectRatio: _chartWidth / _chartHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return MouseRegion(
              onExit: (_) => onExit(),
              child: Listener(
                onPointerHover: (event) =>
                    onMove(_toView(event.localPosition, size)),
                onPointerMove: (event) =>
                    onMove(_toView(event.localPosition, size)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      size: size,
                      painter: _ThermalChartPainter(
                        spec: spec,
                        display: display,
                        reading: reading,
                        activePoint: activePoint,
                        colors: colors,
                      ),
                    ),
                    for (var index = 0; index < display.points.length; index++)
                      _pointTarget(size, index),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _pointTarget(Size size, int index) {
    final point = display.points[index];
    final center = _toPixel(
      Offset(
        _xFor(point.reading.elapsedMinutes, display.maximumTime),
        _yFor(_valueOf(point.reading, spec.key), spec.domain),
      ),
      size,
    );
    return Positioned(
      left: center.dx - _pointHitSize / 2,
      top: center.dy - _pointHitSize / 2,
      width: _pointHitSize,
      height: _pointHitSize,
      child: Focus(
        onFocusChange: (focused) {
          if (focused) {
            onPointEnter(index);
          } else {
            onPointExit(index);
          }
        },
        child: Semantics(
          button: true,
          label: _pointDescription(point, display),
          child: MouseRegion(
            opaque: false,
            onEnter: (_) => onPointEnter(index),
            onExit: (_) => onPointExit(index),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

enum _TextAnchor { start, middle, end }

class _ThermalChartPainter extends CustomPainter {
  _ThermalChartPainter({
    required this.spec,
    required this.display,
    required this.reading,
    required this.activePoint,
    required this.colors,
  });

  final _ChartSpec spec;
  final _DisplaySeries display;
  final ThermalSeriesSample? reading;
  final int? activePoint;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _chartWidth, size.height / _chartHeight);

    final domain = spec.domain;
    final maximumTime = display.maximumTime;
    final plotBottom = _marginTop + _plotHeight;
    final right = _chartWidth - _marginRight;
    final ink = _cssColor(_inkToken, colors);
    final grid = _cssColor(_gridToken, colors);
    final labelColor = _cssColor(_labelToken, colors);
    final curve = _cssColor(spec.colorToken, colors);

    _drawText(
      canvas,
      '${spec.title} (${spec.unit})',
      x: _marginLeft,
      baselineY: 18,
      fontSize: 13,
      weight: FontWeight.w700,
      color: ink,
    );
    _drawText(
      canvas,
      'solid = observed · dotted = estimated',
      x: right,
      baselineY: 18,
      fontSize: 10,
      color: _fade(ink, 0.75),
      anchor: _TextAnchor.end,
    );

    for (var index = 0; index < display.bands.length; index++) {
      final band = display.bands[index];
      final x = _xFor(band.startMinute, maximumTime);
      final width = math.max(0.0, _xFor(band.endMinute, maximumTime) - x);
      final fill = index.isEven
          ? _fade(grid, 0.5)
          : _fade(_cssColor(_oddBandToken, colors), 0.35);
      canvas.drawRect(
        Rect.fromLTWH(x, _marginTop, width, _plotHeight),
        Paint()..color = fill,
      );
      _drawText(
        canvas,
        band.title,
        x: x + width / 2,
        baselineY: _marginTop + 14 + band.labelRow * 12,
        fontSize: 10,
        color: ink,
        anchor: _TextAnchor.middle,
      );
      if (index > 0) {
        _line(
          canvas,
          Offset(x, _marginTop),
          Offset(x, plotBottom),
          color: _fade(ink, 0.45),
          width: 1,
          dash: const <double>[3, 3],
        );
      }
    }

    for (var tick = 0; tick <= 4; tick++) {
      final fraction = tick / 4;
      final y = _marginTop + fraction * _plotHeight;
      final value = domain.max - fraction * (domain.max - domain.min);
      _line(
        canvas,
        Offset(_marginLeft, y),
        Offset(right, y),
        color: grid,
        width: 1,
      );
      _drawText(
        canvas,
        _formatValue(value),
        x: _marginLeft - 8,
        baselineY: y + 4,
        fontSize: 10,
        color: ink,
        anchor: _TextAnchor.end,
      );
    }

    for (var tick = 0; tick <= 4; tick++) {
      final minutes = maximumTime * tick / 4;
      final x = _xFor(minutes, maximumTime);
      _line(
        canvas,
        Offset(x, _marginTop),
        Offset(x, plotBottom),
        color: _fade(grid, 0.45),
        width: 1,
      );
      _drawText(
        canvas,
        _formatValue(minutes),
        x: x,
        baselineY: _chartHeight - 24,
        fontSize: 10,
        color: ink,
        anchor: _TextAnchor.middle,
      );
    }

    final reference = spec.referenceLine;
    if (reference != null) {
      final y = calculateReferenceLineY(
        reference.value,
        domain.min,
        domain.max,
        _plotHeight,
      );
      if (y >= _marginTop && y <= plotBottom) {
        _line(
          canvas,
          Offset(_marginLeft, y),
          Offset(right, y),
          color: _fade(labelColor, 0.85),
          width: 1.5,
          dash: const <double>[6, 4],
        );
        _drawText(
          canvas,
          reference.label,
          x: right - 4,
          baselineY: y - 4,
          fontSize: 10,
          color: ink,
          anchor: _TextAnchor.end,
        );
      }
    }

    _line(
      canvas,
      Offset(_marginLeft, plotBottom),
      Offset(right, plotBottom),
      color: ink,
      width: 1,
    );

    for (final segment in display.curves) {
      if (segment.samples.isEmpty) {
        continue;
      }
      final style = thermalCurveAttributes(spec.colorToken, segment.style);
      final path = _pathFromSvg(
        buildChartPath(
          segment.samples,
          spec.key,
          (minutes) => _xFor(minutes, maximumTime),
          (value) => _yFor(value, domain),
        ),
      );
      final paint = Paint()
        ..color = _cssColor(style.stroke, colors)
        ..strokeWidth = style.strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final dash = style.strokeDasharray;
      if (dash == null) {
        canvas.drawPath(path, paint);
      } else {
        _strokeDashed(canvas, path, paint, _parseDash(dash));
      }
    }

    final hover = reading;
    if (hover != null) {
      final x = _xFor(hover.elapsedMinutes, maximumTime);
      _line(
        canvas,
        Offset(x, _marginTop),
        Offset(x, plotBottom),
        color: _fade(labelColor, 0.8),
        width: 1,
        dash: const <double>[3, 3],
      );
      _circle(
        canvas,
        Offset(x, _yFor(_valueOf(hover, spec.key), domain)),
        5,
        fill: curve,
        stroke: _cssColor(_markerOutlineToken, colors),
        strokeWidth: 1.5,
      );
    }

    for (var index = 0; index < display.points.length; index++) {
      final point = display.points[index];
      final marker = thermalPointMarkerAttributes(
        point.source,
        spec.colorToken,
      );
      _circle(
        canvas,
        Offset(
          _xFor(point.reading.elapsedMinutes, maximumTime),
          _yFor(_valueOf(point.reading, spec.key), domain),
        ),
        activePoint == index ? 7.0 : marker.r,
        fill: _cssColor(marker.fill, colors),
        stroke: _cssColor(marker.stroke, colors),
        strokeWidth: marker.strokeWidth,
      );
    }

    _drawText(
      canvas,
      'time (min)',
      x: right,
      baselineY: _chartHeight - 8,
      fontSize: 10,
      color: ink,
      anchor: _TextAnchor.end,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThermalChartPainter oldDelegate) {
    return oldDelegate.spec != spec ||
        oldDelegate.display != display ||
        oldDelegate.reading != reading ||
        oldDelegate.activePoint != activePoint ||
        oldDelegate.colors != colors;
  }
}

/// Maps the CSS custom-property tokens produced by the domain style helpers to
/// the app's colour scheme. An unmapped token is a programming error.
Color _cssColor(String token, ColorScheme colors) {
  return switch (token) {
    'currentColor' => colors.onSurface,
    'var(--chart-grid)' => colors.outlineVariant,
    'rgb(var(--ocean-850))' => colors.surfaceContainerHighest,
    'var(--chart-feasible)' => colors.primary,
    'var(--chart-helium)' => colors.tertiary,
    'var(--chart-label)' => colors.onSurfaceVariant,
    'var(--chart-badge)' => colors.surface,
    'var(--chart-point-outline)' => colors.surface,
    'var(--chart-marker-outline)' => colors.onSurface,
    _ => throw ArgumentError.value(token, 'token', 'unmapped chart colour'),
  };
}

Color _fade(Color color, double opacity) =>
    color.withValues(alpha: color.a * opacity);

/// Parses an SVG `stroke-dasharray` such as `'2 4'`.
List<double> _parseDash(String dash) => [
  for (final part in dash.split(' ')) double.parse(part),
];

/// Parses the `M x y L x y ...` string produced by [buildChartPath].
Path _pathFromSvg(String d) {
  final path = Path();
  final tokens = d.split(' ');
  for (var index = 0; index + 2 < tokens.length; index += 3) {
    final x = double.parse(tokens[index + 1]);
    final y = double.parse(tokens[index + 2]);
    if (tokens[index] == 'M') {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  return path;
}

void _line(
  Canvas canvas,
  Offset from,
  Offset to, {
  required Color color,
  required double width,
  List<double>? dash,
}) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = width
    ..style = PaintingStyle.stroke;
  final path = Path()
    ..moveTo(from.dx, from.dy)
    ..lineTo(to.dx, to.dy);
  if (dash == null) {
    canvas.drawPath(path, paint);
  } else {
    _strokeDashed(canvas, path, paint, dash);
  }
}

void _circle(
  Canvas canvas,
  Offset center,
  double radius, {
  required Color fill,
  required Color stroke,
  required double strokeWidth,
}) {
  canvas.drawCircle(center, radius, Paint()..color = fill);
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = stroke,
  );
}

/// Dashes [path] with an alternating on/off [pattern] (SVG stroke-dasharray).
void _strokeDashed(
  Canvas canvas,
  Path path,
  Paint paint,
  List<double> pattern,
) {
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    var index = 0;
    while (distance < metric.length) {
      final length = pattern[index % pattern.length];
      if (index.isEven) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            math.min(distance + length, metric.length),
          ),
          paint,
        );
      }
      distance += length;
      index++;
    }
  }
}

void _drawText(
  Canvas canvas,
  String text, {
  required double x,
  required double baselineY,
  required double fontSize,
  required Color color,
  FontWeight weight = FontWeight.w400,
  _TextAnchor anchor = _TextAnchor.start,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: fontSize, color: color, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final left = switch (anchor) {
    _TextAnchor.start => x,
    _TextAnchor.middle => x - painter.width / 2,
    _TextAnchor.end => x - painter.width,
  };
  final baseline = painter.computeDistanceToActualBaseline(
    TextBaseline.alphabetic,
  );
  painter.paint(canvas, Offset(left, baselineY - baseline));
  painter.dispose();
}

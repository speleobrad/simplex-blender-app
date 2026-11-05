import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:simplex_blender/src/domain/ternary_geometry.dart';

const String _hoverPrompt = 'Hover for gas fractions';
const String _canvasLabel = 'Gas composition ternary diagram';
const String _noFeasibleText = 'No feasible blend';
const String _noFeasibleCanvasLabel =
    'Gas composition ternary diagram. No feasible blend.';

/// JS `setTab('ternary')` overwrites the hover readout on every switch.
const String _tabSwitchPrompt = 'Move over diagram for gas fractions';
const String _chartDescription =
    'The solid region connects Air, pure oxygen, and pure helium. '
    'The dotted boundary includes pure nitrogen. '
    'A dashed line connects the initial and scenario endpoint mixes; '
    'arrows show the blend sequence. '
    'Open the Tanks and costs tab for the plotted mix and stage values.';

/// JS `renderTernaryDiagram` fits the trajectory with a 96 px margin.
const double _viewportMargin = 96;

/// Simplex diagram pane (JS `js/ui/ternary.js`, `renderTernaryDiagram`).
///
/// Renders the zoom controls, the hover readout, the ternary canvas, the
/// description and the legend with the boost-vector summary. The initial and
/// goal markers are the first and last trajectory points.
class TernaryDiagram extends StatefulWidget {
  const TernaryDiagram({
    super.key,
    required this.banks,
    required this.trajectory,
    this.noFeasible = false,
    this.activationCount = 0,
  });

  /// Reference banks drawn on the triangle; disabled banks are skipped.
  final List<TernaryBank> banks;

  /// Blend trajectory points, initial to final.
  final List<TernaryTrajectoryPoint> trajectory;

  /// True after a run with no feasible blend (JS `clearTernaryDiagram`). The
  /// summary and hover readout then show `No feasible blend`.
  final bool noFeasible;

  /// Incremented by the owner each time the Simplex tab is selected (JS
  /// `setTab('ternary')` resets the hover readout).
  final int activationCount;

  @override
  State<TernaryDiagram> createState() => _TernaryDiagramState();
}

class _TernaryDiagramState extends State<TernaryDiagram> {
  final GlobalKey _canvasKey = GlobalKey();
  double _zoom = 1;
  late String _readout;

  @override
  void initState() {
    super.initState();
    _readout = widget.noFeasible ? _noFeasibleText : _hoverPrompt;
  }

  @override
  void didUpdateWidget(TernaryDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activationCount != widget.activationCount) {
      _readout = _tabSwitchPrompt;
    } else if (widget.trajectory.isEmpty &&
        !oldWidget.noFeasible &&
        widget.noFeasible) {
      _readout = _noFeasibleText;
    }
  }

  /// Laid-out size of the canvas, or null before the first layout.
  Size? _canvasSize() {
    final renderObject = _canvasKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.size;
    }
    return null;
  }

  /// JS `changeTernaryZoom` / `getNextZoom` against the current maximum zoom.
  double _zoomAfter(double direction) {
    final size = _canvasSize();
    final maxZoom = size == null
        ? 1.0
        : _DiagramView.of(size, _zoom, widget.trajectory).maxZoom;
    return getNextZoom(_zoom, maxZoom, direction);
  }

  void _setZoom(double zoom) {
    setState(() {
      _zoom = zoom;
    });
  }

  /// JS `pointermove` readout: gas fractions under the pointer.
  void _updateReadout(Offset local) {
    final size = _canvasSize();
    if (widget.trajectory.isEmpty || size == null || size.isEmpty) {
      return;
    }
    final view = _DiagramView.of(size, _zoom, widget.trajectory);
    final mix = getCompositionAtPoint(local.dx, local.dy, view.vertices);
    final readout =
        '${mix.oxygenPercent.toStringAsFixed(1)}% O₂ · '
        '${mix.heliumPercent.toStringAsFixed(1)}% He · '
        '${mix.nitrogenPercent.toStringAsFixed(1)}% N₂';
    if (readout != _readout) {
      setState(() {
        _readout = readout;
      });
    }
  }

  /// JS `pointerleave` readout reset (only once a diagram has been drawn).
  void _resetReadout() {
    if (widget.trajectory.isEmpty || _readout == _hoverPrompt) {
      return;
    }
    setState(() {
      _readout = _hoverPrompt;
    });
  }

  /// JS `wheel` zoom. The event is only claimed when the zoom changes, as the
  /// JS handler only calls `preventDefault` in that case.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final dy = event.scrollDelta.dy;
    if (dy == 0) {
      return;
    }
    final next = _zoomAfter(dy < 0 ? 1.0 : -1.0);
    if (next == _zoom) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (_) => _setZoom(next),
    );
  }

  Widget _zoomButton({
    required String label,
    required String text,
    required double direction,
  }) {
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: () => _setZoom(_zoomAfter(direction)),
        child: Text(text),
      ),
    );
  }

  Widget _legendSwatch(Color color, {required bool dashed}) {
    return SizedBox(
      width: 12,
      height: 2,
      child: CustomPaint(
        painter: _LegendSwatchPainter(color: color, dashed: dashed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bodyStyle = theme.textTheme.bodySmall;
    final labelStyle = theme.textTheme.labelSmall;
    final trajectory = widget.trajectory;
    final boostCount = math.max(0, trajectory.length - 1);
    final summary = trajectory.isEmpty
        ? (widget.noFeasible ? _noFeasibleText : 'Ready')
        : '$boostCount boost vector${boostCount == 1 ? '' : 's'}';
    final canvasLabel = trajectory.isEmpty && widget.noFeasible
        ? _noFeasibleCanvasLabel
        : _canvasLabel;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Text(
              'Gas mix trajectory · Use the controls to zoom',
              style: bodyStyle,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _zoomButton(
                  label: 'Zoom out diagram',
                  text: '−',
                  direction: -1.0,
                ),
                const SizedBox(width: 4),
                _zoomButton(
                  label: 'Reset diagram zoom',
                  text: 'Reset',
                  direction: 0.0,
                ),
                const SizedBox(width: 4),
                _zoomButton(
                  label: 'Zoom in diagram',
                  text: '+',
                  direction: 1.0,
                ),
              ],
            ),
            Text(
              _readout,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: bodyStyle?.copyWith(
                color: scheme.primary,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Semantics(
                container: true,
                image: true,
                label: canvasLabel,
                hint: _chartDescription,
                child: MouseRegion(
                  onExit: (_) => _resetReadout(),
                  child: Listener(
                    onPointerHover: (event) =>
                        _updateReadout(event.localPosition),
                    onPointerMove: (event) =>
                        _updateReadout(event.localPosition),
                    onPointerSignal: _onPointerSignal,
                    child: CustomPaint(
                      key: _canvasKey,
                      painter: _TernaryPainter(
                        banks: widget.banks,
                        trajectory: trajectory,
                        zoom: _zoom,
                        colors: scheme,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _legendSwatch(scheme.primary, dashed: false),
                        const SizedBox(width: 4),
                        Text(
                          '➔ Mixing Vector Path',
                          style: bodyStyle?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '•',
                      style: bodyStyle?.copyWith(color: scheme.outline),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _legendSwatch(scheme.outline, dashed: true),
                        const SizedBox(width: 4),
                        Text(
                          'Initial-to-final reference',
                          style: bodyStyle?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Text(
                  summary,
                  style: labelStyle?.copyWith(
                    color: scheme.tertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Zoomed and panned geometry for one canvas size (JS `getTrajectoryViewport`
/// + `transformPointForZoom` as used by `renderTernaryDiagram`).
class _DiagramView {
  _DiagramView._({
    required TernaryVertices base,
    required this.vertices,
    required this.zoom,
    required this.maxZoom,
    required TernaryPoint Function(TernaryPoint) toScreen,
  }) : _base = base,
       _toScreen = toScreen;

  factory _DiagramView.of(
    Size size,
    double requestedZoom,
    List<TernaryTrajectoryPoint> trajectory,
  ) {
    final width = size.width;
    final height = size.height;
    final base = createVertices(width, height);
    final viewport = getTrajectoryViewport<TernaryTrajectoryPoint>(
      trajectory,
      (mix) => toCanvasPoint(
        mix.oxygenPercent,
        mix.heliumPercent,
        mix.nitrogenPercent,
        base,
      ),
      width,
      height,
      _viewportMargin,
    );
    final maxZoom = viewport.maxZoom;
    final zoom = math.max(1.0, math.min(maxZoom, requestedZoom));
    TernaryPoint toScreen(TernaryPoint point) => transformPointForZoom(
      point,
      viewport.center,
      zoom,
      maxZoom,
      width,
      height,
    );
    return _DiagramView._(
      base: base,
      zoom: zoom,
      maxZoom: maxZoom,
      toScreen: toScreen,
      vertices: TernaryVertices(
        oxygen: toScreen(base.oxygen),
        nitrogen: toScreen(base.nitrogen),
        helium: toScreen(base.helium),
        air: toScreen(base.air),
      ),
    );
  }

  final TernaryVertices _base;
  final TernaryPoint Function(TernaryPoint) _toScreen;

  /// Screen-space triangle corners (JS `verticesByCanvas`).
  final TernaryVertices vertices;
  final double zoom;
  final double maxZoom;

  /// JS `toPoint(oxygen, helium, nitrogen)`.
  TernaryPoint toPoint(
    double oxygenPercent,
    double heliumPercent,
    double nitrogenPercent,
  ) {
    return _toScreen(
      toCanvasPoint(oxygenPercent, heliumPercent, nitrogenPercent, _base),
    );
  }
}

class _TernaryPalette {
  const _TernaryPalette(this.colors);

  final ColorScheme colors;

  Color get grid => colors.outlineVariant;
  Color get fullBoundary => colors.outline;
  Color get feasible => colors.primary;
  Color get oxygen => colors.tertiary;
  Color get nitrogen => colors.onSurfaceVariant;
  Color get helium => colors.secondary;
  Color get bank => colors.primary;
  Color get pointOutline => colors.surface;
  Color get markerOutline => colors.surface;
  Color get label => colors.onSurfaceVariant;
  Color get air => colors.onSurfaceVariant;
  Color get badge => colors.surfaceContainerHigh;
  Color get badgeText => colors.onSurface;
  Color get badgeSubtext => colors.onSurfaceVariant;
  Color get direct => colors.outline;
  Color get initial => colors.error;
  Color get target => colors.tertiary;

  /// JS `--chart-path-1` … `--chart-path-5`, cycled per trajectory segment.
  List<Color> get path => [
    colors.primary,
    colors.tertiary,
    colors.secondary,
    colors.error,
    colors.onSurface,
  ];
}

class _TernaryPainter extends CustomPainter {
  const _TernaryPainter({
    required this.banks,
    required this.trajectory,
    required this.zoom,
    required this.colors,
  });

  final List<TernaryBank> banks;
  final List<TernaryTrajectoryPoint> trajectory;
  final double zoom;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (trajectory.isEmpty || size.isEmpty) {
      return;
    }
    final palette = _TernaryPalette(colors);
    final view = _DiagramView.of(size, zoom, trajectory);
    final vertices = view.vertices;
    final first = trajectory.first;
    final last = trajectory.last;

    Offset at(
      double oxygenPercent,
      double heliumPercent,
      double nitrogenPercent,
    ) {
      return _offset(
        view.toPoint(oxygenPercent, heliumPercent, nitrogenPercent),
      );
    }

    // Infeasible region (JS fill with full-boundary colour at alpha 0.12).
    final region = getInfeasibleRegionVertices(vertices);
    final infeasible = Path()
      ..moveTo(region[0].x, region[0].y)
      ..lineTo(region[1].x, region[1].y)
      ..lineTo(region[2].x, region[2].y)
      ..close();
    canvas.drawPath(
      infeasible,
      _fillPaint(palette.fullBoundary.withValues(alpha: 0.12)),
    );

    // Composition grid at 20 % steps.
    final gridPaint = _strokePaint(palette.grid, 1);
    for (var step = 1; step <= 4; step++) {
      final fraction = step * 0.2;
      final percent = fraction * 100;
      final rest = (1 - fraction) * 100;
      canvas.drawLine(at(percent, rest, 0), at(percent, 0, rest), gridPaint);
      canvas.drawLine(at(rest, percent, 0), at(0, percent, rest), gridPaint);
      canvas.drawLine(at(rest, 0, percent), at(0, rest, percent), gridPaint);
    }

    // Full boundary (dashed, includes pure nitrogen).
    final boundary = Path()
      ..moveTo(vertices.oxygen.x, vertices.oxygen.y)
      ..lineTo(vertices.helium.x, vertices.helium.y)
      ..lineTo(vertices.nitrogen.x, vertices.nitrogen.y)
      ..close();
    _strokeDashed(
      canvas,
      boundary,
      _strokePaint(palette.fullBoundary, 1.5),
      const [3.0, 5.0],
    );

    // Feasible region (solid, Air to oxygen to helium).
    final feasible = Path()
      ..moveTo(vertices.air.x, vertices.air.y)
      ..lineTo(vertices.oxygen.x, vertices.oxygen.y)
      ..lineTo(vertices.helium.x, vertices.helium.y)
      ..close();
    canvas.drawPath(feasible, _strokePaint(palette.feasible, 2.5));

    _drawText(
      canvas,
      '100% O₂',
      _textStyle(11, palette.oxygen, bold: true),
      Offset(vertices.oxygen.x, vertices.oxygen.y - 12),
      align: TextAlign.center,
    );
    _drawText(
      canvas,
      '100% N₂',
      _textStyle(11, palette.nitrogen, bold: true),
      Offset(vertices.nitrogen.x - 14, vertices.nitrogen.y + 18),
    );
    _drawText(
      canvas,
      '100% He',
      _textStyle(11, palette.helium, bold: true),
      Offset(vertices.helium.x + 14, vertices.helium.y + 18),
      align: TextAlign.right,
    );

    final air = _offset(vertices.air);
    canvas.drawCircle(air, 3.5, _fillPaint(palette.air));
    _drawText(
      canvas,
      'Air (${formatGasMix(21, 0)})',
      _textStyle(8, palette.label),
      Offset(air.dx - 6, air.dy + 3),
      align: TextAlign.right,
    );

    // Reference banks (enabled only).
    for (final bank in banks) {
      if (!bank.enabled) {
        continue;
      }
      final point = _offset(
        view.toPoint(
          bank.oxygenPercent,
          bank.heliumPercent,
          math.max(0.0, 100 - bank.oxygenPercent - bank.heliumPercent),
        ),
      );
      canvas.drawCircle(point, 4.5, _fillPaint(palette.bank));
      canvas.drawCircle(point, 4.5, _strokePaint(palette.pointOutline, 1.5));
      _drawText(
        canvas,
        bank.name.split(' ').first,
        _textStyle(9, palette.label),
        Offset(point.dx, point.dy - 7),
        align: TextAlign.center,
      );
    }

    // Initial-to-final reference line.
    final start = view.toPoint(
      first.oxygenPercent,
      first.heliumPercent,
      first.nitrogenPercent,
    );
    final target = view.toPoint(
      last.oxygenPercent,
      last.heliumPercent,
      last.nitrogenPercent,
    );
    _strokeDashed(
      canvas,
      Path()
        ..moveTo(start.x, start.y)
        ..lineTo(target.x, target.y),
      _strokePaint(palette.direct, 1.5),
      const [4.0, 4.0],
    );

    // Mixing vector path with step markers and badges.
    final segmentColors = palette.path;
    for (var index = 0; index < trajectory.length - 1; index++) {
      final from = trajectory[index];
      final to = trajectory[index + 1];
      final color = segmentColors[index % segmentColors.length];
      final end = _offset(
        view.toPoint(to.oxygenPercent, to.heliumPercent, to.nitrogenPercent),
      );
      _drawVectorArrow(
        canvas,
        _offset(
          view.toPoint(
            from.oxygenPercent,
            from.heliumPercent,
            from.nitrogenPercent,
          ),
        ),
        end,
        color,
      );
      if (index + 1 >= trajectory.length - 1) {
        continue;
      }
      canvas.drawCircle(end, 5, _fillPaint(color));
      canvas.drawCircle(end, 5, _strokePaint(palette.markerOutline, 1.5));
      _drawStepBadge(canvas, to, end, color, size.width / 2, palette);
    }

    // Endpoint markers.
    _drawMixPoint(
      canvas,
      _offset(start),
      'Init (${formatGasMix(first.oxygenPercent, first.heliumPercent)})',
      palette.initial,
      6.5,
      16,
      palette.markerOutline,
    );
    _drawMixPoint(
      canvas,
      _offset(target),
      'Goal (${formatGasMix(last.oxygenPercent, last.heliumPercent)})',
      palette.target,
      7.5,
      -12,
      palette.markerOutline,
    );
  }

  @override
  bool shouldRepaint(_TernaryPainter oldDelegate) {
    return !identical(oldDelegate.banks, banks) ||
        !identical(oldDelegate.trajectory, trajectory) ||
        oldDelegate.zoom != zoom ||
        oldDelegate.colors != colors;
  }
}

/// JS `drawVectorArrow`: shortened line with a filled head at the target end.
void _drawVectorArrow(
  Canvas canvas,
  Offset from,
  Offset to,
  Color color, {
  double width = 2.5,
  double arrowSize = 9,
  double startRadius = 6,
  double endRadius = 6,
}) {
  final dx = to.dx - from.dx;
  final dy = to.dy - from.dy;
  final distance = math.sqrt(dx * dx + dy * dy);
  if (distance < 1.5) {
    return;
  }

  final effectiveArrowSize = math.min(arrowSize, math.max(4.0, distance * 0.4));
  final effectiveStartOffset = math.min(startRadius, distance * 0.22);
  final effectiveEndOffset = math.min(endRadius, distance * 0.32);
  final unitX = dx / distance;
  final unitY = dy / distance;
  final shaftStart = Offset(
    from.dx + unitX * effectiveStartOffset,
    from.dy + unitY * effectiveStartOffset,
  );
  final tip = Offset(
    to.dx - unitX * effectiveEndOffset,
    to.dy - unitY * effectiveEndOffset,
  );

  canvas.drawLine(
    shaftStart,
    tip,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );

  final angle = math.atan2(dy, dx);
  final head = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(
      tip.dx - effectiveArrowSize * math.cos(angle - math.pi / 6),
      tip.dy - effectiveArrowSize * math.sin(angle - math.pi / 6),
    )
    ..lineTo(
      tip.dx - effectiveArrowSize * math.cos(angle + math.pi / 6),
      tip.dy - effectiveArrowSize * math.sin(angle + math.pi / 6),
    )
    ..close();
  canvas.drawPath(head, _fillPaint(color));
}

/// JS `drawTrajectory` badge: step label, mix and pressure.
void _drawStepBadge(
  Canvas canvas,
  TernaryTrajectoryPoint point,
  Offset end,
  Color color,
  double halfWidth,
  _TernaryPalette palette,
) {
  final stepPrefix = point.step == null ? '' : 'Step ${point.step}: ';
  final label =
      '$stepPrefix${formatGasMix(point.oxygenPercent, point.heliumPercent)}';
  final pressure = point.pressureBar;
  final subLabel = pressure == null
      ? null
      : '${pressure.toStringAsFixed(0)} bar';

  final labelStyle = _textStyle(9, palette.badgeText, bold: true);
  final measure = _layoutText(label, labelStyle);
  final badgeWidth = measure.width + 10;
  measure.dispose();
  const badgeHeight = 22.0;
  final badgeX = end.dx > halfWidth ? end.dx + 8 : end.dx - badgeWidth - 8;
  final badgeY = end.dy - 11;
  final badge = RRect.fromRectAndRadius(
    Rect.fromLTWH(badgeX, badgeY, badgeWidth, badgeHeight),
    const Radius.circular(4),
  );
  canvas.drawRRect(badge, _fillPaint(palette.badge));
  canvas.drawRRect(badge, _strokePaint(color, 1));
  _drawText(canvas, label, labelStyle, Offset(badgeX + 5, badgeY + 9));
  if (subLabel != null) {
    _drawText(
      canvas,
      subLabel,
      _textStyle(9, palette.badgeSubtext, bold: true),
      Offset(badgeX + 5, badgeY + 18),
    );
  }
}

/// JS `drawMixPoint`: filled marker with an outline and a centred label.
void _drawMixPoint(
  Canvas canvas,
  Offset point,
  String label,
  Color color,
  double radius,
  double labelY,
  Color outline,
) {
  canvas.drawCircle(point, radius, _fillPaint(color));
  canvas.drawCircle(point, radius, _strokePaint(outline, 2));
  _drawText(
    canvas,
    label,
    _textStyle(10, color, bold: true),
    Offset(point.dx, point.dy + labelY),
    align: TextAlign.center,
  );
}

/// Dashes a path with the canvas on/off pattern (JS `setLineDash`).
void _strokeDashed(Canvas canvas, Path path, Paint paint, List<double> dash) {
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    var index = 0;
    while (distance < metric.length) {
      final next = math.min(
        distance + dash[index % dash.length],
        metric.length,
      );
      if (index.isEven) {
        canvas.drawPath(metric.extractPath(distance, next), paint);
      }
      distance = next;
      index++;
    }
  }
}

/// Draws text with the canvas `fillText` anchoring: `align` gives the x
/// anchor and `anchor.dy` is the alphabetic baseline.
void _drawText(
  Canvas canvas,
  String text,
  TextStyle style,
  Offset anchor, {
  TextAlign align = TextAlign.left,
}) {
  final painter = _layoutText(text, style);
  final left = switch (align) {
    TextAlign.center => anchor.dx - painter.width / 2,
    TextAlign.right => anchor.dx - painter.width,
    _ => anchor.dx,
  };
  final baseline = painter.computeDistanceToActualBaseline(
    TextBaseline.alphabetic,
  );
  painter.paint(canvas, Offset(left, anchor.dy - baseline));
  painter.dispose();
}

TextPainter _layoutText(String text, TextStyle style) {
  return TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
}

TextStyle _textStyle(double size, Color color, {bool bold = false}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
  );
}

Paint _fillPaint(Color color) {
  return Paint()
    ..color = color
    ..style = PaintingStyle.fill;
}

Paint _strokePaint(Color color, double width) {
  return Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width;
}

Offset _offset(TernaryPoint point) => Offset(point.x, point.y);

class _LegendSwatchPainter extends CustomPainter {
  const _LegendSwatchPainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = _strokePaint(color, 2);
    final midY = size.height / 2;
    final path = Path()
      ..moveTo(0, midY)
      ..lineTo(size.width, midY);
    if (dashed) {
      _strokeDashed(canvas, path, paint, const [3.0, 3.0]);
    } else {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_LegendSwatchPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.dashed != dashed;
  }
}

import 'dart:math' as math;

import 'thermodynamics.dart';

// ignore: constant_identifier_names
const double TRIANGLE_PADDING = 38;

// ignore: constant_identifier_names
const double ZOOM_FACTOR = 1.25;

/// Canvas-space point (JS `{ x, y }`).
class TernaryPoint {
  const TernaryPoint({required this.x, required this.y});

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is TernaryPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'TernaryPoint(x: $x, y: $y)';
}

/// Triangle corners plus the projected Air reference (JS `createVertices`).
class TernaryVertices {
  const TernaryVertices({
    required this.oxygen,
    required this.nitrogen,
    required this.helium,
    required this.air,
  });

  final TernaryPoint oxygen;
  final TernaryPoint nitrogen;
  final TernaryPoint helium;
  final TernaryPoint air;
}

/// Viewport of a trajectory: center of its projected bounds and the largest
/// zoom that keeps it inside the margins (JS `getTrajectoryViewport`).
typedef TernaryViewport = ({TernaryPoint? center, double maxZoom});

/// One bank in the accessible data table. JS bank objects read by
/// `buildAccessibleTernaryData`; `endPressureBar` is the optional JS field
/// set by callers that carry a final pressure.
class TernaryBank {
  const TernaryBank({
    required this.id,
    required this.name,
    required this.enabled,
    required this.oxygenPercent,
    required this.heliumPercent,
    required this.pressureBar,
    this.endPressureBar,
  });

  final String id;
  final String name;
  final bool enabled;
  final double oxygenPercent;
  final double heliumPercent;
  final double pressureBar;
  final double? endPressureBar;
}

/// One optimizer or scenario trajectory point (JS trajectory entry).
class TernaryTrajectoryPoint {
  const TernaryTrajectoryPoint({
    required this.label,
    required this.oxygenPercent,
    required this.heliumPercent,
    required this.nitrogenPercent,
    this.step,
    this.pressureBar,
    this.bankId,
    this.bankName,
    this.sourceEndPressureBar,
  });

  final String label;
  final double oxygenPercent;
  final double heliumPercent;
  final double nitrogenPercent;

  /// Null when the JS point has no `step`.
  final int? step;

  /// Null when the JS point has no `pressureBar`.
  final double? pressureBar;

  /// Null or empty when the JS point has no bank (JS falsy `bankId`).
  final String? bankId;

  /// Null or empty when the JS point has no bank name.
  final String? bankName;

  /// Null when the JS point has no `sourceEndPressureBar`.
  final double? sourceEndPressureBar;
}

/// One row of the accessible mix table (JS `mixRows` entry).
class TernaryMixRow {
  const TernaryMixRow({
    required this.label,
    required this.mix,
    this.startPressureBar,
    this.endPressureBar,
  });

  final String label;
  final GasMixPercent mix;
  final double? startPressureBar;
  final double? endPressureBar;
}

/// One row of the accessible trajectory table (JS `trajectoryRows` entry).
class TernaryTrajectoryRow {
  const TernaryTrajectoryRow({
    required this.label,
    required this.mix,
    this.pressureBar,
  });

  final String label;
  final TernaryTrajectoryPoint mix;
  final double? pressureBar;
}

/// JS `buildAccessibleTernaryData` return shape.
class TernaryAccessibleData {
  const TernaryAccessibleData({
    required this.mixRows,
    required this.trajectoryRows,
    required this.status,
  });

  final List<TernaryMixRow> mixRows;
  final List<TernaryTrajectoryRow> trajectoryRows;
  final String status;
}

bool _isTruthyString(String? value) => value != null && value.isNotEmpty;

String _formatPercent(double value) => value.toStringAsFixed(1);

/// JS `||` on a number: a zero or NaN sum falls back to 1.
double _orOne(double value) => (value == 0 || value.isNaN) ? 1 : value;

TernaryPoint _projectMix(
  double oxygenPercent,
  double heliumPercent,
  double nitrogenPercent, {
  required TernaryPoint oxygen,
  required TernaryPoint nitrogen,
  required TernaryPoint helium,
}) {
  final total = _orOne(oxygenPercent + heliumPercent + nitrogenPercent);
  final oxygenFraction = math.max(0.0, oxygenPercent) / total;
  final heliumFraction = math.max(0.0, heliumPercent) / total;
  final nitrogenFraction = math.max(0.0, nitrogenPercent) / total;
  return TernaryPoint(
    x:
        nitrogenFraction * nitrogen.x +
        heliumFraction * helium.x +
        oxygenFraction * oxygen.x,
    y:
        nitrogenFraction * nitrogen.y +
        heliumFraction * helium.y +
        oxygenFraction * oxygen.y,
  );
}

TernaryPoint toCanvasPoint(
  double oxygenPercent,
  double heliumPercent,
  double nitrogenPercent,
  TernaryVertices vertices,
) {
  return _projectMix(
    oxygenPercent,
    heliumPercent,
    nitrogenPercent,
    oxygen: vertices.oxygen,
    nitrogen: vertices.nitrogen,
    helium: vertices.helium,
  );
}

String formatGasMix(double oxygenPercent, double heliumPercent) {
  return '${_formatPercent(oxygenPercent)}/${_formatPercent(heliumPercent)}';
}

double getNextZoom(double currentZoom, double maximumZoom, double direction) {
  final safeMaximum = maximumZoom.isFinite ? math.max(1.0, maximumZoom) : 1.0;
  final safeCurrent = currentZoom.isFinite
      ? math.max(1.0, math.min(safeMaximum, currentZoom))
      : 1.0;
  if (direction == 0) {
    return 1;
  }
  final requested = direction > 0
      ? safeCurrent * ZOOM_FACTOR
      : safeCurrent / ZOOM_FACTOR;
  return math.max(1.0, math.min(safeMaximum, requested));
}

TernaryVertices createVertices(double width, double height) {
  final oxygen = TernaryPoint(x: width / 2, y: TRIANGLE_PADDING);
  final nitrogen = TernaryPoint(
    x: TRIANGLE_PADDING,
    y: height - TRIANGLE_PADDING + 4,
  );
  final helium = TernaryPoint(
    x: width - TRIANGLE_PADDING,
    y: height - TRIANGLE_PADDING + 4,
  );
  final air = _projectMix(
    21,
    0,
    79,
    oxygen: oxygen,
    nitrogen: nitrogen,
    helium: helium,
  );
  return TernaryVertices(
    oxygen: oxygen,
    nitrogen: nitrogen,
    helium: helium,
    air: air,
  );
}

List<TernaryPoint> getInfeasibleRegionVertices(TernaryVertices vertices) {
  return [vertices.nitrogen, vertices.air, vertices.helium];
}

TernaryViewport getTrajectoryViewport<T>(
  List<T> trajectory,
  TernaryPoint Function(T mix) project,
  double width,
  double height,
  double margin,
) {
  if (trajectory.isEmpty) {
    return (center: null, maxZoom: 1.0);
  }

  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final mix in trajectory) {
    final point = project(mix);
    if (!point.x.isFinite || !point.y.isFinite) {
      continue;
    }
    minX = math.min(minX, point.x);
    minY = math.min(minY, point.y);
    maxX = math.max(maxX, point.x);
    maxY = math.max(maxY, point.y);
  }
  if (!minX.isFinite) {
    return (center: null, maxZoom: 1.0);
  }

  final spanX = maxX - minX;
  final spanY = maxY - minY;
  final horizontalLimit = spanX > 0
      ? math.max(0.0, width - 2 * margin) / spanX
      : double.infinity;
  final verticalLimit = spanY > 0
      ? math.max(0.0, height - 2 * margin) / spanY
      : double.infinity;
  final candidate = math.min(horizontalLimit, verticalLimit);
  return (
    center: TernaryPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2),
    maxZoom: candidate.isFinite ? math.max(1.0, candidate) : 1.0,
  );
}

double calculateMaxZoom<T>(
  List<T> trajectory,
  TernaryPoint Function(T mix) project,
  double width,
  double height, [
  double margin = 96,
]) {
  return getTrajectoryViewport(
    trajectory,
    project,
    width,
    height,
    margin,
  ).maxZoom;
}

TernaryPoint transformPointForZoom(
  TernaryPoint point,
  TernaryPoint? center,
  double zoom,
  double maxZoom,
  double width,
  double height,
) {
  if (center == null || zoom <= 1 || maxZoom <= 1) {
    return point;
  }
  final progress = math.min(1.0, (zoom - 1) / (maxZoom - 1));
  return TernaryPoint(
    x:
        center.x +
        (point.x - center.x) * zoom +
        (width / 2 - center.x) * progress,
    y:
        center.y +
        (point.y - center.y) * zoom +
        (height / 2 - center.y) * progress,
  );
}

/// JS `getCompositionAtPoint` return shape: percentages of the clamped,
/// normalized barycentric fractions.
class CompositionAtPoint {
  const CompositionAtPoint({
    required this.oxygenPercent,
    required this.heliumPercent,
    required this.nitrogenPercent,
  });

  final double oxygenPercent;
  final double heliumPercent;
  final double nitrogenPercent;
}

CompositionAtPoint getCompositionAtPoint(
  double x,
  double y,
  TernaryVertices vertices,
) {
  final oxygen = vertices.oxygen;
  final nitrogen = vertices.nitrogen;
  final helium = vertices.helium;
  final denominator =
      (nitrogen.y - helium.y) * (oxygen.x - helium.x) +
      (helium.x - nitrogen.x) * (oxygen.y - helium.y);
  final oxygenFraction =
      ((nitrogen.y - helium.y) * (x - helium.x) +
          (helium.x - nitrogen.x) * (y - helium.y)) /
      denominator;
  final nitrogenFraction =
      ((helium.y - oxygen.y) * (x - helium.x) +
          (oxygen.x - helium.x) * (y - helium.y)) /
      denominator;
  final heliumFraction = 1 - oxygenFraction - nitrogenFraction;
  final oxygenPart = math.max(0.0, oxygenFraction);
  final nitrogenPart = math.max(0.0, nitrogenFraction);
  final heliumPart = math.max(0.0, heliumFraction);
  final total = _orOne(oxygenPart + nitrogenPart + heliumPart);

  return CompositionAtPoint(
    oxygenPercent: oxygenPart / total * 100,
    heliumPercent: heliumPart / total * 100,
    nitrogenPercent: nitrogenPart / total * 100,
  );
}

TernaryAccessibleData buildAccessibleTernaryData({
  List<TernaryBank> banks = const [],
  required GasMixPercent initialMix,
  required GasMixPercent targetMix,
  List<TernaryTrajectoryPoint> trajectory = const [],
  String mode = 'optimizer',
}) {
  final isCompare = mode == 'compare';
  final isWhatIf = mode == 'what-if';
  final mixRows = <TernaryMixRow>[
    TernaryMixRow(
      label: 'Air reference',
      mix: const GasMixPercent(oxygenPercent: 21, heliumPercent: 0),
    ),
    TernaryMixRow(label: 'Initial mix', mix: initialMix),
    TernaryMixRow(
      label: isCompare || isWhatIf ? 'Final mix' : 'Target mix',
      mix: targetMix,
    ),
  ];

  final sourcePressureByBankId = <String, double?>{};
  for (final point in trajectory) {
    final bankId = point.bankId;
    if (bankId == null || bankId.isEmpty) {
      continue;
    }
    sourcePressureByBankId[bankId] = point.sourceEndPressureBar;
  }

  var enabledBankCount = 0;
  for (final bank in banks) {
    if (!bank.enabled) {
      continue;
    }
    enabledBankCount++;
    mixRows.add(
      TernaryMixRow(
        label: bank.name,
        mix: GasMixPercent(
          oxygenPercent: bank.oxygenPercent,
          heliumPercent: bank.heliumPercent,
        ),
        startPressureBar: bank.pressureBar,
        endPressureBar:
            sourcePressureByBankId[bank.id] ??
            bank.endPressureBar ??
            bank.pressureBar,
      ),
    );
  }

  final trajectoryRows = [
    for (final point in trajectory)
      TernaryTrajectoryRow(
        label: _isTruthyString(point.bankName)
            ? '${point.label}: ${point.bankName}'
            : point.label,
        mix: point,
        pressureBar: point.pressureBar,
      ),
  ];

  final recipeStageCount = trajectory.where((point) => point.step != 0).length;
  final status = isCompare
      ? 'Data covers $recipeStageCount recipe stage${recipeStageCount == 1 ? '' : 's'}.'
      : 'Data covers $enabledBankCount enabled supply bank${enabledBankCount == 1 ? '' : 's'} and ${trajectory.length} trajectory points.';

  return TernaryAccessibleData(
    mixRows: mixRows,
    trajectoryRows: trajectoryRows,
    status: status,
  );
}

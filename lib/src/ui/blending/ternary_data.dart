import 'dart:math' as math;

import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/ternary_geometry.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

/// Status shown after a run with no feasible blend (JS `clearTernaryDiagram`,
/// `js/ui/ternary.js` 632).
const String noFeasibleBlendDataText = 'No feasible blend data to display.';

/// Status shown when the trajectory or endpoints are not valid compositions
/// (JS `renderTernaryDiagram`, `js/ui/ternary.js` 501).
const String invalidTernaryDataText =
    'Simplex diagram unavailable: the scenario trajectory has incomplete or invalid composition data.';

/// Inputs for the Blending Simplex diagram and accessible tables (JS
/// `ternaryData`, `js/main.js` 1375-1392).
class BlendingTernaryInputs {
  const BlendingTernaryInputs({
    required this.banks,
    required this.initialMix,
    required this.targetMix,
    required this.trajectory,
    required this.valid,
  });

  /// All inventory banks; the diagram skips disabled ones.
  final List<TernaryBank> banks;
  final GasMixPercent initialMix;
  final GasMixPercent targetMix;
  final List<TernaryTrajectoryPoint> trajectory;

  /// False when an endpoint or trajectory point is not a valid composition
  /// (JS `validSimplexMix`, `js/ui/ternary.js` 415-421).
  final bool valid;
}

/// Maps the last Blending run to ternary inputs. Returns null when there is
/// no feasible recipe and no maximum-pressure recipe to plot (JS
/// `ternaryData` returns null).
BlendingTernaryInputs? blendingTernaryInputsOf(
  BlendController controller,
  AppController app,
) {
  final result = controller.lastResult;
  final input = controller.lastInput;
  if (result == null || input == null) {
    return null;
  }
  final recipe = result['feasible'] == true
      ? result
      : _mapOrNull(result['maximumPressure']);
  final cylinder = _mapOrNull(input['cylinder']);
  if (recipe == null || cylinder == null) {
    return null;
  }

  final initialMix = GasMixPercent(
    oxygenPercent: _numOrNan(cylinder['initialOxygenPercent']),
    heliumPercent: _numOrNan(cylinder['initialHeliumPercent']),
  );
  final targetMix = GasMixPercent(
    oxygenPercent: _numOrNan(cylinder['targetOxygenPercent']),
    heliumPercent: _numOrNan(cylinder['targetHeliumPercent']),
  );
  final trajectory = _trajectoryOf(recipe['trajectory']);
  final valid =
      _isValidEndpoint(initialMix) &&
      _isValidEndpoint(targetMix) &&
      trajectory.isNotEmpty &&
      trajectory.every(_isValidPoint);

  return BlendingTernaryInputs(
    banks: <TernaryBank>[
      for (final bank in app.banks)
        TernaryBank(
          id: bank.id,
          name: bank.name,
          enabled: bank.enabled,
          oxygenPercent: bank.oxygenPercent,
          heliumPercent: bank.heliumPercent,
          pressureBar: bank.pressureBar,
        ),
    ],
    initialMix: initialMix,
    targetMix: targetMix,
    trajectory: trajectory,
    valid: valid,
  );
}

/// Accessible table data for the Tanks and costs tab (JS
/// `renderAccessibleChartData`, `js/ui/ternary.js` 468-489). [data] is null
/// when the tables are cleared; [status] is always set.
class BlendingTernaryTables {
  const BlendingTernaryTables({required this.status, required this.data});

  final String status;
  final TernaryAccessibleData? data;
}

/// Resolves the Tanks and costs status and tables for the last Blending run
/// (JS `renderTernary` / `clearTernaryDiagram` data-status and table updates).
BlendingTernaryTables blendingTernaryTablesOf(
  BlendController controller,
  AppController app,
) {
  final inputs = blendingTernaryInputsOf(controller, app);
  if (inputs == null) {
    return const BlendingTernaryTables(
      status: noFeasibleBlendDataText,
      data: null,
    );
  }
  if (!inputs.valid) {
    return const BlendingTernaryTables(
      status: invalidTernaryDataText,
      data: null,
    );
  }
  final data = buildAccessibleTernaryData(
    banks: inputs.banks,
    initialMix: inputs.initialMix,
    targetMix: inputs.targetMix,
    trajectory: inputs.trajectory,
  );
  return BlendingTernaryTables(status: data.status, data: data);
}

List<TernaryTrajectoryPoint> _trajectoryOf(Object? raw) {
  if (raw is! List<Object?>) {
    return const <TernaryTrajectoryPoint>[];
  }
  return <TernaryTrajectoryPoint>[
    for (final entry in raw)
      _pointOf(
        entry is Map<String, Object?> ? entry : const <String, Object?>{},
      ),
  ];
}

TernaryTrajectoryPoint _pointOf(Map<String, Object?> point) {
  final label = point['label'];
  final step = point['step'];
  final bankId = point['bankId'];
  final bankName = point['bankName'];
  return TernaryTrajectoryPoint(
    label: label is String ? label : '',
    oxygenPercent: _numOrNan(point['oxygenPercent']),
    heliumPercent: _numOrNan(point['heliumPercent']),
    nitrogenPercent: _numOrNan(point['nitrogenPercent']),
    step: step is num && step.isFinite ? step.toInt() : null,
    pressureBar: _numOrNull(point['pressureBar']),
    bankId: bankId is String ? bankId : null,
    bankName: bankName is String ? bankName : null,
    sourceEndPressureBar: _numOrNull(point['sourceEndPressureBar']),
  );
}

bool _isValidEndpoint(GasMixPercent mix) {
  // JS endpoints carry nitrogen = max(0, 100 - O - He) (`js/main.js` 1381-1390).
  return _isValidComposition(
    mix.oxygenPercent,
    mix.heliumPercent,
    math.max(0.0, 100 - mix.oxygenPercent - mix.heliumPercent),
  );
}

bool _isValidPoint(TernaryTrajectoryPoint point) {
  return _isValidComposition(
    point.oxygenPercent,
    point.heliumPercent,
    point.nitrogenPercent,
  );
}

bool _isValidComposition(double oxygen, double helium, double nitrogen) {
  return oxygen.isFinite &&
      helium.isFinite &&
      nitrogen.isFinite &&
      oxygen >= 0 &&
      helium >= 0 &&
      nitrogen >= 0 &&
      (oxygen + helium + nitrogen - 100).abs() < 1e-6;
}

Map<String, Object?>? _mapOrNull(Object? value) {
  return value is Map<String, Object?> ? value : null;
}

double _numOrNan(Object? value) => value is num ? value.toDouble() : double.nan;

double? _numOrNull(Object? value) {
  return value is num && value.isFinite ? value.toDouble() : null;
}

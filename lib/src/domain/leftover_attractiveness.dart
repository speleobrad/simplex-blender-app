import 'dart:math' as math;

import 'package:simplex_blender/src/domain/physics.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

/// One standard trimix target (JS `STANDARD_TARGETS` entry).
class StandardTarget {
  const StandardTarget({
    required this.oxygenPercent,
    required this.heliumPercent,
  });

  final double oxygenPercent;
  final double heliumPercent;
}

const List<StandardTarget> standardTargets = [
  StandardTarget(oxygenPercent: 21, heliumPercent: 35),
  StandardTarget(oxygenPercent: 18, heliumPercent: 45),
  StandardTarget(oxygenPercent: 15, heliumPercent: 55),
  StandardTarget(oxygenPercent: 12, heliumPercent: 65),
  StandardTarget(oxygenPercent: 10, heliumPercent: 70),
];

const double scoreReferenceHeliumLitres = 1000;

const double _lineSlope = 3.077;
const double _lineDecay = 15;
final double _lineNorm = math.sqrt(_lineSlope * _lineSlope + 1);
const double _weightLine = 0.4;
const double _weightVersatility = 0.4;
const double _weightEnergy = 0.2;
const double _ratioToleranceBar = 1e-9;
const double _fractionSumTolerancePercent = 1e-9;

bool _isFiniteNonNegative(double? value) {
  return value != null && value.isFinite && value >= 0;
}

bool _hasValidFractions(double oxygenPercent, double heliumPercent) {
  return _isFiniteNonNegative(oxygenPercent) &&
      _isFiniteNonNegative(heliumPercent) &&
      oxygenPercent + heliumPercent <= 100 + _fractionSumTolerancePercent;
}

class _ComponentFractions {
  const _ComponentFractions({
    required this.oxygen,
    required this.helium,
    required this.nitrogen,
  });

  final double oxygen;
  final double helium;
  final double nitrogen;
}

// Largest f_x / t_x over the components; a component absent from the target
// but present in the gas makes the target unreachable by adding gas.
double _maxTopUpRatio(_ComponentFractions gas, _ComponentFractions target) {
  final pairs = <(double, double)>[
    (gas.oxygen, target.oxygen),
    (gas.helium, target.helium),
    (gas.nitrogen, target.nitrogen),
  ];
  var maxRatio = 0.0;
  for (final (fraction, targetFraction) in pairs) {
    if (fraction <= 0) continue;
    if (targetFraction <= 0) return double.infinity;
    maxRatio = math.max(maxRatio, fraction / targetFraction);
  }
  return maxRatio;
}

_ComponentFractions _componentFractions(
  double oxygenPercent,
  double heliumPercent,
) {
  final oxygen = oxygenPercent / 100;
  final helium = heliumPercent / 100;
  return _ComponentFractions(
    oxygen: oxygen,
    helium: helium,
    nitrogen: math.max(0, 1 - oxygen - helium),
  );
}

int _reachableTargetCount(
  _ComponentFractions gas,
  double pressureBar,
  double maxPressureBar,
) {
  var count = 0;
  for (final target in standardTargets) {
    final targetGas = _componentFractions(
      target.oxygenPercent,
      target.heliumPercent,
    );
    final ratio = _maxTopUpRatio(gas, targetGas);
    if (pressureBar * ratio <= maxPressureBar + _ratioToleranceBar) count += 1;
  }
  return count;
}

/// Number of standard trimix targets (0 to standardTargets.length) this bank's gas can still be
/// topped up to by adding gas only, within its maximum pressure. Invalid inputs count 0.
double leftoverReachability({
  required double oxygenPercent,
  required double heliumPercent,
  required double pressureBar,
  required double? maxPressureBar,
}) {
  final maxP = maxPressureBar;
  if (!_hasValidFractions(oxygenPercent, heliumPercent)) return 0;
  if (!_isFiniteNonNegative(pressureBar) ||
      maxP == null ||
      !_isFiniteNonNegative(maxP)) {
    return 0;
  }
  return _reachableTargetCount(
    _componentFractions(oxygenPercent, heliumPercent),
    pressureBar,
    maxP,
  ).toDouble();
}

double _lineScore(double oxygenPercent, double heliumPercent) {
  final residual =
      (_lineSlope * (oxygenPercent / 100) + heliumPercent / 100 - 1).abs();
  final perpendicularDistance = residual / _lineNorm;
  return math.exp(-_lineDecay * perpendicularDistance);
}

double _freeGasLitres(
  double pressureBar,
  double volumeL,
  double oxygenPercent,
  double heliumPercent,
  double temperatureC,
  bool useVdw,
) {
  final moles =
      calcMolarDensity(
        pressureBar,
        oxygenPercent,
        heliumPercent,
        temperatureC,
        useVdw,
      ) *
      volumeL;
  return moles * gasConstant * (temperatureC + 273.15);
}

/// Leftover attractiveness of a bank's gas for future blending, on a 0-100 scale.
/// Invalid inputs score 0. A null [physics] means the ideal model at [temperatureC].
double leftoverAttractiveness({
  required double oxygenPercent,
  required double heliumPercent,
  required double pressureBar,
  required double volumeL,
  required double? maxPressureBar,
  double temperatureC = 20,
  PhysicsInput? physics,
}) {
  final maxP = maxPressureBar;
  if (!_hasValidFractions(oxygenPercent, heliumPercent)) return 0;
  if (!_isFiniteNonNegative(pressureBar) ||
      !_isFiniteNonNegative(volumeL) ||
      maxP == null ||
      !_isFiniteNonNegative(maxP)) {
    return 0;
  }

  final useVdw = physics?.useVdw ?? false;
  final temperature = physics?.temperatureC ?? temperatureC;
  final gas = _componentFractions(oxygenPercent, heliumPercent);

  final sLine = _lineScore(oxygenPercent, heliumPercent);
  final sVersatility =
      _reachableTargetCount(gas, pressureBar, maxP) / standardTargets.length;
  final heliumLitres =
      _freeGasLitres(
        pressureBar,
        volumeL,
        oxygenPercent,
        heliumPercent,
        temperature,
        useVdw,
      ) *
      gas.helium;
  final sEnergy = math.min(1, heliumLitres / scoreReferenceHeliumLitres);

  return 100 *
      (_weightLine * sLine +
          _weightVersatility * sVersatility +
          _weightEnergy * sEnergy);
}

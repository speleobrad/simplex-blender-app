import 'dart:math' as math;

const double gasConstant = 0.083144626;
const double heliumSalvageMaxPercent = 98;

class _GasParameters {
  const _GasParameters(this.a, this.b);

  final double a;
  final double b;
}

const _GasParameters _helium = _GasParameters(0.0346, 0.0238);
const _GasParameters _oxygen = _GasParameters(1.382, 0.0319);
const _GasParameters _nitrogen = _GasParameters(1.370, 0.0387);

class MixParams {
  const MixParams({required this.a, required this.b});

  final double a;
  final double b;
}

MixParams getMixParams(double oxygenPercent, double heliumPercent) {
  final oxygenFraction = math.max(0.0, oxygenPercent) / 100;
  final heliumFraction = math.max(0.0, heliumPercent) / 100;
  final nitrogenFraction = math.max(0.0, 1 - oxygenFraction - heliumFraction);

  final attractionRoot =
      oxygenFraction * math.sqrt(_oxygen.a) +
      heliumFraction * math.sqrt(_helium.a) +
      nitrogenFraction * math.sqrt(_nitrogen.a);

  return MixParams(
    a: attractionRoot * attractionRoot,
    b:
        oxygenFraction * _oxygen.b +
        heliumFraction * _helium.b +
        nitrogenFraction * _nitrogen.b,
  );
}

double calcPressure(
  double molarDensity,
  double oxygenPercent,
  double heliumPercent,
  double temperatureC, [
  bool useVdw = true,
]) {
  final temperatureK = temperatureC + 273.15;
  if (!useVdw) return molarDensity * gasConstant * temperatureK;

  final mix = getMixParams(oxygenPercent, heliumPercent);
  final denominator = 1 - mix.b * molarDensity;
  if (denominator <= 0.001) return 9999;

  final pressure =
      (molarDensity * gasConstant * temperatureK) / denominator -
      mix.a * molarDensity * molarDensity;
  return math.max(0.0, pressure);
}

double calcMolarDensity(
  double pressureBar,
  double oxygenPercent,
  double heliumPercent,
  double temperatureC, [
  bool useVdw = true,
]) {
  final temperatureK = temperatureC + 273.15;
  if (pressureBar <= 0) return 0;
  if (!useVdw) return pressureBar / (gasConstant * temperatureK);

  final mix = getMixParams(oxygenPercent, heliumPercent);
  final a = mix.a;
  final b = mix.b;
  var density = pressureBar / (gasConstant * temperatureK);
  final maxDensity = 0.96 / b;
  if (density >= maxDensity) density = maxDensity * 0.8;

  for (var iteration = 0; iteration < 40; iteration++) {
    final denominator = 1 - b * density;
    if (denominator <= 0.001) {
      density = maxDensity * 0.95;
      break;
    }

    final residual =
        (density * gasConstant * temperatureK) / denominator -
        a * density * density -
        pressureBar;
    final derivative =
        (gasConstant * temperatureK) / (denominator * denominator) -
        2 * a * density;

    if (derivative.abs() < 1e-9) break;
    final delta = residual / derivative;
    density -= delta;

    if (density >= maxDensity) density = maxDensity * 0.95;
    if (density < 0) density = 1e-4;
    if (delta.abs() < 1e-6) break;
  }

  return math.max(0.0, density);
}

double calcZFromDensity(
  double pressureBar,
  double molarDensity,
  double temperatureC, [
  bool useVdw = true,
]) {
  if (pressureBar <= 0 || !useVdw || molarDensity <= 0) return 1;
  final temperatureK = temperatureC + 273.15;
  return pressureBar / (molarDensity * gasConstant * temperatureK);
}

double calcZ(
  double pressureBar,
  double oxygenPercent,
  double heliumPercent,
  double temperatureC, [
  bool useVdw = true,
]) {
  if (pressureBar <= 0 || !useVdw) return 1;
  final density = calcMolarDensity(
    pressureBar,
    oxygenPercent,
    heliumPercent,
    temperatureC,
    true,
  );
  return calcZFromDensity(pressureBar, density, temperatureC, true);
}

part of '../optimizer.dart';

/// JS `optimizeBlend`. Validates [input] first; an invalid input returns the JS
/// invalid-input failure.
Map<String, Object?> optimizeBlend(Map<String, Object?> input) {
  final inputErrors = _validateBlendInput(
    input,
    internalThermalTarget: _internalThermalTargetFlag(input),
  );
  if (inputErrors.isNotEmpty) {
    return _invalidBlendInputResult(inputErrors);
  }
  return solveThermalWithSalvageFallback(input, optimizeBlendWithoutThermal);
}

/// JS `solveThermalWithSalvageFallback`. [optimizeStatic] is the static solver;
/// [searchSalvage] defaults to `searchSalvageVariant` and is injectable so tests
/// can count searches.
Map<String, Object?> solveThermalWithSalvageFallback(
  Map<String, Object?> input,
  Map<String, Object?> Function(Map<String, Object?>) optimizeStatic, {
  List<String>? Function(Map<String, Object?>)? searchSalvage,
}) {
  final inputErrors = _validateBlendInput(
    input,
    internalThermalTarget: _internalThermalTargetFlag(input),
  );
  if (inputErrors.isNotEmpty) {
    return _invalidBlendInputResult(inputErrors);
  }
  final search = searchSalvage ?? searchSalvageVariant;
  final parsed = _parseBlendInput(input);
  final thermal = parsed.thermal;
  final ctx = thermal == null
      ? null
      : _ThermalContext(
          physics: parsed.physics,
          settings: parsed.settings,
          thermal: thermal,
        );
  Map<String, Object?> solve(Map<String, Object?> candidate) {
    if (ctx != null) {
      return _optimizeThermalBlend(candidate, optimizeStatic, ctx);
    }
    return optimizeStatic(candidate);
  }

  if (input['_salvage'] == false) {
    return solve(input);
  }
  final receiverIds = search(input);
  if (receiverIds == null) {
    return solve(<String, Object?>{...input, '_salvage': false});
  }
  final withSalvage = solve(<String, Object?>{
    ...input,
    '_salvageReceiverIds': receiverIds,
  });
  if (ctx == null || withSalvage['feasible'] == true) {
    return withSalvage;
  }
  final baselineResult = _optimizeThermalBlend(
    <String, Object?>{...input, '_salvage': false},
    optimizeStatic,
    ctx,
  );
  return baselineResult['feasible'] == true ? baselineResult : withSalvage;
}

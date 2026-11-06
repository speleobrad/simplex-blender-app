import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/domain/units.dart';

/// JS `formatTransferRate` (`js/ui/results.js` 253-268).
String formatTransferRate({
  required double? rateBarPerMin,
  required double durationMinutes,
  required List<ThermalSample> samples,
  String? units,
}) {
  final sampleRates = [
    for (final sample in samples)
      if (sample.elapsedMinutes <= durationMinutes &&
          sample.rateBarPerMin != null &&
          sample.rateBarPerMin!.isFinite)
        sample.rateBarPerMin!,
  ];
  final start = sampleRates.isNotEmpty ? sampleRates.first : rateBarPerMin;
  final end = sampleRates.isNotEmpty ? sampleRates.last : rateBarPerMin;
  if (start == null || end == null || !start.isFinite || !end.isFinite) {
    return '—';
  }
  String display(double value) =>
      convertToDisplay(value, 'pressureBarPerMin', units).toStringAsFixed(1);
  final range = (start - end).abs() < 1e-9
      ? display(start)
      : '${display(start)} - ${display(end)}';
  return '$range ${unitLabel('pressureBarPerMin', units)}';
}

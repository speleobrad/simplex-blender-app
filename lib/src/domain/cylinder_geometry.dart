import 'dart:math' as math;

import 'package:simplex_blender/src/domain/domain_error.dart';

/// Lower edge of the plausible `volume / envelope` band. Heuristic: the five
/// built-in cylinders fall between 0.60 and 0.77.
const double plausibleVolumeRatioMin = 0.45;

/// Upper edge of the plausible band. Heuristic, see [plausibleVolumeRatioMin].
const double plausibleVolumeRatioMax = 0.90;

bool _positiveFinite(double? value) =>
    value != null && value.isFinite && value > 0;

/// Heat-transfer surface in m²: side wall plus one hemispherical end
/// (`π·D·L + π·D²/2`). The bottom is excluded. Inputs are millimetres.
double tankSurfaceAreaM2({
  required double diameterMm,
  required double lengthMm,
}) {
  if (!_positiveFinite(diameterMm) || !_positiveFinite(lengthMm)) {
    throw const DomainError(
      'Cylinder diameter and length must be greater than 0 mm.',
    );
  }
  final d = diameterMm / 1000;
  final l = lengthMm / 1000;
  return math.pi * d * l + math.pi * d * d / 2;
}

/// Outer envelope volume in litres, `π/4 · D² · L`. The internal water volume
/// can never exceed it. Inputs are millimetres.
double cylinderEnvelopeVolumeL({
  required double diameterMm,
  required double lengthMm,
}) {
  final d = diameterMm / 1000;
  final l = lengthMm / 1000;
  return math.pi / 4 * d * d * l * 1000;
}

enum VolumePlausibility { plausible, tooSmall, tooLarge, impossible }

/// Classifies `volume / envelope`. The band edges are plausible; a ratio above
/// 1 cannot physically occur.
VolumePlausibility classifyVolumeRatio(double ratio) {
  if (ratio > 1) return VolumePlausibility.impossible;
  if (ratio > plausibleVolumeRatioMax) return VolumePlausibility.tooLarge;
  if (ratio < plausibleVolumeRatioMin) return VolumePlausibility.tooSmall;
  return VolumePlausibility.plausible;
}

/// Warning text for a volume that does not fit the stated geometry, or null
/// when the geometry is missing, invalid, or plausible. Advisory only.
String? cylinderPlausibilityMessage({
  required double volumeL,
  required double? diameterMm,
  required double? lengthMm,
}) {
  if (!_positiveFinite(diameterMm) ||
      !_positiveFinite(lengthMm) ||
      !_positiveFinite(volumeL)) {
    return null;
  }
  final ratio =
      volumeL /
      cylinderEnvelopeVolumeL(diameterMm: diameterMm!, lengthMm: lengthMm!);
  final shown = ratio.toStringAsFixed(2);
  return switch (classifyVolumeRatio(ratio)) {
    VolumePlausibility.plausible => null,
    VolumePlausibility.tooSmall =>
      'Volume looks too small for this diameter and length '
          '(volume is $shown of the outer envelope). Check the dimensions.',
    VolumePlausibility.tooLarge =>
      'Volume looks too large for this diameter and length '
          '(volume is $shown of the outer envelope). Check the dimensions.',
    VolumePlausibility.impossible =>
      'Volume is impossible for this diameter and length '
          '(volume is $shown of the outer envelope). Check the dimensions.',
  };
}

/// Message shown where the selected preset name matches no preset in Settings.
const String selectCylinderPresetMessage =
    'Select an available cylinder preset.';

/// Message shown where an incomplete preset is refused.
String incompleteCylinderMessage(String name) =>
    'Cylinder preset “$name” needs a diameter and length. '
    'Enter them in Settings > Cylinder presets.';

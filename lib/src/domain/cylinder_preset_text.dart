import 'package:simplex_blender/src/domain/settings.dart';

/// `184.2 mm × 658.0 mm, 0.43 m² heat-transfer surface.` for a complete
/// preset; null when the diameter or length is missing.
String? cylinderGeometryText(CylinderPreset preset) {
  if (!preset.isComplete) {
    return null;
  }
  return '${preset.diameterMm!.toStringAsFixed(1)} mm × '
      '${preset.lengthMm!.toStringAsFixed(1)} mm, '
      '${preset.surfaceAreaM2.toStringAsFixed(2)} m² heat-transfer surface.';
}

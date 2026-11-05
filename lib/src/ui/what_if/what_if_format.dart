import 'package:simplex_blender/src/domain/pressure_limits.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/units.dart';

/// JS number-to-string: whole numbers have no trailing `.0`.
String jsNumberText(double value) {
  if (value.isFinite && value == value.truncateToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// JS `formatScenarioInputValue`. Takes a metric value and a canonical
/// quantity (`pressureBar` or `temperatureC`), returns display-unit text.
/// Temperatures drop a trailing `.0`.
String scenarioInputText(double metricValue, String quantity, String? units) {
  final text = formatInputValue(metricValue, quantity, units);
  return quantity == 'temperatureC'
      ? text.replaceFirst(RegExp(r'\.0$'), '')
      : text;
}

/// Looks up a cylinder preset by name; null when absent.
CylinderPreset? findCylinderPreset(List<CylinderPreset> presets, String? name) {
  if (name == null) {
    return null;
  }
  for (final preset in presets) {
    if (preset.name == name) {
      return preset;
    }
  }
  return null;
}

const Map<String, String> _warningSourceLabels = <String, String>{
  'initial': 'Initial input',
  'target': 'Target input',
  'interim': 'Interim input',
  'ambient': 'Ambient state',
  'settled': 'Settled state',
  'start': 'Start state',
  'cooling': 'Cooling state',
};

/// JS `pressureWarningLocation` (results.js).
String _warningLocation(CylinderPressureWarning warning) {
  final identifier = warning.stepIdentifier;
  if (identifier != null && identifier.isNotEmpty) {
    return identifier;
  }
  return _warningSourceLabels[warning.source] ?? 'Recorded input';
}

/// JS `formatPressureWarning` (results.js).
String pressureWarningText(CylinderPressureWarning warning, String? units) {
  final kind = warning.kind == 'hot-overfill'
      ? 'Transient hot-overfill'
      : 'Working pressure';
  final pressure = formatUnitValue(warning.pressureBar, 'pressureBar', units);
  final limit = formatUnitValue(warning.limitBar, 'pressureBar', units);
  return '$kind limit exceeded: $pressure > $limit '
      '(${_warningLocation(warning)})';
}

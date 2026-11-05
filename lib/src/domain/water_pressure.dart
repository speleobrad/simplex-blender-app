import 'package:simplex_blender/src/domain/thermodynamics.dart';

// ignore: non_constant_identifier_names
final List<double> WATER_TEMPERATURES_C = List.unmodifiable(
  List.generate(13, (index) => 4.0 + index * 2.0),
);

// ignore: non_constant_identifier_names
final List<double> CAR_TEMPERATURES_C = List.unmodifiable(
  List.generate(8, (index) => 25.0 + index * 5.0),
);

/// One projected pressure row, JS `{...projection, exceedsWorkingPressure}`.
class PressureProjectionRow {
  const PressureProjectionRow({
    required this.temperatureC,
    required this.pressureBar,
    required this.exceedsWorkingPressure,
  });

  final double temperatureC;
  final double pressureBar;
  final bool exceedsWorkingPressure;
}

typedef PressureProjectionData = ({
  List<PressureProjectionRow> water,
  List<PressureProjectionRow> car,
});

/// Splits rows into two contiguous halves; the first half gets the extra row when odd.
(List<T>, List<T>) splitPressureProjections<T>(List<T> projections) {
  final midpoint = (projections.length / 2).ceil();
  return (projections.sublist(0, midpoint), projections.sublist(midpoint));
}

bool isPressureAboveWorkingPressure(
  double? pressureBar,
  double? workingPressureBar,
) {
  if (pressureBar == null || workingPressureBar == null) {
    return false;
  }
  return pressureBar.isFinite &&
      workingPressureBar.isFinite &&
      pressureBar > workingPressureBar;
}

/// Water and car series for the pressure pane; null when any input is non-finite or the volume is not positive.
PressureProjectionData? buildPressureProjectionData({
  required double? pressureBar,
  required double? oxygenPercent,
  required double? heliumPercent,
  required double? fromTemperatureC,
  required double? volumeL,
  required double? workingPressureBar,
  required bool useVdw,
}) {
  if (pressureBar == null ||
      oxygenPercent == null ||
      heliumPercent == null ||
      fromTemperatureC == null ||
      volumeL == null) {
    return null;
  }
  if (!pressureBar.isFinite ||
      !oxygenPercent.isFinite ||
      !heliumPercent.isFinite ||
      !fromTemperatureC.isFinite ||
      !volumeL.isFinite ||
      volumeL <= 0) {
    return null;
  }

  return (
    water: _projectRows(
      pressureBar: pressureBar,
      oxygenPercent: oxygenPercent,
      heliumPercent: heliumPercent,
      fromTemperatureC: fromTemperatureC,
      temperaturesC: WATER_TEMPERATURES_C,
      volumeL: volumeL,
      workingPressureBar: workingPressureBar,
      useVdw: useVdw,
    ),
    car: _projectRows(
      pressureBar: pressureBar,
      oxygenPercent: oxygenPercent,
      heliumPercent: heliumPercent,
      fromTemperatureC: fromTemperatureC,
      temperaturesC: CAR_TEMPERATURES_C,
      volumeL: volumeL,
      workingPressureBar: workingPressureBar,
      useVdw: useVdw,
    ),
  );
}

List<PressureProjectionRow> _projectRows({
  required double pressureBar,
  required double oxygenPercent,
  required double heliumPercent,
  required double fromTemperatureC,
  required List<double> temperaturesC,
  required double volumeL,
  required double? workingPressureBar,
  required bool useVdw,
}) {
  final projections = projectPressureAtTemperatures(
    pressureBar: pressureBar,
    oxygenPercent: oxygenPercent,
    heliumPercent: heliumPercent,
    fromTemperatureC: fromTemperatureC,
    temperaturesC: temperaturesC,
    volumeL: volumeL,
    useVdw: useVdw,
  );
  return [
    for (final projection in projections)
      PressureProjectionRow(
        temperatureC: projection.temperatureC,
        pressureBar: projection.pressureBar,
        exceedsWorkingPressure: isPressureAboveWorkingPressure(
          projection.pressureBar,
          workingPressureBar,
        ),
      ),
  ];
}

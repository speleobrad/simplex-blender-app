import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/water_pressure.dart';

void main() {
  group('water pressure projections', () {
    test(
      'builds water and car pressure series with working-pressure flags',
      () {
        final data = buildPressureProjectionData(
          pressureBar: 210,
          oxygenPercent: 18,
          heliumPercent: 45,
          fromTemperatureC: 20,
          volumeL: 12,
          workingPressureBar: 220,
          useVdw: false,
        )!;

        expect(
          data.water.map((row) => row.temperatureC).toList(),
          equals([4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28]),
        );
        expect(
          data.car.map((row) => row.temperatureC).toList(),
          equals([25, 30, 35, 40, 45, 50, 55, 60]),
        );
        expect(data.water.every((row) => !row.exceedsWorkingPressure), isTrue);
        expect(data.car.any((row) => row.exceedsWorkingPressure), isTrue);
        expect(isPressureAboveWorkingPressure(220, 220), isFalse);
        expect(isPressureAboveWorkingPressure(220.1, 220), isTrue);
        expect(isPressureAboveWorkingPressure(double.nan, 220), isFalse);
      },
    );

    test('splits projection rows into balanced contiguous table columns', () {
      final projections = List<int>.generate(13, (index) => index);

      final (first, second) = splitPressureProjections(projections);

      expect(first, equals(projections.sublist(0, 7)));
      expect(second, equals(projections.sublist(7)));
    });
  });
}

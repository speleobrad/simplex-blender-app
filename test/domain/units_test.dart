import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/units.dart';

void main() {
  group('units', () {
    test('imperial conversions use scuba volume and pressure units', () {
      expect(
        convertToDisplay(10, 'volumeL', imperialUnits),
        closeTo(0.353146667, 1e-9),
      );
      expect(
        convertFromDisplay(0.353146667, 'volumeL', imperialUnits),
        closeTo(10, 1e-6),
      );
      expect(
        convertToDisplay(200, 'pressureBar', imperialUnits),
        closeTo(2900.75476, 1e-5),
      );
      expect(
        convertFromDisplay(2900.75476, 'pressureBar', imperialUnits),
        closeTo(200, 1e-6),
      );
    });

    test('material labels follow the selected unit system', () {
      expect(materialLabel('aluminum', metricUnits), 'Aluminium');
      expect(materialLabel('aluminum', imperialUnits), 'Aluminum');
      expect(materialLabel('steel', metricUnits), 'Steel');
    });

    test(
      'imperial conversions cover mass, temperature, flow, and small volume',
      () {
        expect(
          convertToDisplay(10, 'massKg', imperialUnits),
          closeTo(22.0462262185, 1e-9),
        );
        expect(convertToDisplay(25, 'temperatureC', imperialUnits), 77);
        expect(convertToDisplay(10, 'temperatureDeltaC', imperialUnits), 18);
        expect(
          convertToDisplay(100, 'flowLPerMin', imperialUnits),
          closeTo(3.53146667, 1e-8),
        );
        expect(
          convertToDisplay(5, 'pressureBarPerMin', imperialUnits),
          closeTo(72.518869, 1e-6),
        );
        expect(
          convertToDisplay(9, 'volumeCm3', imperialUnits),
          closeTo(0.5492136969, 1e-9),
        );
      },
    );

    test('metric units are identity conversions and formatting includes the selected unit', () {
      expect(convertToDisplay(12.5, 'volumeL', metricUnits), 12.5);
      expect(convertFromDisplay(12.5, 'volumeL', metricUnits), 12.5);
      expect(formatUnitValue(11.1, 'volumeL', metricUnits, 1), '11.1 L');
      expect(formatUnitValue(1, 'volumeL', imperialUnits, 2), '0.04 cu ft');
    });

    test('formats pressure inputs to one decimal place in PSI', () {
      expect(formatInputValue(200, 'pressureBar', imperialUnits), '2900.8');
      expect(formatInputValue(350, 'pressureBar', imperialUnits), '5076.3');
      expect(formatInputValue(200, 'pressureBar', metricUnits), '200');
    });

    test(
      'formats temperature inputs to one decimal place in both unit systems',
      () {
        expect(formatInputValue(22.5, 'temperatureC', metricUnits), '22.5');
        expect(formatInputValue(22.5, 'temperatureC', imperialUnits), '72.5');
      },
    );

    test('price per litre converts to price per cubic foot and back', () {
      expect(convertToDisplay(0.02, 'pricePerVolumeL', 'metric'), 0.02);
      final perCubicFoot = convertToDisplay(
        0.02,
        'pricePerVolumeL',
        'imperial',
      );
      expect(perCubicFoot, closeTo(0.02 * 28.316846592, 1e-12));
      expect(
        convertFromDisplay(perCubicFoot, 'pricePerVolumeL', 'imperial'),
        closeTo(0.02, 1e-12),
      );
      expect(unitLabel('pricePerVolumeL', 'metric'), '/L');
      expect(unitLabel('pricePerVolumeL', 'imperial'), '/cu ft');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/physics.dart';

void main() {
  group('physics', () {
    test('ideal-gas pressure uses kelvin and bar-litres per mole', () {
      expect(calcPressure(1, 21, 0, 20, false), closeTo(24.3738471119, 1e-10));
    });

    test('VDW density matches the current 200-bar trimix calculation', () {
      expect(
        calcMolarDensity(200, 18, 45, 20, true),
        closeTo(7.263268210473831, 1e-10),
      );
    });

    test('VDW pressure round-trips the requested state and zero pressure is neutral', () {
      final density = calcMolarDensity(200, 18, 45, 20, true);
      expect(calcPressure(density, 18, 45, 20, true), closeTo(200, 1e-8));
      expect(calcMolarDensity(0, 18, 45, 20, true), 0);
      expect(calcZ(0, 18, 45, 20, true), 1);
    });

    test(
      'compressibility uses an already calculated density with the same model',
      () {
        expect(
          calcZFromDensity(200, 7.263268210473831, 20, true),
          closeTo(1.1297278403662991, 1e-12),
        );
        expect(calcZFromDensity(0, 0, 20, true), 1);
        expect(calcZFromDensity(200, 3, 20, false), 1);
      },
    );
  });
}

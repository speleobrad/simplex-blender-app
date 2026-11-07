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

    test('VDW density round-trips through pressure over the valid grid', () {
      // Silent-failure guard: calcMolarDensity clamps and breaks out of its
      // Newton loop without signalling. A solved density that does not
      // reproduce the requested pressure is the only observable symptom.
      for (var oxygen = 0.0; oxygen <= 100; oxygen += 10) {
        for (var helium = 0.0; helium <= 100 - oxygen; helium += 10) {
          for (var temperature = -10.0; temperature <= 40; temperature += 10) {
            for (final pressure in [0.5, 5.0, 50.0, 200.0, 400.0]) {
              final density = calcMolarDensity(
                pressure,
                oxygen,
                helium,
                temperature,
                true,
              );
              expect(
                calcPressure(density, oxygen, helium, temperature, true),
                closeTo(pressure, pressure * 1e-9),
                reason:
                    'O2 $oxygen% He $helium% at ${temperature}C, $pressure bar',
              );
            }
          }
        }
      }
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

    test(
      'inventoryPressure matches calcPressure at the inventory molar density',
      () {
        const volumeL = 10.0;
        const moles = 4.0;
        const oxygenPercent = 21.0;
        final expected = calcPressure(
          moles / volumeL,
          oxygenPercent,
          0,
          20,
          true,
        );
        final actual = inventoryPressure(
          moles: moles,
          volumeL: volumeL,
          oxygenMoles: moles * oxygenPercent / 100,
          heliumMoles: 0,
          temperatureC: 20,
          useVdw: true,
        );
        expect(actual, closeTo(expected, 1e-9));
      },
    );

    test('inventoryPressure is zero for an empty inventory', () {
      expect(
        inventoryPressure(
          moles: 0,
          volumeL: 10,
          oxygenMoles: 0,
          heliumMoles: 0,
          temperatureC: 20,
          useVdw: true,
        ),
        0,
      );
    });
  });
}

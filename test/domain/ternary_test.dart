import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/ternary_geometry.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

void main() {
  group('ternary', () {
    test('air is the solid-region vertex on the O2/N2 edge', () {
      final vertices = createVertices(300, 300);
      final air = toCanvasPoint(21, 0, 79, vertices);
      expect(air.x, closeTo(vertices.air.x, 1e-9));
      expect(air.y, closeTo(vertices.air.y, 1e-9));
      expect(air, isNot(equals(vertices.nitrogen)));
    });

    test('infeasible region uses nitrogen, air, and helium vertices in drawing order', () {
      final vertices = createVertices(300, 300);

      expect(
        getInfeasibleRegionVertices(vertices),
        equals([
          toCanvasPoint(0, 0, 100, vertices),
          toCanvasPoint(21, 0, 79, vertices),
          toCanvasPoint(0, 100, 0, vertices),
        ]),
      );
    });

    test('15/0 lies beyond the feasible Air/O2 edge', () {
      final vertices = createVertices(300, 300);
      final lowOxygen = toCanvasPoint(15, 0, 85, vertices);
      expect(lowOxygen.y, greaterThan(vertices.air.y));
    });

    test('maximum zoom keeps every projected trajectory point inside the inset canvas', () {
      const trajectory = [
        TernaryPoint(x: 30, y: 30),
        TernaryPoint(x: 40, y: 38),
        TernaryPoint(x: 50, y: 40),
      ];
      TernaryPoint project(TernaryPoint point) => point;
      const width = 220.0;
      const height = 140.0;
      const margin = 20.0;
      final zoom = calculateMaxZoom(trajectory, project, width, height, margin);
      const center = TernaryPoint(x: 40, y: 35);
      expect(zoom, greaterThanOrEqualTo(1));
      for (final point in trajectory) {
        final x = (point.x - center.x) * zoom + width / 2;
        final y = (point.y - center.y) * zoom + height / 2;
        expect(x, greaterThanOrEqualTo(margin - 1e-9));
        expect(x, lessThanOrEqualTo(width - margin + 1e-9));
        expect(y, greaterThanOrEqualTo(margin - 1e-9));
        expect(y, lessThanOrEqualTo(height - margin + 1e-9));
      }
    });

    test('empty and point-sized paths cannot create an unbounded zoom', () {
      TernaryPoint identity(TernaryPoint point) => point;
      expect(calculateMaxZoom<TernaryPoint>(const [], identity, 220, 140), 1);
      expect(
        calculateMaxZoom(
          const [TernaryPoint(x: 10, y: 10)],
          identity,
          220,
          140,
        ),
        1,
      );
    });

    test(
      'zoom preserves the full view at 1x and centers the path at maximum zoom',
      () {
        const point = TernaryPoint(x: 30, y: 30);
        const center = TernaryPoint(x: 40, y: 35);
        expect(
          transformPointForZoom(point, center, 1, 9, 220, 140),
          equals(const TernaryPoint(x: 30, y: 30)),
        );
        expect(
          transformPointForZoom(point, center, 9, 9, 220, 140),
          equals(const TernaryPoint(x: 20, y: 25)),
        );
      },
    );

    test('zoom controls change zoom within the diagram bounds', () {
      expect(getNextZoom(1, 3, 1), 1.25);
      expect(getNextZoom(2.8, 3, 1), 3);
      expect(getNextZoom(1.1, 3, -1), 1);
    });

    test('formats gas composition as O2/He with one decimal place', () {
      expect(formatGasMix(21, 0), '21.0/0.0');
      expect(formatGasMix(0, 100), '0.0/100.0');
      expect(formatGasMix(19.46, 40.04), '19.5/40.0');
    });

    test(
      'compare accessible data keeps manual stages without supply banks',
      () {
        final data = buildAccessibleTernaryData(
          mode: 'compare',
          banks: const [],
          initialMix: const GasMixPercent(oxygenPercent: 21, heliumPercent: 0),
          targetMix: const GasMixPercent(oxygenPercent: 18, heliumPercent: 35),
          trajectory: const [
            TernaryTrajectoryPoint(
              step: 0,
              label: 'Start mix',
              oxygenPercent: 21,
              heliumPercent: 0,
              nitrogenPercent: 79,
              pressureBar: 100,
            ),
            TernaryTrajectoryPoint(
              step: 1,
              label: 'Step 1',
              oxygenPercent: 20,
              heliumPercent: 15,
              nitrogenPercent: 65,
              pressureBar: 120,
            ),
            TernaryTrajectoryPoint(
              step: 2,
              label: 'Step 2',
              oxygenPercent: 18,
              heliumPercent: 35,
              nitrogenPercent: 47,
              pressureBar: 200,
            ),
          ],
        );

        expect(
          data.mixRows.map((row) => row.label).toList(),
          equals(['Air reference', 'Initial mix', 'Final mix']),
        );
        expect(
          data.trajectoryRows
              .map((row) => [row.label, row.pressureBar])
              .toList(),
          equals([
            ['Start mix', 100],
            ['Step 1', 120],
            ['Step 2', 200],
          ]),
        );
        expect(data.status, 'Data covers 2 recipe stages.');
      },
    );
  });
}

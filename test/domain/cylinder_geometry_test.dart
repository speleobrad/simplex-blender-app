import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/cylinder_geometry.dart';
import 'package:simplex_blender/src/domain/domain_error.dart';

void main() {
  group('tankSurfaceAreaM2', () {
    // Hand computation: pi*D*L + pi*D^2/2 with D, L in metres.
    const cases = <(String, double, double, double)>[
      ('Faber 3L', 100.1, 495.3, 0.1715),
      ('Catalina S13', 111.3, 325, 0.1331),
      ('Luxfer S40', 133, 625, 0.2889),
      ('Luxfer S80', 184, 662, 0.4358),
      ('Catalina S80', 184.2, 658, 0.4341),
    ];
    for (final (name, d, l, expected) in cases) {
      test(name, () {
        expect(
          tankSurfaceAreaM2(diameterMm: d, lengthMm: l),
          closeTo(expected, 5e-4),
        );
      });
    }

    test('rejects non-positive and non-finite dimensions', () {
      for (final (d, l) in <(double, double)>[
        (0, 500),
        (-1, 500),
        (100, 0),
        (100, -5),
        (double.nan, 500),
        (100, double.infinity),
      ]) {
        expect(
          () => tankSurfaceAreaM2(diameterMm: d, lengthMm: l),
          throwsA(isA<DomainError>()),
          reason: 'D=$d L=$l',
        );
      }
    });
  });

  group('plausibility', () {
    test('envelope volume of a 100 x 500 mm cylinder is about 3.927 L', () {
      expect(
        cylinderEnvelopeVolumeL(diameterMm: 100, lengthMm: 500),
        closeTo(3.927, 1e-3),
      );
    });

    test(
      'classifyVolumeRatio thresholds are inclusive of the plausible band',
      () {
        expect(classifyVolumeRatio(0.45), VolumePlausibility.plausible);
        expect(classifyVolumeRatio(0.90), VolumePlausibility.plausible);
        expect(classifyVolumeRatio(0.4499), VolumePlausibility.tooSmall);
        expect(classifyVolumeRatio(0.9001), VolumePlausibility.tooLarge);
        expect(classifyVolumeRatio(1.0), VolumePlausibility.tooLarge);
        expect(classifyVolumeRatio(1.0001), VolumePlausibility.impossible);
      },
    );

    test('every default cylinder is plausible', () {
      const defaults = <(double, double, double)>[
        (3, 100.1, 495.3),
        (1.9, 111.3, 325),
        (5.7, 133, 625),
        (11.1, 184, 662),
        (11.1, 184.2, 658),
      ];
      for (final (v, d, l) in defaults) {
        expect(
          cylinderPlausibilityMessage(volumeL: v, diameterMm: d, lengthMm: l),
          isNull,
          reason: 'V=$v D=$d L=$l',
        );
      }
    });

    test('3 L with a 186 x 500 mm body is flagged as too small', () {
      final message = cylinderPlausibilityMessage(
        volumeL: 3,
        diameterMm: 186,
        lengthMm: 500,
      );
      expect(message, contains('too small'));
      expect(message, contains('0.22'));
    });

    test('20 L on S80 dimensions is flagged as impossible', () {
      final message = cylinderPlausibilityMessage(
        volumeL: 20,
        diameterMm: 184.2,
        lengthMm: 658,
      );
      expect(message, contains('impossible'));
    });

    test('missing or invalid geometry is not checked', () {
      expect(
        cylinderPlausibilityMessage(
          volumeL: 3,
          diameterMm: null,
          lengthMm: 500,
        ),
        isNull,
      );
      expect(
        cylinderPlausibilityMessage(
          volumeL: 3,
          diameterMm: double.nan,
          lengthMm: 500,
        ),
        isNull,
      );
    });
  });

  test('incompleteCylinderMessage names the preset', () {
    expect(
      incompleteCylinderMessage('Faber 7L'),
      'Cylinder preset “Faber 7L” needs a diameter and length. '
      'Enter them in Settings > Cylinder presets.',
    );
  });
}

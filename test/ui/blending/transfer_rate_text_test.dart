import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/domain/units.dart';
import 'package:simplex_blender/src/ui/blending/transfer_rate_text.dart';

ThermalSample _sample(double elapsedMinutes, double? rateBarPerMin) =>
    ThermalSample(
      elapsedMinutes: elapsedMinutes,
      temperatureC: 20,
      pressureBar: 100,
      rateBarPerMin: rateBarPerMin,
    );

void main() {
  test('shows the first and last sampled rate for profile transfers', () {
    expect(
      formatTransferRate(
        rateBarPerMin: 1.5,
        durationMinutes: 2,
        samples: [_sample(0, 3), _sample(1, 1.5), _sample(2, 0.8)],
      ),
      '3.0 - 0.8 bar/min',
    );
  });

  test('ignores null trailing samples and collapses a constant rate', () {
    expect(
      formatTransferRate(
        rateBarPerMin: 1.5,
        durationMinutes: 2,
        samples: [_sample(0, 1.5), _sample(2, 1.5), _sample(3, null)],
      ),
      '1.5 bar/min',
    );
  });

  test('uses the configured rate without samples and dashes when absent', () {
    expect(
      formatTransferRate(
        rateBarPerMin: 3,
        durationMinutes: 0,
        samples: const [],
      ),
      '3.0 bar/min',
    );
    expect(
      formatTransferRate(
        rateBarPerMin: null,
        durationMinutes: 0,
        samples: const [],
      ),
      '—',
    );
  });

  test('converts to imperial units', () {
    expect(
      formatTransferRate(
        rateBarPerMin: 1,
        durationMinutes: 0,
        samples: const [],
        units: imperialUnits,
      ),
      '14.5 psi/min',
    );
  });

  test('ignores samples after the transfer window', () {
    expect(
      formatTransferRate(
        rateBarPerMin: 1.5,
        durationMinutes: 2,
        samples: [_sample(0, 3), _sample(2, 0.8), _sample(3, 0.1)],
      ),
      '3.0 - 0.8 bar/min',
    );
  });
}

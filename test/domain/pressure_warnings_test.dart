import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/pressure_limits.dart';
import 'package:simplex_blender/src/domain/pressure_warnings.dart';

// Source of truth: js/main.js collectPressureWarnings (returns [] unless
// pressureLimitMode is 'warning', otherwise collectCylinderPressureWarnings).

const CylinderPressureSpec _cylinder100 = CylinderPressureSpec(
  workingPressureBar: 100,
  hotOverfillPercent: 0,
);

// 150 bar is above the 100 bar working pressure, so it must warn.
const List<PressureObservation> _overLimit = <PressureObservation>[
  PressureObservation(
    pressureBar: 150,
    source: 'initial',
    stepIdentifier: null,
    stepIndex: null,
  ),
];

void main() {
  test('the mode gate returns no warnings unless the mode is warning', () {
    final hardStop = collectPressureWarnings(
      pressureLimitMode: 'hard-stop',
      cylinder: _cylinder100,
      observations: _overLimit,
    );
    final unknown = collectPressureWarnings(
      pressureLimitMode: 'Warning',
      cylinder: _cylinder100,
      observations: _overLimit,
    );

    expect(hardStop, isEmpty);
    expect(unknown, isEmpty);
  });

  test('in warning mode collectPressureWarnings matches collectCylinderPressureWarnings', () {
    final gated = collectPressureWarnings(
      pressureLimitMode: 'warning',
      cylinder: _cylinder100,
      observations: _overLimit,
    );
    final direct = collectCylinderPressureWarnings(
      cylinder: _cylinder100,
      observations: _overLimit,
    );

    expect(gated, isNotEmpty);
    expect(gated.length, direct.length);
    for (var index = 0; index < direct.length; index++) {
      expect(gated[index].kind, direct[index].kind);
      expect(gated[index].source, direct[index].source);
      expect(gated[index].stepIdentifier, direct[index].stepIdentifier);
      expect(gated[index].stepIndex, direct[index].stepIndex);
    }
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/ui/blending/blending_form.dart';

import '../../support/memory_storage.dart';

import 'package:simplex_blender/src/ui/shell/tour_targets.dart';

// Source of truth: browser/blending.spec.js. Line references are to the JS
// spec that asserts the same visible behaviour: the cylinder rating hint
// (settings.spec.js, `#cylinder-rating-hint`), the submersion field shown
// only for water (blending.spec.js 36-40), the gas preset select falling back
// to Custom after a manual O2 edit (blending.spec.js 55-61), and the wait-mode
// fields (blending.spec.js 98-103).

CylinderPreset _catalinaS80() => DEFAULT_SETTINGS.cylinderPresets.firstWhere(
  (preset) => preset.name == 'Catalina S80',
);

BlendInputs _inputs({String medium = 'air'}) => BlendInputs(
  cylinderPreset: _catalinaS80(),
  initialPressureBar: 50,
  initialOxygenPercent: 21,
  initialHeliumPercent: 0,
  targetPressureBar: 195,
  targetOxygenPercent: 18,
  targetHeliumPercent: 45,
  ambientTemperatureC: 21,
  targetInWaterTemperatureC: 10,
  waitTargetTemperatureC: 25,
  inletTemperatureC: 21,
  coolingMedium: medium,
  waterSubmersionPercent: 60,
  waitMode: 'minutes',
  waitMinutes: 5,
);

class _Harness {
  _Harness(this.app, this.blend);

  final AppController app;
  final BlendController blend;

  static _Harness create({String medium = 'air'}) {
    const analytics = NoopAnalytics();
    final app = AppController(storage: MemoryStorage(), analytics: analytics);
    final blend = BlendController(
      inputs: _inputs(medium: medium),
      banks: app.banks,
      settings: app.settings,
      updateBank: (_) {},
      analytics: analytics,
    );
    return _Harness(app, blend);
  }
}

Future<void> _pump(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(
    TourTargetsScope(
      targets: TourTargets(),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BlendingForm(controller: harness.blend, app: harness.app),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _textMatching(RegExp pattern) => find.byWidgetPredicate((widget) {
  if (widget is! Text) {
    return false;
  }
  final data = widget.data;
  return data != null && pattern.hasMatch(data);
});

void main() {
  testWidgets('shows the working tank labels and hides submersion for air', (
    tester,
  ) async {
    final harness = _Harness.create();
    await _pump(tester, harness);

    for (final label in <String>[
      'Working tank',
      'CURRENT',
      'TARGET',
      'Start pressure:',
      'Ambient temperature:',
      'Target pressure:',
      'Dive site temperature:',
      'Cylinder',
      'Surrounding medium',
      'Wait between fills',
      'Wait time',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Tank submerged'), findsNothing);
    expect(find.text('Target medium temperature'), findsNothing);
  });

  testWidgets('shows the cylinder rating hint for the selected preset', (
    tester,
  ) async {
    final harness = _Harness.create();
    await _pump(tester, harness);

    // JS: /11\.10 L alumini?um cylinder.*14\.30 kg.*207\.00 bar/i
    expect(
      _textMatching(
        RegExp(r'11\.10 L alumini?um cylinder.*14\.30 kg.*207\.00 bar'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows tank submersion once the medium is water', (tester) async {
    final harness = _Harness.create();
    await _pump(tester, harness);

    harness.blend.setInputs(
      harness.blend.inputs.copyWith(coolingMedium: 'water'),
    );
    await tester.pump();

    expect(find.text('Tank submerged'), findsOneWidget);
  });

  testWidgets('switches the wait fields when wait mode is temperature', (
    tester,
  ) async {
    final harness = _Harness.create();
    await _pump(tester, harness);

    harness.blend.setInputs(
      harness.blend.inputs.copyWith(waitMode: 'temperature'),
    );
    await tester.pump();

    expect(find.text('Target medium temperature'), findsOneWidget);
    expect(find.text('Wait time'), findsNothing);
  });

  testWidgets('a manual target O2 edit writes the input and shows Custom', (
    tester,
  ) async {
    final harness = _Harness.create();
    await _pump(tester, harness);

    final targetOxygen = find.descendant(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Target oxygen percentage',
      ),
      matching: find.byType(TextField),
    );
    await tester.enterText(targetOxygen, '21');
    await tester.pump();

    expect(harness.blend.inputs.targetOxygenPercent, 21);
    expect(find.text('Custom'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/interim_measurements.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/domain/units.dart';
import 'package:simplex_blender/src/ui/blending/mixing_steps.dart';
import 'package:simplex_blender/src/ui/shell/tour_targets.dart';

import '../../support/memory_storage.dart';

// Source of truth: js/ui/results.js `renderProtocol` and the interim
// measurement control (480-575); index.html 600-606 for the section markup.
// The valid reading is the planned start state of a measured step, as in
// test/controllers/blend_controller_test.dart.

CylinderPreset _catalinaS80() => DEFAULT_SETTINGS.cylinderPresets.firstWhere(
  (preset) => preset.name == 'Catalina S80',
);

BlendInputs _inputs() => BlendInputs(
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
  coolingMedium: 'water',
  waterSubmersionPercent: 40,
  waitMode: 'minutes',
  waitMinutes: 5,
);

class _Harness {
  _Harness(this.app, this.blend);

  final AppController app;
  final BlendController blend;

  static _Harness create() {
    const analytics = NoopAnalytics();
    final app = AppController(storage: MemoryStorage(), analytics: analytics);
    final blend = BlendController(
      inputs: _inputs(),
      banks: app.banks,
      settings: app.settings,
      updateBank: (_) {},
      analytics: analytics,
    );
    return _Harness(app, blend);
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Harness harness, {
  TourTargets? targets,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TourTargetsScope(
            targets: targets ?? TourTargets(),
            child: MixingSteps(controller: harness.blend, app: harness.app),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

List<ProtocolStep> _steps(BlendController controller) =>
    controller.lastResult!['protocolSteps']! as List<ProtocolStep>;

/// First step that shows an interim control: after the first step, not a
/// keep, salvage, or drain step, and carrying a measurement index.
int _measurableIndex(List<ProtocolStep> steps) {
  for (var index = 1; index < steps.length; index++) {
    final step = steps[index];
    final thermal = step.thermal;
    if (thermal != null &&
        thermal.measurementIndex != null &&
        step.type != 'keep' &&
        step.type != 'salvage' &&
        step.type != 'drain') {
      return index;
    }
  }
  fail('the default recipe has no step that accepts an interim reading');
}

Finder _errorText(Finder card) => find.descendant(
  of: card,
  matching: find.byWidgetPredicate((widget) {
    if (widget is! Text) {
      return false;
    }
    final data = widget.data ?? '';
    return data.startsWith('Measured pressure') ||
        data.startsWith('Measured temperature') ||
        data.startsWith('This reading cannot');
  }),
);

Future<void> _enterReading(
  WidgetTester tester,
  Finder card, {
  required String units,
  required double pressureBar,
  required double temperatureC,
}) async {
  final pressureField = find
      .descendant(of: card, matching: find.byType(TextField))
      .at(0);
  final temperatureField = find
      .descendant(of: card, matching: find.byType(TextField))
      .at(1);
  await tester.ensureVisible(pressureField);
  await tester.enterText(
    pressureField,
    convertToDisplay(pressureBar, 'pressureBar', units).toString(),
  );
  await tester.ensureVisible(temperatureField);
  await tester.enterText(
    temperatureField,
    convertToDisplay(temperatureC, 'temperatureC', units).toString(),
  );
  await tester.pump();
}

Future<void> _tapApply(WidgetTester tester, Finder card) async {
  final apply = find.descendant(
    of: card,
    matching: find.widgetWithText(FilledButton, 'Apply'),
  );
  await tester.ensureVisible(apply);
  await tester.tap(apply);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the heading and one card per protocol step', (
    tester,
  ) async {
    final harness = _Harness.create();
    await _pump(tester, harness);

    expect(find.text('Mixing steps'), findsOneWidget);
    final steps = _steps(harness.blend);
    expect(steps, isNotEmpty);
    for (var index = 0; index < steps.length; index++) {
      final card = find.byKey(ValueKey<String>('step-$index'));
      expect(card, findsOneWidget);
      final step = steps[index];
      if (step.type != 'salvage') {
        expect(
          find.descendant(
            of: card,
            matching: find.textContaining(
              'Step ${protocolStepNumber(step, index)}: ',
            ),
          ),
          findsWidgets,
        );
      }
    }
  });

  testWidgets(
    'an out-of-tolerance reading shows the error and a valid reading clears it',
    (tester) async {
      final harness = _Harness.create();
      await _pump(tester, harness);
      final steps = _steps(harness.blend);
      final index = _measurableIndex(steps);
      final thermal = steps[index].thermal!;
      final card = find.byKey(ValueKey<String>('step-$index'));
      final units = harness.app.settings.units;
      final plannedPressureBar = thermal.pressureStartBar;
      final plannedTemperatureC = thermal.temperatureStartC;

      await tester.ensureVisible(
        find.descendant(of: card, matching: find.byType(ExpansionTile)),
      );
      await tester.tap(
        find.descendant(of: card, matching: find.byType(ExpansionTile)),
      );
      await tester.pumpAndSettle();

      await _enterReading(
        tester,
        card,
        units: units,
        pressureBar: plannedPressureBar * 0.5,
        temperatureC: plannedTemperatureC,
      );
      await _tapApply(tester, card);

      expect(_errorText(card), findsOneWidget);
      expect(
        harness.blend.interimMeasurements.whereType<InterimMeasurement>(),
        isEmpty,
      );

      await _enterReading(
        tester,
        card,
        units: units,
        pressureBar: plannedPressureBar,
        temperatureC: plannedTemperatureC,
      );
      await _tapApply(tester, card);

      expect(_errorText(card), findsNothing);
      expect(
        harness.blend.interimMeasurements.whereType<InterimMeasurement>(),
        isNotEmpty,
      );
    },
  );

  testWidgets('attaches the mixing-steps tour target', (tester) async {
    final harness = _Harness.create();
    final targets = TourTargets();
    await _pump(tester, harness, targets: targets);

    expect(targets.keyFor('mixing-steps-section').currentContext, isNotNull);
  });
}

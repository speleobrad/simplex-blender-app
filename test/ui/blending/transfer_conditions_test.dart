import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/ui/blending/transfer_conditions.dart';

import '../../support/memory_storage.dart';

// Source of truth: js/main.js `effectiveInletTemperatureC` (ambient when
// "Same as ambient" is checked, else the field value) and
// `syncInletGasTemperatureControl` (field disabled and set to ambient while
// checked); index.html lines 823-835 for the markup and label text.

CylinderPreset _catalinaS80() => DEFAULT_SETTINGS.cylinderPresets.firstWhere(
  (preset) => preset.name == 'Catalina S80',
);

BlendInputs _inputs({double ambient = 21, double inlet = 21}) => BlendInputs(
  cylinderPreset: _catalinaS80(),
  initialPressureBar: 50,
  initialOxygenPercent: 21,
  initialHeliumPercent: 0,
  targetPressureBar: 195,
  targetOxygenPercent: 18,
  targetHeliumPercent: 45,
  ambientTemperatureC: ambient,
  targetInWaterTemperatureC: 10,
  waitTargetTemperatureC: 25,
  inletTemperatureC: inlet,
  coolingMedium: 'water',
  waterSubmersionPercent: 40,
  waitMode: 'minutes',
  waitMinutes: 5,
);

class _Harness {
  _Harness(this.app, this.blend);

  final AppController app;
  final BlendController blend;

  static _Harness create({double ambient = 21, double inlet = 21}) {
    const analytics = NoopAnalytics();
    final app = AppController(storage: MemoryStorage(), analytics: analytics);
    final blend = BlendController(
      inputs: _inputs(ambient: ambient, inlet: inlet),
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
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TransferConditions(
            controller: harness.blend,
            app: harness.app,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

Future<void> _tapSameAsAmbient(WidgetTester tester) async {
  await tester.tap(find.text('Same as ambient'));
  await tester.pump();
}

void main() {
  testWidgets('shows the heading, label, unit, checkbox, and note', (
    tester,
  ) async {
    final harness = _Harness.create();
    await _pump(tester, harness);

    expect(find.text('Transfer conditions'), findsOneWidget);
    expect(find.text('Temperature of inventory gases'), findsOneWidget);
    expect(find.text('°C'), findsOneWidget);
    expect(find.text('Same as ambient'), findsOneWidget);
    expect(
      find.text(
        'The temperature at which inventory gases are assumed to be stored; '
        'compressor and source-specific temperature modifiers still apply.',
      ),
      findsOneWidget,
    );
    expect(_field(tester).controller!.text, '21');
    expect(_field(tester).enabled, isTrue);
  });

  testWidgets('checking "Same as ambient" makes the effective inlet equal '
      'ambient and disables the field', (tester) async {
    final harness = _Harness.create(ambient: 30, inlet: 15);
    await _pump(tester, harness);

    await _tapSameAsAmbient(tester);

    expect(harness.blend.inputs.inletTemperatureC, 30);
    expect(_field(tester).enabled, isFalse);
    expect(_field(tester).controller!.text, '30');
  });

  testWidgets('while checked, a later ambient change still sets the effective '
      'inlet to ambient', (tester) async {
    final harness = _Harness.create(ambient: 21, inlet: 21);
    await _pump(tester, harness);
    await _tapSameAsAmbient(tester);

    harness.blend.setInputs(
      harness.blend.inputs.copyWith(ambientTemperatureC: 35),
    );
    await tester.pump();

    expect(harness.blend.inputs.inletTemperatureC, 35);
    expect(_field(tester).controller!.text, '35');
  });

  testWidgets('unchecked, typing sets the inlet temperature from the field', (
    tester,
  ) async {
    final harness = _Harness.create();
    await _pump(tester, harness);

    await tester.enterText(find.byType(TextField), '15');
    await tester.pump();

    expect(harness.blend.inputs.inletTemperatureC, 15);
    expect(_field(tester).enabled, isTrue);
  });

  testWidgets('unchecking restores the field to its own value', (tester) async {
    final harness = _Harness.create(ambient: 30, inlet: 15);
    await _pump(tester, harness);
    await _tapSameAsAmbient(tester);
    expect(harness.blend.inputs.inletTemperatureC, 30);

    await _tapSameAsAmbient(tester);
    expect(_field(tester).enabled, isTrue);

    await tester.enterText(find.byType(TextField), '12');
    await tester.pump();
    expect(harness.blend.inputs.inletTemperatureC, 12);
  });

  testWidgets('imperial units show the field in °F and convert the entry '
      'back to °C', (tester) async {
    final harness = _Harness.create();
    harness.app.applySettings(DEFAULT_SETTINGS.copyWith(units: 'imperial'));
    await _pump(tester, harness);

    expect(find.text('°F'), findsOneWidget);
    expect(_field(tester).controller!.text, '69.8');

    await tester.enterText(find.byType(TextField), '50');
    await tester.pump();
    expect(harness.blend.inputs.inletTemperatureC, closeTo(10, 1e-9));
  });

  testWidgets('a blank ambient with "Same as ambient" on does not loop', (
    tester,
  ) async {
    final harness = _Harness.create();
    await _pump(tester, harness);
    await _tapSameAsAmbient(tester);

    harness.blend.setInputs(
      harness.blend.inputs.copyWith(ambientTemperatureC: double.nan),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(harness.blend.inputs.inletTemperatureC.isNaN, isTrue);
  });
}

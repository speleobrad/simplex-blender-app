import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/units.dart';
import 'package:simplex_blender/src/ui/inventory/supply_banks_section.dart';

import '../../support/memory_storage.dart';

// Source of truth: tests/supply-banks-ui.test.js. Behaviour is asserted through
// the widget tree. CSS class and HTML min/max/step checks have no Flutter
// equivalent and are dropped. The JS tests inject fixed suggestions; here the
// real pricer runs, so the expected strings use its real output.

const String _bankName = 'Tx 18/45';

const Costs _euroCosts = Costs(
  currencySymbol: '€',
  leftoverDiscountPercent: 0,
  operationPrices: OperationPrices(boost: 0, decant: 0, topUp: 0),
);

CylinderPreset _catalinaS80() => DEFAULT_SETTINGS.cylinderPresets.firstWhere(
  (preset) => preset.name == 'Catalina S80',
);

BlendInputs _defaultInputs() => BlendInputs(
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

/// Appends a bank. `addBank` names banks by millisecond timestamp, so the
/// helper waits 2 ms first to keep ids unique.
Future<void> _addBank(
  WidgetTester tester,
  AppController app, {
  required String name,
  required double oxygen,
  required double helium,
  double? pricePerLitre,
}) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 2)),
  );
  app.addBank();
  app.updateBank(
    app.banks.last.copyWith(
      name: name,
      volumeL: 12,
      pressureBar: 150,
      oxygenPercent: oxygen,
      heliumPercent: helium,
      maxPressureBar: () => 200,
      pricePerLitre: () => pricePerLitre,
    ),
  );
}

/// An inventory holding one bank named [_bankName] with the given values.
/// With [pureSources], priced pure oxygen and helium banks are appended so
/// the pricer has gas sources.
Future<AppController> _appWithBank(
  WidgetTester tester, {
  String units = 'metric',
  double oxygen = 18,
  double helium = 45,
  double? pricePerLitre,
  Costs costs = _euroCosts,
  bool pureSources = false,
}) async {
  final app = AppController(
    storage: MemoryStorage(),
    analytics: const NoopAnalytics(),
  );
  app.applySettings(DEFAULT_SETTINGS.copyWith(units: units, costs: costs));
  for (final bank in List<Bank>.of(app.banks)) {
    app.removeBank(bank.id);
  }
  await _addBank(
    tester,
    app,
    name: _bankName,
    oxygen: oxygen,
    helium: helium,
    pricePerLitre: pricePerLitre,
  );
  if (pureSources) {
    await _addBank(
      tester,
      app,
      name: 'Pure O2',
      oxygen: 100,
      helium: 0,
      pricePerLitre: 0.01,
    );
    await _addBank(
      tester,
      app,
      name: 'Pure He',
      oxygen: 0,
      helium: 100,
      pricePerLitre: 0.05,
    );
  }
  return app;
}

BlendController _blendFor(AppController app) => BlendController(
  inputs: _defaultInputs(),
  banks: app.banks,
  settings: app.settings,
  updateBank: app.updateBank,
  analytics: const NoopAnalytics(),
);

Future<void> _pump(
  WidgetTester tester,
  AppController app,
  BlendController blend,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SupplyBanksSection(app: app, blend: blend),
      ),
    ),
  );
}

Finder _labelled(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

Finder _textMatching(RegExp pattern) => find.byWidgetPredicate(
  (widget) => widget is Text && pattern.hasMatch(widget.data ?? ''),
);

String _fieldText(WidgetTester tester, String label) {
  final field = tester.widget<TextField>(
    find.descendant(of: _labelled(label), matching: find.byType(TextField)),
  );
  return field.controller!.text;
}

Finder _basisDropdown() => find.descendant(
  of: _labelled('Price basis for $_bankName'),
  matching: find.byType(DropdownButton<String>),
);

void main() {
  testWidgets(
    'shows Calculating and disables Calculate until the pricer runs',
    (tester) async {
      final app = await _appWithBank(tester, pureSources: true);
      final blend = _blendFor(app);
      await _pump(tester, app, blend);

      await tester.tap(find.text('Calculate price').first);
      await tester.pump();

      expect(find.text('Calculating…'), findsOneWidget);
      expect(find.text('Calculating price for $_bankName…'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Calculate price'),
            )
            .onPressed,
        isNull,
      );

      await tester.pump(Duration.zero);
      await tester.pump();

      expect(find.text('Calculating…'), findsNothing);
      expect(_textMatching(RegExp(r'^Indicative price')), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Calculate price'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('announces the indicative price in the live status line', (
    tester,
  ) async {
    final app = await _appWithBank(tester, pureSources: true);
    final blend = _blendFor(app);
    await _pump(tester, app, blend);

    await tester.tap(find.text('Calculate price').first);
    await tester.pump(Duration.zero);
    await tester.pump();

    final status = tester.widget<Text>(
      find
          .descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.liveRegion == true,
            ),
            matching: find.byType(Text),
          )
          .first,
    );
    expect(status.data, startsWith('$_bankName: Indicative price'));
  });

  testWidgets('discards a calculation whose pricing inputs changed mid-run', (
    tester,
  ) async {
    final app = await _appWithBank(tester, pureSources: true);
    final blend = _blendFor(app);
    await _pump(tester, app, blend);

    await tester.tap(find.text('Calculate price').first);
    await tester.pump();
    final bank = app.banks.firstWhere(
      (candidate) => candidate.name == _bankName,
    );
    app.updateBank(bank.copyWith(oxygenPercent: 20));
    await tester.pump();
    await tester.pump(Duration.zero);
    await tester.pump();

    final status = tester.widget<Text>(
      find
          .descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.liveRegion == true,
            ),
            matching: find.byType(Text),
          )
          .first,
    );
    expect(status.data, 'Price calculation for $_bankName was discarded.');
    expect(find.text('Calculating…'), findsNothing);
    expect(blend.bankSuggestionFor(bank.id), isNull);
  });

  testWidgets('renders inventory bank values and editable controls', (
    tester,
  ) async {
    final app = await _appWithBank(tester);
    await _pump(tester, app, _blendFor(app));

    expect(_fieldText(tester, '$_bankName bank name'), _bankName);
    expect(_fieldText(tester, '$_bankName volume in L'), '12');
    expect(_fieldText(tester, '$_bankName pressure in bar'), '150');
    expect(_fieldText(tester, '$_bankName max pressure in bar'), '200');
    expect(_fieldText(tester, '$_bankName oxygen percentage'), '18');
    expect(_fieldText(tester, '$_bankName helium percentage'), '45');
    expect(find.bySemanticsLabel('Use $_bankName'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove $_bankName'), findsOneWidget);
  });

  testWidgets('converts editable imperial supply-bank values', (tester) async {
    final app = await _appWithBank(tester, units: 'imperial');
    await _pump(tester, app, _blendFor(app));

    final volume = double.parse(
      _fieldText(tester, '$_bankName volume in cu ft'),
    );
    expect(volume, closeTo(convertToDisplay(12, 'volumeL', 'imperial'), 1e-9));
    final pressure = double.parse(
      _fieldText(tester, '$_bankName pressure in psi'),
    );
    expect(pressure, closeTo(2175.56607, 1e-4));
  });

  testWidgets(
    'renders an empty price input and a Calculate button for an unpriced bank',
    (tester) async {
      final app = await _appWithBank(tester);
      await _pump(tester, app, _blendFor(app));

      expect(_fieldText(tester, '$_bankName price per /L'), '');
      expect(find.text('Calculate price'), findsOneWidget);
      expect(find.text('Apply'), findsNothing);
      expect(_textMatching(RegExp(r'^Indicative price')), findsNothing);
    },
  );

  testWidgets('labels the price column and input in the display unit', (
    tester,
  ) async {
    final metric = await _appWithBank(tester, pricePerLitre: 0.02);
    await _pump(tester, metric, _blendFor(metric));
    expect(find.text('Price (/L)'), findsOneWidget);
    expect(_fieldText(tester, '$_bankName price per /L'), '0.020000');

    final imperial = await _appWithBank(
      tester,
      units: 'imperial',
      pricePerLitre: 0.02,
    );
    await _pump(tester, imperial, _blendFor(imperial));
    expect(find.text('Price (/cu ft)'), findsOneWidget);
    expect(_fieldText(tester, '$_bankName price per /cu ft'), '0.566337');
  });

  testWidgets('shows an indicative price with Apply for an unpriced bank', (
    tester,
  ) async {
    final app = await _appWithBank(tester, pureSources: true);
    final blend = _blendFor(app);
    await _pump(tester, app, blend);

    await tester.tap(find.text('Calculate price').first);
    await tester.pumpAndSettle();

    expect(
      _textMatching(
        RegExp(r'^Indicative price €\d+\.\d{6} per L \(recipe cost'),
      ),
      findsOneWidget,
    );
    expect(find.text('Apply'), findsOneWidget);
  });

  testWidgets('offers Replace beside the current price for a priced bank', (
    tester,
  ) async {
    final app = await _appWithBank(
      tester,
      pricePerLitre: 0.03,
      pureSources: true,
    );
    final blend = _blendFor(app);
    await _pump(tester, app, blend);

    await tester.tap(find.text('Calculate price').first);
    await tester.pumpAndSettle();

    expect(
      _textMatching(RegExp(r'Current price €0\.030000 per L\.$')),
      findsWidgets,
    );
    expect(find.text('Replace'), findsOneWidget);
  });

  testWidgets('separates word currency symbols from the amount', (
    tester,
  ) async {
    final app = await _appWithBank(
      tester,
      pureSources: true,
      costs: const Costs(
        currencySymbol: 'USD',
        leftoverDiscountPercent: 0,
        operationPrices: OperationPrices(boost: 0, decant: 0, topUp: 0),
      ),
    );
    final blend = _blendFor(app);
    await _pump(tester, app, blend);

    await tester.tap(find.text('Calculate price').first);
    await tester.pumpAndSettle();

    expect(
      _textMatching(RegExp(r'^Indicative price USD \d+\.\d{6} per L')),
      findsOneWidget,
    );
  });

  testWidgets(
    'shows the pricer reason for a failed calculation without Apply',
    (tester) async {
      final app = await _appWithBank(tester);
      final blend = _blendFor(app);
      await _pump(tester, app, blend);

      await tester.tap(find.text('Calculate price'));
      await tester.pumpAndSettle();

      expect(
        _textMatching(RegExp(r'^Set a price on a pure oxygen bank first\.$')),
        findsOneWidget,
      );
      expect(find.text('Apply'), findsNothing);
      expect(find.text('Replace'), findsNothing);
    },
  );

  testWidgets('ignores suggestions that belong to other banks', (tester) async {
    final app = await _appWithBank(tester, pureSources: true);
    await _addBank(tester, app, name: 'Other', oxygen: 21, helium: 0);
    final other = app.banks.last;
    final blend = _blendFor(app);
    await _pump(tester, app, blend);

    blend.calculateBankPrice(other.id);
    await tester.pumpAndSettle();

    // The suggestion is keyed to 'Other'. The Tx row shows no Apply.
    expect(_labelled('Apply suggested price for $_bankName'), findsNothing);
    expect(
      _textMatching(RegExp(r'^(Indicative price|Set a price)')),
      findsOneWidget,
    );
  });

  testWidgets('notes the leftover discount when one is configured', (
    tester,
  ) async {
    final app = await _appWithBank(
      tester,
      pureSources: true,
      costs: const Costs(
        currencySymbol: '€',
        leftoverDiscountPercent: 10,
        operationPrices: OperationPrices(boost: 0, decant: 0, topUp: 0),
      ),
    );
    final blend = _blendFor(app);
    await _pump(tester, app, blend);

    await tester.tap(find.text('Calculate price').first);
    await tester.pumpAndSettle();

    expect(
      _textMatching(
        RegExp(
          r'^Indicative price €\d+\.\d{6} per L after 10% leftover discount \(recipe cost',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'pure oxygen and helium banks have no Calculate control or note, enabled or not',
    (tester) async {
      for (final composition in <({double oxygen, double helium})>[
        (oxygen: 100, helium: 0),
        (oxygen: 0, helium: 100),
      ]) {
        for (final enabled in <bool>[true, false]) {
          final app = await _appWithBank(
            tester,
            oxygen: composition.oxygen,
            helium: composition.helium,
          );
          app.setBankEnabled(app.banks.single.id, enabled: enabled);
          await _pump(tester, app, _blendFor(app));

          expect(find.text('Calculate price'), findsNothing);
          expect(_textMatching(RegExp(r'^Indicative price')), findsNothing);
        }
      }
    },
  );

  testWidgets('offers a per-volume or full-tank price basis for every bank', (
    tester,
  ) async {
    final app = await _appWithBank(tester);
    await _pump(tester, app, _blendFor(app));

    final dropdown = tester.widget<DropdownButton<String>>(_basisDropdown());
    expect(dropdown.value, 'per-volume');
    expect(dropdown.items!.map((item) => item.value).toList(), <String>[
      'per-volume',
      'full-tank',
    ]);
  });

  testWidgets('full-tank basis shows an empty input for the tank price', (
    tester,
  ) async {
    final app = await _appWithBank(tester);
    await _pump(tester, app, _blendFor(app));

    await tester.tap(_basisDropdown());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full tank').last);
    await tester.pumpAndSettle();

    expect(_fieldText(tester, '$_bankName full tank price'), '');
    final field = tester.widget<TextField>(
      find.descendant(
        of: _labelled('$_bankName full tank price'),
        matching: find.byType(TextField),
      ),
    );
    expect(field.decoration!.hintText, 'Full tank price');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/data/analytics_storage.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/ui/settings/settings_screen.dart';
import 'package:simplex_blender/src/ui/shell/tour_targets.dart';

import '../../support/memory_storage.dart';

class _NoopAnalytics implements Analytics {
  @override
  void track(
    String event, [
    Map<String, Object> props = const <String, Object>{},
  ]) {}
}

AppController _app([MemoryStorage? storage]) => AppController(
  storage: storage ?? MemoryStorage(),
  analytics: _NoopAnalytics(),
);

Future<void> _pump(WidgetTester tester, AppController app) =>
    _pumpWith(tester, app, TourTargets());

Future<void> _pumpWith(
  WidgetTester tester,
  AppController app,
  TourTargets tourTargets,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TourTargetsScope(
          targets: tourTargets,
          child: SettingsScreen(app: app),
        ),
      ),
    ),
  );
}

Finder _currencyField() => find.descendant(
  of: find.ancestor(
    of: find.text('Currency symbol'),
    matching: find.byType(TextFormField),
  ),
  matching: find.byType(EditableText),
);

Future<void> _enterCurrency(WidgetTester tester, String text) async {
  await tester.dragUntilVisible(
    _currencyField(),
    find.byType(ListView),
    const Offset(0, -200),
  );
  await tester.enterText(_currencyField(), text);
}

Future<void> _tapAction(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.dragUntilVisible(
    button,
    find.byType(ListView),
    const Offset(0, -200),
  );
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Finder _firstCardField(String label) => find.descendant(
  of: find.widgetWithText(TextFormField, label).first,
  matching: find.byType(EditableText),
);
CylinderPreset _cylinderNamed(AppController app, String name) =>
    app.settings.cylinderPresets.firstWhere((p) => p.name == name);

void main() {
  testWidgets('Cancel discards an unsaved edit', (tester) async {
    final app = _app();
    final originalSymbol = app.settings.costs.currencySymbol;
    app.setSettingsCategory('costs');
    await _pump(tester, app);

    await _enterCurrency(tester, 'EUR');
    await _tapAction(tester, 'Cancel');

    expect(app.settings.costs.currencySymbol, originalSymbol);
    expect(find.text('EUR'), findsNothing);
  });

  testWidgets('Save applies an edited currency symbol to saved settings', (
    tester,
  ) async {
    final app = _app();
    app.setSettingsCategory('costs');
    await _pump(tester, app);

    await _enterCurrency(tester, 'EUR');
    await _tapAction(tester, 'Save settings');

    expect(app.settings.costs.currencySymbol, 'EUR');
  });

  testWidgets('Only the category selected in the app is shown', (tester) async {
    final app = _app();
    await _pump(tester, app);

    expect(
      find.byKey(const ValueKey<String>('settings-pane-general')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('settings-pane-costs')),
      findsNothing,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Costs'));
    await tester.pumpAndSettle();

    expect(app.settingsCategory, 'costs');
    expect(
      find.byKey(const ValueKey<String>('settings-pane-costs')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('settings-pane-general')),
      findsNothing,
    );
  });

  testWidgets('A category changed by the app rebuilds the open screen', (
    tester,
  ) async {
    final app = _app();
    final tourTargets = TourTargets();
    await _pumpWith(tester, app, tourTargets);

    app.setSettingsCategory('equipment');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings-pane-equipment')),
      findsNothing,
    );
    expect(
      find.byKey(tourTargets.keyFor('settings-pane-equipment')),
      findsOneWidget,
    );
  });

  testWidgets('The analytics switch turns sending off and saves the choice', (
    tester,
  ) async {
    final storage = MemoryStorage();
    final app = _app(storage);
    await _pump(tester, app);

    expect(app.analyticsEnabled, isTrue);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('settings-analytics')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('settings-analytics')));
    await tester.pumpAndSettle();

    expect(app.analyticsEnabled, isFalse);
    expect(storage.getItem(analyticsStorageKey), '{"enabled":false}');
  });

  testWidgets('cylinder editor shows dimensions, surface, and plausibility', (
    tester,
  ) async {
    final app = _app();
    app.setSettingsCategory('cylinder-presets');
    await _pump(tester, app);

    // First card by volume is Catalina S13: 111.3 mm x 325 mm,
    // pi*D*L + pi*D^2/2 = 0.133100 m^2 -> 0.133.
    expect(_firstCardField('Diameter (mm)'), findsOneWidget);
    expect(
      find.textContaining('Heat-transfer surface: 0.133 m²'),
      findsOneWidget,
    );
    expect(find.textContaining('too small'), findsNothing);
  });

  testWidgets('clearing a dimension blocks saving with a message', (
    tester,
  ) async {
    final app = _app();
    app.setSettingsCategory('cylinder-presets');
    await _pump(tester, app);

    await tester.enterText(_firstCardField('Diameter (mm)'), '');
    await tester.pump();
    await _tapAction(tester, 'Save settings');
    expect(
      find.textContaining('diameter must be greater than 0 mm'),
      findsOneWidget,
    );
    expect(_cylinderNamed(app, 'Catalina S13').diameterMm, 111.3);
  });

  testWidgets('an implausible volume is flagged but still saves', (
    tester,
  ) async {
    final app = _app();
    app.setSettingsCategory('cylinder-presets');
    await _pump(tester, app);

    await tester.enterText(_firstCardField('Diameter (mm)'), '186');
    await tester.enterText(_firstCardField('Length, no valve (mm)'), '500');
    await tester.pump();
    expect(find.textContaining('too small'), findsOneWidget);
    await _tapAction(tester, 'Save settings');
    expect(_cylinderNamed(app, 'Catalina S13').diameterMm, 186);
  });

  testWidgets('Add cylinder starts incomplete and cannot be saved', (
    tester,
  ) async {
    final app = _app();
    app.setSettingsCategory('cylinder-presets');
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester, app);

    await _tapAction(tester, 'Add cylinder');
    expect(
      find.textContaining('“New cylinder” diameter must be greater than 0 mm'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Save settings'));
    await tester.tap(find.text('Save settings'));
    await tester.pump();
    expect(
      app.settings.cylinderPresets.length,
      DEFAULT_SETTINGS.cylinderPresets.length,
    );
  });
}

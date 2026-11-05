import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/ui/about/about_screen.dart';

import '../../support/memory_storage.dart';

class _NoopAnalytics implements Analytics {
  @override
  void track(
    String event, [
    Map<String, Object> props = const <String, Object>{},
  ]) {}
}

AppController _app() =>
    AppController(storage: MemoryStorage(), analytics: _NoopAnalytics());

Future<void> _pump(WidgetTester tester, AppController app) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: AboutScreen(app: app)),
    ),
  );
}

void main() {
  testWidgets('shows the title, credit, and description from index.html', (
    tester,
  ) async {
    await _pump(tester, _app());

    expect(find.text('About Simplex blender'), findsOneWidget);
    expect(find.text('Made with curiosity by Speleobrad.'), findsOneWidget);
    expect(
      find.textContaining('treating temperature as a blending parameter'),
      findsOneWidget,
    );
  });

  testWidgets('lists the GitHub, Instagram, and Facebook links', (
    tester,
  ) async {
    await _pump(tester, _app());

    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('Facebook'), findsOneWidget);
  });

  testWidgets('lists the three bug and feature request links', (tester) async {
    await _pump(tester, _app());

    expect(find.text('Bugs and feature requests'), findsOneWidget);
    expect(find.text('Report a bug'), findsOneWidget);
    expect(find.text('Request a feature'), findsOneWidget);
    expect(find.text('Browse open issues'), findsOneWidget);
  });

  testWidgets('states the GPL-3.0-only license', (tester) async {
    await _pump(tester, _app());
    final footer = find.textContaining('free software, licensed under');
    await tester.dragUntilVisible(
      footer,
      find.byType(ListView),
      const Offset(0, -200),
    );

    expect(footer, findsOneWidget);
  });

  testWidgets('the licenses button opens the Flutter license page', (
    tester,
  ) async {
    await _pump(tester, _app());

    final button = find.widgetWithText(OutlinedButton, 'Open-source licenses');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/ui/onboarding/onboarding_tour.dart';
import 'package:simplex_blender/src/ui/shell/tour_targets.dart';

import '../../support/memory_storage.dart';

const String _onboardingKey = 'simplex-gas-remixer-onboarding';

class _NoopAnalytics implements Analytics {
  @override
  void track(
    String event, [
    Map<String, Object> props = const <String, Object>{},
  ]) {}
}

/// Mounts the tour over a bare host with the given [targetWidgets] wired
/// through [TourTargets]. The host sits under a [Stack] so the overlay used
/// by the spotlight has a `Overlay` ancestor from [MaterialApp].
Future<AppController> _pumpTour(
  WidgetTester tester,
  MemoryStorage storage, {
  List<Widget> targetWidgets = const <Widget>[],
  TourTargets? targets,
}) async {
  final app = AppController(storage: storage, analytics: _NoopAnalytics());
  final tourTargets = targets ?? TourTargets();
  await tester.pumpWidget(
    TourTargetsScope(
      targets: tourTargets,
      child: MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              ...targetWidgets,
              OnboardingTour(app: app),
            ],
          ),
        ),
      ),
    ),
  );
  return app;
}

void main() {
  group('guided tour', () {
    testWidgets('shows the first step with a counter of eight steps', (
      tester,
    ) async {
      await _pumpTour(tester, MemoryStorage());

      expect(find.text('Step 1 of 8'), findsOneWidget);
      expect(find.text('Back'), findsNothing);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('Next and Back move between steps and navigate to each', (
      tester,
    ) async {
      final app = await _pumpTour(tester, MemoryStorage());

      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Step 2 of 8'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      expect(app.primaryScreen, 'inventory');

      // Step 4 targets a settings category, so Settings opens there.
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Step 4 of 8'), findsOneWidget);
      expect(app.primaryScreen, 'settings');
      expect(app.settingsCategory, 'equipment');

      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(find.text('Step 3 of 8'), findsOneWidget);
      expect(app.primaryScreen, 'inventory');
    });

    testWidgets('temperatures step names the dive site temperature', (
      tester,
    ) async {
      await _pumpTour(tester, MemoryStorage());
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Next'));
        await tester.pump();
      }
      expect(find.text('Step 6 of 8'), findsOneWidget);
      expect(
        find.textContaining('dive site temperature', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('Done persists the tour as seen and returns to Blending', (
      tester,
    ) async {
      final storage = MemoryStorage();
      final app = await _pumpTour(tester, storage);
      for (var i = 0; i < 7; i++) {
        await tester.tap(find.text('Next'));
        await tester.pump();
      }
      expect(find.text('Done'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pump();

      expect(storage.values[_onboardingKey], '{"wizardSeen":true}');
      expect(app.onboarding.wizardSeen, isTrue);
      expect(app.primaryScreen, 'blending');
      expect(find.text('Step 8 of 8'), findsNothing);
    });

    testWidgets('Skip persists the tour as seen and returns to Blending', (
      tester,
    ) async {
      final storage = MemoryStorage();
      final app = await _pumpTour(tester, storage);
      await tester.tap(find.text('Next'));
      await tester.pump();

      await tester.tap(find.text('Skip'));
      await tester.pump();

      expect(storage.values[_onboardingKey], '{"wizardSeen":true}');
      expect(app.primaryScreen, 'blending');
      expect(find.text('Step 2 of 8'), findsNothing);
    });

    testWidgets('the close button persists the tour as seen', (tester) async {
      final storage = MemoryStorage();
      await _pumpTour(tester, storage);

      await tester.tap(find.byTooltip('Close tour'));
      await tester.pump();

      expect(storage.values[_onboardingKey], '{"wizardSeen":true}');
      expect(find.text('Step 1 of 8'), findsNothing);
    });

    testWidgets('Escape persists the tour as seen without navigating', (
      tester,
    ) async {
      final storage = MemoryStorage();
      final app = await _pumpTour(tester, storage);
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(app.primaryScreen, 'inventory');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(storage.values[_onboardingKey], '{"wizardSeen":true}');
      expect(app.onboarding.wizardSeen, isTrue);
      expect(app.primaryScreen, 'inventory');
      expect(find.text('Step 2 of 8'), findsNothing);
    });

    testWidgets('outlines a mounted target after the step is shown', (
      tester,
    ) async {
      final targets = TourTargets();
      final ambient = targets.keyFor('ambient-temperature');
      await _pumpTour(
        tester,
        MemoryStorage(),
        targets: targets,
        targetWidgets: <Widget>[
          Positioned(
            left: 40,
            top: 40,
            child: SizedBox(
              key: ambient,
              width: 60,
              height: 30,
              child: const Text('ambient'),
            ),
          ),
        ],
      );
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Next'));
        await tester.pump();
        await tester.pump();
      }

      final painter = tester.widget<CustomPaint>(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is SpotlightPainter,
        ),
      );
      final spotlight = painter.painter! as SpotlightPainter;
      expect(spotlight.rects, isNotEmpty);
    });

    testWidgets('draws no outline when the target is not mounted', (
      tester,
    ) async {
      await _pumpTour(tester, MemoryStorage());
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Next'));
        await tester.pump();
        await tester.pump();
      }

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is SpotlightPainter,
        ),
        findsNothing,
      );
    });
  });
}

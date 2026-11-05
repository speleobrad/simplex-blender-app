import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/data/analytics_storage.dart';

import '../support/memory_storage.dart';

typedef _Call = ({String event, Map<String, Object> props});

/// Records every event; stands in for the backend.
class _RecordingAnalytics implements Analytics {
  final List<_Call> calls = <_Call>[];

  @override
  void track(
    String event, [
    Map<String, Object> props = const <String, Object>{},
  ]) {
    calls.add((event: event, props: props));
  }
}

void main() {
  test('a saved opt-out is loaded and blocks events', () {
    final storage = MemoryStorage()
      ..setItem(analyticsStorageKey, '{"enabled":false}');
    final backend = _RecordingAnalytics();
    final app = AppController(storage: storage, analytics: backend);

    expect(app.analyticsEnabled, isFalse);
    app.analytics.track('screen_view', <String, Object>{'name': 'Settings'});

    expect(backend.calls, isEmpty);
  });

  test('events are not sent while disabled and resume after re-enable', () {
    final backend = _RecordingAnalytics();
    final app = AppController(storage: MemoryStorage(), analytics: backend);

    app.setAnalyticsEnabled(enabled: false);
    app.analytics.track('screen_view', <String, Object>{'name': 'Settings'});
    expect(backend.calls, isEmpty);

    app.setAnalyticsEnabled(enabled: true);
    app.analytics.track('screen_view', <String, Object>{'name': 'Settings'});
    expect(backend.calls.map((call) => call.event), <String>['screen_view']);
  });

  test('a disabled choice is saved so a new launch keeps it', () {
    final storage = MemoryStorage();
    AppController(
      storage: storage,
      analytics: _RecordingAnalytics(),
    ).setAnalyticsEnabled(enabled: false);

    final relaunched = AppController(
      storage: storage,
      analytics: _RecordingAnalytics(),
    );

    expect(relaunched.analyticsEnabled, isFalse);
  });

  test('factory reset restores analytics to enabled after it runs', () {
    final storage = MemoryStorage();
    final backend = _RecordingAnalytics();
    final app = AppController(storage: storage, analytics: backend)
      ..setAnalyticsEnabled(enabled: false);

    final outcome = app.factoryReset(confirm: () => true);

    expect(outcome, FactoryResetOutcome.reset);
    expect(app.analyticsEnabled, isTrue);
  });
}

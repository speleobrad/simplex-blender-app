import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/analytics/analytics_events.dart';

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

/// Fails on every event, like a broken backend.
class _ThrowingAnalytics implements Analytics {
  @override
  void track(
    String event, [
    Map<String, Object> props = const <String, Object>{},
  ]) {
    throw StateError('backend down');
  }
}

void main() {
  test('app_started is sent once with no properties', () {
    final _RecordingAnalytics fake = _RecordingAnalytics();

    trackAppStarted(fake);

    expect(fake.calls.single.event, 'app_started');
    expect(fake.calls.single.props, equals(<String, Object>{}));
  });

  test('screen_view names every primary destination as in the web app', () {
    final _RecordingAnalytics fake = _RecordingAnalytics();

    for (final AnalyticsScreen screen in AnalyticsScreen.values) {
      trackScreenView(fake, screen);
    }

    expect(fake.calls.map((_Call c) => c.event).toSet(), {'screen_view'});
    expect(
      fake.calls.map((_Call c) => c.props),
      equals(<Map<String, Object>>[
        <String, Object>{'name': 'Blending'},
        <String, Object>{'name': 'What-if'},
        <String, Object>{'name': 'Inventory'},
        <String, Object>{'name': 'Settings'},
        <String, Object>{'name': 'About'},
      ]),
    );
  });

  test('blend_calculated sends the wire mode and outcome values', () {
    final _RecordingAnalytics fake = _RecordingAnalytics();

    trackBlendCalculated(
      fake,
      mode: AnalyticsBlendMode.whatIf,
      outcome: AnalyticsOutcome.invalidInput,
    );
    trackBlendCalculated(
      fake,
      mode: AnalyticsBlendMode.optimize,
      outcome: AnalyticsOutcome.infeasible,
    );

    expect(
      fake.calls.map((_Call c) => c.props),
      equals(<Map<String, Object>>[
        <String, Object>{'mode': 'what_if', 'outcome': 'invalid_input'},
        <String, Object>{'mode': 'optimize', 'outcome': 'infeasible'},
      ]),
    );
  });

  test('preset_imported sends category, source, and a numeric count', () {
    final _RecordingAnalytics fake = _RecordingAnalytics();

    trackPresetImported(
      fake,
      category: AnalyticsPresetCategory.cylinder,
      source: AnalyticsPresetSource.url,
      count: 3,
    );

    expect(fake.calls.single.event, 'preset_imported');
    expect(
      fake.calls.single.props,
      equals(<String, Object>{
        'category': 'cylinder',
        'source': 'url',
        'count': 3,
      }),
    );
  });

  test('factory_reset is sent with no properties', () {
    final _RecordingAnalytics fake = _RecordingAnalytics();

    trackFactoryReset(fake);

    expect(fake.calls.single.event, 'factory_reset');
    expect(fake.calls.single.props, equals(<String, Object>{}));
  });

  test('safeTrack does not propagate a throwing backend', () {
    expect(
      () => trackBlendCalculated(
        _ThrowingAnalytics(),
        mode: AnalyticsBlendMode.compare,
        outcome: AnalyticsOutcome.feasible,
      ),
      returnsNormally,
    );
  });

  test('NoopAnalytics accepts events and properties without throwing', () {
    const NoopAnalytics analytics = NoopAnalytics();

    expect(
      () => analytics.track('screen_view', <String, Object>{'name': 'About'}),
      returnsNormally,
    );
  });
}

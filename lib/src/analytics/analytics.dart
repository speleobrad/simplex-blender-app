/// Analytics backend abstraction.
///
/// Port of the Aptabase design in the Flutter rewrite plan. The web app's
/// `js/analytics.js` (Google Analytics) is not ported.
library;

import 'dart:async';

import 'package:aptabase_flutter/aptabase_flutter.dart';

/// Records named events with string or number properties.
abstract interface class Analytics {
  void track(
    String event, [
    Map<String, Object> props = const <String, Object>{},
  ]);
}

/// Used when no App Key is configured; never touches the network.
final class NoopAnalytics implements Analytics {
  const NoopAnalytics();

  @override
  void track(
    String event, [
    Map<String, Object> props = const <String, Object>{},
  ]) {}
}

/// The single sink every controller reports through. While [enabled] is false
/// no event reaches the wrapped backend, so callers never check the setting.
final class GatedAnalytics implements Analytics {
  GatedAnalytics(this._inner, {required this.enabled});

  final Analytics _inner;
  bool enabled;

  @override
  void track(
    String event, [
    Map<String, Object> props = const <String, Object>{},
  ]) {
    if (enabled) {
      _inner.track(event, props);
    }
  }
}

/// Aptabase-backed analytics. Create it only through [AptabaseAnalytics.init].
final class AptabaseAnalytics implements Analytics {
  const AptabaseAnalytics._();

  /// Starts the Aptabase SDK with [appKey], which must be non-empty.
  ///
  /// If the SDK fails to start, returns [NoopAnalytics] so that analytics
  /// problems never stop the app from launching.
  static Future<Analytics> init(String appKey) async {
    assert(appKey.isNotEmpty, 'Aptabase init requires a non-empty App Key.');
    try {
      await Aptabase.init(appKey);
    } on Object {
      return const NoopAnalytics();
    }
    return const AptabaseAnalytics._();
  }

  @override
  void track(
    String event, [
    Map<String, Object> props = const <String, Object>{},
  ]) {
    // trackEvent is asynchronous; a failure surfaces on the returned future,
    // so it is consumed here to keep it from becoming an unhandled error.
    unawaited(
      Aptabase.instance.trackEvent(event, props).catchError((Object _) {}),
    );
  }
}

/// Calls [analytics].track and swallows any error it throws.
///
/// Analytics must never break calculation or navigation, so every app-level
/// event goes through this wrapper.
void safeTrack(
  Analytics analytics,
  String event, [
  Map<String, Object> props = const <String, Object>{},
]) {
  try {
    analytics.track(event, props);
  } on Object {
    // Deliberately ignored: a failed analytics call must not affect the app.
  }
}

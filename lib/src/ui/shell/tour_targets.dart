import 'package:flutter/widgets.dart';

/// Keys for elements the guided tour highlights. Ids are the JS target ids
/// (`js/onboarding.js` `targetId` values, `js/ui/onboarding.js` spotlights).
///
/// One instance lives in the root shell and is provided to the tree through
/// [TourTargetsScope]. A screen attaches `key: TourTargetsScope.of(context)
/// .keyFor(id)` to the widget that the tour should highlight. The same id
/// always returns the same key.
class TourTargets {
  final Map<String, GlobalKey<State<StatefulWidget>>> _keys =
      <String, GlobalKey<State<StatefulWidget>>>{};

  GlobalKey<State<StatefulWidget>> keyFor(String targetId) {
    return _keys.putIfAbsent(
      targetId,
      () => GlobalKey<State<StatefulWidget>>(debugLabel: targetId),
    );
  }
}

class TourTargetsScope extends InheritedWidget {
  const TourTargetsScope({
    super.key,
    required this.targets,
    required super.child,
  });

  final TourTargets targets;

  static TourTargets of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<TourTargetsScope>();
    if (scope == null) {
      throw StateError('TourTargetsScope is missing above this widget.');
    }
    return scope.targets;
  }

  @override
  bool updateShouldNotify(TourTargetsScope oldWidget) =>
      oldWidget.targets != targets;
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/app_controller.dart';
import '../../domain/onboarding.dart';
import '../shell/tour_targets.dart';

/// JS `BLENDING_RESULT_TARGETS` (`js/ui/onboarding.js` 16-19). These ids are
/// only resolved for a blending step, inside the blending result host.
const Set<String> _blendingResultTargets = <String>{
  'mixing-steps-section',
  'results-tablist',
};

/// Port of the guided tour in `js/ui/onboarding.js`, shown as a sequential
/// card. Each step navigates to the step's screen (and Settings category)
/// through [AppController.navigate], then outlines the step's target and
/// spotlight elements once the frame has been drawn.
///
/// Next and Back move through the steps. Done, Skip, and Close go to Blending
/// and persist `wizardSeen`. Escape persists `wizardSeen` without navigating
/// (JS `closeInternal(true, false)`). The tour does not apply the JS `tab`
/// field; the JS `onNavigate` ignores it too.
class OnboardingTour extends StatefulWidget {
  const OnboardingTour({super.key, required this.app, this.onClosed});

  final AppController app;

  /// Runs after the tour is dismissed by Done, Skip, Close, or Escape. The
  /// shell uses it to hide the tour (the web app's `closeInternal`).
  final VoidCallback? onClosed;

  @override
  State<OnboardingTour> createState() => _OnboardingTourState();
}

class _OnboardingTourState extends State<OnboardingTour> {
  int _index = 0;
  bool _closed = false;
  OverlayEntry? _highlight;

  WizardStep get _step => WIZARD_STEPS[_index];

  bool get _isLast => _index == WIZARD_STEPS.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closed) {
        _showHighlights();
      }
    });
  }

  @override
  void dispose() {
    _removeHighlight();
    super.dispose();
  }

  void _moveTo(int index) {
    setState(() {
      _index = index;
    });
    final step = _step;
    widget.app.navigate(
      screen: step.screen,
      settingsCategory: step.settingsCategory,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closed) {
        _showHighlights();
      }
    });
  }

  void _next() {
    if (_isLast) {
      _close();
      return;
    }
    _moveTo(_index + 1);
  }

  void _back() {
    if (_index == 0) {
      return;
    }
    _moveTo(_index - 1);
  }

  void _close() {
    widget.app.navigate(screen: 'blending', settingsCategory: null);
    _dismiss();
  }

  void _dismiss() {
    widget.app.markTourSeen();
    _removeHighlight();
    setState(() {
      _closed = true;
    });
    widget.onClosed?.call();
  }

  bool _resolvable(String targetId, String screen) {
    return !_blendingResultTargets.contains(targetId) || screen == 'blending';
  }

  void _showHighlights() {
    _removeHighlight();
    final step = _step;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return;
    }
    final overlayBox = overlay.context.findRenderObject();
    if (overlayBox is! RenderBox) {
      return;
    }
    final targets = TourTargetsScope.of(context);
    final ids = <String>[];
    final primary = step.targetId;
    if (primary != null) {
      ids.add(primary);
    }
    ids.addAll(step.spotlights.map((spotlight) => spotlight.targetId));

    final rects = <Rect>[];
    for (final id in ids) {
      if (!_resolvable(id, step.screen)) {
        continue;
      }
      final box = targets.keyFor(id).currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) {
        continue;
      }
      final topLeft = overlayBox.globalToLocal(box.localToGlobal(Offset.zero));
      rects.add(topLeft & box.size);
    }
    if (rects.isEmpty) {
      return;
    }
    final color = Theme.of(context).colorScheme.primary;
    final entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: SpotlightPainter(rects: rects, color: color),
          ),
        ),
      ),
    );
    _highlight = entry;
    overlay.insert(entry);
  }

  void _removeHighlight() {
    final entry = _highlight;
    _highlight = null;
    entry?.remove();
    entry?.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _dismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (_closed) {
      return const SizedBox.shrink();
    }
    final step = _step;
    final theme = Theme.of(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Step ${_index + 1} of ${WIZARD_STEPS.length}',
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close tour',
                    icon: const Icon(Icons.close),
                    onPressed: _close,
                  ),
                ],
              ),
              Text(step.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(step.body),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(onPressed: _close, child: const Text('Skip')),
                  if (_index > 0)
                    TextButton(onPressed: _back, child: const Text('Back')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _next,
                    child: Text(_isLast ? 'Done' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws an outline around each highlighted target. [rects] are in the
/// coordinates of the overlay that hosts the tour.
class SpotlightPainter extends CustomPainter {
  const SpotlightPainter({required this.rects, required this.color});

  final List<Rect> rects;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color;
    for (final rect in rects) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(4), const Radius.circular(6)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(SpotlightPainter oldDelegate) {
    return oldDelegate.rects != rects || oldDelegate.color != color;
  }
}

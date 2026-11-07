import 'package:flutter/widgets.dart';

/// A [FocusNode] that calls [onFocusLost] each time it loses focus.
///
/// Owns the node and its listener. Call [dispose] from the owning State
/// instead of disposing [focusNode] directly.
class FocusLossNode {
  FocusLossNode({required this.onFocusLost}) {
    focusNode.addListener(_handleFocusChange);
  }

  final VoidCallback onFocusLost;
  final FocusNode focusNode = FocusNode();

  void _handleFocusChange() {
    if (!focusNode.hasFocus) {
      onFocusLost();
    }
  }

  void dispose() {
    focusNode.removeListener(_handleFocusChange);
    focusNode.dispose();
  }
}

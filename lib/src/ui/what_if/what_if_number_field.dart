import 'package:flutter/material.dart';
import 'package:simplex_blender/src/domain/finite_number.dart';
import 'package:simplex_blender/src/ui/shared/focus_loss_node.dart';
import 'package:simplex_blender/src/ui/shared/number_input.dart';

/// Numeric text field that commits its value on submit or focus loss.
///
/// Unparseable input is discarded and the field shows [displayText] again.
/// While the field has focus the parent's new [displayText] does not overwrite
/// the user's typing.
class WhatIfNumberField extends StatefulWidget {
  const WhatIfNumberField({
    super.key,
    required this.label,
    required this.displayText,
    required this.onCommit,
    this.suffixText,
    this.errorText,
  });

  final String label;
  final String displayText;
  final ValueChanged<double> onCommit;
  final String? suffixText;
  final String? errorText;

  @override
  State<WhatIfNumberField> createState() => _WhatIfNumberFieldState();
}

class _WhatIfNumberFieldState extends State<WhatIfNumberField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.displayText,
  );
  late final FocusLossNode _focus = FocusLossNode(onFocusLost: _commit);

  @override
  void didUpdateWidget(covariant WhatIfNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.focusNode.hasFocus && _text.text != widget.displayText) {
      _text.text = widget.displayText;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = parseFiniteNumber(_text.text);
    if (parsed == null) {
      _text.text = widget.displayText;
      return;
    }
    widget.onCommit(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _text,
      focusNode: _focus.focusNode,
      keyboardType: signedDecimalKeyboard,
      onSubmitted: (_) => _commit(),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffixText,
        errorText: widget.errorText,
        isDense: true,
      ),
    );
  }
}

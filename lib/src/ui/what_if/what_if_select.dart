import 'package:flutter/material.dart';

/// Labelled dropdown. Callers must pass a [value] that is null or matches
/// exactly one of [items].
class WhatIfSelect<T> extends StatelessWidget {
  const WhatIfSelect({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.errorText,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: errorText == null ? null : '$label. Invalid: $errorText',
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          isDense: true,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

part of '../optimizer.dart';

// Typed readers for the untyped JS-shaped maps used by the optimizer.

/// JS `Number(x)` for a map value; non-numeric values (including absent keys)
/// yield `null`.
double? _numberOrNull(Object? value) => value is num ? value.toDouble() : null;

/// JS `Number(x)` for a map value; non-numeric values yield NaN.
double _numberOrNan(Object? value) => _numberOrNull(value) ?? double.nan;

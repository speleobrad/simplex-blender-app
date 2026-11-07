part of '../compare_recipe.dart';

// ---------------------------------------------------------------------------
// Validation results
// ---------------------------------------------------------------------------

class CompareRecipeError {
  const CompareRecipeError({
    required this.rowId,
    required this.field,
    required this.message,
  });

  final String? rowId;
  final String field;
  final String message;
}

class CompareRecipeValidation {
  const CompareRecipeValidation({
    required this.valid,
    required this.errors,
    required this.normalizedRows,
  });

  final bool valid;
  final List<CompareRecipeError> errors;
  final List<CompareRow> normalizedRows;
}

class ComparePressureFields {
  const ComparePressureFields({
    required this.pressureAddedBar,
    required this.targetPressureBar,
    required this.pressureInputMode,
  });

  final double pressureAddedBar;
  final double targetPressureBar;
  final String? pressureInputMode;
}

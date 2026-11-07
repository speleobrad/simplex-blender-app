part of '../compare_recipe.dart';

CompareRecipeValidation validateCompareRecipe(
  List<CompareRow> rows, {
  required CompareCylinder cylinder,
  List<Bank> banks = const <Bank>[],
  PhysicsInput? physics,
  CompareSettings? settings,
  Map<String, CompareWaitState> waitStates = const <String, CompareWaitState>{},
}) {
  final errors = <CompareRecipeError>[];
  if (rows.isEmpty) {
    errors.add(
      const CompareRecipeError(
        rowId: null,
        field: 'recipe',
        message: 'Add at least one recipe row.',
      ),
    );
    return CompareRecipeValidation(
      valid: false,
      errors: errors,
      normalizedRows: const <CompareRow>[],
    );
  }

  final normalizedRows = List<CompareRow>.of(rows);
  final bankIndex = _indexedBanks(banks);
  final pressureCeilingBar = _receiverPressureCeiling(cylinder, settings);
  final initialPressure = cylinder.initialPressureBar;
  var currentPressure =
      initialPressure != null && _validPressure(initialPressure)
      ? initialPressure
      : double.nan;

  for (var index = 0; index < normalizedRows.length; index++) {
    final row = normalizedRows[index];
    final rowId = row.id;
    final type = row.type;
    if (!_knownRowTypes.contains(type)) {
      errors.add(
        CompareRecipeError(
          rowId: rowId,
          field: 'type',
          message: 'Select a valid recipe row type.',
        ),
      );
      continue;
    }
    if (type == 'drain') {
      final target = row.targetPressureBar ?? double.nan;
      if (!_validPressure(target)) {
        errors.add(
          CompareRecipeError(
            rowId: rowId,
            field: 'targetPressureBar',
            message: 'Drain target pressure must be between 0 and 350 bar.',
          ),
        );
      } else if (currentPressure.isFinite && target > currentPressure) {
        errors.add(
          CompareRecipeError(
            rowId: rowId,
            field: 'targetPressureBar',
            message:
                'Drain target pressure cannot exceed the current pressure.',
          ),
        );
      } else {
        currentPressure = target;
      }
      continue;
    }
    if (type == 'add') {
      final result = _validateAddRow(
        row,
        rowId,
        currentPressure,
        pressureCeilingBar,
        bankIndex,
        settings,
        errors,
      );
      normalizedRows[index] = result.row;
      currentPressure = result.currentPressure;
      continue;
    }
    if (type == 'wait') {
      final waitMode = row.waitMode;
      if (waitMode != 'minutes' && waitMode != 'target') {
        errors.add(
          CompareRecipeError(
            rowId: rowId,
            field: 'waitMode',
            message: 'Choose a valid wait mode.',
          ),
        );
      } else if (waitMode == 'minutes') {
        final waitMinutes = row.waitMinutes ?? double.nan;
        if (!waitMinutes.isFinite ||
            waitMinutes < 0 ||
            waitMinutes > MAX_WAIT_MINUTES) {
          errors.add(
            CompareRecipeError(
              rowId: rowId,
              field: 'waitMinutes',
              message: 'Wait duration must be between 0 and 1440 minutes.',
            ),
          );
        }
      } else {
        final targetTemperatureC = row.targetTemperatureC ?? double.nan;
        final ambientC = physics?.temperatureC;
        if (!targetTemperatureC.isFinite ||
            targetTemperatureC < 5 ||
            targetTemperatureC > 40) {
          errors.add(
            CompareRecipeError(
              rowId: rowId,
              field: 'targetTemperatureC',
              message: 'Target medium temperature must be between 5 and 40 °C.',
            ),
          );
        } else if (ambientC != null &&
            ambientC.isFinite &&
            targetTemperatureC < ambientC) {
          errors.add(
            CompareRecipeError(
              rowId: rowId,
              field: 'targetTemperatureC',
              message: 'Target medium temperature cannot be below ambient temperature.',
            ),
          );
        }
      }
      final waitPressureBar = waitStates[rowId]?.pressureBar;
      if (waitPressureBar != null && waitPressureBar.isFinite) {
        currentPressure = waitPressureBar;
      }
    }
  }

  return CompareRecipeValidation(
    valid: errors.isEmpty,
    errors: errors,
    normalizedRows: normalizedRows,
  );
}

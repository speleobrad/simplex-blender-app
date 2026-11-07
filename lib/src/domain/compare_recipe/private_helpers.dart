part of '../compare_recipe.dart';

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

bool _validPressure(double? value) {
  return value != null &&
      value.isFinite &&
      value >= 0 &&
      value <= MAX_PRESSURE_BAR;
}

double _receiverPressureCeiling(
  CompareCylinder cylinder,
  CompareSettings? settings,
) {
  if (settings?.pressureLimitMode == 'warning') {
    return MAX_PRESSURE_BAR;
  }
  final working = cylinder.workingPressureBar;
  if (working != null && working.isFinite && working >= 0) {
    return math.min(MAX_PRESSURE_BAR, working);
  }
  return MAX_PRESSURE_BAR;
}

/// JS number formatting for messages: whole numbers print without `.0`.
String _formatNumber(double value) {
  if (value == value.truncateToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

Bank _copiedBank(Bank bank) {
  return Bank(
    id: bank.id,
    name: bank.name,
    volumeL: bank.volumeL,
    pressureBar: bank.pressureBar,
    oxygenPercent: bank.oxygenPercent,
    heliumPercent: bank.heliumPercent,
    enabled: bank.enabled,
    isCompressor: bank.isCompressor == true ? true : null,
  );
}

_BankIndex _indexedBanks(List<Bank> banks) {
  final byId = <String, Bank>{};
  final duplicateIds = <String>{};
  for (final bank in banks) {
    if (bank.id.isEmpty) {
      continue;
    }
    if (byId.containsKey(bank.id)) {
      duplicateIds.add(bank.id);
    } else {
      byId[bank.id] = bank;
    }
  }
  return _BankIndex(byId: byId, duplicateIds: duplicateIds);
}

bool _isUsableBank(Bank bank) {
  return bank.enabled &&
      bank.name.trim().isNotEmpty &&
      bank.volumeL.isFinite &&
      bank.volumeL > 0 &&
      _validPressure(bank.pressureBar) &&
      isValidGasComposition(bank.oxygenPercent, bank.heliumPercent);
}

/// Returns the updated row and the receiver pressure after the row.
({CompareRow row, double currentPressure}) _validateAddRow(
  CompareRow row,
  String rowId,
  double currentPressure,
  double pressureCeilingBar,
  _BankIndex bankIndex,
  CompareSettings? settings,
  List<CompareRecipeError> errors,
) {
  if (row.pressureInputMode != 'added' && row.pressureInputMode != 'target') {
    errors.add(
      CompareRecipeError(
        rowId: rowId,
        field: 'pressureInputMode',
        message:
            'Choose whether pressure added or receiver target is being edited.',
      ),
    );
    return (row: row, currentPressure: currentPressure);
  }

  var updated = row;
  final bankId = row.bankId;
  final isCompressor = bankId == COMPRESSOR_AIR_ID;
  final Bank? bank = bankId == null ? null : bankIndex.byId[bankId];
  if (isCompressor) {
    updated = updated.copyWith(
      sourceBank: _copiedBank(compressorAirBank(settings)),
    );
  } else if (bank == null ||
      bankId == null ||
      bankIndex.duplicateIds.contains(bankId) ||
      !_isUsableBank(bank)) {
    errors.add(
      CompareRecipeError(
        rowId: rowId,
        field: 'bankId',
        message: 'Select an enabled supply bank or Compressor Air.',
      ),
    );
  } else {
    updated = updated.copyWith(sourceBank: _copiedBank(bank));
  }

  final isTarget = row.pressureInputMode == 'target';
  final activePressure = isTarget
      ? row.targetPressureBar
      : row.pressureAddedBar;
  final activeField = isTarget ? 'targetPressureBar' : 'pressureAddedBar';
  if (!_validPressure(activePressure)) {
    errors.add(
      CompareRecipeError(
        rowId: rowId,
        field: activeField,
        message:
            '${isTarget ? 'Receiver target pressure' : 'Pressure added'} must be between 0 and 350 bar.',
      ),
    );
    return (row: updated, currentPressure: currentPressure);
  }
  if (!currentPressure.isFinite) {
    return (row: updated, currentPressure: currentPressure);
  }

  final normalized = normalizeComparePressureFields(updated, currentPressure);
  if (!_validPressure(normalized.targetPressureBar)) {
    errors.add(
      CompareRecipeError(
        rowId: rowId,
        field: 'targetPressureBar',
        message: 'Add target pressure must be between 0 and 350 bar.',
      ),
    );
    return (row: updated, currentPressure: currentPressure);
  }
  if (normalized.targetPressureBar > pressureCeilingBar) {
    errors.add(
      CompareRecipeError(
        rowId: rowId,
        field: 'targetPressureBar',
        message:
            'Add target pressure cannot exceed the cylinder working pressure of ${_formatNumber(pressureCeilingBar)} bar.',
      ),
    );
    return (row: updated, currentPressure: currentPressure);
  }
  if (isCompressor) {
    final compressorCeilingBar = compressorAirBank(settings).pressureBar;
    if (normalized.targetPressureBar > compressorCeilingBar) {
      errors.add(
        CompareRecipeError(
          rowId: rowId,
          field: 'targetPressureBar',
          message:
              'Compressor Air cannot reach above its ${_formatNumber(compressorCeilingBar)} bar pressure limit.',
        ),
      );
      return (row: updated, currentPressure: currentPressure);
    }
  }
  if (normalized.pressureAddedBar < 0 ||
      normalized.targetPressureBar < currentPressure) {
    errors.add(
      CompareRecipeError(
        rowId: rowId,
        field: activeField,
        message: 'Add target pressure cannot be below the current pressure.',
      ),
    );
    return (row: updated, currentPressure: currentPressure);
  }

  final assigned = updated.copyWith(
    pressureAddedBar: normalized.pressureAddedBar,
    targetPressureBar: normalized.targetPressureBar,
  );
  return (row: assigned, currentPressure: normalized.targetPressureBar);
}

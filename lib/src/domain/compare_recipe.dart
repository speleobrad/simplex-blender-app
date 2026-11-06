import 'dart:math' as math;

import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/domain_error.dart';
import 'package:simplex_blender/src/domain/gas_input.dart';
import 'package:simplex_blender/src/domain/physics.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

// JS NaN/null stand-in: `double.nan` where JS used a non-finite number or
// null. Every comparison against NaN is false, matching the JS guards.

// ignore: constant_identifier_names
const String COMPRESSOR_AIR_ID = 'compressor-air';
// ignore: constant_identifier_names
const double COMPRESSOR_AIR_DEFAULT_PRESSURE_BAR = 232;
// ignore: constant_identifier_names
const double MAX_PRESSURE_BAR = 350;
// ignore: constant_identifier_names
const double MAX_WAIT_MINUTES = 1440;
// ignore: constant_identifier_names
const double MIN_WAIT_TEMPERATURE_C = -100;
// ignore: constant_identifier_names
const double MAX_WAIT_TEMPERATURE_C = 100;
// ignore: constant_identifier_names
const double PRESSURE_TOLERANCE_BAR = 1e-7;
// ignore: constant_identifier_names
const List<String> STEP_COLORS = [
  '#06b6d4',
  '#f59e0b',
  '#10b981',
  '#a855f7',
  '#ec4899',
];

const Set<String> _knownRowTypes = {'drain', 'keep', 'add', 'wait'};

class CompareOption {
  const CompareOption({required this.value, required this.label});

  final String value;
  final String label;
}

// ignore: constant_identifier_names
const List<CompareOption> COMPARE_ROW_TYPES = [
  CompareOption(value: 'drain', label: 'Drain'),
  CompareOption(value: 'add', label: 'Add gas'),
  CompareOption(value: 'wait', label: 'Wait'),
];

// ignore: constant_identifier_names
const List<CompareOption> COMPARE_METHODS = [
  CompareOption(value: 'decant', label: 'Decant'),
  CompareOption(value: 'boost', label: 'Boost'),
  CompareOption(value: 'compressor', label: 'Compressor'),
];

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

/// Booster and compressor settings read by Compare. Null fields fall back to
/// the same defaults the JS uses for non-finite values.
class CompareBoosterSettings {
  const CompareBoosterSettings({
    this.minimumSourcePressureBar,
    this.maxCompressorPressureBar,
    this.maxBoosterOutputPressureBar,
    this.oxygenDecantRateBarPerMin,
    this.otherDecantRateBarPerMin,
    this.cylinderVolumeCm3,
    this.oxygenBoostBpm,
    this.otherBoostBpm,
  });

  final double? minimumSourcePressureBar;
  final double? maxCompressorPressureBar;
  final double? maxBoosterOutputPressureBar;
  final double? oxygenDecantRateBarPerMin;
  final double? otherDecantRateBarPerMin;
  final double? cylinderVolumeCm3;
  final double? oxygenBoostBpm;
  final double? otherBoostBpm;
}

class CompareSettings {
  const CompareSettings({this.booster, this.pressureLimitMode});

  final CompareBoosterSettings? booster;
  final String? pressureLimitMode;
}

class CompareCylinder {
  const CompareCylinder({
    required this.volumeL,
    this.workingPressureBar,
    this.initialPressureBar,
    required this.initialOxygenPercent,
    required this.initialHeliumPercent,
  });

  final double volumeL;
  final double? workingPressureBar;
  final double? initialPressureBar;
  final double initialOxygenPercent;
  final double initialHeliumPercent;
}

/// Modeled state of the receiver at the end of a wait row.
class CompareWaitState {
  const CompareWaitState({
    required this.pressureBar,
    this.temperatureC,
    this.totalMoles,
    this.oxygenMoles,
    this.heliumMoles,
    this.mix,
  });

  final double pressureBar;
  final double? temperatureC;
  final double? totalMoles;
  final double? oxygenMoles;
  final double? heliumMoles;
  final GasMixPercent? mix;
}

class CompareRow {
  const CompareRow({
    required this.id,
    required this.type,
    this.bankId,
    this.pressureAddedBar,
    this.targetPressureBar,
    this.pressureInputMode,
    this.waitMode,
    this.waitMinutes,
    this.targetTemperatureC,
    this.sourceBank,
  });

  final String id;
  final String type;
  final String? bankId;
  final double? pressureAddedBar;
  final double? targetPressureBar;
  final String? pressureInputMode;
  final String? waitMode;
  final double? waitMinutes;
  final double? targetTemperatureC;
  final Bank? sourceBank;

  CompareRow copyWith({
    double? pressureAddedBar,
    double? targetPressureBar,
    Bank? sourceBank,
  }) {
    return CompareRow(
      id: id,
      type: type,
      bankId: bankId,
      pressureAddedBar: pressureAddedBar ?? this.pressureAddedBar,
      targetPressureBar: targetPressureBar ?? this.targetPressureBar,
      pressureInputMode: pressureInputMode,
      waitMode: waitMode,
      waitMinutes: waitMinutes,
      targetTemperatureC: targetTemperatureC,
      sourceBank: sourceBank ?? this.sourceBank,
    );
  }
}

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

// ---------------------------------------------------------------------------
// Protocol results
// ---------------------------------------------------------------------------

class CompareSourceState {
  const CompareSourceState({
    required this.bankId,
    required this.name,
    required this.volumeL,
    required this.pressureBar,
    required this.moles,
    required this.oxygenPercent,
    required this.heliumPercent,
  });

  final String bankId;
  final String name;
  final double volumeL;
  final double pressureBar;
  final double moles;
  final double oxygenPercent;
  final double heliumPercent;
}

class CompareSourceSnapshot {
  const CompareSourceSnapshot({
    required this.pressureBar,
    required this.moles,
    required this.oxygenPercent,
    required this.heliumPercent,
  });

  final double? pressureBar;
  final double? moles;
  final double oxygenPercent;
  final double heliumPercent;
}

class CompareSourceBankSummary {
  const CompareSourceBankSummary({
    required this.id,
    required this.name,
    required this.initial,
    required this.finalState,
  });

  final String id;
  final String name;
  final CompareSourceSnapshot initial;
  final CompareSourceSnapshot finalState;
}

class CompareTransferRate {
  const CompareTransferRate({
    required this.source,
    this.rateBarPerMin,
    this.estimatedDurationMinutes,
    this.boosterBpm,
    this.boosterCylinderVolumeCm3,
  });

  final String source;
  final double? rateBarPerMin;
  final double? estimatedDurationMinutes;
  final double? boosterBpm;
  final double? boosterCylinderVolumeCm3;
}

class CompareStep {
  const CompareStep({
    required this.type,
    required this.compareRowId,
    required this.receiverStartPressureBar,
    required this.receiverEndPressureBar,
    required this.resultingPressureBar,
    required this.resultingMix,
    required this.operation,
    required this.recipeAction,
    required this.title,
    required this.recipeLabel,
    this.method,
    this.sourceBankId,
    this.sourceBankName,
    this.sourceComposition,
    this.sourceOxygenPercent,
    this.sourceHeliumPercent,
    this.sourceStartPressureBar,
    this.sourceEndPressureBar,
    this.sourceState,
    this.sourceMolesAfter,
    this.transferRate,
    this.oxygenCompressionRatio,
    this.recipeGas,
    this.waitMinutes,
    this.waitMode,
    this.targetTemperatureC,
    this.costOperation,
    this.sourceConsumedMoles,
    this.costOperationId,
    this.sourceVolumeL,
    this.sourceStartMoles,
  });

  final String type;
  final String? method;
  final String compareRowId;
  final String? sourceBankId;
  final String? sourceBankName;
  final GasMixPercent? sourceComposition;
  final double? sourceOxygenPercent;
  final double? sourceHeliumPercent;
  final double? sourceStartPressureBar;
  final double? sourceEndPressureBar;
  final CompareSourceState? sourceState;
  final double? sourceMolesAfter;
  final double receiverStartPressureBar;
  final double receiverEndPressureBar;
  final double resultingPressureBar;
  final GasMixPercent resultingMix;
  final CompareTransferRate? transferRate;
  final double? oxygenCompressionRatio;
  final String operation;
  final String recipeAction;
  final String? recipeGas;
  final String title;
  final String recipeLabel;
  final double? waitMinutes;
  final String? waitMode;
  final double? targetTemperatureC;
  final String? costOperation;
  final double? sourceConsumedMoles;
  final String? costOperationId;
  final double? sourceVolumeL;
  final double? sourceStartMoles;
}

class CompareTrajectoryPoint {
  const CompareTrajectoryPoint({
    required this.step,
    required this.label,
    required this.oxygenPercent,
    required this.heliumPercent,
    required this.nitrogenPercent,
    required this.pressureBar,
    required this.pressureDeltaBar,
    required this.color,
  });

  final int step;
  final String label;
  final double oxygenPercent;
  final double heliumPercent;
  final double nitrogenPercent;
  final double pressureBar;
  final double pressureDeltaBar;
  final String color;
}

class CompareSummary {
  const CompareSummary({
    required this.retainedPressureBar,
    required this.retainedPercent,
    required this.ventedPressureBar,
    required this.ventedGasLitres,
    required this.heliumVentedLitres,
    required this.heliumSalvagedLitres,
    required this.heliumRetainedLitres,
  });

  final double retainedPressureBar;
  final double retainedPercent;
  final double ventedPressureBar;
  final double ventedGasLitres;
  final double heliumVentedLitres;
  final double heliumSalvagedLitres;
  final double heliumRetainedLitres;
}

class CompareProtocol {
  const CompareProtocol({
    required this.protocolSteps,
    required this.trajectory,
    required this.initialMix,
    required this.sourceBanks,
    required this.summary,
  });

  final List<CompareStep> protocolSteps;
  final List<CompareTrajectoryPoint> trajectory;
  final GasMixPercent initialMix;
  final List<CompareSourceBankSummary> sourceBanks;
  final CompareSummary summary;
}

// ---------------------------------------------------------------------------
// Internal state
// ---------------------------------------------------------------------------

class _Limits {
  const _Limits({
    required this.minimumSourcePressureBar,
    required this.maxBoosterOutputPressureBar,
    required this.oxygenDecantRateBarPerMin,
    required this.otherDecantRateBarPerMin,
    required this.cylinderVolumeCm3,
    required this.oxygenBoostBpm,
    required this.otherBoostBpm,
  });

  final double minimumSourcePressureBar;
  final double maxBoosterOutputPressureBar;
  final double oxygenDecantRateBarPerMin;
  final double otherDecantRateBarPerMin;
  final double cylinderVolumeCm3;
  final double oxygenBoostBpm;
  final double otherBoostBpm;
}

class _Receiver {
  const _Receiver({
    required this.totalMoles,
    required this.oxygenMoles,
    required this.heliumMoles,
    required this.mix,
    required this.pressureBar,
    this.temperatureC,
  });

  final double totalMoles;
  final double oxygenMoles;
  final double heliumMoles;
  final GasMixPercent mix;
  final double pressureBar;
  final double? temperatureC;

  _Receiver withPressureBar(double value) {
    return _Receiver(
      totalMoles: totalMoles,
      oxygenMoles: oxygenMoles,
      heliumMoles: heliumMoles,
      mix: mix,
      pressureBar: value,
      temperatureC: temperatureC,
    );
  }
}

class _BankIndex {
  const _BankIndex({required this.byId, required this.duplicateIds});

  final Map<String, Bank> byId;
  final Set<String> duplicateIds;
}

class _BankState {
  _BankState({required this.bank, required this.moles});

  final Bank bank;
  double moles;
}

// ---------------------------------------------------------------------------
// Public helpers
// ---------------------------------------------------------------------------

/// JS `compressorAirBank`: unlimited Air whose ceiling is the booster
/// compressor limit (232 bar when not configured).
Bank compressorAirBank(CompareSettings? settings) {
  final configured = settings?.booster?.maxCompressorPressureBar;
  final maxPressureBar = configured != null && configured.isFinite
      ? configured
      : COMPRESSOR_AIR_DEFAULT_PRESSURE_BAR;
  return Bank(
    id: COMPRESSOR_AIR_ID,
    name: 'Compressor Air',
    volumeL: 1,
    pressureBar: maxPressureBar,
    oxygenPercent: 21,
    heliumPercent: 0,
    enabled: true,
    isCompressor: true,
  );
}

CompareRow createCompareRow(String type, String id) {
  switch (type) {
    case 'drain':
      return CompareRow(id: id, type: 'drain', targetPressureBar: 0);
    case 'add':
      return CompareRow(
        id: id,
        type: 'add',
        pressureAddedBar: 0,
        targetPressureBar: 0,
        pressureInputMode: 'added',
      );
    case 'wait':
      return CompareRow(
        id: id,
        type: 'wait',
        waitMode: 'minutes',
        waitMinutes: 0,
      );
    default:
      return CompareRow(id: id, type: 'keep');
  }
}

ComparePressureFields normalizeComparePressureFields(
  CompareRow row,
  double receiverStartPressureBar,
) {
  if (row.pressureInputMode == 'target') {
    final target = row.targetPressureBar ?? double.nan;
    return ComparePressureFields(
      pressureAddedBar: target - receiverStartPressureBar,
      targetPressureBar: target,
      pressureInputMode: row.pressureInputMode,
    );
  }
  final added = row.pressureAddedBar ?? double.nan;
  return ComparePressureFields(
    pressureAddedBar: added,
    targetPressureBar: receiverStartPressureBar + added,
    pressureInputMode: row.pressureInputMode,
  );
}

bool validTemperature(double? value) {
  return value != null &&
      value.isFinite &&
      value >= MIN_WAIT_TEMPERATURE_C &&
      value <= MAX_WAIT_TEMPERATURE_C;
}

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

GasMixPercent _mixFromMoles(
  double totalMoles,
  double oxygenMoles,
  double heliumMoles,
) {
  if (totalMoles <= 0) {
    return const GasMixPercent(oxygenPercent: 0, heliumPercent: 0);
  }
  return GasMixPercent(
    oxygenPercent: (oxygenMoles / totalMoles) * 100,
    heliumPercent: (heliumMoles / totalMoles) * 100,
  );
}

CompareTrajectoryPoint _trajectoryPoint({
  required int step,
  required String label,
  required GasMixPercent mix,
  required double pressureBar,
  required double pressureDeltaBar,
  required String color,
}) {
  return CompareTrajectoryPoint(
    step: step,
    label: label,
    oxygenPercent: mix.oxygenPercent,
    heliumPercent: mix.heliumPercent,
    nitrogenPercent: math.max(
      0.0,
      100.0 - mix.oxygenPercent - mix.heliumPercent,
    ),
    pressureBar: pressureBar,
    pressureDeltaBar: pressureDeltaBar,
    color: color,
  );
}

double _receiverTemperature(_Receiver receiver, double temperatureC) {
  final receiverC = receiver.temperatureC;
  return receiverC != null && receiverC.isFinite ? receiverC : temperatureC;
}

_Receiver _receiverAfterAddedMoles(
  _Receiver receiver,
  double addedMoles,
  Bank sourceBank,
  double volumeL,
  double temperatureC,
  bool useVdw,
) {
  final receiverTemperatureC = _receiverTemperature(receiver, temperatureC);
  final totalMoles = receiver.totalMoles + addedMoles;
  final oxygenMoles =
      receiver.oxygenMoles + addedMoles * (sourceBank.oxygenPercent / 100);
  final heliumMoles =
      receiver.heliumMoles + addedMoles * (sourceBank.heliumPercent / 100);
  final mix = _mixFromMoles(totalMoles, oxygenMoles, heliumMoles);
  final pressureBar = calcPressure(
    totalMoles / volumeL,
    mix.oxygenPercent,
    mix.heliumPercent,
    receiverTemperatureC,
    useVdw,
  );
  return _Receiver(
    totalMoles: totalMoles,
    oxygenMoles: oxygenMoles,
    heliumMoles: heliumMoles,
    mix: mix,
    pressureBar: pressureBar,
    temperatureC: receiverTemperatureC,
  );
}

double _pressureForSourceMoles(
  double moles,
  Bank bank,
  double temperatureC,
  bool useVdw,
) {
  return calcPressure(
    math.max(0.0, moles) / bank.volumeL,
    bank.oxygenPercent,
    bank.heliumPercent,
    temperatureC,
    useVdw,
  );
}

double _solveAddedMoles(
  _Receiver receiver,
  double targetPressureBar,
  Bank bank,
  double volumeL,
  double temperatureC,
  bool useVdw,
) {
  if (targetPressureBar <= receiver.pressureBar + PRESSURE_TOLERANCE_BAR) {
    return 0;
  }
  final receiverTemperatureC = _receiverTemperature(receiver, temperatureC);
  var high = math.max(
    1.0,
    calcMolarDensity(
          targetPressureBar,
          bank.oxygenPercent,
          bank.heliumPercent,
          receiverTemperatureC,
          useVdw,
        ) *
        volumeL,
  );
  var highState = _receiverAfterAddedMoles(
    receiver,
    high,
    bank,
    volumeL,
    temperatureC,
    useVdw,
  );
  while (highState.pressureBar < targetPressureBar && high < 1e9) {
    high *= 2;
    highState = _receiverAfterAddedMoles(
      receiver,
      high,
      bank,
      volumeL,
      temperatureC,
      useVdw,
    );
  }
  if (highState.pressureBar < targetPressureBar) {
    throw RangeError(
      'Supply bank transfer cannot reach the requested receiver pressure.',
    );
  }
  var low = 0.0;
  for (var iteration = 0; iteration < 80; iteration++) {
    final middle = (low + high) / 2;
    final pressure = _receiverAfterAddedMoles(
      receiver,
      middle,
      bank,
      volumeL,
      temperatureC,
      useVdw,
    ).pressureBar;
    if (pressure < targetPressureBar) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return (low + high) / 2;
}

double _solveEqualizationMoles(
  _Receiver receiver,
  double sourceMoles,
  double requiredMoles,
  Bank bank,
  double volumeL,
  double temperatureC,
  bool useVdw,
) {
  var low = 0.0;
  var high = requiredMoles;
  for (var iteration = 0; iteration < 80; iteration++) {
    final middle = (low + high) / 2;
    final receiverPressure = _receiverAfterAddedMoles(
      receiver,
      middle,
      bank,
      volumeL,
      temperatureC,
      useVdw,
    ).pressureBar;
    final sourcePressure = _pressureForSourceMoles(
      sourceMoles - middle,
      bank,
      temperatureC,
      useVdw,
    );
    if (sourcePressure > receiverPressure) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return (low + high) / 2;
}

CompareSourceState _sourceState(
  Bank bank,
  double moles,
  double temperatureC,
  bool useVdw,
) {
  return CompareSourceState(
    bankId: bank.id,
    name: bank.name,
    volumeL: bank.volumeL,
    pressureBar: _pressureForSourceMoles(moles, bank, temperatureC, useVdw),
    moles: moles,
    oxygenPercent: bank.oxygenPercent,
    heliumPercent: bank.heliumPercent,
  );
}

CompareSourceSnapshot _sourceSummaryState(CompareSourceState state) {
  return CompareSourceSnapshot(
    pressureBar: state.pressureBar,
    moles: state.moles,
    oxygenPercent: state.oxygenPercent,
    heliumPercent: state.heliumPercent,
  );
}

CompareTransferRate _transferRate({
  required String type,
  required CompareSourceState sourceStart,
  required CompareSourceState sourceEnd,
  required _Receiver receiverStart,
  required _Receiver receiverEnd,
  required _Limits limits,
  required double receiverVolumeL,
  required double temperatureC,
  required bool useVdw,
}) {
  final pressureIncreaseBar = math.max(
    0.0,
    receiverEnd.pressureBar - receiverStart.pressureBar,
  );
  if (type == 'decant' || type == 'equalize') {
    final rate = sourceStart.oxygenPercent >= 40
        ? limits.oxygenDecantRateBarPerMin
        : limits.otherDecantRateBarPerMin;
    return CompareTransferRate(
      source: 'decant',
      rateBarPerMin: rate,
      estimatedDurationMinutes: pressureIncreaseBar / rate,
    );
  }
  final boosterBpm = sourceStart.oxygenPercent >= 40
      ? limits.oxygenBoostBpm
      : limits.otherBoostBpm;
  final rate = calculateBoosterFillRate(
    cylinderVolumeCm3: limits.cylinderVolumeCm3,
    bpm: boosterBpm,
    sourcePressureBar: (sourceStart.pressureBar + sourceEnd.pressureBar) / 2,
    receiverPressureBar:
        (receiverStart.pressureBar + receiverEnd.pressureBar) / 2,
    sourceOxygenPercent: sourceStart.oxygenPercent,
    sourceHeliumPercent: sourceStart.heliumPercent,
    receiverOxygenPercent: receiverEnd.mix.oxygenPercent,
    receiverHeliumPercent: receiverEnd.mix.heliumPercent,
    receiverVolumeL: receiverVolumeL,
    temperatureC: temperatureC,
    useVdw: useVdw,
  ).fillRateBarPerMin;
  return CompareTransferRate(
    source: 'booster',
    boosterBpm: boosterBpm,
    boosterCylinderVolumeCm3: limits.cylinderVolumeCm3,
    rateBarPerMin: rate,
    estimatedDurationMinutes: pressureIncreaseBar / rate,
  );
}

CompareStep _plannedTransferStep({
  required String type,
  required CompareRow row,
  required Bank bank,
  required CompareSourceState sourceStart,
  required CompareSourceState sourceEnd,
  required _Receiver receiverStart,
  required _Receiver receiverEnd,
  required _Limits limits,
  required double receiverVolumeL,
  required double temperatureC,
  required bool useVdw,
  required String costOperation,
  required double sourceConsumedMoles,
  required String costOperationId,
}) {
  final operation = '${type[0].toUpperCase()}${type.substring(1)}';
  final oxygenCompressionRatio =
      type == 'boost' && bank.oxygenPercent > 40 && sourceEnd.pressureBar > 0
      ? receiverEnd.pressureBar / sourceEnd.pressureBar
      : null;
  return CompareStep(
    type: type,
    compareRowId: row.id,
    sourceBankId: bank.id,
    sourceBankName: bank.name,
    sourceComposition: GasMixPercent(
      oxygenPercent: bank.oxygenPercent,
      heliumPercent: bank.heliumPercent,
    ),
    sourceOxygenPercent: bank.oxygenPercent,
    sourceHeliumPercent: bank.heliumPercent,
    sourceStartPressureBar: sourceStart.pressureBar,
    sourceEndPressureBar: sourceEnd.pressureBar,
    sourceState: sourceEnd,
    sourceMolesAfter: sourceEnd.moles,
    receiverStartPressureBar: receiverStart.pressureBar,
    receiverEndPressureBar: receiverEnd.pressureBar,
    resultingPressureBar: receiverEnd.pressureBar,
    resultingMix: receiverEnd.mix,
    oxygenCompressionRatio: oxygenCompressionRatio,
    transferRate: _transferRate(
      type: type,
      sourceStart: sourceStart,
      sourceEnd: sourceEnd,
      receiverStart: receiverStart,
      receiverEnd: receiverEnd,
      limits: limits,
      receiverVolumeL: receiverVolumeL,
      temperatureC: temperatureC,
      useVdw: useVdw,
    ),
    operation: operation,
    recipeAction: operation,
    recipeGas: bank.name,
    title: operation,
    recipeLabel: operation,
    costOperation: costOperation,
    sourceConsumedMoles: sourceConsumedMoles,
    costOperationId: costOperationId,
    sourceVolumeL: bank.volumeL,
    sourceStartMoles: sourceStart.moles,
  );
}

CompareStep _plannedCompressorStep({
  required CompareRow row,
  required Bank bank,
  required _Receiver receiverStart,
  required _Receiver receiverEnd,
  required double sourceConsumedMoles,
  required String costOperationId,
}) {
  return CompareStep(
    type: 'add',
    method: 'compressor',
    compareRowId: row.id,
    sourceBankId: bank.id,
    sourceBankName: bank.name,
    sourceComposition: GasMixPercent(
      oxygenPercent: bank.oxygenPercent,
      heliumPercent: bank.heliumPercent,
    ),
    sourceOxygenPercent: bank.oxygenPercent,
    sourceHeliumPercent: bank.heliumPercent,
    receiverStartPressureBar: receiverStart.pressureBar,
    receiverEndPressureBar: receiverEnd.pressureBar,
    resultingPressureBar: receiverEnd.pressureBar,
    resultingMix: receiverEnd.mix,
    transferRate: const CompareTransferRate(source: 'compressor'),
    operation: 'Top-up',
    recipeAction: 'Top-up',
    recipeGas: bank.name,
    title: 'Top-up',
    recipeLabel: 'Top-up',
    costOperation: 'topUp',
    sourceConsumedMoles: sourceConsumedMoles,
    costOperationId: costOperationId,
  );
}

CompareStep _passiveStep({
  required CompareRow row,
  required String type,
  required _Receiver receiverStart,
  required double receiverEndPressureBar,
  required GasMixPercent resultingMix,
}) {
  final String operation;
  if (type == 'wait') {
    operation = 'Wait';
  } else if (type == 'drain') {
    operation = 'Drain';
  } else {
    operation = 'Keep';
  }
  return CompareStep(
    type: type,
    compareRowId: row.id,
    waitMinutes: row.waitMinutes,
    waitMode: row.waitMode,
    targetTemperatureC: row.targetTemperatureC,
    receiverStartPressureBar: receiverStart.pressureBar,
    receiverEndPressureBar: receiverEndPressureBar,
    resultingPressureBar: receiverEndPressureBar,
    resultingMix: resultingMix,
    operation: operation,
    recipeAction: operation,
    title: operation,
    recipeLabel: operation,
  );
}

_Receiver _receiverAfterDrain(
  _Receiver receiver,
  double targetPressureBar,
  double volumeL,
  double temperatureC,
  bool useVdw,
) {
  final receiverTemperatureC = _receiverTemperature(receiver, temperatureC);
  final oxygenPercent = receiver.mix.oxygenPercent;
  final heliumPercent = receiver.mix.heliumPercent;
  final totalMoles =
      calcMolarDensity(
        targetPressureBar,
        oxygenPercent,
        heliumPercent,
        receiverTemperatureC,
        useVdw,
      ) *
      volumeL;
  return _Receiver(
    totalMoles: totalMoles,
    oxygenMoles: totalMoles * (oxygenPercent / 100),
    heliumMoles: totalMoles * (heliumPercent / 100),
    mix: receiver.mix,
    pressureBar: targetPressureBar,
    temperatureC: receiverTemperatureC,
  );
}

_Limits _equipmentLimits(CompareSettings? settings) {
  final booster = settings?.booster;
  double pick(double? value, double fallback) {
    return value != null && value.isFinite ? value : fallback;
  }

  return _Limits(
    minimumSourcePressureBar: pick(booster?.minimumSourcePressureBar, 0),
    maxBoosterOutputPressureBar: pick(
      booster?.maxBoosterOutputPressureBar,
      MAX_PRESSURE_BAR,
    ),
    oxygenDecantRateBarPerMin: pick(booster?.oxygenDecantRateBarPerMin, 5),
    otherDecantRateBarPerMin: pick(booster?.otherDecantRateBarPerMin, 10),
    cylinderVolumeCm3: pick(booster?.cylinderVolumeCm3, 9),
    oxygenBoostBpm: pick(booster?.oxygenBoostBpm, 35),
    otherBoostBpm: pick(booster?.otherBoostBpm, 50),
  );
}

int _addTrajectoryPoint(
  List<CompareTrajectoryPoint> trajectory,
  CompareStep step,
  int currentStep,
) {
  if (step.type == 'keep') {
    return currentStep;
  }
  final trajectoryStep = currentStep + 1;
  trajectory.add(
    _trajectoryPoint(
      step: trajectoryStep,
      label: 'Step $trajectoryStep',
      mix: step.resultingMix,
      pressureBar: step.resultingPressureBar,
      pressureDeltaBar:
          step.resultingPressureBar - step.receiverStartPressureBar,
      color: STEP_COLORS[(trajectoryStep - 1) % STEP_COLORS.length],
    ),
  );
  return trajectoryStep;
}

CompareProtocol buildCompareProtocol(
  List<CompareRow> rows, {
  required CompareCylinder cylinder,
  required PhysicsInput physics,
  List<Bank> banks = const <Bank>[],
  CompareSettings? settings,
  Map<String, CompareWaitState> waitStates = const <String, CompareWaitState>{},
}) {
  final validation = validateCompareRecipe(
    rows,
    cylinder: cylinder,
    banks: banks,
    physics: physics,
    settings: settings,
    waitStates: waitStates,
  );
  if (!validation.valid) {
    final messages = validation.errors.map((error) => error.message).join(' ');
    throw DomainError('Invalid compare recipe: $messages');
  }

  final volumeL = cylinder.volumeL;
  final initialP = cylinder.initialPressureBar ?? double.nan;
  if (!volumeL.isFinite || volumeL <= 0 || !_validPressure(initialP)) {
    throw RangeError(
      'Compare protocol requires a finite cylinder volume and initial pressure.',
    );
  }
  if (!physics.temperatureC.isFinite) {
    throw RangeError('Compare protocol requires a finite gas temperature.');
  }
  final temperatureC = physics.temperatureC;
  final useVdw = physics.model != 'ideal';
  final ceiling = _receiverPressureCeiling(cylinder, settings);
  if (initialP > ceiling + PRESSURE_TOLERANCE_BAR) {
    throw RangeError(
      'Compare protocol initial pressure cannot exceed the cylinder working pressure of ${_formatNumber(ceiling)} bar.',
    );
  }

  final limits = _equipmentLimits(settings);
  final bankIndex = _indexedBanks(banks);
  final bankStates = <String, _BankState>{};
  for (final entry in bankIndex.byId.entries) {
    final bank = entry.value;
    bankStates[entry.key] = _BankState(
      bank: _copiedBank(bank),
      moles:
          calcMolarDensity(
            bank.pressureBar,
            bank.oxygenPercent,
            bank.heliumPercent,
            temperatureC,
            useVdw,
          ) *
          bank.volumeL,
    );
  }

  final initialMix = GasMixPercent(
    oxygenPercent: cylinder.initialOxygenPercent,
    heliumPercent: cylinder.initialHeliumPercent,
  );
  final initialMoles =
      calcMolarDensity(
        initialP,
        initialMix.oxygenPercent,
        initialMix.heliumPercent,
        temperatureC,
        useVdw,
      ) *
      volumeL;
  var receiver = _Receiver(
    totalMoles: initialMoles,
    oxygenMoles: initialMoles * (initialMix.oxygenPercent / 100),
    heliumMoles: initialMoles * (initialMix.heliumPercent / 100),
    mix: initialMix,
    pressureBar: initialP,
  );
  var retainedInitialMoles = initialMoles;
  var addedHeliumMoles = 0.0;

  double salvagedHeliumFrom(double moles, double heliumPercent) {
    return heliumPercent < 98 ? moles * (heliumPercent / 100) : 0;
  }

  final protocolSteps = <CompareStep>[];
  var costOperationCounter = 0;
  String nextCostOperationId() {
    costOperationCounter += 1;
    return 'op-$costOperationCounter';
  }

  final sourceSummaries = <String, CompareSourceBankSummary>{};

  void recordCompressorSummary(Bank bank) {
    if (sourceSummaries.containsKey(bank.id)) {
      return;
    }
    final initial = CompareSourceSnapshot(
      pressureBar: null,
      moles: null,
      oxygenPercent: bank.oxygenPercent,
      heliumPercent: bank.heliumPercent,
    );
    sourceSummaries[bank.id] = CompareSourceBankSummary(
      id: bank.id,
      name: bank.name,
      initial: initial,
      finalState: initial,
    );
  }

  void recordFiniteSummary(
    Bank bank,
    CompareSourceState sourceStart,
    CompareSourceState sourceFinal,
  ) {
    final existing = sourceSummaries[bank.id];
    final initial =
        existing?.initial ??
        CompareSourceSnapshot(
          pressureBar: bank.pressureBar,
          moles: sourceStart.moles,
          oxygenPercent: sourceStart.oxygenPercent,
          heliumPercent: sourceStart.heliumPercent,
        );
    sourceSummaries[bank.id] = CompareSourceBankSummary(
      id: bank.id,
      name: bank.name,
      initial: initial,
      finalState: _sourceSummaryState(sourceFinal),
    );
  }

  final trajectory = <CompareTrajectoryPoint>[
    _trajectoryPoint(
      step: 0,
      label: 'Start Mix',
      mix: receiver.mix,
      pressureBar: receiver.pressureBar,
      pressureDeltaBar: 0,
      color: '#f43f5e',
    ),
  ];
  var trajectoryStep = 0;

  for (final row in validation.normalizedRows) {
    if (row.type == 'drain') {
      final receiverStart = receiver;
      final receiverFinal = _receiverAfterDrain(
        receiver,
        row.targetPressureBar ?? double.nan,
        volumeL,
        temperatureC,
        useVdw,
      );
      final retainedFraction = receiver.totalMoles > 0
          ? receiverFinal.totalMoles / receiver.totalMoles
          : 0.0;
      retainedInitialMoles *= retainedFraction;
      addedHeliumMoles *= retainedFraction;
      final step = _passiveStep(
        row: row,
        type: 'drain',
        receiverStart: receiverStart,
        receiverEndPressureBar: receiverFinal.pressureBar,
        resultingMix: receiverFinal.mix,
      );
      protocolSteps.add(step);
      trajectoryStep = _addTrajectoryPoint(trajectory, step, trajectoryStep);
      receiver = receiverFinal;
      continue;
    }

    if (row.type != 'add') {
      final receiverStart = receiver;
      final waitState = row.type == 'wait' ? waitStates[row.id] : null;
      if (waitState != null && waitState.pressureBar.isFinite) {
        final totalMoles = waitState.totalMoles;
        final oxygenMoles = waitState.oxygenMoles;
        final heliumMoles = waitState.heliumMoles;
        if (totalMoles != null &&
            totalMoles.isFinite &&
            oxygenMoles != null &&
            oxygenMoles.isFinite &&
            heliumMoles != null &&
            heliumMoles.isFinite) {
          final waitTemperatureC = waitState.temperatureC;
          receiver = _Receiver(
            totalMoles: totalMoles,
            oxygenMoles: oxygenMoles,
            heliumMoles: heliumMoles,
            mix: waitState.mix ?? receiver.mix,
            pressureBar: waitState.pressureBar,
            temperatureC: waitTemperatureC != null && waitTemperatureC.isFinite
                ? waitTemperatureC
                : (receiver.temperatureC ?? temperatureC),
          );
        } else {
          receiver = receiver.withPressureBar(waitState.pressureBar);
        }
      }
      final step = _passiveStep(
        row: row,
        type: row.type,
        receiverStart: receiverStart,
        receiverEndPressureBar: receiver.pressureBar,
        resultingMix: receiver.mix,
      );
      protocolSteps.add(step);
      trajectoryStep = _addTrajectoryPoint(trajectory, step, trajectoryStep);
      continue;
    }

    // Add row.
    final targetRow = normalizeComparePressureFields(row, receiver.pressureBar);
    final targetPressureBar = targetRow.targetPressureBar;
    if (targetPressureBar > ceiling + PRESSURE_TOLERANCE_BAR) {
      throw RangeError(
        'Compare protocol target pressure cannot exceed the cylinder working pressure of ${_formatNumber(ceiling)} bar.',
      );
    }
    final bank = row.sourceBank;
    if (bank == null) {
      throw StateError('Compare add row ${row.id} has no source bank.');
    }

    if (bank.isCompressor == true) {
      recordCompressorSummary(bank);
      final requiredMoles = _solveAddedMoles(
        receiver,
        targetPressureBar,
        bank,
        volumeL,
        temperatureC,
        useVdw,
      );
      if (requiredMoles <= 1e-9) {
        final step = _passiveStep(
          row: row,
          type: 'keep',
          receiverStart: receiver,
          receiverEndPressureBar: receiver.pressureBar,
          resultingMix: receiver.mix,
        );
        protocolSteps.add(step);
        trajectoryStep = _addTrajectoryPoint(trajectory, step, trajectoryStep);
        continue;
      }
      addedHeliumMoles += salvagedHeliumFrom(requiredMoles, bank.heliumPercent);
      final receiverStart = receiver;
      final receiverFinal = _receiverAfterAddedMoles(
        receiver,
        requiredMoles,
        bank,
        volumeL,
        temperatureC,
        useVdw,
      ).withPressureBar(targetPressureBar);
      final step = _plannedCompressorStep(
        row: row,
        bank: bank,
        receiverStart: receiverStart,
        receiverEnd: receiverFinal,
        sourceConsumedMoles: requiredMoles,
        costOperationId: nextCostOperationId(),
      );
      protocolSteps.add(step);
      trajectoryStep = _addTrajectoryPoint(trajectory, step, trajectoryStep);
      receiver = receiverFinal;
      continue;
    }

    final source = bankStates[bank.id];
    if (source == null) {
      throw StateError('Compare supply bank ${bank.id} was not indexed.');
    }
    final sourceBank = source.bank;
    final requiredMoles = _solveAddedMoles(
      receiver,
      targetPressureBar,
      sourceBank,
      volumeL,
      temperatureC,
      useVdw,
    );
    if (requiredMoles <= 1e-9) {
      final step = _passiveStep(
        row: row,
        type: 'keep',
        receiverStart: receiver,
        receiverEndPressureBar: receiver.pressureBar,
        resultingMix: receiver.mix,
      );
      protocolSteps.add(step);
      trajectoryStep = _addTrajectoryPoint(trajectory, step, trajectoryStep);
      continue;
    }
    addedHeliumMoles += salvagedHeliumFrom(
      requiredMoles,
      sourceBank.heliumPercent,
    );
    final sourceMinimumMoles =
        calcMolarDensity(
          limits.minimumSourcePressureBar,
          sourceBank.oxygenPercent,
          sourceBank.heliumPercent,
          temperatureC,
          useVdw,
        ) *
        sourceBank.volumeL;
    if (source.moles - requiredMoles <
        sourceMinimumMoles - PRESSURE_TOLERANCE_BAR) {
      throw RangeError(
        'Supply bank ${sourceBank.name} cannot retain its ${_formatNumber(limits.minimumSourcePressureBar)} bar minimum pressure for this transfer.',
      );
    }

    final receiverStart = receiver;
    final sourceStart = _sourceState(
      sourceBank,
      source.moles,
      temperatureC,
      useVdw,
    );
    final receiverFinal = _receiverAfterAddedMoles(
      receiver,
      requiredMoles,
      sourceBank,
      volumeL,
      temperatureC,
      useVdw,
    ).withPressureBar(targetPressureBar);
    final sourceFinal = _sourceState(
      sourceBank,
      source.moles - requiredMoles,
      temperatureC,
      useVdw,
    );
    recordFiniteSummary(sourceBank, sourceStart, sourceFinal);

    if (sourceFinal.pressureBar >= targetPressureBar - PRESSURE_TOLERANCE_BAR) {
      final step = _plannedTransferStep(
        type: 'decant',
        row: row,
        bank: sourceBank,
        sourceStart: sourceStart,
        sourceEnd: sourceFinal,
        receiverStart: receiverStart,
        receiverEnd: receiverFinal,
        limits: limits,
        receiverVolumeL: volumeL,
        temperatureC: temperatureC,
        useVdw: useVdw,
        costOperation: 'decant',
        sourceConsumedMoles: requiredMoles,
        costOperationId: nextCostOperationId(),
      );
      protocolSteps.add(step);
      trajectoryStep = _addTrajectoryPoint(trajectory, step, trajectoryStep);
    } else {
      if (targetPressureBar >
          limits.maxBoosterOutputPressureBar + PRESSURE_TOLERANCE_BAR) {
        throw RangeError(
          'Supply bank transfer requires boosting above the ${_formatNumber(limits.maxBoosterOutputPressureBar)} bar booster output limit.',
        );
      }
      final sourceStartsAboveReceiver =
          sourceStart.pressureBar >
          receiverStart.pressureBar + PRESSURE_TOLERANCE_BAR;
      final equalizationMoles = sourceStartsAboveReceiver
          ? _solveEqualizationMoles(
              receiver,
              source.moles,
              requiredMoles,
              sourceBank,
              volumeL,
              temperatureC,
              useVdw,
            )
          : 0.0;
      if (equalizationMoles > 1e-7) {
        final sourceEqualized = _sourceState(
          sourceBank,
          source.moles - equalizationMoles,
          temperatureC,
          useVdw,
        );
        final receiverEqualized = _receiverAfterAddedMoles(
          receiver,
          equalizationMoles,
          sourceBank,
          volumeL,
          temperatureC,
          useVdw,
        ).withPressureBar(sourceEqualized.pressureBar);
        final equalizeStep = _plannedTransferStep(
          type: 'equalize',
          row: row,
          bank: sourceBank,
          sourceStart: sourceStart,
          sourceEnd: sourceEqualized,
          receiverStart: receiverStart,
          receiverEnd: receiverEqualized,
          limits: limits,
          receiverVolumeL: volumeL,
          temperatureC: temperatureC,
          useVdw: useVdw,
          costOperation: 'equalize',
          sourceConsumedMoles: equalizationMoles,
          costOperationId: nextCostOperationId(),
        );
        protocolSteps.add(equalizeStep);
        trajectoryStep = _addTrajectoryPoint(
          trajectory,
          equalizeStep,
          trajectoryStep,
        );

        final boostStep = _plannedTransferStep(
          type: 'boost',
          row: row,
          bank: sourceBank,
          sourceStart: sourceEqualized,
          sourceEnd: sourceFinal,
          receiverStart: receiverEqualized,
          receiverEnd: receiverFinal,
          limits: limits,
          receiverVolumeL: volumeL,
          temperatureC: temperatureC,
          useVdw: useVdw,
          costOperation: 'boost',
          sourceConsumedMoles: requiredMoles - equalizationMoles,
          costOperationId: nextCostOperationId(),
        );
        protocolSteps.add(boostStep);
        trajectoryStep = _addTrajectoryPoint(
          trajectory,
          boostStep,
          trajectoryStep,
        );
      } else {
        final boostStep = _plannedTransferStep(
          type: 'boost',
          row: row,
          bank: sourceBank,
          sourceStart: sourceStart,
          sourceEnd: sourceFinal,
          receiverStart: receiverStart,
          receiverEnd: receiverFinal,
          limits: limits,
          receiverVolumeL: volumeL,
          temperatureC: temperatureC,
          useVdw: useVdw,
          costOperation: 'boost',
          sourceConsumedMoles: requiredMoles,
          costOperationId: nextCostOperationId(),
        );
        protocolSteps.add(boostStep);
        trajectoryStep = _addTrajectoryPoint(
          trajectory,
          boostStep,
          trajectoryStep,
        );
      }
    }
    source.moles -= requiredMoles;
    receiver = receiverFinal;
  }

  final retainedPressureBar = calcPressure(
    retainedInitialMoles / volumeL,
    initialMix.oxygenPercent,
    initialMix.heliumPercent,
    temperatureC,
    useVdw,
  );
  final ventedMoles = math.max(0.0, initialMoles - retainedInitialMoles);
  final gasMolarVolumeL = gasConstant * (temperatureC + 273.15);
  final summary = CompareSummary(
    retainedPressureBar: retainedPressureBar,
    retainedPercent: initialMoles > 0
        ? (retainedInitialMoles / initialMoles) * 100
        : 0.0,
    ventedPressureBar: math.max(0.0, initialP - retainedPressureBar),
    ventedGasLitres: ventedMoles * gasMolarVolumeL,
    heliumVentedLitres:
        ventedMoles * (initialMix.heliumPercent / 100) * gasMolarVolumeL,
    heliumSalvagedLitres:
        (salvagedHeliumFrom(retainedInitialMoles, initialMix.heliumPercent) +
            addedHeliumMoles) *
        gasMolarVolumeL,
    heliumRetainedLitres:
        retainedInitialMoles *
        (initialMix.heliumPercent / 100) *
        gasMolarVolumeL,
  );

  return CompareProtocol(
    protocolSteps: protocolSteps,
    trajectory: trajectory,
    initialMix: initialMix,
    sourceBanks: sourceSummaries.values.toList(),
    summary: summary,
  );
}

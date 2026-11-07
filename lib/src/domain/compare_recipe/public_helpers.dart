part of '../compare_recipe.dart';

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

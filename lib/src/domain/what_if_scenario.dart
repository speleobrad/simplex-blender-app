import 'dart:convert';

import 'bank.dart';
import 'compare_recipe.dart';
import 'cost.dart';
import 'settings.dart';
import 'thermodynamics.dart';

// ignore: constant_identifier_names
const List<String> START_FIELDS = <String>[
  'pressureBar',
  'oxygenPercent',
  'heliumPercent',
  'ambientTemperatureC',
  'cylinderPresetName',
  'coolingMedium',
  'waterSubmersionPercent',
  'inWaterTemperatureC',
];

/// Starting state of a What-if scenario, snapshotted from Blending.
class WhatIfStart {
  const WhatIfStart({
    this.pressureBar,
    this.oxygenPercent,
    this.heliumPercent,
    this.ambientTemperatureC,
    this.cylinderPresetName,
    this.coolingMedium,
    this.waterSubmersionPercent,
    this.inWaterTemperatureC,
  });

  final double? pressureBar;
  final double? oxygenPercent;
  final double? heliumPercent;
  final double? ambientTemperatureC;
  final String? cylinderPresetName;
  final String? coolingMedium;
  final double? waterSubmersionPercent;
  final double? inWaterTemperatureC;

  /// Overlays the non-null fields of [patch] onto this start (JS spread).
  WhatIfStart merge(WhatIfStart patch) => WhatIfStart(
    pressureBar: patch.pressureBar ?? pressureBar,
    oxygenPercent: patch.oxygenPercent ?? oxygenPercent,
    heliumPercent: patch.heliumPercent ?? heliumPercent,
    ambientTemperatureC: patch.ambientTemperatureC ?? ambientTemperatureC,
    cylinderPresetName: patch.cylinderPresetName ?? cylinderPresetName,
    coolingMedium: patch.coolingMedium ?? coolingMedium,
    waterSubmersionPercent:
        patch.waterSubmersionPercent ?? waterSubmersionPercent,
    inWaterTemperatureC: patch.inWaterTemperatureC ?? inWaterTemperatureC,
  );
}

class WhatIfScenario {
  const WhatIfScenario({
    required this.initialized,
    required this.start,
    required this.rows,
    required this.draftRevision,
    required this.resultRevision,
    required this.sharedInputSignature,
  });

  final bool initialized;
  final WhatIfStart? start;
  final List<CompareRow> rows;
  final int draftRevision;
  final int resultRevision;
  final String? sharedInputSignature;

  WhatIfScenario copyWith({
    bool? initialized,
    WhatIfStart? start,
    List<CompareRow>? rows,
    int? draftRevision,
    int? resultRevision,
    String? sharedInputSignature,
  }) => WhatIfScenario(
    initialized: initialized ?? this.initialized,
    start: start ?? this.start,
    rows: rows ?? this.rows,
    draftRevision: draftRevision ?? this.draftRevision,
    resultRevision: resultRevision ?? this.resultRevision,
    sharedInputSignature: sharedInputSignature ?? this.sharedInputSignature,
  );
}

/// Shared-equipment inputs for one What-if run. Replaces the JS input object.
class WhatIfInput {
  const WhatIfInput({
    required this.cylinderPresetName,
    required this.cylinderPreset,
    required this.initialPressureBar,
    required this.initialOxygenPercent,
    required this.initialHeliumPercent,
    required this.physicsModel,
    required this.physicsTemperatureC,
    required this.tankMaterial,
    required this.tankMassKg,
    this.tankSurfaceAreaM2,
    required this.coolingMedium,
    required this.waterSubmersionPercent,
    required this.ambientTemperatureC,
    required this.inletTemperatureC,
    required this.inWaterTemperatureC,
    required this.banks,
    required this.settings,
  });

  final String? cylinderPresetName;
  final CylinderPreset? cylinderPreset;
  final double? initialPressureBar;
  final double? initialOxygenPercent;
  final double? initialHeliumPercent;
  final String physicsModel;
  final double? physicsTemperatureC;
  final String? tankMaterial;
  final double? tankMassKg;
  final double? tankSurfaceAreaM2;
  final String? coolingMedium;
  final double? waterSubmersionPercent;
  final double? ambientTemperatureC;
  final double? inletTemperatureC;
  final double? inWaterTemperatureC;
  final List<Bank> banks;
  final Settings settings;

  double? get volumeL => cylinderPreset?.volumeL;
}

/// In-water projection of the final ambient-settled state.
class WhatIfProjection {
  const WhatIfProjection({
    required this.pressureBar,
    required this.temperatureC,
    required this.oxygenPercent,
    required this.heliumPercent,
  });

  final double pressureBar;
  final double temperatureC;
  final double oxygenPercent;
  final double heliumPercent;
}

WhatIfScenario createWhatIfScenario() => const WhatIfScenario(
  initialized: false,
  start: null,
  rows: <CompareRow>[
    CompareRow(
      id: 'compare-row-1',
      type: 'add',
      bankId: 'bank-oxygen',
      pressureAddedBar: 15,
      targetPressureBar: 60,
      pressureInputMode: 'target',
    ),
  ],
  draftRevision: 0,
  resultRevision: -1,
  sharedInputSignature: null,
);

/// Keeps only drain/add operations and inserts a wait row after every
/// operation except the last. A missing wait minute count defaults to zero;
/// a present NaN is preserved so validation can reject it.
List<CompareRow> expandWhatIfRows(List<CompareRow> rows) {
  final operations = rows
      .where((row) => row.type == 'drain' || row.type == 'add')
      .toList();
  final expanded = <CompareRow>[];
  for (var index = 0; index < operations.length; index++) {
    final row = operations[index];
    expanded.add(row);
    if (index == operations.length - 1) {
      continue;
    }
    expanded.add(
      CompareRow(
        id: '${row.id}-wait',
        type: 'wait',
        waitMode: 'minutes',
        waitMinutes: row.waitMinutes ?? 0,
      ),
    );
  }
  return expanded;
}

WhatIfStart snapshotWhatIfFromBlending({
  required double? initialPressureBar,
  required double? initialOxygenPercent,
  required double? initialHeliumPercent,
  required String? cylinderPresetName,
  required double? ambientTemperatureC,
  required String? coolingMedium,
  required double? waterSubmersionPercent,
  required double? targetInWaterTemperatureC,
}) => WhatIfStart(
  pressureBar: initialPressureBar,
  oxygenPercent: initialOxygenPercent,
  heliumPercent: initialHeliumPercent,
  ambientTemperatureC: ambientTemperatureC,
  cylinderPresetName: cylinderPresetName,
  coolingMedium: coolingMedium,
  waterSubmersionPercent: waterSubmersionPercent,
  inWaterTemperatureC: targetInWaterTemperatureC,
);

WhatIfScenario applyWhatIfStartPatch(
  WhatIfScenario scenario,
  WhatIfStart patch,
) => scenario.copyWith(
  start: (scenario.start ?? const WhatIfStart()).merge(patch),
  rows: List<CompareRow>.of(scenario.rows),
  draftRevision: scenario.draftRevision + 1,
);

String whatIfDraftSignature(WhatIfScenario scenario) {
  final all = _startFieldMap(scenario.start ?? const WhatIfStart());
  return _stable(<String, Object?>{
    'start': <String, Object?>{
      for (final field in START_FIELDS) field: all[field],
    },
    'rows': [for (final row in scenario.rows) _rowJson(row)],
  });
}

String whatIfSharedInputSignature({
  required Settings settings,
  required List<Bank> banks,
  required String? cylinderPresetName,
  double? inletTemperatureC,
}) {
  final preset = _findCylinderPreset(
    settings.cylinderPresets,
    cylinderPresetName,
  );
  return _stable(<String, Object?>{
    'physics': <String, Object?>{'model': settings.physics.model},
    'thermal': <String, Object?>{'inletTemperatureC': inletTemperatureC},
    'cylinderPreset': preset?.toJson(),
    'booster': _boosterJson(settings.booster),
    'pressureLimitMode': settings.pressureLimitMode,
    'banks': [for (final bank in withoutBankPrices(banks)) _bankJson(bank)],
  });
}

WhatIfInput buildWhatIfInput(
  WhatIfScenario scenario, {
  required Settings settings,
  required List<Bank> banks,
  double? inletTemperatureC,
}) {
  final start = scenario.start ?? const WhatIfStart();
  final preset = _findCylinderPreset(
    settings.cylinderPresets,
    start.cylinderPresetName,
  );
  final inlet = inletTemperatureC != null && inletTemperatureC.isFinite
      ? inletTemperatureC
      : start.ambientTemperatureC;
  return WhatIfInput(
    cylinderPresetName: start.cylinderPresetName,
    cylinderPreset: preset,
    initialPressureBar: start.pressureBar,
    initialOxygenPercent: start.oxygenPercent,
    initialHeliumPercent: start.heliumPercent,
    physicsModel: settings.physics.model,
    physicsTemperatureC: start.ambientTemperatureC,
    tankMaterial: preset?.material,
    tankMassKg: preset?.massKg,
    tankSurfaceAreaM2: preset != null && preset.isComplete
        ? preset.surfaceAreaM2
        : null,
    coolingMedium: start.coolingMedium,
    waterSubmersionPercent: start.waterSubmersionPercent,
    ambientTemperatureC: start.ambientTemperatureC,
    inletTemperatureC: inlet,
    inWaterTemperatureC: start.inWaterTemperatureC,
    banks: List<Bank>.of(banks),
    settings: settings,
  );
}

WhatIfProjection projectWhatIfInWater(
  StateSnapshot finalState, {
  required double inWaterTemperatureC,
  required double volumeL,
  required bool useVdw,
}) => WhatIfProjection(
  pressureBar: calculatePressureAtTemperature(
    pressureBar: finalState.pressureBar,
    oxygenPercent: finalState.oxygenPercent,
    heliumPercent: finalState.heliumPercent,
    fromTemperatureC: finalState.temperatureC,
    toTemperatureC: inWaterTemperatureC,
    volumeL: volumeL,
    useVdw: useVdw,
  ),
  temperatureC: inWaterTemperatureC,
  oxygenPercent: finalState.oxygenPercent,
  heliumPercent: finalState.heliumPercent,
);

CylinderPreset? _findCylinderPreset(
  List<CylinderPreset> presets,
  String? name,
) {
  for (final preset in presets) {
    if (preset.name == name) {
      return preset;
    }
  }
  return null;
}

Map<String, Object?> _startFieldMap(WhatIfStart start) => <String, Object?>{
  'pressureBar': start.pressureBar,
  'oxygenPercent': start.oxygenPercent,
  'heliumPercent': start.heliumPercent,
  'ambientTemperatureC': start.ambientTemperatureC,
  'cylinderPresetName': start.cylinderPresetName,
  'coolingMedium': start.coolingMedium,
  'waterSubmersionPercent': start.waterSubmersionPercent,
  'inWaterTemperatureC': start.inWaterTemperatureC,
};

Map<String, Object?> _rowJson(CompareRow row) {
  final bank = row.sourceBank;
  return <String, Object?>{
    'id': row.id,
    'type': row.type,
    'bankId': row.bankId,
    'pressureAddedBar': row.pressureAddedBar,
    'targetPressureBar': row.targetPressureBar,
    'pressureInputMode': row.pressureInputMode,
    'waitMode': row.waitMode,
    'waitMinutes': row.waitMinutes,
    'targetTemperatureC': row.targetTemperatureC,
    'sourceBank': bank == null ? null : _bankJson(bank),
  };
}

Map<String, Object?> _bankJson(Bank bank) => <String, Object?>{
  'id': bank.id,
  'name': bank.name,
  'volumeL': bank.volumeL,
  'pressureBar': bank.pressureBar,
  'oxygenPercent': bank.oxygenPercent,
  'heliumPercent': bank.heliumPercent,
  'enabled': bank.enabled,
  'pricePerLitre': bank.pricePerLitre,
  'maxPressureBar': bank.maxPressureBar,
  'minimumPressureBar': bank.minimumPressureBar,
  'isCompressor': bank.isCompressor,
};

Map<String, Object?> _boosterJson(SettingsBooster booster) => <String, Object?>{
  'minimumSourcePressureBar': booster.minimumSourcePressureBar,
  'cylinderVolumeCm3': booster.cylinderVolumeCm3,
  'oxygenBoostBpm': booster.oxygenBoostBpm,
  'otherBoostBpm': booster.otherBoostBpm,
  'oxygenDecantRateBarPerMin': booster.oxygenDecantRateBarPerMin,
  'otherDecantRateBarPerMin': booster.otherDecantRateBarPerMin,
  'drainingRateBarPerMin': booster.drainingRateBarPerMin,
  'compressorInletFlowLPerMin': booster.compressorInletFlowLPerMin,
  'maxCompressorPressureBar': booster.maxCompressorPressureBar,
  'maxBoosterOutputPressureBar': booster.maxBoosterOutputPressureBar,
  'boosterTemperatureModifierC': booster.boosterTemperatureModifierC,
  'compressorTemperatureModifierC': booster.compressorTemperatureModifierC,
};

/// Deterministic serializer with sorted object keys (JS `stable`).
/// Non-finite numbers serialize as `null`, as `JSON.stringify` does.
String _stable(Object? value) {
  if (value is List<Object?>) {
    return '[${value.map(_stable).join(',')}]';
  }
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_stable(value[key])}').join(',')}}';
  }
  if (value is double && !value.isFinite) {
    return 'null';
  }
  return jsonEncode(value);
}

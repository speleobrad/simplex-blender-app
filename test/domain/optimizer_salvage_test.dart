import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/data/bank_storage.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/optimizer.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/simplex.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

import 'optimizer_fixtures.dart';

Map<String, Object?> _m(Object? value) => value! as Map<String, Object?>;

double _d(Object? value) => (value! as num).toDouble();

List<Map<String, Object?>> _maps(Object? value) =>
    (value! as List<Object?>).cast<Map<String, Object?>>().toList();

List<ProtocolStep> _steps(Object? value) =>
    (value! as List<Object?>).cast<ProtocolStep>().toList();

/// Field-wise view of value classes that define no `==`. JS `deepEqual`
/// compares these objects by their fields, so the tests compare the same way.
Object? _canon(Object? value) {
  switch (value) {
    case Map():
      return <Object?, Object?>{
        for (final entry in value.entries) entry.key: _canon(entry.value),
      };
    case List():
      return <Object?>[for (final item in value) _canon(item)];
    case SimplexStep x:
      return <String, Object?>{
        'phase': _canon(x.phase),
        'note': _canon(x.note),
        'pivotRow': _canon(x.pivotRow),
        'pivotCol': _canon(x.pivotCol),
        'tableau': _canon(x.tableau),
        'varNames': _canon(x.varNames),
      };
    case GasMixPercent x:
      return <String, Object?>{
        'oxygenPercent': _canon(x.oxygenPercent),
        'heliumPercent': _canon(x.heliumPercent),
      };
    case GasLine x:
      return <String, Object?>{
        'sourceBankId': _canon(x.sourceBankId),
        'name': _canon(x.name),
        'litres': _canon(x.litres),
        'unitPrice': _canon(x.unitPrice),
        'cost': _canon(x.cost),
      };
    case UnpricedSource x:
      return <String, Object?>{
        'sourceBankId': _canon(x.sourceBankId),
        'name': _canon(x.name),
      };
    case FillCost x:
      return <String, Object?>{
        'gasLines': _canon(x.gasLines),
        'operationLines': _canon(x.operationLines),
        'gasTotal': _canon(x.gasTotal),
        'operationTotal': _canon(x.operationTotal),
        'total': _canon(x.total),
        'unpricedSources': _canon(x.unpricedSources),
        'incomplete': _canon(x.incomplete),
        'configured': _canon(x.configured),
      };
    case ThermalSample x:
      return <String, Object?>{
        'elapsedMinutes': _canon(x.elapsedMinutes),
        'temperatureC': _canon(x.temperatureC),
        'pressureBar': _canon(x.pressureBar),
        'projectedPressureBar': _canon(x.projectedPressureBar),
        'ambientPressureBar': _canon(x.ambientPressureBar),
        'oxygenPercent': _canon(x.oxygenPercent),
        'heliumPercent': _canon(x.heliumPercent),
        'pressureReferenceTemperatureC': _canon(
          x.pressureReferenceTemperatureC,
        ),
        'pressureAtTransferEndReferenceBar': _canon(
          x.pressureAtTransferEndReferenceBar,
        ),
        'pressureAtTransferEndAmbientBar': _canon(
          x.pressureAtTransferEndAmbientBar,
        ),
        'pressureAtTransferEndHotBar': _canon(x.pressureAtTransferEndHotBar),
      };
    case ThermalStep x:
      return <String, Object?>{
        'rateSource': _canon(x.rateSource),
        'rateBarPerMin': _canon(x.rateBarPerMin),
        'durationMinutes': _canon(x.durationMinutes),
        'inletTemperatureC': _canon(x.inletTemperatureC),
        'pressureStartBar': _canon(x.pressureStartBar),
        'temperatureStartC': _canon(x.temperatureStartC),
        'temperatureAtTransferEndC': _canon(x.temperatureAtTransferEndC),
        'pressureReferenceTemperatureC': _canon(
          x.pressureReferenceTemperatureC,
        ),
        'pressureAtTransferEndReferenceBar': _canon(
          x.pressureAtTransferEndReferenceBar,
        ),
        'pressureAtTransferEndAmbientBar': _canon(
          x.pressureAtTransferEndAmbientBar,
        ),
        'waitMinutes': _canon(x.waitMinutes),
        'temperatureAfterWaitC': _canon(x.temperatureAfterWaitC),
        'pressureAtTransferEndBar': _canon(x.pressureAtTransferEndBar),
        'pressureAtTransferEndHotBar': _canon(x.pressureAtTransferEndHotBar),
        'pressureAfterWaitBar': _canon(x.pressureAfterWaitBar),
        'samples': _canon(x.samples),
        'plannedStartPressureBar': _canon(x.plannedStartPressureBar),
        'plannedStartTemperatureC': _canon(x.plannedStartTemperatureC),
        'measurementIndex': _canon(x.measurementIndex),
        'measurementApplied': _canon(x.measurementApplied),
        'measuredStartPressureBar': _canon(x.measuredStartPressureBar),
        'measuredStartTemperatureC': _canon(x.measuredStartTemperatureC),
        'receiverStartMix': _canon(x.receiverStartMix),
        'configuredWaitMinutes': _canon(x.configuredWaitMinutes),
        'automaticWaitMinutes': _canon(x.automaticWaitMinutes),
        'measuredWaitMinutes': _canon(x.measuredWaitMinutes),
      };
    case ProtocolStep x:
      return <String, Object?>{
        'type': _canon(x.type),
        'operation': _canon(x.operation),
        'title': _canon(x.title),
        'method': _canon(x.method),
        'stage': _canon(x.stage),
        'receiverStartPressureBar': _canon(x.receiverStartPressureBar),
        'receiverEndPressureBar': _canon(x.receiverEndPressureBar),
        'resultingPressureBar': _canon(x.resultingPressureBar),
        'resultingMix': _canon(x.resultingMix),
        'receiverStartMix': _canon(x.receiverStartMix),
        'receiverVolumeL': _canon(x.receiverVolumeL),
        'sourceStartPressureBar': _canon(x.sourceStartPressureBar),
        'sourceEndPressureBar': _canon(x.sourceEndPressureBar),
        'sourcePressureBar': _canon(x.sourcePressureBar),
        'sourceOxygenPercent': _canon(x.sourceOxygenPercent),
        'sourceHeliumPercent': _canon(x.sourceHeliumPercent),
        'pressureReferenceTemperatureC': _canon(
          x.pressureReferenceTemperatureC,
        ),
        'pressureAtTransferEndReferenceBar': _canon(
          x.pressureAtTransferEndReferenceBar,
        ),
        'pressureAtTransferEndAmbientBar': _canon(
          x.pressureAtTransferEndAmbientBar,
        ),
        'pressureAtTransferEndHotBar': _canon(x.pressureAtTransferEndHotBar),
        'automaticWaitMinutes': _canon(x.automaticWaitMinutes),
        'costOperation': _canon(x.costOperation),
        'costOperationId': _canon(x.costOperationId),
        'sourceConsumedMoles': _canon(x.sourceConsumedMoles),
        'waitMode': _canon(x.waitMode),
        'waitMinutes': _canon(x.waitMinutes),
        'targetTemperatureC': _canon(x.targetTemperatureC),
        'measurementIndex': _canon(x.measurementIndex),
        'measurementIndexExplicitNull': _canon(x.measurementIndexExplicitNull),
        'applyInterimMeasurement': _canon(x.applyInterimMeasurement),
        'scheduledMeasuredStartPressureBar': _canon(
          x.scheduledMeasuredStartPressureBar,
        ),
        'scheduledMeasuredStartTemperatureC': _canon(
          x.scheduledMeasuredStartTemperatureC,
        ),
        'safetyWaitOnly': _canon(x.safetyWaitOnly),
        'thermal': _canon(x.thermal),
        'recipeAction': _canon(x.recipeAction),
        'sourceBankId': _canon(x.sourceBankId),
        'description': _canon(x.description),
        'pressureDeltaBar': _canon(x.pressureDeltaBar),
        'minimumSourcePressureBar': _canon(x.minimumSourcePressureBar),
        'sourceExhausted': _canon(x.sourceExhausted),
        'oxygenCompressionRatio': _canon(x.oxygenCompressionRatio),
        'badgeClass': _canon(x.badgeClass),
        'receiverBankId': _canon(x.receiverBankId),
        'receiverBankName': _canon(x.receiverBankName),
        'movedMoles': _canon(x.movedMoles),
        'movedHeliumLitres': _canon(x.movedHeliumLitres),
        'receiverEndMix': _canon(x.receiverEndMix),
        'thermalSplit': _canon(x.thermalSplit),
        'sourceInventory': _canon(x.sourceInventory),
        'sourceVolumeL': _canon(x.sourceVolumeL),
        'sourceStartMoles': _canon(x.sourceStartMoles),
        'sourceEndMoles': _canon(x.sourceEndMoles),
        'receiverStartMoles': _canon(x.receiverStartMoles),
        'receiverEndMoles': _canon(x.receiverEndMoles),
        'recipeGas': _canon(x.recipeGas),
        'recipeLabel': _canon(x.recipeLabel),
        'id': _canon(x.id),
        'automaticWaitMetadata': _canon(x.automaticWaitMetadata),
      };
    default:
      return value;
  }
}

Map<String, Object?> _bankMap(Bank bank) {
  return <String, Object?>{
    'id': bank.id,
    'name': bank.name,
    'volumeL': bank.volumeL,
    'pressureBar': bank.pressureBar,
    'oxygenPercent': bank.oxygenPercent,
    'heliumPercent': bank.heliumPercent,
    'enabled': bank.enabled,
    if (bank.maxPressureBar != null) 'maxPressureBar': bank.maxPressureBar,
    if (bank.minimumPressureBar != null)
      'minimumPressureBar': bank.minimumPressureBar,
    if (bank.pricePerLitre != null) 'pricePerLitre': bank.pricePerLitre,
  };
}

Map<String, Object?> _settingsMap(Settings settings) {
  final booster = settings.booster;
  return <String, Object?>{
    'pressureLimitMode': settings.pressureLimitMode,
    'booster': <String, Object?>{
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
    },
  };
}

Map<String, Object?> _idealPhysics() => <String, Object?>{
  'model': 'ideal',
  'temperatureC': 20.0,
};

Map<String, Object?> _cylinder({
  required double volumeL,
  required double initialPressureBar,
  required double initialOxygenPercent,
  required double initialHeliumPercent,
  required double targetPressureBar,
  required double targetOxygenPercent,
  required double targetHeliumPercent,
  double? workingPressureBar,
  double? hotOverfillPercent,
}) => <String, Object?>{
  'volumeL': volumeL,
  'initialPressureBar': initialPressureBar,
  'initialOxygenPercent': initialOxygenPercent,
  'initialHeliumPercent': initialHeliumPercent,
  'targetPressureBar': targetPressureBar,
  'targetOxygenPercent': targetOxygenPercent,
  'targetHeliumPercent': targetHeliumPercent,
  'workingPressureBar': ?workingPressureBar,
  'hotOverfillPercent': ?hotOverfillPercent,
};

Map<String, Object?> _bank({
  required String id,
  required String name,
  required double volumeL,
  required double pressureBar,
  double maxPressureBar = 350,
  double? minimumPressureBar,
  required double oxygenPercent,
  required double heliumPercent,
}) => <String, Object?>{
  'id': id,
  'name': name,
  'volumeL': volumeL,
  'pressureBar': pressureBar,
  'maxPressureBar': maxPressureBar,
  'minimumPressureBar': ?minimumPressureBar,
  'oxygenPercent': oxygenPercent,
  'heliumPercent': heliumPercent,
  'enabled': true,
};

Bank _bankFromMap(Map<String, Object?> map) => Bank(
  id: map['id']! as String,
  name: map['name']! as String,
  volumeL: _d(map['volumeL']),
  pressureBar: _d(map['pressureBar']),
  oxygenPercent: _d(map['oxygenPercent']),
  heliumPercent: _d(map['heliumPercent']),
  enabled: map['enabled']! as bool,
  maxPressureBar: (map['maxPressureBar'] as num?)?.toDouble(),
  minimumPressureBar: (map['minimumPressureBar'] as num?)?.toDouble(),
);

/// Maps protocol steps to cost-model fill steps (the JS cost function reads
/// the same fields from the step objects directly).
List<FillStep> _fillSteps(List<ProtocolStep> steps) => <FillStep>[
  for (final step in steps)
    FillStep(
      costOperation: step.costOperation,
      costOperationId: step.costOperationId,
      sourceBankId: step.sourceBankId,
      recipeGas: step.recipeGas,
      sourceConsumedMoles: step.sourceConsumedMoles,
    ),
];

ProtocolStep _keep(String id) => ProtocolStep(
  id: id,
  type: 'keep',
  receiverStartPressureBar: 0,
  receiverEndPressureBar: 0,
  resultingPressureBar: 0,
  resultingMix: const GasMixPercent(oxygenPercent: 21, heliumPercent: 0),
);

ProtocolStep _boost({
  String? id,
  required double receiverStart,
  required double receiverEnd,
  required double sourceStart,
  required double sourceEnd,
  double sourceVolumeL = 12,
  double sourceO2 = 21,
  double sourceHe = 0,
  double mixO2 = 21,
  double mixHe = 0,
  String operation = 'Boost',
  String? recipeGas,
}) => ProtocolStep(
  id: id,
  type: 'boost',
  operation: operation,
  recipeGas: recipeGas,
  receiverStartPressureBar: receiverStart,
  receiverEndPressureBar: receiverEnd,
  resultingPressureBar: receiverEnd,
  resultingMix: GasMixPercent(oxygenPercent: mixO2, heliumPercent: mixHe),
  sourceOxygenPercent: sourceO2,
  sourceHeliumPercent: sourceHe,
  sourceStartPressureBar: sourceStart,
  sourceEndPressureBar: sourceEnd,
  sourceVolumeL: sourceVolumeL,
);

/// Typed thermal state for safety-helper tests. Required fields not read by the
/// tested paths get neutral filler values (0 / 'manual' / empty samples).
ThermalStep _thermalState({
  double pressureStartBar = 0,
  double temperatureStartC = 20,
  double pressureReferenceTemperatureC = 20,
  double pressureAtTransferEndReferenceBar = 0,
  double pressureAtTransferEndAmbientBar = 0,
  double pressureAtTransferEndBar = 0,
  double pressureAtTransferEndHotBar = 0,
  double temperatureAtTransferEndC = 20,
  double pressureAfterWaitBar = 0,
  double temperatureAfterWaitC = 20,
  double waitMinutes = 0,
  double durationMinutes = 0,
  List<ThermalSample> samples = const <ThermalSample>[],
  bool? measurementApplied,
  double? measuredStartPressureBar,
  double? measuredStartTemperatureC,
}) => ThermalStep(
  rateSource: 'manual',
  rateBarPerMin: 0,
  durationMinutes: durationMinutes,
  inletTemperatureC: 20,
  pressureStartBar: pressureStartBar,
  temperatureStartC: temperatureStartC,
  temperatureAtTransferEndC: temperatureAtTransferEndC,
  pressureReferenceTemperatureC: pressureReferenceTemperatureC,
  pressureAtTransferEndReferenceBar: pressureAtTransferEndReferenceBar,
  pressureAtTransferEndAmbientBar: pressureAtTransferEndAmbientBar,
  waitMinutes: waitMinutes,
  temperatureAfterWaitC: temperatureAfterWaitC,
  pressureAtTransferEndBar: pressureAtTransferEndBar,
  pressureAtTransferEndHotBar: pressureAtTransferEndHotBar,
  pressureAfterWaitBar: pressureAfterWaitBar,
  samples: samples,
  measurementApplied: measurementApplied,
  measuredStartPressureBar: measuredStartPressureBar,
  measuredStartTemperatureC: measuredStartTemperatureC,
);

ThermalSample _sample({
  double elapsedMinutes = 0,
  required double temperatureC,
  double pressureBar = 0,
  double? projectedPressureBar,
  double? ambientPressureBar,
}) => ThermalSample(
  elapsedMinutes: elapsedMinutes,
  temperatureC: temperatureC,
  pressureBar: pressureBar,
  projectedPressureBar: projectedPressureBar,
  ambientPressureBar: ambientPressureBar,
);

const ThermalFinal _filler = ThermalFinal(
  finalTransferEndPressureBar: 0,
  finalTransferEndTemperatureC: 0,
  finalAmbientPressureBar: 0,
  finalAmbientTemperatureC: 0,
);

ThermalProtocolResult _simulation(List<ProtocolStep> steps) =>
    ThermalProtocolResult(protocolSteps: steps, finalSummary: _filler);

const ThermalInput _steelThermal = ThermalInput(
  ambientTemperatureC: 20,
  tankMaterial: 'steel',
  coolingMedium: 'air',
  inletTemperatureC: 40,
  targetMediumTemperatureC: 20,
  targetInWaterTemperatureC: 20,
  waitMode: 'minutes',
  waitMinutes: 0,
);

/// JS `schedulerFixture`.
final Map<String, Object?> schedulerFixtureCylinder = <String, Object?>{
  'volumeL': 12.0,
  'initialPressureBar': 0.0,
  'workingPressureBar': 80.0,
};

Map<String, Object?> _scheduleWith({
  required Map<String, Object?> cylinder,
  required PhysicsInput physics,
  required ThermalInput thermal,
  required List<ProtocolStep> protocolSteps,
  BlendSettings? settings,
}) => scheduleSafeThermalProtocol(
  protocolSteps: protocolSteps,
  thermal: thermal,
  cylinder: cylinder,
  physics: physics,
  settings: settings,
);

const PhysicsInput _idealPhysics20 = PhysicsInput(
  model: 'ideal',
  temperatureC: 20,
);

/// JS `thermalFailureFixture`.
final Map<String, Object?> thermalFailureFixture = <String, Object?>{
  'tankMaterial': 'steel',
  'coolingMedium': 'air',
  'ambientTemperatureC': 25,
  'inletTemperatureC': 25,
  'targetMediumTemperatureC': 25,
  'targetInWaterTemperatureC': 10,
  'waitMode': 'minutes',
  'waitMinutes': 10,
  'targetTemperatureC': 25,
};

final Map<String, Object?> defaultRecipeInput = <String, Object?>{
  'cylinder': _cylinder(
    volumeL: 11.1,
    initialPressureBar: 45,
    initialOxygenPercent: 21,
    initialHeliumPercent: 0,
    targetPressureBar: 195,
    targetOxygenPercent: 18,
    targetHeliumPercent: 45,
    workingPressureBar: 207,
    hotOverfillPercent: 2,
  ),
  'physics': <String, Object?>{'model': 'vdw', 'temperatureC': 21.0},
  'banks': <Object?>[for (final bank in DEFAULT_BANKS) _bankMap(bank)],
  'thermal': <String, Object?>{
    'tankMaterial': 'aluminum',
    'coolingMedium': 'air',
    'ambientTemperatureC': 21.0,
    'inletTemperatureC': 25.0,
    'targetMediumTemperatureC': 21.0,
    'targetInWaterTemperatureC': 10.0,
    'waitMode': 'minutes',
    'waitMinutes': 5.0,
    'interimMeasurements': <Object?>[],
  },
  'settings': _settingsMap(DEFAULT_SETTINGS),
};

/// JS `schedulerSplitInput`.
final Map<String, Object?> schedulerSplitInput = <String, Object?>{
  'cylinder': _cylinder(
    volumeL: 12,
    initialPressureBar: 95,
    initialOxygenPercent: 0,
    initialHeliumPercent: 0,
    targetPressureBar: 99,
    targetOxygenPercent: 4,
    targetHeliumPercent: 0.2,
    workingPressureBar: 99.01,
    hotOverfillPercent: 0,
  ),
  'physics': _idealPhysics(),
  'thermal': <String, Object?>{
    'tankMaterial': 'steel',
    'coolingMedium': 'air',
    'ambientTemperatureC': 20.0,
    'inletTemperatureC': 40.0,
    'targetMediumTemperatureC': 20.0,
    'targetInWaterTemperatureC': 20.0,
    'waitMode': 'minutes',
    'waitMinutes': 0.0,
  },
  'settings': <String, Object?>{
    'booster': <String, Object?>{
      'otherBoostBpm': 50.0,
      'oxygenBoostBpm': 50.0,
      'otherDecantRateBarPerMin': 5.0,
      'oxygenDecantRateBarPerMin': 5.0,
      'cylinderVolumeCm3': 9.0,
      'minimumSourcePressureBar': 0.0,
    },
  },
  'banks': <Object?>[
    _bank(
      id: 'o2',
      name: 'Oxygen',
      volumeL: 12,
      pressureBar: 300,
      maxPressureBar: 350,
      minimumPressureBar: 0,
      oxygenPercent: 100,
      heliumPercent: 0,
    ),
    _bank(
      id: 'he',
      name: 'Helium',
      volumeL: 12,
      pressureBar: 300,
      maxPressureBar: 350,
      minimumPressureBar: 0,
      oxygenPercent: 0,
      heliumPercent: 100,
    ),
  ],
};

Map<String, Object?> _leftoverBank({
  required String id,
  required double oxygenPercent,
  required double heliumPercent,
  required double pressureBar,
  double maxPressureBar = 200,
  double volumeL = 50,
  bool enabled = true,
}) => <String, Object?>{
  'id': id,
  'name': id,
  'volumeL': volumeL,
  'pressureBar': pressureBar,
  'oxygenPercent': oxygenPercent,
  'heliumPercent': heliumPercent,
  'maxPressureBar': maxPressureBar,
  'minimumPressureBar': 10.0,
  'enabled': enabled,
  'isCompressor': false,
};

Map<String, Object?> _drainSalvageInput(List<Object?> banks) =>
    <String, Object?>{
      'cylinder': _cylinder(
        volumeL: 12,
        initialPressureBar: 150,
        initialOxygenPercent: 21,
        initialHeliumPercent: 35,
        targetPressureBar: 100,
        targetOxygenPercent: 21,
        targetHeliumPercent: 35,
      ),
      'physics': <String, Object?>{'model': 'vdw', 'temperatureC': 20.0},
      'banks': banks,
    };

/// JS `salvageThenDecantInput`.
Map<String, Object?> _salvageThenDecantInput({Map<String, Object?>? thermal}) =>
    <String, Object?>{
      'cylinder': _cylinder(
        volumeL: 12,
        initialPressureBar: 150,
        initialOxygenPercent: 32,
        initialHeliumPercent: 0,
        targetPressureBar: 100,
        targetOxygenPercent: 21,
        targetHeliumPercent: 35,
      ),
      'physics': <String, Object?>{'model': 'vdw', 'temperatureC': 20.0},
      'banks': <Object?>[
        _bank(
          id: 'bank-he',
          name: 'Pure Helium',
          volumeL: 50,
          pressureBar: 200,
          maxPressureBar: 350,
          minimumPressureBar: 15,
          oxygenPercent: 0,
          heliumPercent: 100,
        ),
        _bank(
          id: 'bank-o2',
          name: 'Pure Oxygen',
          volumeL: 40,
          pressureBar: 180,
          maxPressureBar: 350,
          minimumPressureBar: 10,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
        _bank(
          id: 'bank-n',
          name: 'Leftover N',
          volumeL: 50,
          pressureBar: 20,
          maxPressureBar: 200,
          minimumPressureBar: 10,
          oxygenPercent: 32,
          heliumPercent: 0,
        ),
      ],
      'settings': <String, Object?>{
        'booster': <String, Object?>{
          'maxCompressorPressureBar': 350.0,
          'maxBoosterOutputPressureBar': 350.0,
        },
      },
      'thermal': ?thermal,
    };

final Map<String, Object?> _salvageThermal = <String, Object?>{
  'tankMaterial': 'steel',
  'coolingMedium': 'air',
  'ambientTemperatureC': 20.0,
  'inletTemperatureC': 40.0,
  'targetMediumTemperatureC': 20.0,
  'targetInWaterTemperatureC': 20.0,
  'waitMode': 'minutes',
  'waitMinutes': 0.0,
};

/// JS `shallowDeepInput`.
final Map<String, Object?> _shallowDeepInput = <String, Object?>{
  'cylinder': _cylinder(
    volumeL: 11.1,
    initialPressureBar: 45,
    initialOxygenPercent: 7,
    initialHeliumPercent: 70,
    targetPressureBar: 195,
    targetOxygenPercent: 50,
    targetHeliumPercent: 0,
    workingPressureBar: 207,
    hotOverfillPercent: 2,
  ),
  'physics': <String, Object?>{'model': 'vdw', 'temperatureC': 21.0},
  'banks': <Object?>[
    _bank(
      id: 'he',
      name: 'Helium',
      volumeL: 40,
      pressureBar: 150,
      maxPressureBar: 200,
      oxygenPercent: 0,
      heliumPercent: 100,
    ),
    _bank(
      id: 'o2',
      name: 'Oxygen',
      volumeL: 50,
      pressureBar: 200,
      maxPressureBar: 200,
      oxygenPercent: 100,
      heliumPercent: 0,
    ),
    _bank(
      id: 'shallow',
      name: 'Shallow',
      volumeL: 18,
      pressureBar: 117,
      maxPressureBar: 200,
      oxygenPercent: 17,
      heliumPercent: 42,
    ),
    _bank(
      id: 'deep',
      name: 'Deep',
      volumeL: 12,
      pressureBar: 42,
      maxPressureBar: 200,
      oxygenPercent: 11,
      heliumPercent: 63,
    ),
  ],
  'settings': _settingsMap(DEFAULT_SETTINGS),
};

List<String> _salvageReceivers(Map<String, Object?> result) => <String>[
  for (final step in _steps(result['protocolSteps']))
    if (step.type == 'salvage') step.receiverBankId!,
];

void main() {
  group('thermal optimizer', () {
    test(
      'rejects invalid thermal inputs with the existing invalid result shape',
      () {
        final validThermal = <String, Object?>{
          'tankMaterial': 'steel',
          'ambientTemperatureC': 20.0,
          'inletTemperatureC': 20.0,
          'targetMediumTemperatureC': 25.0,
          'targetInWaterTemperatureC': 20.0,
          'waitMode': 'minutes',
          'waitMinutes': 10.0,
          'targetTemperatureC': 25.0,
        };
        final cylinder = _cylinder(
          volumeL: 12,
          initialPressureBar: 80,
          initialOxygenPercent: 21,
          initialHeliumPercent: 0,
          targetPressureBar: 210,
          targetOxygenPercent: 21,
          targetHeliumPercent: 0,
        );
        final variants = <Map<String, Object?>>[
          <String, Object?>{...validThermal, 'tankMaterial': 'carbon'},
          <String, Object?>{...validThermal, 'coolingMedium': 'oil'},
          <String, Object?>{...validThermal, 'waitMode': 'hours'},
          <String, Object?>{...validThermal, 'waitMinutes': -1.0},
          <String, Object?>{
            ...validThermal,
            'waitMode': 'temperature',
            'targetTemperatureC': 20.0,
          },
        ];
        for (final thermal in variants) {
          final result = optimizeBlend(<String, Object?>{
            'cylinder': cylinder,
            'physics': _idealPhysics(),
            'banks': <Object?>[],
            'thermal': thermal,
          });
          expect(result['feasible'], isFalse);
          expect(result['gas'], isNull);
          expect(result['solution'], isNull);
          expect(result['blend'], isNull);
          expect(result['maximumPressure'], isNull);
          expect(result['diagnostics'], isNull);
          expect(_steps(result['protocolSteps']), isEmpty);
          expect(_maps(result['trajectory']), isEmpty);
          expect(
            result['error'],
            matches(
              RegExp(r'invalid blend input:.*thermal', caseSensitive: false),
            ),
          );
        }
        final missingCylinder = optimizeBlend(<String, Object?>{
          'thermal': validThermal,
        });
        expect(
          missingCylinder['error'],
          matches(
            RegExp(r'invalid blend input:.*cylinder', caseSensitive: false),
          ),
        );
      },
    );

    test('thermal target search lowers the hot recipe when ambient warming raises pressure', () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': _cylinder(
          volumeL: 12,
          initialPressureBar: 80,
          initialOxygenPercent: 21,
          initialHeliumPercent: 0,
          targetPressureBar: 80,
          targetOxygenPercent: 21,
          targetHeliumPercent: 0,
        ),
        'physics': _idealPhysics(),
        'banks': <Object?>[],
        'thermal': <String, Object?>{
          'tankMaterial': 'steel',
          'coolingMedium': 'air',
          'ambientTemperatureC': 30.0,
          'waitMinutes': 10.0,
          'targetTemperatureC': 35.0,
        },
        'settings': <String, Object?>{
          'booster': <String, Object?>{
            'minimumSourcePressureBar': 0.0,
            'cylinderVolumeCm3': 9.0,
            'oxygenBoostBpm': 50.0,
            'otherBoostBpm': 50.0,
            'oxygenDecantRateBarPerMin': 5.0,
            'otherDecantRateBarPerMin': 5.0,
            'compressorInletFlowLPerMin': 100.0,
          },
        },
      });
      final thermal = _m(result['thermal']);
      expect(_d(thermal['finalTransferEndPressureBar']), lessThan(80));
      expect(_d(thermal['finalAmbientPressureBar']), closeTo(80, 1e-5));
    });

    test(
      'reaches a high settled target below the equipment pressure ceiling',
      () {
        final result = optimizeBlend(<String, Object?>{
          'cylinder': _cylinder(
            volumeL: 12,
            initialPressureBar: 80,
            initialOxygenPercent: 21,
            initialHeliumPercent: 0,
            targetPressureBar: 340,
            targetOxygenPercent: 21,
            targetHeliumPercent: 0,
          ),
          'physics': _idealPhysics(),
          'banks': <Object?>[],
          'thermal': <String, Object?>{
            'tankMaterial': 'steel',
            'coolingMedium': 'air',
            'ambientTemperatureC': 20.0,
            'waitMinutes': 10.0,
            'targetTemperatureC': 25.0,
          },
          'settings': <String, Object?>{
            'booster': <String, Object?>{
              'maxCompressorPressureBar': 350.0,
              'maxBoosterOutputPressureBar': 350.0,
            },
          },
        });
        expect(result['feasible'], isTrue, reason: result['error'] as String?);
        expect(result['maximumPressure'], isNull);
        final thermal = _m(result['thermal']);
        expect(_d(thermal['finalAmbientPressureBar']), closeTo(340, 1e-5));
        expect(_d(thermal['finalInWaterPressureBar']), closeTo(340, 1e-5));
      },
    );

    test(
      'thermal infeasibility preserves the no-positive-candidate result shape',
      () {
        final result = optimizeBlend(<String, Object?>{
          'cylinder': _cylinder(
            volumeL: 12,
            initialPressureBar: 80,
            initialOxygenPercent: 21,
            initialHeliumPercent: 0,
            targetPressureBar: 210,
            targetOxygenPercent: 32,
            targetHeliumPercent: 0,
          ),
          'physics': _idealPhysics(),
          'banks': <Object?>[],
          'thermal': <String, Object?>{
            'tankMaterial': 'steel',
            'coolingMedium': 'air',
            'ambientTemperatureC': 20.0,
            'waitMode': 'minutes',
            'waitMinutes': 10.0,
            'targetTemperatureC': 25.0,
          },
        });
        final gas = _m(result['gas']);
        expect(_d(gas['targetPressureBar']), 210);
        expect(result['maximumPressure'], isNull);
        expect(_steps(result['protocolSteps']), isEmpty);
        final thermal = _m(result['thermal']);
        expect(_d(thermal['requestedInWaterPressureBar']), 210);
        expect(_d(thermal['requestedInWaterTemperatureC']), 20);
        expect(
          result['error'],
          matches(RegExp('requested in-water pressure', caseSensitive: false)),
        );
      },
    );

    test(
      'normalizes the requested in-water target and reports all thermal states',
      () {
        final result = optimizeBlend(<String, Object?>{
          'cylinder': _cylinder(
            volumeL: 12,
            initialPressureBar: 50,
            initialOxygenPercent: 18,
            initialHeliumPercent: 45,
            targetPressureBar: 188.6,
            targetOxygenPercent: 18,
            targetHeliumPercent: 45,
          ),
          'physics': <String, Object?>{'model': 'vdw', 'temperatureC': 25.0},
          'thermal': <String, Object?>{
            'tankMaterial': 'steel',
            'coolingMedium': 'water',
            'ambientTemperatureC': 25.0,
            'inletTemperatureC': 25.0,
            'targetMediumTemperatureC': 25.0,
            'targetInWaterTemperatureC': 10.0,
            'waitMode': 'minutes',
            'waitMinutes': 10.0,
          },
          'banks': <Object?>[
            _bank(
              id: '1845',
              name: '1845',
              volumeL: 50,
              pressureBar: 200,
              maxPressureBar: 350,
              minimumPressureBar: 20,
              oxygenPercent: 18,
              heliumPercent: 45,
            ),
          ],
          'settings': <String, Object?>{
            'booster': <String, Object?>{
              'minimumSourcePressureBar': 0.0,
              'maxCompressorPressureBar': 350.0,
              'maxBoosterOutputPressureBar': 350.0,
              'cylinderVolumeCm3': 9.0,
              'oxygenBoostBpm': 50.0,
              'otherBoostBpm': 50.0,
              'oxygenDecantRateBarPerMin': 5.0,
              'otherDecantRateBarPerMin': 5.0,
              'compressorInletFlowLPerMin': 100.0,
            },
          },
        });
        final thermal = _m(result['thermal']);
        expect(
          _d(thermal['ambientSettledTargetPressureBar']),
          closeTo(200, 0.2),
        );
        expect(_d(thermal['finalAmbientPressureBar']), closeTo(200, 0.2));
        expect(_d(thermal['finalAmbientTemperatureC']), closeTo(25, 1e-9));
        expect(_d(thermal['finalInWaterTemperatureC']), closeTo(10, 1e-9));
        expect(_d(thermal['finalInWaterPressureBar']), closeTo(188.6, 0.2));
        expect(_d(thermal['requestedInWaterPressureBar']), 188.6);
        expect(_d(thermal['requestedInWaterTemperatureC']), 10);
      },
    );

    test('thermal initial infeasibility preserves requested target and maximum fallback state', () {
      final base = defaultOptimizerInput();
      final result = optimizeBlend(<String, Object?>{
        ...base,
        'cylinder': <String, Object?>{
          ..._m(base['cylinder']),
          'targetPressureBar': 200.0,
          'targetOxygenPercent': 15.0,
          'targetHeliumPercent': 55.0,
        },
        'thermal': thermalFailureFixture,
        'banks': <Object?>[
          _bank(
            id: 'he',
            name: 'Pure Helium',
            volumeL: 1,
            pressureBar: 10,
            maxPressureBar: 350,
            minimumPressureBar: 0,
            oxygenPercent: 0,
            heliumPercent: 100,
          ),
          _bank(
            id: 'o2',
            name: 'Pure Oxygen',
            volumeL: 10,
            pressureBar: 100,
            maxPressureBar: 350,
            minimumPressureBar: 0,
            oxygenPercent: 100,
            heliumPercent: 0,
          ),
        ],
      });
      final thermal = _m(result['thermal']);
      expect(_d(thermal['requestedInWaterPressureBar']), 200);
      expect(_d(thermal['ambientSettledTargetPressureBar']), greaterThan(200));
      expect(result['maximumPressure'], isNotNull);
    });

    test(
      'thermal floor infeasibility prefixes the requested in-water pressure',
      () {
        final result = optimizeBlend(<String, Object?>{
          'cylinder': _cylinder(
            volumeL: 12,
            initialPressureBar: 80,
            initialOxygenPercent: 21,
            initialHeliumPercent: 0,
            targetPressureBar: 300,
            targetOxygenPercent: 15,
            targetHeliumPercent: 55,
          ),
          'physics': _idealPhysics(),
          'banks': <Object?>[
            _bank(
              id: 'he',
              name: 'Pure Helium',
              volumeL: 1,
              pressureBar: 10,
              maxPressureBar: 350,
              minimumPressureBar: 0,
              oxygenPercent: 0,
              heliumPercent: 100,
            ),
            _bank(
              id: 'o2',
              name: 'Pure Oxygen',
              volumeL: 10,
              pressureBar: 100,
              maxPressureBar: 350,
              minimumPressureBar: 0,
              oxygenPercent: 100,
              heliumPercent: 0,
            ),
          ],
          'thermal': thermalFailureFixture,
        });
        expect(
          result['error'],
          matches(RegExp(r'^Requested in-water pressure 300\.0 bar')),
        );
        expect(
          result['error'],
          matches(RegExp('ambient', caseSensitive: false)),
        );
      },
    );

    test('thermal high-ceiling infeasibility retains requested and ambient target diagnostics', () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': _cylinder(
          volumeL: 12,
          initialPressureBar: 80,
          initialOxygenPercent: 21,
          initialHeliumPercent: 0,
          targetPressureBar: 350,
          targetOxygenPercent: 21,
          targetHeliumPercent: 0,
        ),
        'physics': _idealPhysics(),
        'banks': <Object?>[],
        'thermal': thermalFailureFixture,
      });
      final thermal = _m(result['thermal']);
      expect(_d(thermal['requestedInWaterPressureBar']), 350);
      expect(_d(thermal['ambientSettledTargetPressureBar']), greaterThan(350));
    });

    test('thermal no-maximum result leaves final state fields null', () {
      final base = defaultOptimizerInput();
      final result = optimizeBlend(<String, Object?>{
        ...base,
        'cylinder': <String, Object?>{
          ..._m(base['cylinder']),
          'targetPressureBar': 200.0,
          'targetOxygenPercent': 100.0,
          'targetHeliumPercent': 0.0,
        },
        'thermal': thermalFailureFixture,
        'banks': <Object?>[],
      });
      expect(result['feasible'], isFalse);
      expect(result['maximumPressure'], isNull);
      final thermal = _m(result['thermal']);
      expect(thermal['finalAmbientPressureBar'], isNull);
      expect(thermal['finalAmbientTemperatureC'], isNull);
      expect(thermal['finalInWaterPressureBar'], isNull);
      expect(thermal['finalInWaterTemperatureC'], isNull);
      expect(thermal['finalTransferEndPressureBar'], isNull);
      expect(_d(thermal['requestedInWaterPressureBar']), 200);
      expect(_d(thermal['requestedInWaterTemperatureC']), 10);
    });
  });

  group('thermal scheduler', () {
    test('scheduler enforces working pressure at above-ambient target-temperature waits', () {
      final scheduled = _scheduleWith(
        cylinder: _cylinder(
          volumeL: 12,
          initialPressureBar: 0,
          initialOxygenPercent: 21,
          initialHeliumPercent: 0,
          targetPressureBar: 100,
          targetOxygenPercent: 21,
          targetHeliumPercent: 0,
          workingPressureBar: 100,
          hotOverfillPercent: 5,
        ),
        physics: _idealPhysics20,
        thermal: const ThermalInput(
          ambientTemperatureC: 20,
          tankMaterial: 'steel',
          coolingMedium: 'air',
          inletTemperatureC: 40,
          targetMediumTemperatureC: 30,
          targetTemperatureC: 30,
          waitMode: 'temperature',
        ),
        protocolSteps: <ProtocolStep>[
          _boost(
            receiverStart: 0,
            receiverEnd: 99.5,
            sourceStart: 300,
            sourceEnd: 200,
          ),
          _keep('keep'),
        ],
      );
      final steps = _steps(scheduled['protocolSteps']);
      final nonLast = steps.sublist(0, steps.length - 1);
      expect(
        nonLast.any((step) => (step.thermal?.temperatureAfterWaitC ?? 0) > 20),
        isTrue,
      );
      final exceedsWorkingPressure = steps.any(
        (step) => (step.thermal?.pressureAfterWaitBar ?? 0) > 100 + 1e-7,
      );
      expect(scheduled['unsafe'] == true || !exceedsWorkingPressure, isTrue);
    });

    test(
      'scheduler rejects an unsafe transfer after the 1440-minute ceiling',
      () {
        final scheduled = _scheduleWith(
          cylinder: schedulerFixtureCylinder,
          physics: _idealPhysics20,
          thermal: _steelThermal,
          protocolSteps: <ProtocolStep>[
            _boost(
              receiverStart: 0,
              receiverEnd: 95,
              sourceStart: 200,
              sourceEnd: 100,
            ),
          ],
        );
        expect(scheduled['unsafe'], isTrue);
        for (final wait in _maps(scheduled['automaticWaits'])) {
          expect(
            _d(wait['configuredWaitMinutes']) + _d(wait['addedWaitMinutes']),
            lessThanOrEqualTo(1440),
          );
        }
      },
    );

    test(
      'scheduler reports split stages and warning metadata at a hot boundary',
      () {
        final scheduled = _scheduleWith(
          cylinder: _cylinder(
            volumeL: 12,
            initialPressureBar: 0,
            initialOxygenPercent: 21,
            initialHeliumPercent: 0,
            targetPressureBar: 100,
            targetOxygenPercent: 21,
            targetHeliumPercent: 0,
            workingPressureBar: 100,
            hotOverfillPercent: 0,
          ),
          physics: _idealPhysics20,
          thermal: _steelThermal,
          protocolSteps: <ProtocolStep>[
            _boost(
              receiverStart: 0,
              receiverEnd: 98,
              sourceStart: 300,
              sourceEnd: 200,
            ),
          ],
        );
        final steps = _steps(scheduled['protocolSteps']);
        expect(steps.where((step) => step.thermalSplit == true), isNotEmpty);
        expect(scheduled['unsafe'], isFalse);
      },
    );

    test(
      'solves a nonzero minimum wait before the first transfer after keep',
      () {
        final scheduled = _scheduleWith(
          cylinder: _cylinder(
            volumeL: 12,
            initialPressureBar: 0,
            initialOxygenPercent: 21,
            initialHeliumPercent: 0,
            targetPressureBar: 100,
            targetOxygenPercent: 21,
            targetHeliumPercent: 0,
            workingPressureBar: 100,
            hotOverfillPercent: 0,
          ),
          physics: _idealPhysics20,
          thermal: _steelThermal,
          protocolSteps: <ProtocolStep>[
            _keep('keep'),
            _boost(
              receiverStart: 0,
              receiverEnd: 98,
              sourceStart: 300,
              sourceEnd: 200,
            ),
          ],
        );
        expect(scheduled['unsafe'], isFalse);
        final waits = _maps(scheduled['automaticWaits']);
        expect(waits, isNotEmpty);
        expect(_d(waits.first['actualWaitMinutes']), greaterThan(0));
      },
    );

    test('splits by transferred inventories and cools between safe transfer stages', () {
      final scheduled = _scheduleWith(
        cylinder: _cylinder(
          volumeL: 12,
          initialPressureBar: 0,
          initialOxygenPercent: 21,
          initialHeliumPercent: 0,
          targetPressureBar: 100,
          targetOxygenPercent: 21,
          targetHeliumPercent: 0,
          workingPressureBar: 100,
          hotOverfillPercent: 0,
        ),
        physics: _idealPhysics20,
        thermal: _steelThermal,
        protocolSteps: <ProtocolStep>[
          _boost(
            id: 'split',
            receiverStart: 0,
            receiverEnd: 98,
            sourceStart: 300,
            sourceEnd: 200,
          ),
        ],
      );
      final steps = _steps(scheduled['protocolSteps']);
      final boosts = steps.where((step) => step.type == 'boost').toList();
      expect(boosts.length, greaterThanOrEqualTo(2));
      expect(steps.any((step) => step.safetyWaitOnly == true), isTrue);
    });

    test('generated split waits carry the first hot endpoint and cooled inventory forward', () {
      final scheduled = _scheduleWith(
        cylinder: <String, Object?>{
          ...schedulerFixtureCylinder,
          'initialOxygenPercent': 21.0,
          'initialHeliumPercent': 0.0,
          'workingPressureBar': 100.0,
        },
        physics: _idealPhysics20,
        thermal: const ThermalInput(
          ambientTemperatureC: 20,
          tankMaterial: 'steel',
          coolingMedium: 'air',
          inletTemperatureC: 30,
          targetMediumTemperatureC: 20,
          targetInWaterTemperatureC: 20,
          waitMode: 'minutes',
          waitMinutes: 0,
        ),
        protocolSteps: <ProtocolStep>[
          _boost(
            receiverStart: 0,
            receiverEnd: 98,
            sourceStart: 300,
            sourceEnd: 200,
            sourceVolumeL: 12,
          ),
        ],
      );
      final steps = _steps(scheduled['protocolSteps']);
      final first = steps.firstWhere(
        (step) => step.title?.contains('safe stage 1') ?? false,
      );
      final wait = steps.firstWhere(
        (step) =>
            step.safetyWaitOnly == true &&
            (step.title?.contains('between safe') ?? false),
      );
      final second = steps.firstWhere(
        (step) => step.title?.contains('safe stage 2') ?? false,
      );
      expect(
        wait.resultingMix!.oxygenPercent,
        first.resultingMix!.oxygenPercent,
      );
      expect(
        wait.resultingMix!.heliumPercent,
        first.resultingMix!.heliumPercent,
      );
      expect(
        wait.thermal!.pressureAtTransferEndHotBar,
        first.thermal!.pressureAtTransferEndHotBar,
      );
      expect(
        wait.thermal!.receiverStartMix!.oxygenPercent,
        first.resultingMix!.oxygenPercent,
      );
      expect(
        wait.thermal!.receiverStartMix!.heliumPercent,
        first.resultingMix!.heliumPercent,
      );
      expect(
        second.thermal!.receiverStartMix!.oxygenPercent,
        first.resultingMix!.oxygenPercent,
      );
      expect(
        second.thermal!.receiverStartMix!.heliumPercent,
        first.resultingMix!.heliumPercent,
      );
      expect(
        second.thermal!.pressureStartBar,
        wait.thermal!.pressureAfterWaitBar,
      );
      expect(
        second.thermal!.temperatureStartC,
        wait.thermal!.temperatureAfterWaitC,
      );
    });

    test('finite-source split inventories convert reference pressure to common ambient temperature', () {
      final scheduled = _scheduleWith(
        cylinder: _cylinder(
          volumeL: 12,
          initialPressureBar: 0,
          initialOxygenPercent: 21,
          initialHeliumPercent: 0,
          targetPressureBar: 100,
          targetOxygenPercent: 21,
          targetHeliumPercent: 0,
          workingPressureBar: 100,
          hotOverfillPercent: 0,
        ),
        physics: _idealPhysics20,
        thermal: _steelThermal,
        protocolSteps: <ProtocolStep>[
          _boost(
            receiverStart: 0,
            receiverEnd: 98,
            sourceStart: 300,
            sourceEnd: 200,
          ),
        ],
      );
      expect(scheduled['unsafe'], isFalse);
      for (final step in _steps(scheduled['protocolSteps'])) {
        final state = step.thermal;
        if (state == null) {
          continue;
        }
        expect(
          state.pressureAtTransferEndHotBar,
          lessThanOrEqualTo(100 + 1e-7),
        );
      }
    });

    test('optimizer returns a safe split protocol near the thermal working-pressure ceiling', () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': _cylinder(
          volumeL: 12,
          initialPressureBar: 0,
          initialOxygenPercent: 21,
          initialHeliumPercent: 0,
          targetPressureBar: 99.5,
          targetOxygenPercent: 21,
          targetHeliumPercent: 0,
          workingPressureBar: 100,
          hotOverfillPercent: 0,
        ),
        'physics': _idealPhysics(),
        'thermal': <String, Object?>{
          'tankMaterial': 'steel',
          'coolingMedium': 'air',
          'ambientTemperatureC': 20.0,
          'inletTemperatureC': 40.0,
          'targetMediumTemperatureC': 20.0,
          'targetInWaterTemperatureC': 20.0,
          'waitMode': 'minutes',
          'waitMinutes': 0.0,
        },
        'settings': <String, Object?>{
          'booster': <String, Object?>{'compressorInletFlowLPerMin': 100.0},
        },
        'banks': <Object?>[],
      });
      expect(result['feasible'], isTrue, reason: result['error'] as String?);
      expect(result['maximumPressure'], isNull);
      final thermal = _m(result['thermal']);
      expect(_d(thermal['finalAmbientPressureBar']), closeTo(99.5, 1e-7));
      expect(
        _d(thermal['finalTransferEndPressureBar']),
        lessThanOrEqualTo(100 + 1e-7),
      );
      final transferSteps = _steps(result['protocolSteps'])
          .where((step) => step.type == 'boost' || step.type == 'decant')
          .toList();
      expect(transferSteps.length, greaterThanOrEqualTo(2));
      for (final step in transferSteps) {
        final state = step.thermal!;
        expect(
          state.pressureAtTransferEndReferenceBar,
          lessThanOrEqualTo(100 + 1e-7),
        );
        expect(
          state.pressureAtTransferEndAmbientBar,
          lessThanOrEqualTo(100 + 1e-7),
        );
        expect(
          state.pressureAtTransferEndHotBar,
          lessThanOrEqualTo(100 + 1e-7),
        );
        expect(state.pressureAfterWaitBar, lessThanOrEqualTo(100 + 1e-7));
        for (final sample in state.samples) {
          expect(
            sample.ambientPressureBar ??
                sample.projectedPressureBar ??
                sample.pressureBar,
            lessThanOrEqualTo(100 + 1e-7),
          );
        }
      }
    });

    test(
      'scheduler preserves interim measurement identity across inserted waits',
      () {
        final scheduled = _scheduleWith(
          cylinder: _cylinder(
            volumeL: 12,
            initialPressureBar: 0,
            initialOxygenPercent: 21,
            initialHeliumPercent: 0,
            targetPressureBar: 100,
            targetOxygenPercent: 21,
            targetHeliumPercent: 0,
            workingPressureBar: 100,
            hotOverfillPercent: 0,
          ),
          physics: const PhysicsInput(model: 'ideal', temperatureC: 40),
          thermal: const ThermalInput(
            ambientTemperatureC: 20,
            tankMaterial: 'steel',
            coolingMedium: 'air',
            inletTemperatureC: 40,
            targetMediumTemperatureC: 20,
            targetInWaterTemperatureC: 20,
            waitMode: 'minutes',
            waitMinutes: 0,
            interimMeasurements: <InterimMeasurement>[
              InterimMeasurement(pressureBar: 0, temperatureC: 40),
              InterimMeasurement(pressureBar: 0, temperatureC: 40),
              InterimMeasurement(pressureBar: 95, temperatureC: 20),
            ],
          ),
          protocolSteps: <ProtocolStep>[
            ProtocolStep(
              id: 'keep',
              type: 'keep',
              receiverStartPressureBar: 0,
              receiverEndPressureBar: 0,
              resultingPressureBar: 0,
              resultingMix: const GasMixPercent(
                oxygenPercent: 21,
                heliumPercent: 0,
              ),
            ),
            ProtocolStep(
              id: 'first-transfer',
              type: 'boost',
              operation: 'Boost',
              receiverStartPressureBar: 0,
              receiverEndPressureBar: 100,
              resultingPressureBar: 100,
              resultingMix: const GasMixPercent(
                oxygenPercent: 21,
                heliumPercent: 0,
              ),
              sourceOxygenPercent: 21,
              sourceHeliumPercent: 0,
              sourceStartPressureBar: 200,
              sourceEndPressureBar: 100,
              sourceVolumeL: 12,
            ),
            ProtocolStep(
              id: 'second-transfer',
              type: 'boost',
              operation: 'Boost',
              receiverStartPressureBar: 100,
              receiverEndPressureBar: 100,
              resultingPressureBar: 100,
              resultingMix: const GasMixPercent(
                oxygenPercent: 21,
                heliumPercent: 0,
              ),
              sourceOxygenPercent: 21,
              sourceHeliumPercent: 0,
              sourceStartPressureBar: 200,
              sourceEndPressureBar: 100,
              sourceVolumeL: 12,
            ),
          ],
        );
        expect(scheduled['unsafe'], isFalse);
        final steps = _steps(scheduled['protocolSteps']);
        final keep = steps.firstWhere((step) => step.id == 'keep');
        final first = steps.firstWhere((step) => step.id == 'first-transfer');
        final second = steps.firstWhere((step) => step.id == 'second-transfer');
        expect(keep.thermal!.measuredStartPressureBar, 0);
        expect(keep.thermal!.measuredStartTemperatureC, 40);
        expect(first.thermal!.measuredStartPressureBar, 0);
        expect(first.thermal!.measuredStartTemperatureC, 40);
        expect(second.thermal!.measuredStartPressureBar, 95);
        expect(second.thermal!.measuredStartTemperatureC, 20);
        expect(
          steps.any((step) => step.measurementIndexExplicitNull == true),
          isTrue,
        );
      },
    );

    test('scheduler projects endpoints from the physics pressure reference temperature', () {
      final thermal = const ThermalInput(
        ambientTemperatureC: 20,
        tankMaterial: 'steel',
        coolingMedium: 'air',
        inletTemperatureC: 40,
        targetMediumTemperatureC: 20,
        targetInWaterTemperatureC: 20,
        waitMode: 'minutes',
        waitMinutes: 0,
      );
      final scheduled = _scheduleWith(
        cylinder: _cylinder(
          volumeL: 12,
          initialPressureBar: 0,
          initialOxygenPercent: 21,
          initialHeliumPercent: 0,
          targetPressureBar: 100,
          targetOxygenPercent: 21,
          targetHeliumPercent: 0,
          workingPressureBar: 100,
          hotOverfillPercent: 0,
        ),
        physics: const PhysicsInput(model: 'ideal', temperatureC: 30),
        thermal: thermal,
        protocolSteps: <ProtocolStep>[
          _boost(
            receiverStart: 0,
            receiverEnd: 98,
            sourceStart: 300,
            sourceEnd: 200,
          ),
        ],
      );
      expect(scheduled['unsafe'], isFalse);
      expect(
        isSafeSimulation(
          scheduled['simulation'] as ThermalProtocolResult,
          100,
          thermal: thermal,
          physics: const PhysicsInput(model: 'ideal', temperatureC: 30),
          cylinder: _cylinder(
            volumeL: 12,
            initialPressureBar: 0,
            initialOxygenPercent: 21,
            initialHeliumPercent: 0,
            targetPressureBar: 100,
            targetOxygenPercent: 21,
            targetHeliumPercent: 0,
            workingPressureBar: 100,
          ),
        ),
        isTrue,
      );
      for (final step in _steps(scheduled['protocolSteps'])) {
        final state = step.thermal;
        if (state == null) {
          continue;
        }
        expect(state.pressureReferenceTemperatureC, 30);
        final expectedHotPressure = calculatePressureAtTemperature(
          pressureBar: state.pressureAtTransferEndReferenceBar,
          oxygenPercent: step.resultingMix?.oxygenPercent ?? 21,
          heliumPercent: step.resultingMix?.heliumPercent ?? 0,
          fromTemperatureC: 30,
          toTemperatureC: state.temperatureAtTransferEndC,
          volumeL: 12,
          useVdw: false,
        );
        expect(
          expectedHotPressure,
          closeTo(state.pressureAtTransferEndBar, 1e-9),
        );
        expect(expectedHotPressure, lessThanOrEqualTo(100 + 1e-7));
      }
    });

    test('compressor-air splits keep the source effectively unlimited', () {
      final scheduled = _scheduleWith(
        cylinder: _cylinder(
          volumeL: 12,
          initialPressureBar: 0,
          initialOxygenPercent: 21,
          initialHeliumPercent: 0,
          targetPressureBar: 100,
          targetOxygenPercent: 21,
          targetHeliumPercent: 0,
          workingPressureBar: 100,
          hotOverfillPercent: 0,
        ),
        physics: _idealPhysics20,
        thermal: const ThermalInput(
          ambientTemperatureC: 20,
          tankMaterial: 'steel',
          coolingMedium: 'air',
          inletTemperatureC: 30,
          targetMediumTemperatureC: 20,
          targetInWaterTemperatureC: 20,
          waitMode: 'minutes',
          waitMinutes: 0,
        ),
        protocolSteps: <ProtocolStep>[
          _boost(
            receiverStart: 0,
            receiverEnd: 98,
            sourceStart: 350,
            sourceEnd: 350,
            sourceVolumeL: 1,
            operation: 'Top-up',
            recipeGas: 'Compressor Air',
          ),
        ],
      );
      expect(scheduled['unsafe'], isFalse);
      final stages = _steps(scheduled['protocolSteps'])
          .where((step) => step.type == 'boost')
          .toList();
      expect(stages.length, 2);
      for (final stage in stages) {
        expect(stage.sourceInventory, 'unlimited');
        expect(stage.sourceStartMoles, isNull);
        expect(stage.sourceEndMoles, isNull);
        expect(stage.sourceVolumeL, isNull);
        expect(stage.sourceOxygenPercent, 21);
        expect(stage.sourceHeliumPercent, 0);
        expect(stage.thermal!.rateSource, 'compressor');
        expect(stage.sourceStartPressureBar, 350);
        expect(stage.sourceEndPressureBar, 350);
      }
    });
  });

  group('thermal safety helpers', () {
    test('thermal safety allows transient hot overfill but keeps settled pressure at working pressure', () {
      final cylinder = <String, Object?>{
        'volumeL': 12.0,
        'initialPressureBar': 0.0,
        'targetPressureBar': 100.0,
        'targetOxygenPercent': 21.0,
        'targetHeliumPercent': 0.0,
        'workingPressureBar': 100.0,
        'hotOverfillPercent': 2.0,
      };
      final thermal = const ThermalInput(
        ambientTemperatureC: 20,
        targetInWaterTemperatureC: 10,
      );
      const physics = PhysicsInput(model: 'ideal', temperatureC: 20);
      final state = _thermalState(
        pressureStartBar: 0,
        temperatureStartC: 20,
        pressureAtTransferEndReferenceBar: 100,
        pressureAtTransferEndAmbientBar: 100,
        pressureAtTransferEndBar: 101.5,
        pressureAtTransferEndHotBar: 101.5,
        temperatureAtTransferEndC: 40,
        pressureAfterWaitBar: 100,
        temperatureAfterWaitC: 20,
        pressureReferenceTemperatureC: 20,
        samples: <ThermalSample>[
          _sample(
            temperatureC: 40,
            ambientPressureBar: 100,
            projectedPressureBar: 101.5,
          ),
          _sample(
            temperatureC: 20,
            ambientPressureBar: 100,
            projectedPressureBar: 100,
          ),
        ],
      );
      final simulation = _simulation(<ProtocolStep>[
        ProtocolStep(thermal: state),
      ]);

      expect(
        isSafeSimulation(
          simulation,
          100,
          thermal: thermal,
          physics: physics,
          cylinder: cylinder,
        ),
        isTrue,
      );
      final hot102 = _simulation(<ProtocolStep>[
        ProtocolStep(
          thermal: _thermalState(
            pressureStartBar: 0,
            temperatureStartC: 20,
            pressureAtTransferEndReferenceBar: 100,
            pressureAtTransferEndAmbientBar: 100,
            pressureAtTransferEndBar: 102,
            pressureAtTransferEndHotBar: 102,
            temperatureAtTransferEndC: 40,
            pressureAfterWaitBar: 100,
            temperatureAfterWaitC: 20,
            pressureReferenceTemperatureC: 20,
            samples: <ThermalSample>[
              _sample(
                temperatureC: 40,
                ambientPressureBar: 100,
                projectedPressureBar: 102,
              ),
            ],
          ),
        ),
      ]);
      expect(
        isSafeSimulation(
          hot102,
          100,
          thermal: thermal,
          physics: physics,
          cylinder: cylinder,
        ),
        isTrue,
      );
      final hot1021 = _simulation(<ProtocolStep>[
        ProtocolStep(
          thermal: _thermalState(
            pressureStartBar: 0,
            temperatureStartC: 20,
            pressureAtTransferEndReferenceBar: 100,
            pressureAtTransferEndAmbientBar: 100,
            pressureAtTransferEndBar: 102.1,
            pressureAtTransferEndHotBar: 102.1,
            temperatureAtTransferEndC: 40,
            pressureAfterWaitBar: 100,
            temperatureAfterWaitC: 20,
            pressureReferenceTemperatureC: 20,
            samples: <ThermalSample>[
              _sample(
                temperatureC: 40,
                ambientPressureBar: 100,
                projectedPressureBar: 102.1,
              ),
            ],
          ),
        ),
      ]);
      expect(
        isSafeSimulation(
          hot1021,
          100,
          thermal: thermal,
          physics: physics,
          cylinder: cylinder,
        ),
        isFalse,
      );
      final ambientHigh = _simulation(<ProtocolStep>[
        ProtocolStep(
          thermal: _thermalState(
            pressureStartBar: 0,
            temperatureStartC: 20,
            pressureAtTransferEndReferenceBar: 100,
            pressureAtTransferEndAmbientBar: 100.1,
            pressureAtTransferEndBar: 101.5,
            pressureAtTransferEndHotBar: 101.5,
            temperatureAtTransferEndC: 40,
            pressureAfterWaitBar: 100,
            temperatureAfterWaitC: 20,
            pressureReferenceTemperatureC: 20,
            samples: <ThermalSample>[
              _sample(
                temperatureC: 40,
                ambientPressureBar: 100,
                projectedPressureBar: 101.5,
              ),
            ],
          ),
        ),
      ]);
      expect(
        isSafeSimulation(
          ambientHigh,
          100,
          thermal: thermal,
          physics: physics,
          cylinder: cylinder,
        ),
        isFalse,
      );
      expect(
        isSafeSimulation(
          simulation,
          100,
          thermal: thermal,
          physics: physics,
          cylinder: <String, Object?>{...cylinder, 'hotOverfillPercent': 0.0},
        ),
        isFalse,
      );
    });

    test('Hard stop retains hot overfill for measured warm interim starts', () {
      final cylinder = <String, Object?>{
        'volumeL': 12.0,
        'initialPressureBar': 0.0,
        'workingPressureBar': 100.0,
        'hotOverfillPercent': 5.0,
      };
      final state = _thermalState(
        pressureStartBar: 101.5,
        temperatureStartC: 30,
        measurementApplied: true,
        measuredStartPressureBar: 101.5,
        measuredStartTemperatureC: 30,
        pressureAtTransferEndAmbientBar: 100,
        pressureAtTransferEndHotBar: 101.5,
        temperatureAtTransferEndC: 40,
        pressureAfterWaitBar: 100,
        temperatureAfterWaitC: 20,
      );
      expect(
        isSafeSimulation(
          _simulation(<ProtocolStep>[ProtocolStep(thermal: state)]),
          100,
          thermal: const ThermalInput(
            ambientTemperatureC: 20,
            waitMode: 'temperature',
            targetMediumTemperatureC: 30,
          ),
          physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
          cylinder: cylinder,
        ),
        isTrue,
      );
    });

    test('Hard stop applies working pressure at an above-ambient target-temperature wait', () {
      final cylinder = <String, Object?>{
        'volumeL': 12.0,
        'initialPressureBar': 0.0,
        'workingPressureBar': 100.0,
        'hotOverfillPercent': 5.0,
      };
      final state = _thermalState(
        pressureStartBar: 0,
        temperatureStartC: 20,
        pressureAtTransferEndAmbientBar: 100,
        pressureAtTransferEndHotBar: 101.5,
        temperatureAtTransferEndC: 40,
        pressureAfterWaitBar: 101.5,
        temperatureAfterWaitC: 30,
        durationMinutes: 1,
        waitMinutes: 1,
        samples: <ThermalSample>[
          _sample(
            elapsedMinutes: 2,
            temperatureC: 30,
            ambientPressureBar: 100,
            projectedPressureBar: 101.5,
          ),
        ],
      );
      expect(
        isSafeSimulation(
          _simulation(<ProtocolStep>[ProtocolStep(thermal: state)]),
          100,
          thermal: const ThermalInput(
            ambientTemperatureC: 20,
            waitMode: 'temperature',
            targetMediumTemperatureC: 30,
            targetTemperatureC: 30,
          ),
          physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
          cylinder: cylinder,
        ),
        isFalse,
      );
    });

    test('hot overfill preserves the requested ambient and target pressure at safe endpoints', () {
      const workingPressureBar = 99.01;
      final result = optimizeBlend(<String, Object?>{
        'cylinder': _cylinder(
          volumeL: 12,
          initialPressureBar: 95,
          initialOxygenPercent: 0,
          initialHeliumPercent: 0,
          targetPressureBar: 99,
          targetOxygenPercent: 4,
          targetHeliumPercent: 0.2,
          workingPressureBar: workingPressureBar,
          hotOverfillPercent: 2,
        ),
        'physics': _idealPhysics20Map(),
        'thermal': <String, Object?>{
          'tankMaterial': 'steel',
          'coolingMedium': 'air',
          'ambientTemperatureC': 20.0,
          'inletTemperatureC': 40.0,
          'targetMediumTemperatureC': 20.0,
          'targetInWaterTemperatureC': 20.0,
          'waitMode': 'minutes',
          'waitMinutes': 0.0,
        },
        'settings': <String, Object?>{
          'booster': <String, Object?>{
            'otherBoostBpm': 50.0,
            'oxygenBoostBpm': 50.0,
            'otherDecantRateBarPerMin': 5.0,
            'oxygenDecantRateBarPerMin': 5.0,
            'cylinderVolumeCm3': 9.0,
            'minimumSourcePressureBar': 0.0,
          },
        },
        'banks': <Object?>[
          _bank(
            id: 'o2',
            name: 'Oxygen',
            volumeL: 12,
            pressureBar: 300,
            maxPressureBar: 350,
            minimumPressureBar: 0,
            oxygenPercent: 100,
            heliumPercent: 0,
          ),
          _bank(
            id: 'he',
            name: 'Helium',
            volumeL: 12,
            pressureBar: 300,
            maxPressureBar: 350,
            minimumPressureBar: 0,
            oxygenPercent: 0,
            heliumPercent: 100,
          ),
        ],
      });
      expect(result['feasible'], isTrue, reason: result['error'] as String?);
      final thermal = _m(result['thermal']);
      expect(_d(thermal['finalAmbientPressureBar']), closeTo(99, 1e-5));
      expect(
        _d(thermal['finalAmbientPressureBar']),
        lessThanOrEqualTo(workingPressureBar),
      );
      expect(
        _d(thermal['finalInWaterPressureBar']),
        lessThanOrEqualTo(workingPressureBar),
      );
      final hotPressures = <double>[
        for (final step in _steps(result['protocolSteps']))
          if ((step.thermal?.temperatureAtTransferEndC ?? 0) > 20)
            step.thermal!.pressureAtTransferEndHotBar,
      ];
      expect(
        hotPressures.any((pressure) => pressure > workingPressureBar),
        isTrue,
      );
      expect(
        hotPressures.every((pressure) => pressure <= workingPressureBar * 1.02),
        isTrue,
      );
    });

    test('rejects invalid explicit hot-overfill values in safety helpers', () {
      final cylinder = <String, Object?>{
        'volumeL': 12.0,
        'initialPressureBar': 0.0,
        'workingPressureBar': 100.0,
        'hotOverfillPercent': 2.25,
      };
      final matchesHotOverfill = throwsA(
        predicate(
          (Object error) => RegExp(
            'hot overfill',
            caseSensitive: false,
          ).hasMatch(error.toString()),
        ),
      );
      expect(
        () => isSafeSimulation(
          _simulation(<ProtocolStep>[]),
          100,
          cylinder: cylinder,
        ),
        matchesHotOverfill,
      );
      expect(
        () => scheduleSafeThermalProtocol(
          protocolSteps: <ProtocolStep>[],
          cylinder: cylinder,
          physics: _idealPhysics20,
          thermal: const ThermalInput(ambientTemperatureC: 20),
          settings: null,
        ),
        matchesHotOverfill,
      );
    });
  });

  group('cost contract', () {
    test('optimizer steps carry cost contract fields', () {
      final result = optimizeBlend(defaultRecipeInput);
      final transfers = _steps(result['protocolSteps'])
          .where((step) => step.type == 'boost' || step.type == 'decant')
          .toList();
      expect(transfers, isNotEmpty);
      for (final step in transfers) {
        expect(step.sourceConsumedMoles, isNotNull);
        expect(step.sourceConsumedMoles!.isFinite, isTrue);
        expect(step.sourceConsumedMoles!, greaterThan(0));
        expect(step.costOperationId, matches(RegExp(r'^op-\d+$')));
        expect(
          <String?>['boost', 'decant', 'topUp'].contains(step.costOperation),
          isTrue,
        );
        expect(
          step.costOperation == 'topUp',
          step.sourceBankId == 'compressor-air',
        );
      }
    });

    test('a thermally split transfer shares one operation id and its moles sum to the whole', () {
      final result = optimizeBlend(schedulerSplitInput);
      final stages = _steps(result['protocolSteps'])
          .where((step) => step.thermalSplit == true)
          .toList();
      expect(stages.length, 4);
      expect(stages[0].costOperationId, stages[1].costOperationId);
      expect(stages[2].costOperationId, stages[3].costOperationId);
      expect(stages[0].costOperationId, isNot(stages[2].costOperationId));
      expect(
        stages.every((step) => (step.sourceConsumedMoles ?? 0) > 0),
        isTrue,
      );
    });

    test('operation ids are unique per operation', () {
      final ids = <String>[
        for (final step in _steps(
          optimizeBlend(defaultRecipeInput)['protocolSteps'],
        ))
          if (step.costOperationId != null &&
              !RegExp('safe stage').hasMatch(step.title ?? ''))
            step.costOperationId!,
      ];
      expect(ids, isNotEmpty);
      expect(ids.toSet().length, ids.length);
    });

    test('scheduler-split stages sum to the logical protocol step moles per cost operation', () {
      final result = optimizeBlend(schedulerSplitInput);
      expect(result['feasible'], isTrue, reason: result['error'] as String?);
      final splitStages = _steps(result['protocolSteps'])
          .where((step) => step.thermalSplit == true)
          .toList();
      expect(splitStages, isNotEmpty);
      final ids = splitStages.map((step) => step.costOperationId).toSet();
      final logicalSteps = _steps(_m(result['logicalPlan'])['protocolSteps']);
      for (final id in ids) {
        final summed = splitStages
            .where((step) => step.costOperationId == id)
            .fold<double>(
              0,
              (total, step) => total + step.sourceConsumedMoles!,
            );
        final logicalMatches = logicalSteps
            .where((step) => step.costOperationId == id)
            .toList();
        expect(logicalMatches.length, 1, reason: 'one logical step for $id');
        final logical = logicalMatches.first;
        expect(logical, isNotNull, reason: 'logical step for $id');
        final logicalMoles = logical.sourceConsumedMoles!;
        expect(
          (summed - logicalMoles).abs(),
          lessThanOrEqualTo(
            1e-9 * (logicalMoles.abs() > 1 ? logicalMoles.abs() : 1),
          ),
          reason: '$id',
        );
      }
    });
  });

  group('salvage', () {
    test('salvage moves drained gas into an attractive leftover bank before the vent drain', () {
      final input = _drainSalvageInput(<Object?>[
        _leftoverBank(
          id: 'bank-n',
          oxygenPercent: 32,
          heliumPercent: 0,
          pressureBar: 20,
        ),
      ]);
      final baseline = optimizeBlend(_drainSalvageInput(<Object?>[]));
      final result = optimizeBlend(input);

      expect(result['feasible'], isTrue);
      final steps = _steps(result['protocolSteps']);
      final salvageIndex = steps.indexWhere((step) => step.type == 'salvage');
      final drainIndex = steps.indexWhere((step) => step.type == 'drain');
      expect(
        salvageIndex,
        greaterThanOrEqualTo(0),
        reason: 'expected a salvage step',
      );
      expect(
        drainIndex < 0 || salvageIndex < drainIndex,
        isTrue,
        reason: 'salvage must precede the vent drain',
      );
      expect(
        _d(_m(result['blend'])['heliumVentedLitres']),
        lessThan(_d(_m(baseline['blend'])['heliumVentedLitres'])),
      );
    });

    test('partial salvage is followed by the vent drain down to the retained pressure', () {
      // The receiver's 30 bar ceiling caps the salvage below the surplus, so the tank is still
      // above its retained pressure after the salvage steps and the drain follows them.
      final input = _drainSalvageInput(<Object?>[
        _leftoverBank(
          id: 'bank-n',
          oxygenPercent: 32,
          heliumPercent: 0,
          pressureBar: 20,
          maxPressureBar: 30,
        ),
      ]);
      final result = optimizeBlend(input);

      expect(result['feasible'], isTrue);
      final steps = _steps(result['protocolSteps']);
      final types = steps.map((step) => step.type).toList();
      final salvageIndex = types.lastIndexOf('salvage');
      final drainIndex = types.indexOf('drain');
      expect(
        salvageIndex,
        greaterThanOrEqualTo(0),
        reason: 'expected a salvage step',
      );
      expect(
        drainIndex,
        salvageIndex + 1,
        reason: 'the drain follows the salvage steps',
      );
      expect(
        types.contains('keep'),
        isFalse,
        reason: 'no keep when the drain runs',
      );
      final salvagePressure = steps[salvageIndex].resultingPressureBar!;
      final drainPressure = steps[drainIndex].resultingPressureBar!;
      expect(salvagePressure, greaterThan(drainPressure + 1));
      expect((drainPressure - 100).abs(), lessThan(0.01));
      expect(
        steps[salvageIndex].title,
        matches(
          RegExp(r'^Salvage: (decant|boost) into .+ to [0-9]+\.[0-9] bar$'),
        ),
      );
    });

    test('salvage never fills a receiver already at its maximum pressure', () {
      final input = _drainSalvageInput(<Object?>[
        _leftoverBank(
          id: 'bank-full',
          oxygenPercent: 32,
          heliumPercent: 0,
          pressureBar: 200,
          maxPressureBar: 200,
        ),
      ]);
      final result = optimizeBlend(input);

      expect(result['feasible'], isTrue);
      expect(
        _steps(result['protocolSteps']).any((step) => step.type == 'salvage'),
        isFalse,
      );
    });

    test(
      'salvage with no eligible receivers matches the vent-only result exactly',
      () {
        final input = _drainSalvageInput(<Object?>[
          _leftoverBank(
            id: 'bank-off',
            oxygenPercent: 32,
            heliumPercent: 0,
            pressureBar: 20,
            enabled: false,
          ),
        ]);
        final result = optimizeBlend(input);

        expect(
          _canon(result),
          equals(
            _canon(
              optimizeBlend(<String, Object?>{...input, '_salvage': false}),
            ),
          ),
        );
        expect(
          _steps(result['protocolSteps']).any((step) => step.type == 'salvage'),
          isFalse,
        );
      },
    );

    test(
      'salvage can be disabled by the internal flag and falls back to the vent',
      () {
        final input = _drainSalvageInput(<Object?>[
          _leftoverBank(
            id: 'bank-n',
            oxygenPercent: 32,
            heliumPercent: 0,
            pressureBar: 20,
          ),
        ]);
        final disabled = optimizeBlend(<String, Object?>{
          ...input,
          '_salvage': false,
        });
        final ventOnly = optimizeBlend(_drainSalvageInput(<Object?>[]));

        expect(
          _steps(disabled['protocolSteps'])
              .any((step) => step.type == 'salvage'),
          isFalse,
        );
        expect(
          _d(_m(disabled['blend'])['heliumVentedLitres']),
          _d(_m(ventOnly['blend'])['heliumVentedLitres']),
        );
      },
    );

    test(
      'default preservation case keeps the cylinder gas without salvage',
      () {
        final result = optimizeBlend(defaultOptimizerInput());

        expect(result['feasible'], isTrue);
        expect(_steps(result['protocolSteps']).first.type, 'keep');
        expect(
          _steps(result['protocolSteps']).any((step) => step.type == 'salvage'),
          isFalse,
        );
      },
    );

    test('default input matches the salvage-off result apart from salvage-only fields', () {
      final withSalvage = optimizeBlend(defaultOptimizerInput());
      final withoutSalvage = optimizeBlend(<String, Object?>{
        ...defaultOptimizerInput(),
        '_salvage': false,
      });
      final rest = Map<String, Object?>.of(withSalvage)
        ..remove('salvageTransfers')
        ..remove('salvageBanks');

      expect(_canon(rest), equals(_canon(withoutSalvage)));
      expect(withSalvage.containsKey('lpCost'), isFalse);
      expect(withoutSalvage.containsKey('lpCost'), isFalse);
    });

    test('salvage declines a receiver whose transfer would lose the target and vents instead', () {
      final baseline = optimizeBlend(_drainSalvageInput(<Object?>[]));
      final input = _drainSalvageInput(<Object?>[
        _leftoverBank(
          id: 'bank-rich',
          oxygenPercent: 12,
          heliumPercent: 65,
          pressureBar: 150,
        ),
      ]);
      final result = optimizeBlend(input);

      expect(result['feasible'], isTrue);
      expect(
        _steps(result['protocolSteps']).any((step) => step.type == 'salvage'),
        isFalse,
      );
      expect(
        (_d(_m(result['blend'])['heliumVentedLitres']) -
                _d(_m(baseline['blend'])['heliumVentedLitres']))
            .abs(),
        lessThan(1e-9),
      );
    });

    test('thermal fallback returns the feasible vent baseline when the salvage winner is thermally infeasible', () {
      final input = <String, Object?>{
        ..._drainSalvageInput(<Object?>[
          _leftoverBank(
            id: 'bank-src',
            oxygenPercent: 21,
            heliumPercent: 35,
            pressureBar: 40,
          ),
        ]),
        'thermal': <String, Object?>{
          'tankMaterial': 'steel',
          'coolingMedium': 'air',
          'ambientTemperatureC': 20.0,
          'inletTemperatureC': 20.0,
          'targetMediumTemperatureC': 20.0,
          'targetInWaterTemperatureC': 20.0,
          'waitMode': 'minutes',
          'waitMinutes': 0.0,
        },
      };
      Map<String, Object?> withoutThermal(Map<String, Object?> candidate) {
        final copy = Map<String, Object?>.of(candidate)..remove('thermal');
        return copy;
      }

      Map<String, Object?> staticSolve(Map<String, Object?> candidate) =>
          candidate['_salvage'] == false
          ? optimizeBlend(withoutThermal(candidate))
          : <String, Object?>{
              'feasible': false,
              'error': 'injected: salvage winner has no feasible thermal plan',
            };

      expect(
        _steps(optimizeBlend(withoutThermal(input))['protocolSteps'])
            .any((step) => step.type == 'salvage'),
        isTrue,
        reason: 'scenario must have a salvage winner in the static search',
      );
      final result = solveThermalWithSalvageFallback(input, staticSolve);
      final expected = optimizeBlend(<String, Object?>{
        ...input,
        '_salvage': false,
      });

      expect(result['feasible'], isTrue);
      expect(
        _steps(result['protocolSteps']).any((step) => step.type == 'salvage'),
        isFalse,
      );
      expect(
        _canon(result['protocolSteps']),
        equals(_canon(expected['protocolSteps'])),
      );
      expect(_canon(result['blend']), equals(_canon(expected['blend'])));
    });

    test(
      'salvage keeps the receiver end state consistent with the salvaged bank',
      () {
        final input = _drainSalvageInput(<Object?>[
          _leftoverBank(
            id: 'bank-src',
            oxygenPercent: 21,
            heliumPercent: 35,
            pressureBar: 40,
          ),
        ]);
        final result = optimizeBlend(input);

        final salvageSteps = _steps(result['protocolSteps'])
            .where((step) => step.type == 'salvage')
            .toList();
        expect(salvageSteps, isNotEmpty, reason: 'expected a salvage step');
        expect(_maps(result['salvageTransfers']).length, salvageSteps.length);
        final last = salvageSteps.last;
        final receiver = (result['salvageBanks']! as List<Object?>)
            .cast<Bank>()
            .firstWhere((bank) => bank.id == last.receiverBankId);
        expect(
          (receiver.pressureBar - last.receiverEndPressureBar!).abs(),
          lessThan(1e-9),
        );
        expect(receiver.oxygenPercent, last.receiverEndMix!.oxygenPercent);
        expect(receiver.heliumPercent, last.receiverEndMix!.heliumPercent);
      },
    );

    test('thermal salvage step cools the tank while its pressure falls', () {
      final input = <String, Object?>{
        ..._drainSalvageInput(<Object?>[
          _leftoverBank(
            id: 'bank-n',
            oxygenPercent: 32,
            heliumPercent: 0,
            pressureBar: 20,
          ),
        ]),
        'thermal': <String, Object?>{
          'tankMaterial': 'steel',
          'coolingMedium': 'air',
          'ambientTemperatureC': 20.0,
          'inletTemperatureC': 40.0,
          'targetMediumTemperatureC': 20.0,
          'targetInWaterTemperatureC': 20.0,
          'waitMode': 'minutes',
          'waitMinutes': 0.0,
        },
        'settings': <String, Object?>{
          'booster': <String, Object?>{'compressorInletFlowLPerMin': 100.0},
        },
      };
      final result = optimizeBlend(input);

      expect(result['feasible'], isTrue);
      final salvage = _steps(result['protocolSteps'])
          .firstWhere((step) => step.type == 'salvage');
      expect(
        salvage.thermal,
        isNotNull,
        reason: 'expected a thermal salvage step',
      );
      expect(
        salvage.thermal!.temperatureAtTransferEndC,
        lessThan(salvage.thermal!.temperatureStartC),
      );
      expect(
        salvage.resultingPressureBar!,
        lessThan(_d(_m(input['cylinder'])['initialPressureBar'])),
      );
    });

    test('thermal trajectory maps bank points to recipe decants, never to salvage steps', () {
      final result = optimizeBlend(
        _salvageThenDecantInput(thermal: _salvageThermal),
      );
      final decantPressures = <double>[
        for (final step in _steps(result['protocolSteps']))
          if (step.type == 'decant') step.resultingPressureBar!,
      ];
      final bankPoints = _maps(result['trajectory'])
          .where((point) => point['bankId'] != null)
          .toList();
      expect(decantPressures.length, bankPoints.length);
      for (var i = 0; i < bankPoints.length; i++) {
        expect(
          _d(bankPoints[i]['pressureBar']),
          closeTo(decantPressures[i], 1e-6),
        );
      }
    });

    test(
      'salvage that takes the whole surplus emits no drain and no keep step',
      () {
        for (final thermal in <Map<String, Object?>?>[null, _salvageThermal]) {
          final result = optimizeBlend(
            _salvageThenDecantInput(thermal: thermal),
          );
          expect(result['feasible'], isTrue);
          expect(
            _d(_m(result['blend'])['ventedGasLitres']).abs(),
            lessThan(1e-6),
          );
          final types = _steps(result['protocolSteps'])
              .map((step) => step.type)
              .toList();
          expect(types.first, 'salvage');
          expect(types.contains('drain'), isFalse);
          expect(types.contains('keep'), isFalse);
        }
      },
    );

    test('thermal salvage search runs once per optimize, not once per thermal candidate', () {
      final input = _salvageThenDecantInput(thermal: _salvageThermal);
      final calls = <Map<String, Object?>>[];
      final result = solveThermalWithSalvageFallback(
        input,
        optimizeBlendWithoutThermal,
        searchSalvage: (candidate) {
          calls.add(candidate);
          return searchSalvageVariant(candidate);
        },
      );

      expect(result['feasible'], isTrue);
      expect(_maps(result['salvageTransfers']).length, 1);
      expect(calls.length, 1);
    });

    test('salvage that keeps the cylinder retained gas unchanged is accepted and moves the whole surplus', () {
      final input = _salvageThenDecantInput();
      final baseline = optimizeBlend(<String, Object?>{
        ...input,
        '_salvage': false,
      });
      final result = optimizeBlend(input);

      expect(result['feasible'], isTrue);
      final transfers = _maps(result['salvageTransfers']);
      expect(transfers.length, 1);
      expect(transfers.first['receiverBankId'], 'bank-n');
      expect(
        _d(transfers.first['movedMoles']),
        closeTo(_d(_m(baseline['blend'])['ventedMoles']), 1e-6),
      );
      final xCyl = _d(_m(result['solution'])['x_cyl']);
      final xCylBaseline = _d(_m(baseline['solution'])['x_cyl']);
      expect(
        (xCyl - xCylBaseline).abs(),
        lessThanOrEqualTo(
          1e-9 * (xCylBaseline.abs() > 1 ? xCylBaseline.abs() : 1),
        ),
      );
    });

    test('salvage search ignores invalid input and reports the usual invalid result', () {
      final input = drainSalvageInputWithoutPhysics();
      expect(searchSalvageVariant(input), isNull);
      final withThermal = <String, Object?>{
        ...input,
        'thermal': <String, Object?>{
          'tankMaterial': 'steel',
          'coolingMedium': 'air',
          'ambientTemperatureC': 20.0,
          'inletTemperatureC': 20.0,
          'targetMediumTemperatureC': 25.0,
          'targetInWaterTemperatureC': 20.0,
          'waitMode': 'minutes',
          'waitMinutes': 10.0,
          'targetTemperatureC': 25.0,
        },
      };
      expect(searchSalvageVariant(withThermal), isNull);
      final result = optimizeBlend(withThermal);
      expect(result['feasible'], isFalse);
      expect(result['blend'], isNull);
      expect(
        result['error'] as String,
        matches(RegExp(r'^Invalid blend input:')),
      );
    });

    test('a salvage plan costs only its purchased transfers: salvage adds no gas line, no fee and no operation id', () {
      final input = _salvageThenDecantInput(thermal: _salvageThermal);
      final result = optimizeBlend(input);

      expect(result['feasible'], isTrue);
      final salvageSteps = _steps(result['protocolSteps'])
          .where((step) => step.type == 'salvage')
          .toList();
      expect(salvageSteps.length, 1);
      for (final step in salvageSteps) {
        expect(step.costOperation, isNull);
        expect(step.costOperationId, isNull);
      }
      final costs = const Costs(
        currencySymbol: '',
        leftoverDiscountPercent: 0,
        operationPrices: OperationPrices(boost: 2, decant: 1, topUp: 5),
      );
      final banks = _maps(input['banks']).map(_bankFromMap).toList();
      final withSalvage = computeFillCost(
        steps: _fillSteps(_steps(result['protocolSteps'])),
        banks: banks,
        costs: costs,
        temperatureC: 20,
      );
      final withoutSalvage = computeFillCost(
        steps: _fillSteps(
          _steps(result['protocolSteps'])
              .where((step) => step.type != 'salvage')
              .toList(),
        ),
        banks: banks,
        costs: costs,
        temperatureC: 20,
      );
      expect(_canon(withSalvage), equals(_canon(withoutSalvage)));
      expect(withSalvage.total, greaterThan(0));
      expect(
        withSalvage.gasLines.any((line) => line.sourceBankId == 'bank-n'),
        isFalse,
      );
    });

    test('salvage near tie goes to the receiver that can still reach more standard mixes', () {
      final result = optimizeBlend(_shallowDeepInput);
      expect(result['feasible'], isTrue);
      expect(_salvageReceivers(result).toSet(), <String>{'deep'});
      final last = _maps(result['salvageTransfers']).last;
      final mix = _m(last['receiverEndMix']);
      expect(_d(mix['oxygenPercent']), closeTo(9.1, 0.2));
      expect(_d(mix['heliumPercent']), closeTo(66.3, 0.2));
    });

    test('salvage near-tie preference also holds in the thermal path', () {
      final result = optimizeBlend(<String, Object?>{
        ..._shallowDeepInput,
        'thermal': <String, Object?>{
          'tankMaterial': 'aluminum',
          'coolingMedium': 'air',
          'ambientTemperatureC': 21.0,
          'inletTemperatureC': 25.0,
          'targetMediumTemperatureC': 21.0,
          'targetInWaterTemperatureC': 21.0,
          'waitMode': 'minutes',
          'waitMinutes': 0.0,
          'interimMeasurements': <Object?>[],
        },
      });
      expect(result['feasible'], isTrue);
      expect(_salvageReceivers(result).toSet(), <String>{'deep'});
    });

    test('a receiver that fails alone as first-ranked cannot hide another receiver that passes alone', () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': _cylinder(
          volumeL: 11.1,
          initialPressureBar: 42.7,
          initialOxygenPercent: 24.4,
          initialHeliumPercent: 65.1,
          targetPressureBar: 156.2,
          targetOxygenPercent: 21.2,
          targetHeliumPercent: 15.7,
          workingPressureBar: 207,
          hotOverfillPercent: 2,
        ),
        'physics': <String, Object?>{'model': 'vdw', 'temperatureC': 21.0},
        'settings': _settingsMap(DEFAULT_SETTINGS),
        'banks': <Object?>[
          _bank(
            id: 'he',
            name: 'Helium',
            volumeL: 40,
            pressureBar: 150,
            maxPressureBar: 200,
            oxygenPercent: 0,
            heliumPercent: 100,
          ),
          _bank(
            id: 'o2',
            name: 'Oxygen',
            volumeL: 50,
            pressureBar: 200,
            maxPressureBar: 200,
            oxygenPercent: 100,
            heliumPercent: 0,
          ),
          _bank(
            id: 'shallow',
            name: 'shallow',
            volumeL: 25.5,
            pressureBar: 203.5,
            maxPressureBar: 222.9,
            oxygenPercent: 9.7,
            heliumPercent: 41.9,
          ),
          _bank(
            id: 'deep',
            name: 'deep',
            volumeL: 24.5,
            pressureBar: 149.7,
            maxPressureBar: 239.4,
            oxygenPercent: 14.1,
            heliumPercent: 69.3,
          ),
        ],
      });
      expect(result['feasible'], isTrue);
      expect(_salvageReceivers(result).toSet(), <String>{'deep'});
    });
  });
}

/// JS `drainSalvageInput([...])` variant without `physics` (the JS `physics: undefined` case).
Map<String, Object?> drainSalvageInputWithoutPhysics() {
  final base = _drainSalvageInput(<Object?>[
    _leftoverBank(
      id: 'bank-n',
      oxygenPercent: 32,
      heliumPercent: 0,
      pressureBar: 20,
    ),
  ]);
  return Map<String, Object?>.of(base)..remove('physics');
}

Map<String, Object?> _idealPhysics20Map() => _idealPhysics();

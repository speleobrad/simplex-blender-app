import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/data/bank_storage.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/optimizer.dart';
import 'package:simplex_blender/src/domain/plan_with_readings.dart';
import 'package:simplex_blender/src/domain/savings.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

import 'optimizer_fixtures.dart';

// Default page recipe: 45 bar Air at 21 °C to 195 bar 18/45 with the default banks.
Map<String, Object?> _baseInput() {
  final input = defaultOptimizerInput();
  input['cylinder'] = <String, Object?>{
    'volumeL': 11.1,
    'initialPressureBar': 45.0,
    'targetPressureBar': 195.0,
    'initialOxygenPercent': 21.0,
    'initialHeliumPercent': 0.0,
    'targetOxygenPercent': 18.0,
    'targetHeliumPercent': 45.0,
    'workingPressureBar': 207.0,
    'hotOverfillPercent': 2.0,
  };
  input['physics'] = <String, Object?>{'model': 'vdw', 'temperatureC': 21.0};
  input['banks'] = <Object?>[
    for (final bank in DEFAULT_BANKS) bankToRecord(bank),
  ];
  input['thermal'] = <String, Object?>{
    'tankMaterial': 'aluminum',
    'coolingMedium': 'air',
    'ambientTemperatureC': 21.0,
    'inletTemperatureC': 25.0,
    'targetMediumTemperatureC': 21.0,
    'targetInWaterTemperatureC': 10.0,
    'waitMode': 'minutes',
    'waitMinutes': 5.0,
    'interimMeasurements': <Object?>[],
  };
  input['settings'] = _settingsMap(DEFAULT_SETTINGS);
  return input;
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

/// Sparse interim-measurement list: index `i` holds `readings[i]`, length = last key + 1.
List<Object?> _sparse(Map<int, Object?> readings) {
  final length = readings.isEmpty ? 0 : readings.keys.reduce(math.max) + 1;
  return List<Object?>.generate(length, (index) => readings[index]);
}

Map<String, Object?> _reading(double pressureBar, double temperatureC) =>
    <String, Object?>{'pressureBar': pressureBar, 'temperatureC': temperatureC};

Map<String, Object?> _withReadings(
  Map<String, Object?> input,
  Map<int, Object?> readings,
) {
  final thermal = input['thermal']! as Map<String, Object?>;
  return <String, Object?>{
    ...input,
    'thermal': <String, Object?>{
      ...thermal,
      'interimMeasurements': _sparse(readings),
    },
  };
}

List<ProtocolStep> _steps(Map<String, Object?> plan) =>
    (plan['protocolSteps']! as List<Object?>).cast<ProtocolStep>();

ProtocolStep _stepAt(Map<String, Object?> plan, int index) =>
    _steps(plan).firstWhere((step) => step.measurementIndex == index);

List<String> _titles(Map<String, Object?> plan) => <String>[
  for (final step in _steps(plan)) '${step.measurementIndex}:${step.title}',
];

List<String> _titlesBefore(Map<String, Object?> plan, int index) => <String>[
  for (final step in _steps(plan))
    if ((step.measurementIndex ?? -1) < index)
      '${step.measurementIndex}:${step.title}',
];

List<Map<String, Object?>> _trajectory(Map<String, Object?> plan) =>
    (plan['trajectory']! as List<Object?>).cast<Map<String, Object?>>();

Map<String, Object?> _blend(Map<String, Object?> plan) =>
    plan['blend']! as Map<String, Object?>;

Map<String, Object?> _thermal(Map<String, Object?> plan) =>
    plan['thermal']! as Map<String, Object?>;

Map<String, Object?> _interim(Map<String, Object?> plan) =>
    plan['interimReadings']! as Map<String, Object?>;

num _n(Object? value) => value! as num;

List<Map<String, Object?>> _recordsOf(Object? banks) => <Map<String, Object?>>[
  for (final bank in banks! as List<Object?>) bankToRecord(bank! as Bank),
];

Map<String, Object?> _plan(Map<String, Object?> input) =>
    planWithReadings(input);

Map<String, Object?> _cloneWithCylinder(
  Map<String, Object?> input,
  Map<String, Object?> cylinder,
) => <String, Object?>{...input, 'cylinder': cylinder};

List<FillStep> _fillSteps(Map<String, Object?> plan) => <FillStep>[
  for (final step in _steps(plan))
    FillStep(
      costOperation: step.costOperation,
      costOperationId: step.costOperationId,
      sourceBankId: step.sourceBankId,
      recipeGas: step.recipeGas,
      sourceConsumedMoles: step.sourceConsumedMoles,
    ),
];

ProtocolStep _scrapStep(Map<String, Object?> base) =>
    _steps(base).firstWhere((step) => step.sourceBankId == 'bank-sample-scrap');

List<ProtocolStep> _costOperationSteps(Map<String, Object?> plan) =>
    _steps(plan).where((step) => step.costOperationId != null).toList();

List<ProtocolStep> _logicalTransfers(Map<String, Object?> plan) =>
    _costOperationSteps(plan)
        .where(
          (step) => !RegExp(
            'safe stage',
            caseSensitive: false,
          ).hasMatch(step.title ?? ''),
        )
        .toList();

void _expectNumbersFollowIndices(Map<String, Object?> plan) {
  var transfers = 0;
  for (final step in _steps(plan)) {
    if (step.sourceBankId == null) {
      continue;
    }
    transfers += 1;
    final match = RegExp(r'^Step (\d+)').firstMatch(step.title ?? '');
    if (match != null) {
      expect(
        int.parse(match.group(1)!),
        transfers,
        reason: '${step.title} is transfer $transfers',
      );
    }
  }
}

void _expectFinite(double? value) {
  expect(value, isNotNull);
  expect(value!.isFinite, isTrue);
}

/// The first reading sits at the scrap boost: 54 bar and 22 °C.
Map<int, Object?> _firstReading(int scrapIndex) => <int, Object?>{
  scrapIndex: _reading(54, 22),
};

Map<String, Object?> _salvageInput() => <String, Object?>{
  'cylinder': <String, Object?>{
    'volumeL': 12.0,
    'initialPressureBar': 150.0,
    'initialOxygenPercent': 32.0,
    'initialHeliumPercent': 0.0,
    'targetPressureBar': 100.0,
    'targetOxygenPercent': 21.0,
    'targetHeliumPercent': 35.0,
  },
  'physics': <String, Object?>{'model': 'vdw', 'temperatureC': 20.0},
  'banks': <Object?>[
    <String, Object?>{
      'id': 'bank-he',
      'name': 'Pure Helium',
      'volumeL': 50.0,
      'pressureBar': 200.0,
      'maxPressureBar': 350.0,
      'minimumPressureBar': 15.0,
      'oxygenPercent': 0.0,
      'heliumPercent': 100.0,
      'enabled': true,
    },
    <String, Object?>{
      'id': 'bank-o2',
      'name': 'Pure Oxygen',
      'volumeL': 40.0,
      'pressureBar': 180.0,
      'maxPressureBar': 350.0,
      'minimumPressureBar': 10.0,
      'oxygenPercent': 100.0,
      'heliumPercent': 0.0,
      'enabled': true,
    },
    <String, Object?>{
      'id': 'bank-n',
      'name': 'Leftover N',
      'volumeL': 50.0,
      'pressureBar': 20.0,
      'maxPressureBar': 200.0,
      'minimumPressureBar': 10.0,
      'oxygenPercent': 32.0,
      'heliumPercent': 0.0,
      'enabled': true,
    },
  ],
  'thermal': <String, Object?>{
    'tankMaterial': 'steel',
    'coolingMedium': 'air',
    'ambientTemperatureC': 20.0,
    'inletTemperatureC': 40.0,
    'targetMediumTemperatureC': 20.0,
    'targetInWaterTemperatureC': 20.0,
    'waitMode': 'minutes',
    'waitMinutes': 0.0,
    'interimMeasurements': <Object?>[],
  },
  'settings': <String, Object?>{
    'booster': <String, Object?>{
      'maxCompressorPressureBar': 350.0,
      'maxBoosterOutputPressureBar': 350.0,
    },
  },
};

Map<String, Object?> _drainInput() => <String, Object?>{
  'cylinder': <String, Object?>{
    'volumeL': 12.0,
    'initialPressureBar': 150.0,
    'initialOxygenPercent': 21.0,
    'initialHeliumPercent': 35.0,
    'targetPressureBar': 200.0,
    'targetOxygenPercent': 15.0,
    'targetHeliumPercent': 55.0,
  },
  'physics': <String, Object?>{'model': 'vdw', 'temperatureC': 20.0},
  'banks': <Object?>[
    <String, Object?>{
      'id': 'bank-he',
      'name': 'Pure Helium',
      'volumeL': 50.0,
      'pressureBar': 200.0,
      'maxPressureBar': 350.0,
      'minimumPressureBar': 15.0,
      'oxygenPercent': 0.0,
      'heliumPercent': 100.0,
      'enabled': true,
    },
    <String, Object?>{
      'id': 'bank-o2',
      'name': 'Pure Oxygen',
      'volumeL': 40.0,
      'pressureBar': 180.0,
      'maxPressureBar': 350.0,
      'minimumPressureBar': 10.0,
      'oxygenPercent': 100.0,
      'heliumPercent': 0.0,
      'enabled': true,
    },
    <String, Object?>{
      'id': 'bank-n',
      'name': 'Leftover N',
      'volumeL': 10.0,
      'pressureBar': 20.0,
      'maxPressureBar': 30.0,
      'minimumPressureBar': 10.0,
      'oxygenPercent': 32.0,
      'heliumPercent': 0.0,
      'enabled': true,
    },
  ],
  'thermal': <String, Object?>{
    'tankMaterial': 'steel',
    'coolingMedium': 'air',
    'ambientTemperatureC': 20.0,
    'inletTemperatureC': 40.0,
    'targetMediumTemperatureC': 20.0,
    'targetInWaterTemperatureC': 20.0,
    'waitMode': 'minutes',
    'waitMinutes': 0.0,
    'interimMeasurements': <Object?>[],
  },
  'settings': <String, Object?>{
    'booster': <String, Object?>{
      'maxCompressorPressureBar': 350.0,
      'maxBoosterOutputPressureBar': 350.0,
    },
  },
};

void main() {
  final input = _baseInput();
  final base = optimizeBlend(input);
  final scrapIndex = _scrapStep(base).measurementIndex!;
  final plannedScrapStart = _stepAt(base, scrapIndex).thermal!;

  test('a plan without readings is the optimizer plan', () {
    expect(_titles(_plan(input)), equals(_titles(base)));
  });

  test('a reading at the planned state reproduces the original recipe, thermal states and blend summary', () {
    final plan = _plan(
      _withReadings(input, <int, Object?>{
        scrapIndex: _reading(
          plannedScrapStart.plannedStartPressureBar!,
          plannedScrapStart.plannedStartTemperatureC!,
        ),
      }),
    );
    expect(_interim(plan)['error'], isNull);
    expect(_titles(plan), equals(_titles(base)));

    final baseSteps = _steps(base);
    final planSteps = _steps(plan);
    expect(planSteps.length, baseSteps.length);
    for (var position = 0; position < baseSteps.length; position++) {
      final expected = baseSteps[position].thermal!;
      final actual = planSteps[position].thermal!;
      expect(actual.pressureStartBar, closeTo(expected.pressureStartBar, 1e-6));
      expect(
        actual.temperatureStartC,
        closeTo(expected.temperatureStartC, 1e-6),
      );
      expect(
        actual.pressureAtTransferEndBar,
        closeTo(expected.pressureAtTransferEndBar, 1e-6),
      );
      expect(
        actual.pressureAfterWaitBar,
        closeTo(expected.pressureAfterWaitBar, 1e-6),
      );
      expect(
        actual.temperatureAfterWaitC,
        closeTo(expected.temperatureAfterWaitC, 1e-6),
      );
    }

    final baseBlend = _blend(base);
    final planBlend = _blend(plan);
    for (final entry in baseBlend.entries) {
      if (entry.value == null) {
        expect(planBlend[entry.key], isNull, reason: entry.key);
      } else {
        expect(
          _n(planBlend[entry.key]),
          closeTo(_n(entry.value), 1e-6),
          reason: entry.key,
        );
      }
    }

    final baseThermal = _thermal(base);
    final planThermal = _thermal(plan);
    for (final key in <String>[
      'finalAmbientPressureBar',
      'finalInWaterPressureBar',
      'finalTransferEndPressureBar',
    ]) {
      expect(
        _n(planThermal[key]),
        closeTo(_n(baseThermal[key]), 1e-6),
        reason: key,
      );
    }
  });

  test('a lower reading re-plans the rest of the recipe to the same target, keeping the planned start visible', () {
    final plan = _plan(_withReadings(input, _firstReading(scrapIndex)));
    expect(plan['feasible'], isTrue);
    expect(_interim(plan)['error'], isNull);
    expect(_steps(plan).length, greaterThan(_steps(base).length));

    final first = _stepAt(plan, scrapIndex).thermal!;
    expect(first.pressureStartBar, equals(54));
    expect(first.temperatureStartC, equals(22));
    expect(
      first.plannedStartPressureBar!,
      closeTo(plannedScrapStart.plannedStartPressureBar!, 1e-6),
    );
    expect(
      first.plannedStartTemperatureC!,
      closeTo(plannedScrapStart.plannedStartTemperatureC!, 1e-6),
    );
    _expectNumbersFollowIndices(plan);

    final blend = _blend(plan);
    expect(_n(blend['finalOxygenPercent']), closeTo(18, 1e-6));
    expect(_n(blend['finalHeliumPercent']), closeTo(45, 1e-6));
    expect(_n(_thermal(plan)['finalInWaterPressureBar']), closeTo(195, 1e-3));
    final trajectoryEnd = _trajectory(plan).last;
    expect(_n(trajectoryEnd['oxygenPercent']), closeTo(18, 0.1));
    expect(_n(trajectoryEnd['heliumPercent']), closeTo(45, 0.1));
  });

  test('a reading above the plan that needs venting is a normal step with exact vent accounting', () {
    final plan = _plan(
      _withReadings(input, <int, Object?>{scrapIndex: _reading(57, 22)}),
    );
    expect(plan['feasible'], isTrue);
    expect(_stepAt(plan, scrapIndex).type, equals('drain'));
    _expectNumbersFollowIndices(plan);
    final blend = _blend(plan);
    expect(_n(blend['ventedMoles']), greaterThan(0));
    expect(_n(blend['retainedPercent']), lessThan(100));
    expect(_n(blend['retainedPercent']), greaterThan(80));
    expect(_n(_thermal(plan)['finalInWaterPressureBar']), closeTo(195, 1e-3));
  });

  test('a reading that implies no gas was added keeps the original recipe and reports why', () {
    final plan = _plan(
      _withReadings(input, <int, Object?>{scrapIndex: _reading(40, 21)}),
    );
    expect(
      _interim(plan)['error'],
      equals(
        'The measured 40 bar at 21 °C implies the tank holds no more gas than before the previous step, so the amount it added cannot be derived. Recheck the reading.',
      ),
    );
    expect(_titles(plan), equals(_titles(base)));
  });

  test('later readings chain on the re-planned recipe and every recompute keeps index to step mapping stable', () {
    final first = _firstReading(scrapIndex);
    final afterFirst = _plan(_withReadings(input, first));
    final afterFirstSteps = _steps(afterFirst);
    final laterIndex =
        afterFirstSteps[afterFirstSteps.length - 2].measurementIndex!;
    final laterPlanned = _stepAt(afterFirst, laterIndex).thermal!;
    final both = <int, Object?>{
      ...first,
      laterIndex: _reading(
        laterPlanned.plannedStartPressureBar! - 2,
        laterPlanned.plannedStartTemperatureC! + 0.3,
      ),
    };
    final afterBoth = _plan(_withReadings(input, both));

    expect(_interim(afterBoth)['error'], isNull);
    expect(_interim(afterBoth)['count'], equals(2));
    _expectNumbersFollowIndices(afterBoth);
    expect(
      _titlesBefore(afterBoth, laterIndex),
      equals(_titlesBefore(afterFirst, laterIndex)),
    );
    expect(
      _stepAt(afterBoth, laterIndex).thermal!.pressureStartBar,
      equals(laterPlanned.plannedStartPressureBar! - 2),
    );
    expect(
      _stepAt(afterBoth, scrapIndex).thermal!.pressureStartBar,
      equals(54),
    );
    expect(
      _titles(_plan(_withReadings(input, first))),
      equals(_titles(afterFirst)),
    );
    expect(
      _titles(_plan(_withReadings(input, const <int, Object?>{}))),
      equals(_titles(base)),
    );
  });

  test('a later reading at the exact planned state of the re-planned recipe leaves the recipe unchanged', () {
    final first = _firstReading(scrapIndex);
    final afterFirst = _plan(_withReadings(input, first));
    for (final index in <int>[scrapIndex + 1, scrapIndex + 2]) {
      final planned = _stepAt(afterFirst, index).thermal!;
      final plan = _plan(
        _withReadings(input, <int, Object?>{
          ...first,
          index: _reading(
            planned.plannedStartPressureBar!,
            planned.plannedStartTemperatureC!,
          ),
        }),
      );
      expect(_interim(plan)['error'], isNull, reason: 'index $index');
      expect(
        _titles(plan),
        equals(_titles(afterFirst)),
        reason: 'index $index',
      );
    }
  });

  test('recalculating from a reading keeps vented helium as the helium share of the vented original mix', () {
    final heliumStart = _cloneWithCylinder(input, <String, Object?>{
      'volumeL': 11.1,
      'initialPressureBar': 100.0,
      'targetPressureBar': 195.0,
      'initialOxygenPercent': 40.0,
      'initialHeliumPercent': 20.0,
      'targetOxygenPercent': 18.0,
      'targetHeliumPercent': 45.0,
      'workingPressureBar': 207.0,
      'hotOverfillPercent': 2.0,
    });
    final planned = optimizeBlend(heliumStart);
    expect(_n(_blend(planned)['ventedGasLitres']), greaterThan(100));
    final transfer = _steps(
      planned,
    ).firstWhere((step) => step.sourceBankId != null && step.thermal != null);
    final plan = _plan(
      _withReadings(heliumStart, <int, Object?>{
        transfer.measurementIndex!: _reading(
          transfer.thermal!.plannedStartPressureBar!,
          transfer.thermal!.plannedStartTemperatureC!,
        ),
      }),
    );
    expect(_interim(plan)['error'], isNull);
    final blend = _blend(plan);
    expect(
      (_n(blend['heliumVentedLitres']) -
              _n(_blend(planned)['heliumVentedLitres']))
          .abs(),
      lessThan(1e-6),
    );
    expect(
      (_n(blend['heliumVentedLitres']) - _n(blend['ventedGasLitres']) * 0.2)
          .abs(),
      lessThan(1e-6),
    );
  });

  test('merged plans keep one operation id per operation and consumed moles on every transfer', () {
    final plan = _plan(_withReadings(input, _firstReading(scrapIndex)));
    final transfers = _costOperationSteps(plan);
    final logical = _logicalTransfers(plan);
    expect(
      logical.map((step) => step.costOperationId).toSet().length,
      equals(logical.length),
    );
    for (final step in transfers) {
      _expectFinite(step.sourceConsumedMoles);
    }
  });

  test('a second chained reading never collides', () {
    final first = _firstReading(scrapIndex);
    final afterFirst = _plan(_withReadings(input, first));
    final afterFirstSteps = _steps(afterFirst);
    final laterIndex =
        afterFirstSteps[afterFirstSteps.length - 2].measurementIndex!;
    final laterPlanned = _stepAt(afterFirst, laterIndex).thermal!;
    final both = <int, Object?>{
      ...first,
      laterIndex: _reading(
        laterPlanned.plannedStartPressureBar! - 2,
        laterPlanned.plannedStartTemperatureC! + 0.3,
      ),
    };
    final afterBoth = _plan(_withReadings(input, both));
    final logical = _logicalTransfers(afterBoth);
    expect(
      logical.map((step) => step.costOperationId).toSet().length,
      equals(logical.length),
    );
    for (final step in _costOperationSteps(afterBoth)) {
      _expectFinite(step.sourceConsumedMoles);
    }
  });

  test('a reading after the scrap boost splits its operations into distinct prefix and suffix ids', () {
    final transferIndices = <int?>[
      for (final step in _steps(base))
        if (step.sourceBankId != null) step.measurementIndex,
    ];
    final index = transferIndices[transferIndices.indexOf(scrapIndex) + 1]!;
    final planned = _stepAt(base, index).thermal!;
    final plan = _plan(
      _withReadings(input, <int, Object?>{
        index: _reading(
          planned.plannedStartPressureBar! - 2,
          planned.plannedStartTemperatureC! + 0.3,
        ),
      }),
    );
    expect(_interim(plan)['error'], isNull);
    final scrap = _stepAt(plan, scrapIndex);
    expect(scrap.costOperationId, equals('op-2'));
    expect(scrap.costOperation, equals('boost'));
    _expectFinite(scrap.sourceConsumedMoles);

    final transfers = _logicalTransfers(plan);
    final prefix = transfers
        .where((step) => (step.measurementIndex ?? -1) < index)
        .toList();
    final suffix = transfers
        .where((step) => (step.measurementIndex ?? -1) >= index)
        .toList();
    expect(prefix, isNotEmpty);
    expect(suffix, isNotEmpty);
    for (final step in prefix) {
      expect(step.costOperationId, matches(RegExp(r'^op-\d+$')));
    }
    for (final step in suffix) {
      expect(step.costOperationId, matches(RegExp('^r$index-op-\\d+\$')));
    }
    expect(
      transfers.map((step) => step.costOperationId).toSet().length,
      equals(transfers.length),
    );
    for (final step in _costOperationSteps(plan)) {
      _expectFinite(step.sourceConsumedMoles);
    }
  });

  test('a fallback plan keeps unique operation ids and finite consumed moles on every transfer', () {
    final plan = _plan(
      _withReadings(input, <int, Object?>{scrapIndex: _reading(40, 21)}),
    );
    expect(_interim(plan)['error'], matches(RegExp('cannot be derived')));
    final transfers = _logicalTransfers(plan);
    expect(
      transfers.map((step) => step.costOperationId).toSet().length,
      equals(transfers.length),
    );
    for (final step in _costOperationSteps(plan)) {
      _expectFinite(step.sourceConsumedMoles);
    }
  });

  test('a reading-based Air-start plan has finite zero retained helium, so reuse value is 0 without a helium price', () {
    final plan = _plan(
      _withReadings(input, <int, Object?>{
        scrapIndex: _reading(
          plannedScrapStart.plannedStartPressureBar!,
          plannedScrapStart.plannedStartTemperatureC!,
        ),
      }),
    );
    final retained = _n(_blend(plan)['heliumRetainedLitres']);
    expect(retained.isFinite, isTrue);
    expect(retained, greaterThanOrEqualTo(0));

    const costs = Costs(
      currencySymbol: '',
      leftoverDiscountPercent: 0,
      operationPrices: OperationPrices(boost: 1, decant: 1, topUp: 1),
    );
    final cost = computeFillCost(
      steps: _fillSteps(plan),
      banks: DEFAULT_BANKS,
      costs: costs,
      temperatureC: 21,
    );
    expect(cost.total.isFinite, isTrue);

    final savings = computeSavings(
      heliumRetainedLitres: retained.toDouble(),
      feasible: plan['feasible'] as bool?,
      protocolSteps: _fillSteps(plan),
      banks: DEFAULT_BANKS,
      costs: costs,
      settings: DEFAULT_SETTINGS,
      physics: const PhysicsInput(model: 'vdw', temperatureC: 21),
      inventoryTemperatureC: 21,
    );
    expect(savings.savedCost, equals(0));
    expect(
      savings.missing.whereType<PurePriceGap>().where(
        (gap) => gap.gas == 'helium',
      ),
      isEmpty,
    );
  });

  test('a re-plan keeps the base plan salvage step first, with the same receiver and moved helium', () {
    final salvageInput = _salvageInput();
    final salvageBase = optimizeBlend(salvageInput);
    expect(salvageBase['salvageTransfers'] as List<Object?>, hasLength(1));
    final replanned = _plan(
      _withReadings(salvageInput, <int, Object?>{1: _reading(40, 20)}),
    );
    expect(_interim(replanned)['error'], isNull);
    final salvage = _steps(replanned).first;
    final baseSalvage = _steps(salvageBase).first;
    expect(salvage.type, equals('salvage'));
    expect(salvage.receiverBankId, equals(baseSalvage.receiverBankId));
    expect(salvage.movedMoles, equals(baseSalvage.movedMoles));
  });

  test('a re-plan starts its bank inventory from the post-salvage banks, not the banks before salvage', () {
    final salvageInput = _salvageInput();
    final salvageBase = optimizeBlend(salvageInput);
    final replanned = _plan(
      _withReadings(salvageInput, <int, Object?>{1: _reading(40, 20)}),
    );
    final segment = (replanned['readingPlan']! as ReadingPlan).segments.first;
    final seeded = segment.banks.firstWhere((bank) => bank['id'] == 'bank-n');
    final salvagedBanks = _recordsOf(salvageBase['salvageBanks']);
    final salvaged = salvagedBanks.firstWhere((bank) => bank['id'] == 'bank-n');
    expect(
      _n(seeded['pressureBar']),
      closeTo(_n(salvaged['pressureBar']), 1e-6),
    );
  });

  test('a re-plan never salvages a second time', () {
    final salvageInput = _salvageInput();
    final replanned = _plan(
      _withReadings(salvageInput, <int, Object?>{1: _reading(40, 20)}),
    );
    final salvageSteps = _steps(replanned)
        .where((step) => step.type == 'salvage');
    expect(salvageSteps, hasLength(1));
  });

  test('a reading at the drain end reproduces the vented pressure, vented gas and retained share of the base', () {
    final drainInput = _drainInput();
    final drainBase = optimizeBlend(drainInput);
    final drainStep = _steps(drainBase)
        .firstWhere((step) => step.type == 'drain');
    expect(_steps(drainBase).first.type, equals('salvage'));
    expect(drainStep.measurementIndex, equals(1));
    final drainEnd = drainStep.thermal!;
    final plan = _plan(
      _withReadings(drainInput, <int, Object?>{
        2: _reading(
          drainEnd.pressureAtTransferEndBar,
          drainEnd.temperatureAtTransferEndC,
        ),
      }),
    );
    expect(_interim(plan)['error'], isNull);
    final baseBlend = _blend(drainBase);
    final planBlend = _blend(plan);
    for (final key in <String>[
      'retainedPercent',
      'ventedPressureBar',
      'ventedGasLitres',
      'heliumVentedLitres',
      'heliumSalvagedLitres',
    ]) {
      expect(
        _n(planBlend[key]),
        closeTo(_n(baseBlend[key]), 1e-6),
        reason: key,
      );
    }
  });

  test('a reading after salvage and drain keeps the trajectory to one point per transfer and numbers titles by transfer', () {
    final drainInput = _drainInput();
    final drainBase = optimizeBlend(drainInput);
    final drainEnd = _steps(drainBase)[1].thermal!;
    final plan = _plan(
      _withReadings(drainInput, <int, Object?>{
        2: _reading(
          drainEnd.pressureAtTransferEndBar,
          drainEnd.temperatureAtTransferEndC,
        ),
      }),
    );
    final transfers = _steps(drainBase)
        .where((step) => step.sourceBankId != null)
        .length;
    expect(_trajectory(plan), hasLength(transfers + 1));
    expect(
      _trajectory(plan).map((point) => point['label']).toList(),
      equals(_trajectory(drainBase).map((point) => point['label']).toList()),
    );
    expect(_titles(plan), equals(_titles(drainBase)));
  });

  test(
    'a reading after a full salvage has no vented pressure, like the base plan',
    () {
      final salvageInput = _salvageInput();
      final salvaged = optimizeBlend(salvageInput);
      expect(_n(_blend(salvaged)['ventedPressureBar']), equals(0));
      final replanned = _plan(
        _withReadings(salvageInput, <int, Object?>{1: _reading(40, 20)}),
      );
      expect(_n(_blend(replanned)['ventedPressureBar']), equals(0));
      expect(_n(_blend(replanned)['ventedGasLitres']), equals(0));
    },
  );

  test(
    'a re-plan carries the salvage transfers and the post-salvage banks',
    () {
      final salvageInput = _salvageInput();
      final salvageBase = optimizeBlend(salvageInput);
      final replanned = _plan(
        _withReadings(salvageInput, <int, Object?>{1: _reading(40, 20)}),
      );
      expect(
        replanned['salvageTransfers'],
        equals(salvageBase['salvageTransfers']),
      );
      expect(
        _recordsOf(replanned['salvageBanks']),
        equals(_recordsOf(salvageBase['salvageBanks'])),
      );
    },
  );
}

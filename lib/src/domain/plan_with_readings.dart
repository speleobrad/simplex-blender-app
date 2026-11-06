/// Port of `js/plan-with-readings.js`.
///
/// Re-plans the remainder of a blend from interim gauge readings. The optimizer
/// result stays a JS-shaped `Map<String, Object?>`; the reading ledger
/// (`readingPlan`) is typed as [ReadingPlan].
library;

import 'dart:math' as math;

import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/calculator_input.dart';
import 'package:simplex_blender/src/domain/compare_recipe.dart';
import 'package:simplex_blender/src/domain/js_number.dart';
import 'package:simplex_blender/src/domain/optimizer.dart';
import 'package:simplex_blender/src/domain/physics.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

/// JS `readingPlan.segments[k]`: banks and the gas mix in force from [fromIndex].
final class ReadingSegment {
  const ReadingSegment({
    required this.fromIndex,
    required this.banks,
    required this.startMix,
  });

  final int fromIndex;
  final List<Map<String, Object?>> banks;
  final GasMixPercent startMix;
}

/// JS `readingPlan`. [ventedHeliumMoles] is null after a reading re-plan, as in
/// the JS port (its returned ledger omits the field).
final class ReadingPlan {
  const ReadingPlan({
    required this.segments,
    required this.retainedFraction,
    required this.ventedMoles,
    required this.ventedHeliumMoles,
  });

  final List<ReadingSegment> segments;
  final double retainedFraction;
  final double ventedMoles;
  final double? ventedHeliumMoles;
}

const int _solveIterations = 80;
const double _maxBracketMoles = 1e6;
final RegExp _stepPrefix = RegExp(r'^Step[ ]+[0-9]+', caseSensitive: false);
final RegExp _stepLabel = RegExp(r'^Step \d+$', caseSensitive: false);

const Map<String, Object?> _air = <String, Object?>{
  'id': COMPRESSOR_AIR_ID,
  'name': 'Compressor Air',
  'oxygenPercent': 21.0,
  'heliumPercent': 0.0,
};

/// JS `planWithReadings(input)`.
Map<String, Object?> planWithReadings(Map<String, Object?> input) {
  final thermal = _map(input['thermal']);
  final raw = thermal['interimMeasurements'];
  final measurements = raw is List<Object?> ? raw : <Object?>[];
  final indices = <int>[
    for (var i = 0; i < measurements.length; i++)
      if (measurements[i] != null) i,
  ];
  final base = optimizeBlend(_withReadings(input, <Object?>[]));
  if (indices.isEmpty) {
    return base;
  }
  if (base['feasible'] == false ||
      base['logicalPlan'] == null ||
      base['blend'] == null) {
    return optimizeBlend(input);
  }
  var plan = _startingPlan(base, input);
  var applied = 0;
  for (final index in indices) {
    final result = _applyReading(
      plan,
      input,
      _withReadings(input, _readingsUpTo(measurements, index)),
      index,
      measurements[index]! as Map<String, Object?>,
    );
    final error = result.error;
    if (error != null) {
      return <String, Object?>{
        ...plan,
        'interimReadings': <String, Object?>{'count': applied, 'error': error},
      };
    }
    plan = result.plan!;
    applied += 1;
  }
  return <String, Object?>{
    ...plan,
    'interimReadings': <String, Object?>{'count': applied, 'error': null},
  };
}

final class _Applied {
  const _Applied.ok(Map<String, Object?> this.plan) : error = null;
  const _Applied.fail(String this.error) : plan = null;

  final Map<String, Object?>? plan;
  final String? error;
}

final class _Solved {
  const _Solved(this.addedMoles, this.mix);

  final double addedMoles;
  final GasMixPercent mix;
}

_Applied _applyReading(
  Map<String, Object?> plan,
  Map<String, Object?> input,
  Map<String, Object?> readingsInput,
  int index,
  Map<String, Object?> reading,
) {
  final physics = _map(input['physics']);
  final cylinder = _map(input['cylinder']);
  final thermal = _map(input['thermal']);
  final referenceC = _num(physics, 'temperatureC');
  final useVdw = physics['model'] != 'ideal';
  final volumeL = _num(cylinder, 'volumeL');
  final readingPlan = plan['readingPlan']! as ReadingPlan;
  final logical = _logicalSteps(plan);
  final readingPressure = _num(reading, 'pressureBar');
  final readingTemperature = _num(reading, 'temperatureC');

  final step = index < logical.length ? logical[index] : null;
  if (step == null || step.type == 'keep') {
    return const _Applied.fail(
      'This reading does not match a step of the recipe.',
    );
  }

  final bankMoles = _bankMolesBefore(plan, index, input);
  final previousIndex = index - 1;
  final previous = previousIndex >= 0 && previousIndex < logical.length
      ? logical[previousIndex]
      : null;
  final banks = _segmentFor(
    readingPlan,
    previousIndex >= 0 ? previousIndex : 0,
  ).banks;
  final previousSource = previous?.sourceBankId;
  final Map<String, Object?>? sourceBank = previousSource == COMPRESSOR_AIR_ID
      ? _air
      : previousSource == null
      ? null
      : _firstOrNull(banks, (bank) => bank['id'] == previousSource);
  final prefix = <ProtocolStep>[...logical.take(index)];
  var mix = _mixBefore(plan, index);

  if (sourceBank != null && previous != null) {
    final previousThermal = _simulatedStep(plan, previousIndex)?.thermal;
    if (previousThermal == null) {
      return const _Applied.fail(
        'This reading cannot be checked because the previous step has no simulated state.',
      );
    }
    final mix0 = _mixBefore(plan, previousIndex);
    final n0 = _molesIn(
      previousThermal.pressureStartBar,
      mix0,
      previousThermal.temperatureStartC,
      volumeL,
      useVdw,
    );
    final solved = _solveAddedMoles(
      pressureBar: readingPressure,
      temperatureC: readingTemperature,
      mix0: mix0,
      gas: _mixOfBank(sourceBank),
      n0: n0,
      volumeL: volumeL,
      useVdw: useVdw,
    );
    if (solved == null) {
      return _Applied.fail(
        'The measured ${jsNumberString(readingPressure)} bar at ${jsNumberString(readingTemperature)} °C implies the tank holds no more gas than before the previous step, so the amount it added cannot be derived. Recheck the reading.',
      );
    }
    mix = solved.mix;
    prefix[previousIndex] = _copyStep(
      previous,
      sourceConsumedMoles: solved.addedMoles,
    );
    final sourceId = sourceBank['id']! as String;
    if (sourceId != COMPRESSOR_AIR_ID) {
      final before =
          _bankMolesBefore(plan, previousIndex, input)[sourceId] ?? double.nan;
      bankMoles[sourceId] = _jsMax(0, before - solved.addedMoles);
    }
  }

  final allBanks = _segmentFor(readingPlan, index).banks;
  final remainingBanks = <Map<String, Object?>>[
    for (final bank in allBanks)
      () {
        final id = bank['id']! as String;
        final volumeL = _num(bank, 'volumeL');
        final pressureBar = calcPressure(
          _jsMax(0, bankMoles[id] ?? double.nan) / volumeL,
          _num(bank, 'oxygenPercent'),
          _num(bank, 'heliumPercent'),
          referenceC,
          useVdw,
        );
        return <String, Object?>{
          ...bank,
          'pressureBar': pressureBar,
          'maxPressureBar': _jsMax(_num(bank, 'maxPressureBar'), pressureBar),
        };
      }(),
  ];
  final pressureAtReferenceBar = calculatePressureAtTemperature(
    pressureBar: readingPressure,
    oxygenPercent: mix.oxygenPercent,
    heliumPercent: mix.heliumPercent,
    fromTemperatureC: readingTemperature,
    toTemperatureC: referenceC,
    volumeL: volumeL,
    useVdw: useVdw,
  );

  final suffixInput = <String, Object?>{
    ...input,
    '_salvage': false,
    'cylinder': <String, Object?>{
      ...cylinder,
      'initialPressureBar': pressureAtReferenceBar,
      'initialOxygenPercent': mix.oxygenPercent,
      'initialHeliumPercent': mix.heliumPercent,
    },
    'banks': remainingBanks,
    'thermal': <String, Object?>{
      ...thermal,
      'interimMeasurements': <Object?>[],
    },
  };

  final probe = optimizeBlend(suffixInput);
  if (probe['feasible'] == false || probe['logicalPlan'] == null) {
    return _Applied.fail(
      _str(probe['error']) ?? 'No plan reaches the target from this reading.',
    );
  }
  final probeSteps = _logicalSteps(probe);
  final firstIndex = probeSteps.isNotEmpty && probeSteps[0].type == 'keep'
      ? 1
      : 0;

  final sparse = List<Object?>.filled(firstIndex + 1, null);
  sparse[firstIndex] = reading;
  final suffix = optimizeBlend(<String, Object?>{
    ...suffixInput,
    'thermal': <String, Object?>{...thermal, 'interimMeasurements': sparse},
  });
  if (suffix['feasible'] == false || suffix['logicalPlan'] == null) {
    return _Applied.fail(
      _str(suffix['error']) ?? 'No plan reaches the target from this reading.',
    );
  }

  final suffixSteps = _logicalSteps(suffix).skip(firstIndex);
  final prefixTransfers = prefix.where((s) => _truthy(s.sourceBankId)).length;
  var suffixTransfer = prefixTransfers;
  final renumberedSuffix = <ProtocolStep>[];
  for (final candidate in suffixSteps) {
    if (!_truthy(candidate.sourceBankId)) {
      renumberedSuffix.add(candidate);
      continue;
    }
    suffixTransfer += 1;
    final renumbered = _renumberStep(candidate, suffixTransfer);
    final operationId = renumbered.costOperationId;
    renumberedSuffix.add(
      operationId != null && operationId.isNotEmpty
          ? _copyStep(renumbered, costOperationId: 'r$index-$operationId')
          : renumbered,
    );
  }
  if (renumberedSuffix.isEmpty) {
    return const _Applied.fail('No steps remain to plan from this reading.');
  }
  final mergedSteps = <ProtocolStep>[...prefix, ...renumberedSuffix];

  final planTrajectory = _trajectoryOf(_map(plan['logicalPlan'])['trajectory']);
  final suffixTrajectory = _trajectoryOf(
    _map(suffix['logicalPlan'])['trajectory'],
  );
  final mergedTrajectory = <Map<String, Object?>>[
    ...planTrajectory.take(1 + prefixTransfers),
    for (var offset = 0; offset < suffixTrajectory.skip(1).length; offset++)
      () {
        final point = suffixTrajectory.skip(1).elementAt(offset);
        final step = prefixTransfers + offset + 1;
        final label = point['label'];
        return <String, Object?>{
          ...point,
          'step': step,
          'label': label is String && _stepLabel.hasMatch(label)
              ? 'Step $step'
              : label,
        };
      }(),
  ];

  final suffixBlend = _map(suffix['blend']);
  final rf =
      readingPlan.retainedFraction *
      (_num(suffixBlend, 'retainedPercent') / 100);
  final litresPerMole = gasConstant * (referenceC + 273.15);
  final ventedMoles =
      readingPlan.ventedMoles + _numOr(suffixBlend['ventedMoles'], 0);
  final ventedHeliumMoles =
      (readingPlan.ventedHeliumMoles ?? double.nan) +
      _numOr(suffixBlend['heliumVentedLitres'], 0) / litresPerMole;

  final lastSalvage = _lastOrNull(
    mergedSteps.where((s) => s.type == 'salvage'),
  );
  final lastSalvagePressure = lastSalvage?.resultingPressureBar;
  final postSalvagePressureBar =
      lastSalvagePressure != null && lastSalvagePressure.isFinite
      ? lastSalvagePressure
      : _num(cylinder, 'initialPressureBar');

  final blend = _blendFromLedger(
    input: input,
    template: suffix,
    steps: mergedSteps,
    trajectory: mergedTrajectory,
    retainedFraction: rf,
    ventedMoles: ventedMoles,
    ventedHeliumMoles: ventedHeliumMoles,
    startPressureBar: postSalvagePressureBar,
  );

  final finalized = finalizeComposedPlan(
    readingsInput,
    template: <String, Object?>{...suffix, 'blend': blend},
    protocolSteps: mergedSteps,
    trajectory: mergedTrajectory,
    targetPressureBar: _num(_map(suffix['logicalPlan']), 'targetPressureBar'),
  );
  if (finalized == null) {
    return const _Applied.fail(
      'The re-planned recipe cannot stay within the cylinder pressure limits.',
    );
  }

  final salvageTransfers = plan['salvageTransfers'];
  return _Applied.ok(<String, Object?>{
    ...finalized,
    'salvageTransfers': ?salvageTransfers,
    if (salvageTransfers != null) 'salvageBanks': plan['salvageBanks'],
    'readingPlan': ReadingPlan(
      segments: <ReadingSegment>[
        for (final segment in readingPlan.segments)
          if (segment.fromIndex < index) segment,
        ReadingSegment(fromIndex: index, banks: remainingBanks, startMix: mix),
      ],
      retainedFraction: rf,
      ventedMoles: ventedMoles,
      ventedHeliumMoles: null,
    ),
  });
}

/// JS `solveAddedMoles`: bisects the amount of source gas that reproduces the
/// measured pressure. Returns null when the reading cannot be reached.
_Solved? _solveAddedMoles({
  required double pressureBar,
  required double temperatureC,
  required GasMixPercent mix0,
  required GasMixPercent gas,
  required double n0,
  required double volumeL,
  required bool useVdw,
}) {
  GasMixPercent mixAfter(double added) => GasMixPercent(
    oxygenPercent:
        (n0 * mix0.oxygenPercent + added * gas.oxygenPercent) / (n0 + added),
    heliumPercent:
        (n0 * mix0.heliumPercent + added * gas.heliumPercent) / (n0 + added),
  );

  double residual(double added) {
    return _molesIn(
          pressureBar,
          mixAfter(added),
          temperatureC,
          volumeL,
          useVdw,
        ) -
        (n0 + added);
  }

  if (residual(0) <= 0) {
    return null;
  }
  var low = 0.0;
  var high = _jsMax(1, n0);
  while (residual(high) > 0) {
    if (high > _maxBracketMoles) {
      return null;
    }
    high *= 2;
  }
  for (var i = 0; i < _solveIterations; i++) {
    final mid = (low + high) / 2;
    if (residual(mid) > 0) {
      low = mid;
    } else {
      high = mid;
    }
  }
  final added = (low + high) / 2;
  return _Solved(added, mixAfter(added));
}

/// JS `withReadings`.
Map<String, Object?> _withReadings(
  Map<String, Object?> input,
  List<Object?> measurements,
) {
  return <String, Object?>{
    ...input,
    'thermal': <String, Object?>{
      ..._map(input['thermal']),
      'interimMeasurements': measurements,
    },
  };
}

/// JS `readingsUpTo`: keeps the truthy readings at slots 0..index, in a
/// sparse-array shape (length = last kept slot + 1).
List<Object?> _readingsUpTo(List<Object?> measurements, int index) {
  final kept = <Object?>[];
  for (var slot = 0; slot <= index; slot++) {
    if (slot < measurements.length && measurements[slot] != null) {
      while (kept.length < slot) {
        kept.add(null);
      }
      kept.add(measurements[slot]);
    }
  }
  return kept;
}

ProtocolStep _renumberStep(ProtocolStep step, int number) {
  String? renumber(String? text) =>
      text?.replaceFirst(_stepPrefix, 'Step $number');
  return _copyStep(
    step,
    title: renumber(step.title),
    description: renumber(step.description),
    recipeLabel: renumber(step.recipeLabel),
  );
}

ReadingSegment _segmentFor(ReadingPlan readingPlan, int index) {
  var owner = readingPlan.segments.first;
  for (final segment in readingPlan.segments) {
    if (segment.fromIndex <= index) {
      owner = segment;
    }
  }
  return owner;
}

GasMixPercent _mixBefore(Map<String, Object?> plan, int index) {
  final segment = _segmentFor(plan['readingPlan']! as ReadingPlan, index);
  if (index == segment.fromIndex) {
    return segment.startMix;
  }
  final mix = _logicalSteps(plan)[index - 1].resultingMix;
  if (mix == null) {
    throw StateError('Protocol step ${index - 1} has no resulting mix.');
  }
  return mix;
}

/// JS `bankMolesBefore`: moles held by each bank of the active segment just
/// before step [index].
Map<String, double> _bankMolesBefore(
  Map<String, Object?> plan,
  int index,
  Map<String, Object?> input,
) {
  final segment = _segmentFor(plan['readingPlan']! as ReadingPlan, index);
  final physics = _map(input['physics']);
  final referenceC = _num(physics, 'temperatureC');
  final useVdw = physics['model'] != 'ideal';
  final moles = <String, double>{
    for (final bank in segment.banks)
      bank['id']! as String: _molesIn(
        _num(bank, 'pressureBar'),
        _mixOfBank(bank),
        referenceC,
        _num(bank, 'volumeL'),
        useVdw,
      ),
  };
  final logical = _logicalSteps(plan);
  for (var position = segment.fromIndex; position < index; position++) {
    final step = logical[position];
    final sourceId = step.sourceBankId;
    if (!_truthy(sourceId) || sourceId == COMPRESSOR_AIR_ID) {
      continue;
    }
    final bank = _firstOrNull(segment.banks, (b) => b['id'] == sourceId);
    final endPressure = step.sourceEndPressureBar;
    if (bank == null || endPressure == null || !endPressure.isFinite) {
      continue;
    }
    final referenceOfStep = step.pressureReferenceTemperatureC;
    final stepReferenceC = referenceOfStep != null && referenceOfStep.isFinite
        ? referenceOfStep
        : referenceC;
    moles[sourceId!] = _molesIn(
      endPressure,
      _mixOfBank(bank),
      stepReferenceC,
      _num(bank, 'volumeL'),
      useVdw,
    );
  }
  return moles;
}

ProtocolStep? _simulatedStep(Map<String, Object?> plan, int index) {
  return _firstOrNull(
    _protocolStepsOf(plan['protocolSteps']),
    (step) => step.measurementIndex == index,
  );
}

/// JS `suppliedSalvagedHeliumMoles`.
double _suppliedSalvagedHeliumMoles(
  List<ProtocolStep> steps,
  List<Map<String, Object?>> trajectory,
) {
  final points = trajectory.skip(1).toList();
  var cursor = 0;
  var total = 0.0;
  for (final step in steps) {
    if (!_truthy(step.sourceBankId)) {
      continue;
    }
    final point = cursor < points.length ? points[cursor] : null;
    cursor += 1;
    final consumed = step.sourceConsumedMoles;
    final moles = consumed != null && consumed.isFinite
        ? consumed
        : _orZero(_numOrNan(point?['addedMoles']));
    final helium = step.sourceHeliumPercent;
    if (helium != null && helium < 98) {
      total += moles * (helium / 100);
    }
  }
  return total;
}

/// JS `blendFromLedger`.
Map<String, Object?> _blendFromLedger({
  required Map<String, Object?> input,
  required Map<String, Object?> template,
  required List<ProtocolStep> steps,
  required List<Map<String, Object?>> trajectory,
  required double retainedFraction,
  required double ventedMoles,
  required double ventedHeliumMoles,
  required double startPressureBar,
}) {
  final physics = _map(input['physics']);
  final cylinder = _map(input['cylinder']);
  final temperatureC = _num(physics, 'temperatureC');
  final useVdw = physics['model'] != 'ideal';
  final volumeL = _num(cylinder, 'volumeL');
  final initialMix = _initialMixOf(cylinder);
  final initialMoles = _molesIn(
    _num(cylinder, 'initialPressureBar'),
    initialMix,
    temperatureC,
    volumeL,
    useVdw,
  );
  final retainedMoles = initialMoles * retainedFraction;
  final retainedPressureBar = calcPressure(
    retainedMoles / volumeL,
    initialMix.oxygenPercent,
    initialMix.heliumPercent,
    temperatureC,
    useVdw,
  );
  final retainedHeliumMoles = initialMix.heliumPercent < 98
      ? retainedMoles * (initialMix.heliumPercent / 100)
      : 0.0;
  final litresPerMole = gasConstant * (temperatureC + 273.15);
  final blend = _map(template['blend']);
  return <String, Object?>{
    ...blend,
    'retainedPressureBar': retainedPressureBar,
    'retainedPercent': retainedFraction * 100,
    'ventedPressureBar': _jsMax(0, startPressureBar - retainedPressureBar),
    'ventedMoles': ventedMoles,
    'ventedGasLitres': ventedMoles * litresPerMole,
    'heliumVentedLitres': ventedHeliumMoles * litresPerMole,
    'heliumSalvagedLitres':
        (retainedHeliumMoles +
            _suppliedSalvagedHeliumMoles(steps, trajectory)) *
        litresPerMole,
    'heliumRetainedLitres':
        retainedMoles * (initialMix.heliumPercent / 100) * litresPerMole,
  };
}

/// JS `startingPlan`.
Map<String, Object?> _startingPlan(
  Map<String, Object?> base,
  Map<String, Object?> input,
) {
  final physics = _map(input['physics']);
  final cylinder = _map(input['cylinder']);
  final temperatureC = _num(physics, 'temperatureC');
  final litresPerMole = gasConstant * (temperatureC + 273.15);
  final blend = _map(base['blend']);
  final salvageBanks = base['salvageBanks'];
  final banks = salvageBanks is List<Bank>
      ? <Map<String, Object?>>[
          for (final bank in salvageBanks) optimizerBankJson(bank),
        ]
      : _bankMapsOf(input['banks']);
  return <String, Object?>{
    ...base,
    'readingPlan': ReadingPlan(
      segments: <ReadingSegment>[
        ReadingSegment(
          fromIndex: 0,
          banks: banks,
          startMix: _initialMixOf(cylinder),
        ),
      ],
      retainedFraction: _num(blend, 'retainedPercent') / 100,
      ventedMoles: _numOr(blend['ventedMoles'], 0),
      ventedHeliumMoles: _numOr(blend['heliumVentedLitres'], 0) / litresPerMole,
    ),
  };
}

// ---------------------------------------------------------------------------
// Value helpers (JS coercions made explicit).

Map<String, Object?> _map(Object? value) {
  return value is Map<String, Object?> ? value : const <String, Object?>{};
}

String? _str(Object? value) => value is String ? value : null;

double? _numN(Object? value) => value is num ? value.toDouble() : null;

double _numOrNan(Object? value) => _numN(value) ?? double.nan;

double _numOr(Object? value, double fallback) => _numN(value) ?? fallback;

double _num(Map<String, Object?> map, String key) => _numOrNan(map[key]);

double _orZero(double value) => value.isNaN ? 0.0 : value;

/// JS `Math.max` (NaN-propagating).
double _jsMax(double a, double b) {
  if (a.isNaN || b.isNaN) {
    return double.nan;
  }
  return math.max(a, b);
}

/// JS truthiness of a string id (null and empty are falsy).
bool _truthy(String? value) => value != null && value.isNotEmpty;

T? _firstOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) {
      return item;
    }
  }
  return null;
}

T? _lastOrNull<T>(Iterable<T> items) {
  T? last;
  for (final item in items) {
    last = item;
  }
  return last;
}

GasMixPercent _mixOfBank(Map<String, Object?> bank) => GasMixPercent(
  oxygenPercent: _num(bank, 'oxygenPercent'),
  heliumPercent: _num(bank, 'heliumPercent'),
);

GasMixPercent _initialMixOf(Map<String, Object?> cylinder) => GasMixPercent(
  oxygenPercent: _num(cylinder, 'initialOxygenPercent'),
  heliumPercent: _num(cylinder, 'initialHeliumPercent'),
);

/// JS `molesIn(p, mix, t, v, useVdw)`.
double _molesIn(
  double pressureBar,
  GasMixPercent mix,
  double temperatureC,
  double volumeL,
  bool useVdw,
) {
  return calcMolarDensity(
        pressureBar,
        mix.oxygenPercent,
        mix.heliumPercent,
        temperatureC,
        useVdw,
      ) *
      volumeL;
}

List<Map<String, Object?>> _bankMapsOf(Object? raw) {
  if (raw is! List<Object?>) {
    return <Map<String, Object?>>[];
  }
  return <Map<String, Object?>>[
    for (final entry in raw)
      if (entry is Map<String, Object?>) entry,
  ];
}

List<ProtocolStep> _logicalSteps(Map<String, Object?> plan) {
  return _protocolStepsOf(_map(plan['logicalPlan'])['protocolSteps']);
}

List<ProtocolStep> _protocolStepsOf(Object? value) {
  if (value is! List<Object?>) {
    return <ProtocolStep>[];
  }
  return <ProtocolStep>[for (final step in value) step! as ProtocolStep];
}

List<Map<String, Object?>> _trajectoryOf(Object? value) {
  if (value is! List<Object?>) {
    return <Map<String, Object?>>[];
  }
  return <Map<String, Object?>>[
    for (final point in value) point! as Map<String, Object?>,
  ];
}

/// Full field copy of a [ProtocolStep] with the given overrides (JS object spread).
ProtocolStep _copyStep(
  ProtocolStep source, {
  String? title,
  String? description,
  String? recipeLabel,
  double? sourceConsumedMoles,
  String? costOperationId,
}) {
  return ProtocolStep(
    type: source.type,
    operation: source.operation,
    title: title ?? source.title,
    method: source.method,
    stage: source.stage,
    receiverStartPressureBar: source.receiverStartPressureBar,
    receiverEndPressureBar: source.receiverEndPressureBar,
    resultingPressureBar: source.resultingPressureBar,
    resultingMix: source.resultingMix,
    receiverStartMix: source.receiverStartMix,
    receiverVolumeL: source.receiverVolumeL,
    sourceStartPressureBar: source.sourceStartPressureBar,
    sourceEndPressureBar: source.sourceEndPressureBar,
    sourcePressureBar: source.sourcePressureBar,
    sourceOxygenPercent: source.sourceOxygenPercent,
    sourceHeliumPercent: source.sourceHeliumPercent,
    pressureReferenceTemperatureC: source.pressureReferenceTemperatureC,
    pressureAtTransferEndReferenceBar: source.pressureAtTransferEndReferenceBar,
    pressureAtTransferEndAmbientBar: source.pressureAtTransferEndAmbientBar,
    pressureAtTransferEndHotBar: source.pressureAtTransferEndHotBar,
    automaticWaitMinutes: source.automaticWaitMinutes,
    waitMode: source.waitMode,
    waitMinutes: source.waitMinutes,
    targetTemperatureC: source.targetTemperatureC,
    measurementIndex: source.measurementIndex,
    measurementIndexExplicitNull: source.measurementIndexExplicitNull,
    applyInterimMeasurement: source.applyInterimMeasurement,
    scheduledMeasuredStartPressureBar: source.scheduledMeasuredStartPressureBar,
    scheduledMeasuredStartTemperatureC:
        source.scheduledMeasuredStartTemperatureC,
    safetyWaitOnly: source.safetyWaitOnly,
    costOperation: source.costOperation,
    costOperationId: costOperationId ?? source.costOperationId,
    sourceConsumedMoles: sourceConsumedMoles ?? source.sourceConsumedMoles,
    thermalSplit: source.thermalSplit,
    sourceInventory: source.sourceInventory,
    sourceVolumeL: source.sourceVolumeL,
    sourceStartMoles: source.sourceStartMoles,
    sourceEndMoles: source.sourceEndMoles,
    receiverStartMoles: source.receiverStartMoles,
    receiverEndMoles: source.receiverEndMoles,
    recipeGas: source.recipeGas,
    recipeLabel: recipeLabel ?? source.recipeLabel,
    id: source.id,
    automaticWaitMetadata: source.automaticWaitMetadata,
    thermal: source.thermal,
    recipeAction: source.recipeAction,
    sourceBankId: source.sourceBankId,
    description: description ?? source.description,
    pressureDeltaBar: source.pressureDeltaBar,
    minimumSourcePressureBar: source.minimumSourcePressureBar,
    sourceExhausted: source.sourceExhausted,
    oxygenCompressionRatio: source.oxygenCompressionRatio,
    badgeClass: source.badgeClass,
    receiverBankId: source.receiverBankId,
    receiverBankName: source.receiverBankName,
    movedMoles: source.movedMoles,
    movedHeliumLitres: source.movedHeliumLitres,
    receiverEndMix: source.receiverEndMix,
  );
}

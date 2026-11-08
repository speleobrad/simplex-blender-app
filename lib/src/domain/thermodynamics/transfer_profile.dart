part of '../thermodynamics.dart';

// Port of js/thermodynamics.js 313–333 (profile constants, interpolation),
// 341–500 (`integrateTransferRateProfile`), 605–609 (`transferProfileError`),
// 769–1034 (salvage-booster solver, memo cache, `computeTransferProfile`).

// ignore: constant_identifier_names
const double PROFILE_TIME_EPSILON_MINUTES = 1e-9;
// ignore: constant_identifier_names
const double PROFILE_PRESSURE_EPSILON_BAR = 1e-9;
// ignore: constant_identifier_names
const double PROFILE_MAX_MINUTES = 24 * 60.0;
// ignore: constant_identifier_names
const int PROFILE_SAMPLE_SECONDS = 1;
// ignore: constant_identifier_names
const double PROFILE_SAMPLE_MINUTES = PROFILE_SAMPLE_SECONDS / 60;
// ignore: constant_identifier_names
const double PROFILE_DURATION_TOLERANCE_MINUTES = 1e-6;
// ignore: constant_identifier_names
const int PROFILE_DURATION_MAX_ITERATIONS = 12;
// ignore: constant_identifier_names
const int TRANSFER_PROFILE_CACHE_LIMIT = 64;

/// JS `transferProfileError`: the error carries the `TRANSFER_PROFILE_UNSATISFIED`
/// code that the candidate scheduler branches on.
class TransferProfileException implements Exception {
  const TransferProfileException(this.message);

  final String message;

  String get code => 'TRANSFER_PROFILE_UNSATISFIED';

  @override
  String toString() => 'TransferProfileException: $message';
}

/// One point of the receiver profile. `sourcePressureBar` is NaN for compressor
/// samples, where the JS value is `null`.
class TransferProfileSample {
  const TransferProfileSample({
    required this.elapsedMinutes,
    required this.pressureBar,
    required this.sourcePressureBar,
    required this.rateBarPerMin,
    required this.temperatureC,
    required this.oxygenPercent,
    required this.heliumPercent,
  });

  final double elapsedMinutes;
  final double pressureBar;
  final double sourcePressureBar;
  final double rateBarPerMin;
  final double temperatureC;
  final double oxygenPercent;
  final double heliumPercent;
}

class TransferProfileResult {
  const TransferProfileResult({
    required this.durationMinutes,
    required this.rateBarPerMin,
    required this.reachedEndPressure,
    required this.converged,
    required this.temperatureSamples,
    required this.profileSamples,
  });

  final double durationMinutes;
  final double rateBarPerMin;
  final bool reachedEndPressure;
  final bool converged;
  final List<TemperatureSample> temperatureSamples;
  final List<TransferProfileSample> profileSamples;
}

/// Named fields mirror the JS `computeTransferProfile` argument object.
class TransferProfileInput {
  const TransferProfileInput({
    required this.step,
    required this.transfer,
    required this.currentPressureBar,
    required this.currentTemperatureC,
    required this.transferEndPressureBar,
    required this.currentMix,
    required this.receiverMix,
    required this.cylinder,
    required this.physics,
    required this.thermal,
    required this.booster,
    required this.inletTemperatureC,
  });

  final ProtocolStep step;
  final TransferRate transfer;
  final double currentPressureBar;
  final double currentTemperatureC;
  final double transferEndPressureBar;
  final GasMixPercent currentMix;
  final GasMixPercent receiverMix;
  final CylinderInput cylinder;
  final PhysicsInput physics;
  final ThermalInput thermal;
  final BoosterSettings? booster;
  final double inletTemperatureC;
}

/// JS `interpolateTemperatureC`.
double interpolateTemperatureC(
  List<TemperatureSample> samples,
  double elapsedMinutes,
) {
  if (elapsedMinutes <= samples.first.elapsedMinutes) {
    return samples.first.temperatureC;
  }
  for (var index = 1; index < samples.length; index += 1) {
    final upper = samples[index];
    if (elapsedMinutes <= upper.elapsedMinutes) {
      final lower = samples[index - 1];
      final spanMinutes = upper.elapsedMinutes - lower.elapsedMinutes;
      final fraction = spanMinutes > 0
          ? (elapsedMinutes - lower.elapsedMinutes) / spanMinutes
          : 1.0;
      return lower.temperatureC +
          (upper.temperatureC - lower.temperatureC) * fraction;
    }
  }
  return samples.last.temperatureC;
}

/// Per-instant rate state of the integrator (JS `evaluate` return value).
class _ProfileFlow {
  const _ProfileFlow({
    required this.rateBarPerMin,
    required this.molesPerMin,
    required this.sourcePressureBar,
    required this.temperatureC,
    required this.oxygenPercent,
    required this.heliumPercent,
  });

  final double rateBarPerMin;
  final double molesPerMin;
  final double sourcePressureBar;
  final double temperatureC;
  final double oxygenPercent;
  final double heliumPercent;
}

class _ProfileIntegration {
  const _ProfileIntegration({
    required this.durationMinutes,
    required this.reachedEndPressure,
    required this.samples,
  });

  final double durationMinutes;
  final bool reachedEndPressure;
  final List<TransferProfileSample> samples;
}

/// JS `integrateTransferRateProfile`. The compressor branch ignores the source
/// arguments; booster steps reach here only with finite source inventory.
_ProfileIntegration _integrateTransferRateProfile({
  required String rateSource,
  required double startPressureBar,
  required double endPressureBar,
  required List<TemperatureSample> temperatureSamples,
  required double receiverVolumeL,
  required GasMixPercent receiverStartMix,
  required GasMixPercent receiverEndMix,
  required bool useVdw,
  required double ambientTemperatureC,
  required double cylinderVolumeCm3,
  required double bpm,
  required double sourceVolumeL,
  required double sourceStartMoles,
  required double sourceOxygenPercent,
  required double sourceHeliumPercent,
  required double inletFlowLPerMin,
}) {
  final isBooster = rateSource == 'booster';
  const stepMinutes = thermalIntegrationStepSeconds / 60;
  final pressureSpanBar = endPressureBar - startPressureBar;

  _ProfileFlow evaluate(
    double pressureBar,
    double elapsedMinutes,
    double sourceMoles,
  ) {
    final progress = pressureSpanBar > 0
        ? _clamp((pressureBar - startPressureBar) / pressureSpanBar, 0.0, 1.0)
        : 1.0;
    final oxygenPercent =
        receiverStartMix.oxygenPercent +
        (receiverEndMix.oxygenPercent - receiverStartMix.oxygenPercent) *
            progress;
    final heliumPercent =
        receiverStartMix.heliumPercent +
        (receiverEndMix.heliumPercent - receiverStartMix.heliumPercent) *
            progress;
    final temperatureC = interpolateTemperatureC(
      temperatureSamples,
      elapsedMinutes,
    );
    if (!isBooster) {
      final flow = calculateCompressorFillRate(
        inletFlowLPerMin: inletFlowLPerMin,
        receiverPressureBar: pressureBar,
        receiverOxygenPercent: oxygenPercent,
        receiverHeliumPercent: heliumPercent,
        receiverVolumeL: receiverVolumeL,
        ambientTemperatureC: ambientTemperatureC,
        receiverTemperatureC: temperatureC,
        useVdw: useVdw,
      );
      return _ProfileFlow(
        rateBarPerMin: flow.fillRateBarPerMin,
        molesPerMin: flow.molesPerMin,
        sourcePressureBar: double.nan,
        temperatureC: temperatureC,
        oxygenPercent: oxygenPercent,
        heliumPercent: heliumPercent,
      );
    }
    final sourcePressureBar = inventoryPressure(
      moles: sourceMoles,
      volumeL: sourceVolumeL,
      oxygenMoles: sourceMoles * sourceOxygenPercent / 100,
      heliumMoles: sourceMoles * sourceHeliumPercent / 100,
      temperatureC: ambientTemperatureC,
      useVdw: useVdw,
    );
    final flow = sourceMoles > 0
        ? calculateBoosterFillRate(
            cylinderVolumeCm3: cylinderVolumeCm3,
            bpm: bpm,
            sourcePressureBar: sourcePressureBar,
            receiverPressureBar: pressureBar,
            sourceOxygenPercent: sourceOxygenPercent,
            sourceHeliumPercent: sourceHeliumPercent,
            receiverOxygenPercent: oxygenPercent,
            receiverHeliumPercent: heliumPercent,
            receiverVolumeL: receiverVolumeL,
            temperatureC: temperatureC,
            useVdw: useVdw,
          )
        : null;
    return _ProfileFlow(
      rateBarPerMin: flow?.fillRateBarPerMin ?? 0,
      molesPerMin: flow?.molesPerMin ?? 0,
      sourcePressureBar: sourcePressureBar,
      temperatureC: temperatureC,
      oxygenPercent: oxygenPercent,
      heliumPercent: heliumPercent,
    );
  }

  final samples = <TransferProfileSample>[];
  var pressureBar = startPressureBar;
  var sourceMoles = sourceStartMoles;
  var receiverMoles =
      calcMolarDensity(
        startPressureBar,
        receiverStartMix.oxygenPercent,
        receiverStartMix.heliumPercent,
        interpolateTemperatureC(temperatureSamples, 0),
        useVdw,
      ) *
      receiverVolumeL;
  var elapsedMinutes = 0.0;
  var nextSampleIndex = 0;
  var reachedEndPressure = false;

  for (;;) {
    final state = evaluate(pressureBar, elapsedMinutes, sourceMoles);
    final atEnd = pressureBar >= endPressureBar - PROFILE_PRESSURE_EPSILON_BAR;
    final stalled =
        !(state.rateBarPerMin > 0) || elapsedMinutes >= PROFILE_MAX_MINUTES;
    final nextSampleMinutes = nextSampleIndex * PROFILE_SAMPLE_MINUTES;
    final onSampleBoundary =
        elapsedMinutes + PROFILE_TIME_EPSILON_MINUTES >= nextSampleMinutes;
    if (onSampleBoundary || atEnd || stalled) {
      final sampleMinutes = onSampleBoundary
          ? nextSampleMinutes
          : elapsedMinutes;
      if (samples.isEmpty || samples.last.elapsedMinutes != sampleMinutes) {
        samples.add(
          TransferProfileSample(
            elapsedMinutes: sampleMinutes,
            pressureBar: pressureBar,
            sourcePressureBar: state.sourcePressureBar,
            rateBarPerMin: state.rateBarPerMin,
            temperatureC: state.temperatureC,
            oxygenPercent: state.oxygenPercent,
            heliumPercent: state.heliumPercent,
          ),
        );
      }
    }
    if (onSampleBoundary) nextSampleIndex += 1;
    if (atEnd) {
      reachedEndPressure = true;
      break;
    }
    if (stalled) break;

    final untilSampleMinutes =
        nextSampleIndex * PROFILE_SAMPLE_MINUTES - elapsedMinutes;
    // Both devices advance receiver moles by their molar flow, and pressure follows the EOS at the
    // step's temperature, so receiver mass and pressure agree at every sample. The booster also draws
    // those moles from a finite source: a step never draws more gas than the source holds, and when it
    // would, the step ends at exhaustion and the source is set to zero. The compressor draws from
    // ambient air, which is not limited.
    final sourceLimitMinutes = isBooster && state.molesPerMin > 0
        ? sourceMoles / state.molesPerMin
        : double.infinity;
    final drainsSource =
        sourceLimitMinutes < math.min(stepMinutes, untilSampleMinutes);
    final dtMinutes = drainsSource
        ? sourceLimitMinutes
        : math.min(stepMinutes, untilSampleMinutes);
    final stepMoles = state.molesPerMin * dtMinutes;
    final nextMinutes = elapsedMinutes + dtMinutes;
    final nextPressureBar = calcPressure(
      (receiverMoles + stepMoles) / receiverVolumeL,
      state.oxygenPercent,
      state.heliumPercent,
      interpolateTemperatureC(temperatureSamples, nextMinutes),
      useVdw,
    );
    if (nextPressureBar >= endPressureBar) {
      // Crossing inside the step: commit only the moles drawn up to the crossing.
      final fraction =
          (endPressureBar - pressureBar) / (nextPressureBar - pressureBar);
      receiverMoles += stepMoles * fraction;
      if (isBooster) {
        sourceMoles = math.max(0.0, sourceMoles - stepMoles * fraction);
      }
      elapsedMinutes += dtMinutes * fraction;
      pressureBar = endPressureBar;
    } else {
      receiverMoles += stepMoles;
      if (isBooster) {
        sourceMoles = drainsSource
            ? 0.0
            : math.max(0.0, sourceMoles - stepMoles);
      }
      elapsedMinutes = nextMinutes;
      pressureBar = nextPressureBar;
    }
  }

  return _ProfileIntegration(
    durationMinutes: elapsedMinutes,
    reachedEndPressure: reachedEndPressure,
    samples: samples,
  );
}

/// JS `solveSalvageBoosterProfile`. The working tank is the booster source and
/// the bank is the receiver. The bank is held at the current temperature, so the
/// integrated bank rise needs no fixed point. The tank pressure timeline follows
/// the integrated source depletion and is pinned to the planner's tank endpoints.
TransferProfileResult? _solveSalvageBoosterProfile(
  TransferProfileInput input,
  _ThermalBooster booster,
) {
  final transfer = input.transfer;
  final step = input.step;
  final rate = transfer.rateBarPerMin;
  if (rate == null || !(rate > 0) || !(transfer.pressureIncreaseBar > 0)) {
    return null;
  }
  final useVdw = input.physics.useVdw;
  final ambientTemperatureC = input.thermal.ambientTemperatureC;
  final sourceOxygenPercent =
      step.sourceOxygenPercent ?? step.resultingMix?.oxygenPercent ?? 0.0;
  final sourceHeliumPercent =
      step.sourceHeliumPercent ?? step.resultingMix?.heliumPercent ?? 0.0;
  final isOxygenRich = sourceOxygenPercent >= oxygenRichThreshold;
  final bankStartPressureBar = math.max(
    0.0,
    step.receiverStartPressureBar ?? 0.0,
  );
  final bankEndPressureBar =
      bankStartPressureBar + transfer.pressureIncreaseBar;
  final bankMix = GasMixPercent(
    oxygenPercent: step.receiverStartMix?.oxygenPercent ?? 0.0,
    heliumPercent: step.receiverStartMix?.heliumPercent ?? 0.0,
  );
  final tankAmbientStartPressureBar = calculatePressureAtTemperature(
    pressureBar: input.currentPressureBar,
    oxygenPercent: sourceOxygenPercent,
    heliumPercent: sourceHeliumPercent,
    fromTemperatureC: input.currentTemperatureC,
    toTemperatureC: ambientTemperatureC,
    volumeL: input.cylinder.volumeL,
    useVdw: useVdw,
  );
  final sourceStartMoles =
      calcMolarDensity(
        tankAmbientStartPressureBar,
        sourceOxygenPercent,
        sourceHeliumPercent,
        ambientTemperatureC,
        useVdw,
      ) *
      input.cylinder.volumeL;
  final bankTemperatureSamples = [
    TemperatureSample(
      elapsedMinutes: 0,
      temperatureC: input.currentTemperatureC,
    ),
    TemperatureSample(
      elapsedMinutes: PROFILE_MAX_MINUTES,
      temperatureC: input.currentTemperatureC,
    ),
  ];
  // The integrator's booster branch is the salvage boost rate, so it runs as 'booster'.
  final profile = _integrateTransferRateProfile(
    rateSource: 'booster',
    startPressureBar: bankStartPressureBar,
    endPressureBar: bankEndPressureBar,
    temperatureSamples: bankTemperatureSamples,
    // A salvage step without a receiver volume yields NaN, as in the JS arithmetic.
    receiverVolumeL: step.receiverVolumeL ?? double.nan,
    receiverStartMix: bankMix,
    receiverEndMix: bankMix,
    useVdw: useVdw,
    ambientTemperatureC: ambientTemperatureC,
    cylinderVolumeCm3: booster.cylinderVolumeCm3,
    bpm: isOxygenRich ? booster.oxygenBoostBpm : booster.otherBoostBpm,
    sourceVolumeL: input.cylinder.volumeL,
    sourceStartMoles: sourceStartMoles,
    sourceOxygenPercent: sourceOxygenPercent,
    sourceHeliumPercent: sourceHeliumPercent,
    inletFlowLPerMin: booster.compressorInletFlowLPerMin,
  );
  if (!profile.reachedEndPressure) {
    final stalledAtBar = profile.samples.last.pressureBar;
    throw TransferProfileException(
      'Transfer stalled at ${stalledAtBar.toStringAsFixed(2)} bar before reaching ${bankEndPressureBar.toStringAsFixed(2)} bar; the salvage-booster source cannot supply it.',
    );
  }
  final durationMinutes = profile.durationMinutes;
  final bankRiseBar = profile.samples.last.pressureBar - bankStartPressureBar;
  final temperatureSamples = _estimateTransferTemperatureSamples(
    startTemperatureC: input.currentTemperatureC,
    startPressureBar: input.currentPressureBar,
    addedPressureBar: transfer.pressureChangeBar,
    fillTimeMinutes: durationMinutes,
    volumeL: input.cylinder.volumeL,
    heliumFraction: sourceHeliumPercent / 100,
    oxygenFraction: sourceOxygenPercent / 100,
    tankMaterial: input.thermal.tankMaterial,
    coolingMedium: input.thermal.coolingMedium,
    waterSubmersionPercent: input.thermal.waterSubmersionPercent,
    tankMassKg: input.thermal.tankMassKg,
    tankSurfaceAreaM2: input.thermal.tankSurfaceAreaM2,
    ambientTemperatureC: ambientTemperatureC,
    inletTemperatureC: input.inletTemperatureC,
  );
  final sourceStartBar = profile.samples.first.sourcePressureBar;
  final depletionSpanBar =
      sourceStartBar - profile.samples.last.sourcePressureBar;
  final tankDropBar = input.transferEndPressureBar - input.currentPressureBar;
  final profileSamples = profile.samples.map((sample) {
    final depletedFraction = depletionSpanBar > 0
        ? (sourceStartBar - sample.sourcePressureBar) / depletionSpanBar
        : sample.elapsedMinutes / durationMinutes;
    return TransferProfileSample(
      elapsedMinutes: sample.elapsedMinutes,
      pressureBar: input.currentPressureBar + depletedFraction * tankDropBar,
      // The working tank's pressure from the integrator; the JS sample omits this field.
      sourcePressureBar: sample.sourcePressureBar,
      rateBarPerMin: sample.rateBarPerMin,
      temperatureC: interpolateTemperatureC(
        temperatureSamples,
        sample.elapsedMinutes,
      ),
      oxygenPercent: sourceOxygenPercent,
      heliumPercent: sourceHeliumPercent,
    );
  }).toList();
  return TransferProfileResult(
    durationMinutes: durationMinutes,
    rateBarPerMin: durationMinutes > 0 ? bankRiseBar / durationMinutes : rate,
    reachedEndPressure: true,
    converged: true,
    temperatureSamples: temperatureSamples,
    profileSamples: profileSamples,
  );
}

/// JS `computeTransferProfile`. Returns null for steps without a profile model:
/// transfers other than booster, compressor, and salvage-booster, and booster
/// steps without source inventory. Those steps keep the closed-form duration.
TransferProfileResult? _computeTransferProfile(TransferProfileInput input) {
  final transfer = input.transfer;
  final step = input.step;
  final booster = _ThermalBooster.from(input.booster);
  if (transfer.rateSource == 'salvage-booster') {
    return _solveSalvageBoosterProfile(input, booster);
  }
  final isBooster = transfer.rateSource == 'booster';
  if (!isBooster && transfer.rateSource != 'compressor') return null;
  final rate = transfer.rateBarPerMin;
  if (rate == null || !(rate > 0) || !(transfer.pressureIncreaseBar > 0)) {
    return null;
  }
  final sourceVolumeL = step.sourceVolumeL;
  final sourceStartMoles = step.sourceStartMoles;
  final hasSourceInventory =
      sourceVolumeL != null &&
      sourceVolumeL.isFinite &&
      sourceVolumeL > 0 &&
      sourceStartMoles != null &&
      sourceStartMoles.isFinite &&
      sourceStartMoles >= 0;
  if (isBooster && !hasSourceInventory) return null;
  final sourceOxygenPercent =
      step.sourceOxygenPercent ?? input.receiverMix.oxygenPercent;
  final sourceHeliumPercent =
      step.sourceHeliumPercent ?? input.receiverMix.heliumPercent;
  final receiverStartMix = step.receiverStartMix ?? input.currentMix;
  final useVdw = input.physics.useVdw;
  final isOxygenRich = sourceOxygenPercent >= oxygenRichThreshold;

  List<TemperatureSample> estimateSamples(double fillTimeMinutes) =>
      _estimateTransferTemperatureSamples(
        startTemperatureC: input.currentTemperatureC,
        startPressureBar: input.currentPressureBar,
        addedPressureBar:
            transfer.pressureChangeBar ?? transfer.pressureIncreaseBar,
        fillTimeMinutes: fillTimeMinutes,
        volumeL: input.cylinder.volumeL,
        heliumFraction: sourceHeliumPercent / 100,
        oxygenFraction: sourceOxygenPercent / 100,
        tankMaterial: input.thermal.tankMaterial,
        coolingMedium: input.thermal.coolingMedium,
        waterSubmersionPercent: input.thermal.waterSubmersionPercent,
        tankMassKg: input.thermal.tankMassKg,
        tankSurfaceAreaM2: input.thermal.tankSurfaceAreaM2,
        ambientTemperatureC: input.thermal.ambientTemperatureC,
        inletTemperatureC: input.inletTemperatureC,
      );

  // The compressor branch never reads the source fields; booster steps reach
  // the integrator only with inventory checked above.
  var durationMinutes = transfer.pressureIncreaseBar / rate;
  late List<TemperatureSample> temperatureSamples;
  late _ProfileIntegration profile;
  var converged = false;
  for (
    var iteration = 0;
    iteration < PROFILE_DURATION_MAX_ITERATIONS && !converged;
    iteration += 1
  ) {
    temperatureSamples = estimateSamples(durationMinutes);
    profile = _integrateTransferRateProfile(
      rateSource: transfer.rateSource,
      startPressureBar: input.currentPressureBar,
      endPressureBar: input.transferEndPressureBar,
      temperatureSamples: temperatureSamples,
      receiverVolumeL: input.cylinder.volumeL,
      receiverStartMix: receiverStartMix,
      receiverEndMix: input.receiverMix,
      useVdw: useVdw,
      ambientTemperatureC: input.thermal.ambientTemperatureC,
      cylinderVolumeCm3: booster.cylinderVolumeCm3,
      bpm: isOxygenRich ? booster.oxygenBoostBpm : booster.otherBoostBpm,
      sourceVolumeL: sourceVolumeL ?? double.nan,
      sourceStartMoles: sourceStartMoles ?? double.nan,
      sourceOxygenPercent: sourceOxygenPercent,
      sourceHeliumPercent: sourceHeliumPercent,
      inletFlowLPerMin: booster.compressorInletFlowLPerMin,
    );
    converged =
        (profile.durationMinutes - durationMinutes).abs() <
        PROFILE_DURATION_TOLERANCE_MINUTES;
    durationMinutes = profile.durationMinutes;
  }

  if (!converged) {
    throw TransferProfileException(
      'Transfer duration did not converge within $PROFILE_DURATION_MAX_ITERATIONS iterations; the rate and receiver temperature history disagree.',
    );
  }
  if (!profile.reachedEndPressure) {
    final stalledAtBar = profile.samples.last.pressureBar;
    throw TransferProfileException(
      'Transfer stalled at ${stalledAtBar.toStringAsFixed(2)} bar before reaching ${input.transferEndPressureBar.toStringAsFixed(2)} bar; the ${transfer.rateSource} source cannot supply it.',
    );
  }
  final achievedPressureBar =
      profile.samples.last.pressureBar - input.currentPressureBar;
  return TransferProfileResult(
    durationMinutes: durationMinutes,
    rateBarPerMin: durationMinutes > 0
        ? achievedPressureBar / durationMinutes
        : rate,
    reachedEndPressure: profile.reachedEndPressure,
    converged: converged,
    temperatureSamples: temperatureSamples,
    profileSamples: profile.samples,
  );
}

/// JS `transferProfileCache`: least-recently-used memo of [solveTransferProfile]
/// results. Null results are cached, as in JS. Exceptions are never stored.
final Map<String, TransferProfileResult?> _transferProfileCache =
    <String, TransferProfileResult?>{};

String _transferProfileKeyNumber(double? value) =>
    value == null ? 'null' : value.toString();

String _transferProfileKeyText(String? value) =>
    value == null ? 'null' : '${value.length}:$value';

String _transferProfileKeyMix(GasMixPercent? mix) => mix == null
    ? 'null'
    : '${_transferProfileKeyNumber(mix.oxygenPercent)}/'
          '${_transferProfileKeyNumber(mix.heliumPercent)}';

/// Canonical key over every input field the solver reads (JS `transferProfileKey`
/// serialises the whole argument object; non-finite numbers are kept distinct by
/// their `toString`). Resolved booster settings are keyed, so defaults match.
String _transferProfileKey(TransferProfileInput input) {
  final step = input.step;
  final transfer = input.transfer;
  final thermal = input.thermal;
  final booster = _ThermalBooster.from(input.booster);
  return [
    _transferProfileKeyNumber(step.sourceOxygenPercent),
    _transferProfileKeyNumber(step.sourceHeliumPercent),
    _transferProfileKeyNumber(step.sourceVolumeL),
    _transferProfileKeyNumber(step.sourceStartMoles),
    _transferProfileKeyMix(step.receiverStartMix),
    _transferProfileKeyMix(step.resultingMix),
    _transferProfileKeyNumber(step.receiverStartPressureBar),
    _transferProfileKeyNumber(step.receiverVolumeL),
    _transferProfileKeyText(transfer.rateSource),
    _transferProfileKeyNumber(transfer.rateBarPerMin),
    _transferProfileKeyNumber(transfer.pressureIncreaseBar),
    _transferProfileKeyNumber(transfer.pressureChangeBar),
    _transferProfileKeyNumber(input.currentPressureBar),
    _transferProfileKeyNumber(input.currentTemperatureC),
    _transferProfileKeyNumber(input.transferEndPressureBar),
    _transferProfileKeyMix(input.currentMix),
    _transferProfileKeyMix(input.receiverMix),
    _transferProfileKeyNumber(input.cylinder.volumeL),
    _transferProfileKeyText(input.physics.model),
    _transferProfileKeyNumber(thermal.ambientTemperatureC),
    _transferProfileKeyText(thermal.tankMaterial),
    _transferProfileKeyText(thermal.coolingMedium),
    _transferProfileKeyNumber(thermal.waterSubmersionPercent),
    _transferProfileKeyNumber(thermal.tankMassKg),
    _transferProfileKeyNumber(thermal.tankSurfaceAreaM2),
    _transferProfileKeyNumber(booster.cylinderVolumeCm3),
    _transferProfileKeyNumber(booster.oxygenBoostBpm),
    _transferProfileKeyNumber(booster.otherBoostBpm),
    _transferProfileKeyNumber(booster.compressorInletFlowLPerMin),
    _transferProfileKeyNumber(input.inletTemperatureC),
  ].join('|');
}

/// Solves the fill duration and the receiver temperature history together. The
/// rate depends on receiver temperature, and the temperature history depends on
/// how long the fill takes, so the integrated duration is fed back until it
/// stops moving. Returns null for closed-form steps (see [_computeTransferProfile]).
TransferProfileResult? solveTransferProfile(TransferProfileInput input) {
  final key = _transferProfileKey(input);
  if (_transferProfileCache.containsKey(key)) {
    final cached = _transferProfileCache.remove(key);
    _transferProfileCache[key] = cached;
    return cached;
  }
  final result = _computeTransferProfile(input);
  if (_transferProfileCache.length >= TRANSFER_PROFILE_CACHE_LIMIT) {
    _transferProfileCache.remove(_transferProfileCache.keys.first);
  }
  _transferProfileCache[key] = result;
  return result;
}

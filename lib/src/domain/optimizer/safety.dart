part of '../optimizer.dart';

// ignore: constant_identifier_names
const double THERMAL_SAFETY_TOLERANCE_BAR = 1e-9;

// ignore: constant_identifier_names
const double MAX_AUTOMATIC_WAIT_MINUTES = 1440;

/// JS `context` of the safety checks: `{thermal, physics, cylinder, settings}`.
/// Any entry may be absent; the JS code dereferences some of them only on
/// paths that are guarded by the caller, and so does this port (`!`).
class _SafetyContext {
  const _SafetyContext({
    this.thermal,
    this.physics,
    this.cylinder,
    this.settings,
  });

  final ThermalInput? thermal;
  final PhysicsInput? physics;
  final Map<String, Object?>? cylinder;
  final BlendSettings? settings;
}

/// One pressure the safety check tests, with the temperature it is tested at.
class _SafetyPressure {
  const _SafetyPressure(
    this.pressureBar,
    this.temperatureC,
    this.isTransientHot,
  );

  final double? pressureBar;
  final double? temperatureC;
  final bool isTransientHot;
}

/// JS `{ stepIndex, stepIdentifier, configuredWaitMinutes, actualWaitMinutes,
/// addedWaitMinutes, warning }`.
class _AutomaticWaitMetadata {
  const _AutomaticWaitMetadata({
    required this.stepIndex,
    required this.stepIdentifier,
    required this.configuredWaitMinutes,
    required this.actualWaitMinutes,
    required this.addedWaitMinutes,
  });

  final int stepIndex;
  final Object stepIdentifier;
  final double? configuredWaitMinutes;
  final double? actualWaitMinutes;
  final double addedWaitMinutes;
  final String warning = '!';

  /// The JS object with its key names verbatim.
  Map<String, Object?> toMap() => <String, Object?>{
    'stepIndex': stepIndex,
    'stepIdentifier': stepIdentifier,
    'configuredWaitMinutes': configuredWaitMinutes,
    'actualWaitMinutes': actualWaitMinutes,
    'addedWaitMinutes': addedWaitMinutes,
    'warning': warning,
  };
}

/// JS `{ first, wait, second }` returned by `splitTransferAtSafeHotEndpoint`.
class _SafeTransferSplit {
  const _SafeTransferSplit({
    required this.first,
    required this.wait,
    required this.second,
  });

  final ProtocolStep first;
  final ProtocolStep wait;
  final ProtocolStep second;
}

/// Stage steps for one split fraction, plus the receiver mix shared by the
/// automatic wait between them.
class _SafeStages {
  const _SafeStages({
    required this.first,
    required this.second,
    required this.wait,
    required this.mix,
  });

  final ProtocolStep first;
  final ProtocolStep second;
  final ProtocolStep wait;
  final GasMixPercent mix;
}

/// JS receiver-mix record produced by `receiverMixAt`.
class _ReceiverMix {
  const _ReceiverMix({
    required this.moles,
    required this.oxygenMoles,
    required this.heliumMoles,
    required this.oxygenPercent,
    required this.heliumPercent,
  });

  final double moles;
  final double oxygenMoles;
  final double heliumMoles;
  final double oxygenPercent;
  final double heliumPercent;
}

bool _isFiniteValue(double? value) => value != null && value.isFinite;

double? _finiteValueOrNull(double? value) =>
    value != null && value.isFinite ? value : null;

double _finiteOr(double? value, double fallback) =>
    value != null && value.isFinite ? value : fallback;

ProtocolStep? _protocolStepAt(List<ProtocolStep> steps, int index) =>
    index >= 0 && index < steps.length ? steps[index] : null;

double _pressureAtSample(
  ThermalSample sample,
  ThermalStep state,
  ProtocolStep step,
  _SafetyContext context,
) {
  if (_isFiniteValue(sample.projectedPressureBar)) {
    return sample.projectedPressureBar!;
  }
  final oxygenPercent =
      sample.oxygenPercent ??
      step.resultingMix?.oxygenPercent ??
      state.receiverStartMix?.oxygenPercent ??
      21.0;
  final heliumPercent =
      sample.heliumPercent ??
      step.resultingMix?.heliumPercent ??
      state.receiverStartMix?.heliumPercent ??
      0.0;
  final ambientPressureBar = sample.ambientPressureBar;
  if (ambientPressureBar == null || !ambientPressureBar.isFinite) {
    return sample.pressureBar;
  }
  final fromTemperatureC =
      sample.pressureReferenceTemperatureC ??
      context.thermal!.ambientTemperatureC;
  return calculatePressureAtTemperature(
    pressureBar: ambientPressureBar,
    oxygenPercent: oxygenPercent,
    heliumPercent: heliumPercent,
    fromTemperatureC: fromTemperatureC,
    toTemperatureC: sample.temperatureC,
    volumeL: _numberOrNan(context.cylinder!['volumeL']),
    useVdw: context.physics!.useVdw,
  );
}

double _hotTransferEndpointPressure(
  ThermalStep state,
  ProtocolStep step,
  _SafetyContext context,
) {
  if (state.pressureAtTransferEndHotBar.isFinite) {
    return state.pressureAtTransferEndHotBar;
  }
  return calculatePressureAtTemperature(
    pressureBar: state.pressureAtTransferEndReferenceBar,
    oxygenPercent:
        step.resultingMix?.oxygenPercent ??
        state.receiverStartMix?.oxygenPercent ??
        21.0,
    heliumPercent:
        step.resultingMix?.heliumPercent ??
        state.receiverStartMix?.heliumPercent ??
        0.0,
    fromTemperatureC: state.pressureReferenceTemperatureC,
    toTemperatureC: state.temperatureAtTransferEndC,
    volumeL: _numberOrNan(context.cylinder!['volumeL']),
    useVdw: context.physics!.useVdw,
  );
}

double _thermalEquipmentPressureLimit(
  ThermalStep? state,
  BlendSettings? settings,
) {
  final limits = <double>[];
  final rateSource = state?.rateSource;
  final booster = settings?.booster;
  if (rateSource == 'compressor') {
    limits.add(_finiteOr(booster?.maxCompressorPressureBar, 232.0));
  } else if (rateSource == 'booster') {
    limits.add(_finiteOr(booster?.maxBoosterOutputPressureBar, 200.0));
  }
  return limits.isNotEmpty
      ? limits.reduce((a, b) => math.min(a, b))
      : double.infinity;
}

double _cylinderHotOverfillPercent(Map<String, Object?>? cylinder) {
  if (cylinder == null || !cylinder.containsKey('hotOverfillPercent')) {
    return defaultHotOverfillPercent;
  }
  final value = _numberOrNull(cylinder['hotOverfillPercent']);
  if (!isValidHotOverfillPercent(value)) {
    throw RangeError(
      'Cylinder hot overfill must be between 0 and 5% in 0.5% steps.',
    );
  }
  return value!;
}

double _configuredCylinderPressureLimit(
  double? workingPressureBar,
  bool isTransientHot,
  _SafetyContext context,
) {
  if (workingPressureBar == null || !workingPressureBar.isFinite) {
    return double.infinity;
  }
  final limit = getCylinderPressureLimit(
    cylinder: CylinderPressureSpec(
      workingPressureBar: workingPressureBar,
      hotOverfillPercent: _numberOrNull(
        context.cylinder?['hotOverfillPercent'],
      ),
    ),
    isTransientHot: isTransientHot,
  );
  return limit?.limitBar ?? double.infinity;
}

bool _isAboveAmbientTemperature(
  double? temperatureC,
  double? ambientTemperatureC,
) {
  if (temperatureC == null || ambientTemperatureC == null) return false;
  return temperatureC.isFinite &&
      ambientTemperatureC.isFinite &&
      temperatureC > ambientTemperatureC;
}

double _cylinderPressureLimitAtTemperature(
  double? temperatureC,
  double? workingPressureBar,
  _SafetyContext context, {
  bool? isTransientHot,
}) {
  final transientHot =
      isTransientHot ??
      _isAboveAmbientTemperature(
        temperatureC,
        context.thermal?.ambientTemperatureC,
      );
  final configuredLimit = _configuredCylinderPressureLimit(
    workingPressureBar,
    transientHot,
    context,
  );
  return context.settings?.pressureLimitMode == 'warning'
      ? double.infinity
      : configuredLimit;
}

List<_SafetyPressure> _pressureValuesForSafety(
  ThermalStep state,
  ProtocolStep step,
  _SafetyContext context,
) {
  final ambientTemperatureC = context.thermal?.ambientTemperatureC;
  final targetTemperatureWait = context.thermal?.waitMode == 'temperature';
  final waitEndMinutes = state.durationMinutes + state.waitMinutes;
  bool isTargetWaitEndpoint(ThermalSample sample) =>
      targetTemperatureWait &&
      sample.elapsedMinutes.isFinite &&
      waitEndMinutes.isFinite &&
      sample.elapsedMinutes >= waitEndMinutes - 1e-9;

  final entries = <_SafetyPressure>[
    _SafetyPressure(
      state.pressureStartBar,
      state.temperatureStartC,
      (!targetTemperatureWait || state.measurementApplied == true) &&
          _isAboveAmbientTemperature(
            state.temperatureStartC,
            ambientTemperatureC,
          ),
    ),
    if (state.measurementApplied != false)
      _SafetyPressure(
        state.measuredStartPressureBar,
        state.measuredStartTemperatureC,
        _isAboveAmbientTemperature(
          state.measuredStartTemperatureC,
          ambientTemperatureC,
        ),
      ),
    _SafetyPressure(
      state.pressureAtTransferEndAmbientBar,
      ambientTemperatureC,
      false,
    ),
    _SafetyPressure(
      state.pressureAfterWaitBar,
      state.temperatureAfterWaitC,
      !targetTemperatureWait &&
          _isAboveAmbientTemperature(
            state.temperatureAfterWaitC,
            ambientTemperatureC,
          ),
    ),
    _SafetyPressure(
      _hotTransferEndpointPressure(state, step, context),
      state.temperatureAtTransferEndC,
      _isAboveAmbientTemperature(
        state.temperatureAtTransferEndC,
        ambientTemperatureC,
      ),
    ),
    for (final sample in state.samples) ...[
      _SafetyPressure(sample.ambientPressureBar, ambientTemperatureC, false),
      _SafetyPressure(
        _pressureAtSample(sample, state, step, context),
        sample.temperatureC,
        !isTargetWaitEndpoint(sample) &&
            _isAboveAmbientTemperature(
              sample.temperatureC,
              ambientTemperatureC,
            ),
      ),
    ],
  ];
  return entries.where((entry) => entry.pressureBar != null).toList();
}

bool _exceedsThermalLimit(double? pressure, double limit) =>
    pressure == null ||
    !pressure.isFinite ||
    pressure > limit + THERMAL_SAFETY_TOLERANCE_BAR;

bool _unsafeThermalStep(
  ThermalStep state,
  ProtocolStep step,
  double? workingPressureBar,
  double equipmentLimit,
  _SafetyContext context,
) {
  return _pressureValuesForSafety(state, step, context).any((entry) {
    final cylinderLimit = _cylinderPressureLimitAtTemperature(
      entry.temperatureC,
      workingPressureBar,
      context,
      isTransientHot: entry.isTransientHot,
    );
    return _exceedsThermalLimit(
      entry.pressureBar,
      math.min(cylinderLimit, equipmentLimit),
    );
  });
}

int _firstUnsafeThermalIndex(
  ThermalProtocolResult? simulation,
  double? workingPressureBar,
  _SafetyContext context,
) {
  _cylinderHotOverfillPercent(context.cylinder);
  final initialLimit = _cylinderPressureLimitAtTemperature(
    context.thermal?.ambientTemperatureC,
    workingPressureBar,
    context,
  );
  final initialPressureBar = _numberOrNull(
    context.cylinder?['initialPressureBar'],
  );
  if (_exceedsThermalLimit(initialPressureBar, initialLimit)) {
    return -2;
  }
  final steps = simulation?.protocolSteps ?? const <ProtocolStep>[];
  for (var index = 0; index < steps.length; index++) {
    final step = steps[index];
    final state = step.thermal;
    final equipmentLimit = _thermalEquipmentPressureLimit(
      state,
      context.settings,
    );
    // JS dereferences the thermal state here; a missing state is a fault.
    if (_unsafeThermalStep(
      state!,
      step,
      workingPressureBar,
      equipmentLimit,
      context,
    )) {
      return index;
    }
  }
  return -1;
}

bool isSafeSimulation(
  ThermalProtocolResult? simulation,
  double? workingPressureBar, {
  ThermalInput? thermal,
  PhysicsInput? physics,
  Map<String, Object?>? cylinder,
  BlendSettings? settings,
}) {
  _cylinderHotOverfillPercent(cylinder);
  final context = _SafetyContext(
    thermal: thermal,
    physics: physics,
    cylinder: cylinder,
    settings: settings,
  );
  if (thermal == null || physics == null || cylinder == null) {
    final limit =
        _cylinderPressureLimitAtTemperature(
          thermal?.ambientTemperatureC,
          workingPressureBar,
          context,
        ) +
        THERMAL_SAFETY_TOLERANCE_BAR;
    final initialPressureBar =
        _numberOrNull(cylinder?['initialPressureBar']) ?? 0.0;
    if (!(initialPressureBar <= limit)) {
      return false;
    }
    for (final step in simulation?.protocolSteps ?? const <ProtocolStep>[]) {
      final state = step.thermal;
      if (state == null) {
        continue;
      }
      final pressures = <double?>[
        state.pressureStartBar,
        state.pressureAtTransferEndReferenceBar,
        state.pressureAtTransferEndAmbientBar,
        state.pressureAtTransferEndBar,
        state.pressureAtTransferEndHotBar,
        state.pressureAfterWaitBar,
        for (final sample in state.samples) ...[
          sample.ambientPressureBar,
          sample.projectedPressureBar ?? sample.pressureBar,
        ],
      ];
      if (!pressures.whereType<double>().every(
        (pressure) => pressure.isFinite && pressure <= limit,
      )) {
        return false;
      }
    }
    return true;
  }
  return _firstUnsafeThermalIndex(simulation, workingPressureBar, context) ==
      -1;
}

List<_AutomaticWaitMetadata> _automaticWaitMetadata(
  ThermalProtocolResult? simulation,
) {
  final metadata = <_AutomaticWaitMetadata>[];
  final steps = simulation?.protocolSteps ?? const <ProtocolStep>[];
  for (var stepIndex = 0; stepIndex < steps.length; stepIndex++) {
    final step = steps[stepIndex];
    final state = step.thermal;
    final automaticWaitMinutes = state?.automaticWaitMinutes;
    if (state == null ||
        automaticWaitMinutes == null ||
        !(automaticWaitMinutes > THERMAL_SAFETY_TOLERANCE_BAR)) {
      continue;
    }
    metadata.add(
      _AutomaticWaitMetadata(
        stepIndex: stepIndex,
        stepIdentifier: step.title ?? step.id ?? stepIndex,
        configuredWaitMinutes: state.configuredWaitMinutes,
        actualWaitMinutes: state.waitMinutes,
        addedWaitMinutes: automaticWaitMinutes,
      ),
    );
  }
  return metadata;
}

BoosterSettings? _boosterSettings(BlendSettings? settings) {
  final booster = settings?.booster;
  if (booster == null) {
    return null;
  }
  return BoosterSettings(
    cylinderVolumeCm3: booster.cylinderVolumeCm3,
    oxygenBoostBpm: booster.oxygenBoostBpm,
    otherBoostBpm: booster.otherBoostBpm,
    oxygenDecantRateBarPerMin: booster.oxygenDecantRateBarPerMin,
    otherDecantRateBarPerMin: booster.otherDecantRateBarPerMin,
    drainingRateBarPerMin: booster.drainingRateBarPerMin,
    compressorInletFlowLPerMin: booster.compressorInletFlowLPerMin,
    boosterTemperatureModifierC: booster.boosterTemperatureModifierC,
    compressorTemperatureModifierC: booster.compressorTemperatureModifierC,
  );
}

ThermalProtocolResult _simulated(
  List<ProtocolStep> steps,
  _SafetyContext options,
) {
  return simulateThermalProtocol(
    protocolSteps: steps,
    cylinder: CylinderInput(
      volumeL: _numberOrNan(options.cylinder!['volumeL']),
      initialPressureBar: _numberOrNull(
        options.cylinder!['initialPressureBar'],
      ),
      initialOxygenPercent: _numberOrNull(
        options.cylinder!['initialOxygenPercent'],
      ),
      initialHeliumPercent: _numberOrNull(
        options.cylinder!['initialHeliumPercent'],
      ),
    ),
    physics: options.physics!,
    thermal: options.thermal!,
    booster: _boosterSettings(options.settings),
  );
}

GasMixPercent _mixForStep(ProtocolStep step, ThermalStep? state) {
  return GasMixPercent(
    oxygenPercent:
        state?.receiverStartMix?.oxygenPercent ??
        step.receiverStartMix?.oxygenPercent ??
        21.0,
    heliumPercent:
        state?.receiverStartMix?.heliumPercent ??
        step.receiverStartMix?.heliumPercent ??
        0.0,
  );
}

/// Moles of a bank's gas at the start of a transfer step (JS `optimizer.js`
/// 396–410). The step's source start pressure is moved from the pressure
/// reference temperature to ambient, then converted to molar density at the
/// bank's volume. Returns null when the volume or pressure is not finite and
/// positive. Callers handle unlimited sources and explicit overrides.
double? _derivedSourceStartMoles({
  required double sourceVolumeL,
  required double sourceStartPressureBar,
  required double sourceOxygenPercent,
  required double sourceHeliumPercent,
  required double pressureReferenceTemperatureC,
  required double ambientTemperatureC,
  required bool useVdw,
}) {
  final sourceStartInventoryPressureBar = sourceStartPressureBar.isFinite
      ? calculatePressureAtTemperature(
          pressureBar: sourceStartPressureBar,
          oxygenPercent: sourceOxygenPercent,
          heliumPercent: sourceHeliumPercent,
          fromTemperatureC: pressureReferenceTemperatureC,
          toTemperatureC: ambientTemperatureC,
          volumeL: sourceVolumeL,
          useVdw: useVdw,
        )
      : double.nan;
  return sourceVolumeL.isFinite &&
          sourceVolumeL > 0 &&
          sourceStartInventoryPressureBar.isFinite
      ? calcMolarDensity(
              sourceStartInventoryPressureBar,
              sourceOxygenPercent,
              sourceHeliumPercent,
              ambientTemperatureC,
              useVdw,
            ) *
            sourceVolumeL
      : null;
}

/// JS line 339 `splitTransferAtSafeHotEndpoint`. Builds the two transfer
/// stages (and the automatic wait between them) for the step at
/// [unsafeIndex], choosing the largest first-stage fraction that keeps the
/// simulation safe. Returns null when no safe split exists.
_SafeTransferSplit? _splitTransferAtSafeHotEndpoint({
  required List<ProtocolStep> steps,
  required int unsafeIndex,
  required ThermalProtocolResult simulation,
  required _SafetyContext options,
}) {
  final transferStep = _protocolStepAt(steps, unsafeIndex);
  if (transferStep == null ||
      transferStep.type == 'wait' ||
      transferStep.type == 'keep' ||
      transferStep.thermalSplit) {
    return null;
  }
  final state = _protocolStepAt(simulation.protocolSteps, unsafeIndex)?.thermal;
  if (state == null) {
    return null;
  }
  final physics = options.physics!;
  final thermal = options.thermal!;
  final cylinder = options.cylinder!;
  final useVdw = physics.useVdw;
  final ambientTemperatureC = thermal.ambientTemperatureC;
  final volumeL = _numberOrNan(cylinder['volumeL']);
  final receiverStartMix = _mixForStep(transferStep, state);
  final receiverEndMix = GasMixPercent(
    oxygenPercent:
        transferStep.resultingMix?.oxygenPercent ??
        receiverStartMix.oxygenPercent,
    heliumPercent:
        transferStep.resultingMix?.heliumPercent ??
        receiverStartMix.heliumPercent,
  );
  final receiverStartAmbientPressureBar = calculatePressureAtTemperature(
    pressureBar: state.pressureStartBar,
    oxygenPercent: receiverStartMix.oxygenPercent,
    heliumPercent: receiverStartMix.heliumPercent,
    fromTemperatureC: state.temperatureStartC,
    toTemperatureC: ambientTemperatureC,
    volumeL: volumeL,
    useVdw: useVdw,
  );
  final receiverStartMoles =
      calcMolarDensity(
        receiverStartAmbientPressureBar,
        receiverStartMix.oxygenPercent,
        receiverStartMix.heliumPercent,
        ambientTemperatureC,
        useVdw,
      ) *
      volumeL;
  final receiverEndReferencePressureBar =
      transferStep.receiverEndPressureBar ?? transferStep.resultingPressureBar;
  if (receiverEndReferencePressureBar == null ||
      !receiverEndReferencePressureBar.isFinite) {
    return null;
  }
  final pressureReferenceTemperatureC = _finiteOr(
    transferStep.pressureReferenceTemperatureC,
    physics.temperatureC,
  );
  final receiverEndPressureBar = calculatePressureAtTemperature(
    pressureBar: receiverEndReferencePressureBar,
    oxygenPercent: receiverEndMix.oxygenPercent,
    heliumPercent: receiverEndMix.heliumPercent,
    fromTemperatureC: pressureReferenceTemperatureC,
    toTemperatureC: ambientTemperatureC,
    volumeL: volumeL,
    useVdw: useVdw,
  );
  final receiverEndMoles =
      calcMolarDensity(
        receiverEndPressureBar,
        receiverEndMix.oxygenPercent,
        receiverEndMix.heliumPercent,
        ambientTemperatureC,
        useVdw,
      ) *
      volumeL;
  final totalReceiverMoles = receiverEndMoles - receiverStartMoles;
  if (!(totalReceiverMoles > 1e-10)) {
    return null;
  }

  final sourceUnlimited =
      transferStep.sourceInventory == 'unlimited' ||
      transferStep.recipeGas == 'Compressor Air' ||
      transferStep.method == 'compressor';
  final sourceOxygenPercent =
      transferStep.sourceOxygenPercent ?? receiverEndMix.oxygenPercent;
  final sourceHeliumPercent =
      transferStep.sourceHeliumPercent ?? receiverEndMix.heliumPercent;
  final sourceVolumeL = sourceUnlimited
      ? double.nan
      : (transferStep.sourceVolumeL ?? double.nan);
  final sourceStartMoles = sourceUnlimited
      ? null
      : (_finiteValueOrNull(transferStep.sourceStartMoles) ??
            _derivedSourceStartMoles(
              sourceVolumeL: sourceVolumeL,
              sourceStartPressureBar:
                  transferStep.sourceStartPressureBar ?? double.nan,
              sourceOxygenPercent: sourceOxygenPercent,
              sourceHeliumPercent: sourceHeliumPercent,
              pressureReferenceTemperatureC: pressureReferenceTemperatureC,
              ambientTemperatureC: ambientTemperatureC,
              useVdw: useVdw,
            ));
  final sourceEndMoles = sourceStartMoles != null && sourceStartMoles.isFinite
      ? sourceStartMoles - totalReceiverMoles
      : null;
  if (sourceEndMoles != null &&
      sourceEndMoles.isFinite &&
      sourceEndMoles < -1e-8) {
    return null;
  }

  _ReceiverMix receiverMixAt(double fraction) {
    final transferredMoles = totalReceiverMoles * fraction;
    final totalMoles = receiverStartMoles + transferredMoles;
    final oxygenMoles =
        receiverStartMoles * receiverStartMix.oxygenPercent / 100 +
        transferredMoles * sourceOxygenPercent / 100;
    final heliumMoles =
        receiverStartMoles * receiverStartMix.heliumPercent / 100 +
        transferredMoles * sourceHeliumPercent / 100;
    return _ReceiverMix(
      moles: totalMoles,
      oxygenMoles: oxygenMoles,
      heliumMoles: heliumMoles,
      oxygenPercent: oxygenMoles / totalMoles * 100,
      heliumPercent: heliumMoles / totalMoles * 100,
    );
  }

  double? sourcePressureAt(double moles) {
    if (!sourceVolumeL.isFinite || !moles.isFinite) {
      return null;
    }
    return inventoryPressure(
      moles: moles,
      volumeL: sourceVolumeL,
      oxygenMoles: moles * sourceOxygenPercent / 100,
      heliumMoles: moles * sourceHeliumPercent / 100,
      temperatureC: ambientTemperatureC,
      useVdw: useVdw,
    );
  }

  _SafeStages stagesAt(double fraction) {
    final stage1 = receiverMixAt(fraction);
    final firstConsumedMoles = totalReceiverMoles * fraction;
    final startMoles = sourceStartMoles;
    final firstSourceMoles = startMoles == null
        ? null
        : startMoles - firstConsumedMoles;
    final firstReceiverPressureBar = inventoryPressure(
      moles: stage1.moles,
      volumeL: volumeL,
      oxygenMoles: stage1.oxygenMoles,
      heliumMoles: stage1.heliumMoles,
      temperatureC: ambientTemperatureC,
      useVdw: useVdw,
    );
    final mix = GasMixPercent(
      oxygenPercent: stage1.oxygenPercent,
      heliumPercent: stage1.heliumPercent,
    );
    final first = ProtocolStep(
      type: transferStep.type,
      operation: transferStep.operation,
      title: '${transferStep.title ?? 'undefined'} (safe stage 1)',
      method: transferStep.method,
      stage: transferStep.stage,
      receiverStartPressureBar: receiverStartAmbientPressureBar,
      receiverEndPressureBar: firstReceiverPressureBar,
      resultingPressureBar: firstReceiverPressureBar,
      resultingMix: mix,
      receiverStartMix: receiverStartMix,
      receiverVolumeL: transferStep.receiverVolumeL,
      sourceStartPressureBar: startMoles != null
          ? sourcePressureAt(startMoles)
          : transferStep.sourceStartPressureBar,
      sourceEndPressureBar: firstSourceMoles != null
          ? sourcePressureAt(firstSourceMoles)
          : transferStep.sourceEndPressureBar,
      sourcePressureBar: transferStep.sourcePressureBar,
      sourceOxygenPercent: transferStep.sourceOxygenPercent,
      sourceHeliumPercent: transferStep.sourceHeliumPercent,
      pressureReferenceTemperatureC: ambientTemperatureC,
      pressureAtTransferEndReferenceBar: firstReceiverPressureBar,
      pressureAtTransferEndAmbientBar:
          transferStep.pressureAtTransferEndAmbientBar,
      pressureAtTransferEndHotBar: transferStep.pressureAtTransferEndHotBar,
      automaticWaitMinutes: transferStep.automaticWaitMinutes,
      waitMode: transferStep.waitMode,
      waitMinutes: transferStep.waitMinutes,
      targetTemperatureC: transferStep.targetTemperatureC,
      measurementIndex: transferStep.measurementIndex,
      measurementIndexExplicitNull: transferStep.measurementIndexExplicitNull,
      applyInterimMeasurement: transferStep.applyInterimMeasurement,
      scheduledMeasuredStartPressureBar:
          transferStep.scheduledMeasuredStartPressureBar,
      scheduledMeasuredStartTemperatureC:
          transferStep.scheduledMeasuredStartTemperatureC,
      safetyWaitOnly: transferStep.safetyWaitOnly,
      costOperation: transferStep.costOperation,
      costOperationId: transferStep.costOperationId,
      sourceConsumedMoles: firstConsumedMoles,
      thermalSplit: true,
      thermal: transferStep.thermal,
      recipeGas: transferStep.recipeGas,
      recipeLabel: transferStep.recipeLabel,
      id: transferStep.id,
      sourceInventory: sourceUnlimited
          ? 'unlimited'
          : transferStep.sourceInventory,
      sourceVolumeL: sourceUnlimited ? null : transferStep.sourceVolumeL,
      receiverStartMoles: receiverStartMoles,
      receiverEndMoles: stage1.moles,
      sourceStartMoles: startMoles,
      sourceEndMoles: firstSourceMoles,
    );
    final second = ProtocolStep(
      type: transferStep.type,
      operation: transferStep.operation,
      title: '${transferStep.title ?? 'undefined'} (safe stage 2)',
      method: transferStep.method,
      stage: transferStep.stage,
      receiverStartPressureBar: firstReceiverPressureBar,
      receiverEndPressureBar: receiverEndPressureBar,
      resultingPressureBar: receiverEndPressureBar,
      resultingMix: transferStep.resultingMix,
      receiverStartMix: mix,
      receiverVolumeL: transferStep.receiverVolumeL,
      sourceStartPressureBar: firstSourceMoles != null
          ? sourcePressureAt(firstSourceMoles)
          : transferStep.sourceStartPressureBar,
      sourceEndPressureBar: sourceEndMoles != null
          ? sourcePressureAt(sourceEndMoles)
          : transferStep.sourceEndPressureBar,
      sourcePressureBar: transferStep.sourcePressureBar,
      sourceOxygenPercent: transferStep.sourceOxygenPercent,
      sourceHeliumPercent: transferStep.sourceHeliumPercent,
      pressureReferenceTemperatureC: ambientTemperatureC,
      pressureAtTransferEndReferenceBar: receiverEndPressureBar,
      pressureAtTransferEndAmbientBar:
          transferStep.pressureAtTransferEndAmbientBar,
      pressureAtTransferEndHotBar: transferStep.pressureAtTransferEndHotBar,
      automaticWaitMinutes: transferStep.automaticWaitMinutes,
      waitMode: transferStep.waitMode,
      waitMinutes: transferStep.waitMinutes,
      targetTemperatureC: transferStep.targetTemperatureC,
      measurementIndex: null,
      measurementIndexExplicitNull: true,
      applyInterimMeasurement: transferStep.applyInterimMeasurement,
      scheduledMeasuredStartPressureBar:
          transferStep.scheduledMeasuredStartPressureBar,
      scheduledMeasuredStartTemperatureC:
          transferStep.scheduledMeasuredStartTemperatureC,
      safetyWaitOnly: transferStep.safetyWaitOnly,
      costOperation: transferStep.costOperation,
      costOperationId: transferStep.costOperationId,
      sourceConsumedMoles: totalReceiverMoles - firstConsumedMoles,
      thermalSplit: true,
      thermal: transferStep.thermal,
      recipeGas: transferStep.recipeGas,
      recipeLabel: transferStep.recipeLabel,
      id: transferStep.id,
      sourceInventory: sourceUnlimited
          ? 'unlimited'
          : transferStep.sourceInventory,
      sourceVolumeL: sourceUnlimited ? null : transferStep.sourceVolumeL,
      receiverStartMoles: stage1.moles,
      receiverEndMoles: receiverEndMoles,
      sourceStartMoles: firstSourceMoles,
      sourceEndMoles: sourceEndMoles,
    );
    final wait = _safetyWaitStep(
      pressureReferenceTemperatureC: ambientTemperatureC,
      pressureAtTransferEndReferenceBar: firstReceiverPressureBar,
      pressureBar: firstReceiverPressureBar,
      mix: mix,
      automaticWaitMinutes: 0.0,
    );
    return _SafeStages(first: first, second: second, wait: wait, mix: mix);
  }

  final prefix = steps.sublist(0, unsafeIndex);
  ThermalProtocolResult firstStageSimulationAt(double fraction) =>
      _simulated([...prefix, stagesAt(fraction).first], options);

  double hotEndpointAt(double fraction) {
    final candidate = stagesAt(fraction).first;
    final candidateSimulation = firstStageSimulationAt(fraction);
    final candidateStepCount = candidateSimulation.protocolSteps.length;
    final candidateState = candidateStepCount == 0
        ? null
        : candidateSimulation.protocolSteps.last.thermal;
    return candidateState != null
        ? _hotTransferEndpointPressure(candidateState, candidate, options)
        : double.nan;
  }

  var previousHotEndpoint = double.negativeInfinity;
  for (final fraction in const <double>[0.0, 0.25, 0.5, 0.75, 1.0]) {
    final hotEndpoint = hotEndpointAt(fraction);
    if (!hotEndpoint.isFinite ||
        hotEndpoint + THERMAL_SAFETY_TOLERANCE_BAR < previousHotEndpoint) {
      return null;
    }
    previousHotEndpoint = hotEndpoint;
  }

  bool firstStageSafeAt(double fraction) {
    final candidateSimulation = firstStageSimulationAt(fraction);
    return _firstUnsafeThermalIndex(
          candidateSimulation,
          _numberOrNull(cylinder['workingPressureBar']),
          options,
        ) ==
        -1;
  }

  if (!firstStageSafeAt(0.0)) {
    return null;
  }
  var low = 0.0;
  var high = 1.0;
  if (firstStageSafeAt(1.0)) {
    low = 1.0;
  } else {
    for (var iteration = 0; iteration < 50; iteration++) {
      final middle = (low + high) / 2;
      if (firstStageSafeAt(middle)) {
        low = middle;
      } else {
        high = middle;
      }
    }
  }
  if (!(low > 1e-9)) {
    return null;
  }

  final split = stagesAt(low);
  final firstStageSimulation = firstStageSimulationAt(low);
  final firstStageState = firstStageSimulation.protocolSteps.isEmpty
      ? null
      : firstStageSimulation.protocolSteps.last.thermal;
  if (firstStageState == null) {
    return _SafeTransferSplit(
      first: split.first,
      wait: split.wait,
      second: split.second,
    );
  }
  final hotEndpointBar = firstStageState.pressureAtTransferEndHotBar;
  final targetTemperatureC =
      thermal.targetMediumTemperatureC ??
      thermal.targetTemperatureC ??
      ambientTemperatureC;
  final tauMinutes = coolingTimeConstantMinutes(
    thermal.tankMaterial,
    thermal.coolingMedium,
    thermal.waterSubmersionPercent,
  );
  final splitWaitMinutes =
      (targetTemperatureC - ambientTemperatureC).abs() < 1e-9
      ? 4.6 * tauMinutes
      : calculateCoolingTime(
          transferEndTemperatureC: firstStageState.temperatureAtTransferEndC,
          ambientTemperatureC: ambientTemperatureC,
          targetTemperatureC: targetTemperatureC,
          tauMinutes: tauMinutes,
        );
  final wait = _safetyWaitStep(
    pressureReferenceTemperatureC:
        firstStageState.pressureReferenceTemperatureC,
    pressureAtTransferEndReferenceBar:
        firstStageState.pressureAtTransferEndReferenceBar,
    pressureBar: hotEndpointBar,
    mix: split.mix,
    automaticWaitMinutes: splitWaitMinutes.isFinite
        ? math.max(0.0, splitWaitMinutes)
        : 0.0,
  );
  return _SafeTransferSplit(
    first: split.first,
    wait: wait,
    second: split.second,
  );
}

/// The automatic wait step between two safe transfer stages (JS
/// `wait` object in `splitTransferAtSafeHotEndpoint`).
ProtocolStep _safetyWaitStep({
  required double? pressureReferenceTemperatureC,
  required double? pressureAtTransferEndReferenceBar,
  required double pressureBar,
  required GasMixPercent mix,
  required double automaticWaitMinutes,
}) {
  return ProtocolStep(
    type: 'wait',
    title: 'Automatic wait between safe transfer stages',
    recipeLabel: 'Automatic safety wait',
    measurementIndex: null,
    measurementIndexExplicitNull: true,
    safetyWaitOnly: true,
    pressureReferenceTemperatureC: pressureReferenceTemperatureC,
    pressureAtTransferEndReferenceBar: pressureAtTransferEndReferenceBar,
    receiverStartPressureBar: pressureBar,
    receiverEndPressureBar: pressureBar,
    resultingPressureBar: pressureBar,
    resultingMix: mix,
    receiverStartMix: mix,
    waitMinutes: 0.0,
    automaticWaitMinutes: automaticWaitMinutes,
  );
}

/// A rest sits before the step at `index`: a keep, or the salvage that now
/// stands in for it. Once salvage takes the whole surplus no keep is emitted,
/// so the recipe step follows salvage.
bool _isRestBefore(List<ProtocolStep> steps, int index) {
  if (_protocolStepAt(steps, index - 1)?.type == 'keep') {
    return true;
  }
  return _protocolStepAt(steps, index - 1)?.type == 'salvage' &&
      _protocolStepAt(steps, index)?.type != 'salvage' &&
      _protocolStepAt(steps, index)?.type != 'drain';
}

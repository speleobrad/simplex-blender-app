/// Shared compare-run helpers for the Blending Compare run and the What-if run.
///
/// Port of `compareWaitStates` (`js/main.js` lines 1125-1171). The JS
/// pipeline passes plain objects to `buildCompareProtocol` and
/// `simulateCompareProtocol`; these typed adapters make the same values
/// available to the Dart functions.
library;

import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/compare_recipe.dart';
import 'package:simplex_blender/src/domain/physics.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

/// Typed form of the JS compare `input`: `{ cylinder, physics, thermal, banks,
/// settings }`.
///
/// JS uses one `cylinder` object for both the recipe builder and the
/// simulator. Dart splits it into [CompareCylinder] (recipe builder) and
/// [CylinderInput] (simulator). Callers fill both from the same values.
class CompareRunInputs {
  const CompareRunInputs({
    required this.compareCylinder,
    required this.cylinder,
    required this.physics,
    required this.thermal,
    required this.banks,
    required this.settings,
  });

  final CompareCylinder compareCylinder;
  final CylinderInput cylinder;
  final PhysicsInput physics;
  final ThermalInput thermal;
  final List<Bank> banks;
  final Settings settings;
}

/// JS `settings` subset read by `buildCompareProtocol`: the booster limits and
/// `pressureLimitMode`.
CompareSettings compareSettingsOf(Settings settings) => CompareSettings(
  booster: CompareBoosterSettings(
    minimumSourcePressureBar: settings.booster.minimumSourcePressureBar,
    maxCompressorPressureBar: settings.booster.maxCompressorPressureBar,
    maxBoosterOutputPressureBar: settings.booster.maxBoosterOutputPressureBar,
    oxygenDecantRateBarPerMin: settings.booster.oxygenDecantRateBarPerMin,
    otherDecantRateBarPerMin: settings.booster.otherDecantRateBarPerMin,
    cylinderVolumeCm3: settings.booster.cylinderVolumeCm3,
    oxygenBoostBpm: settings.booster.oxygenBoostBpm,
    otherBoostBpm: settings.booster.otherBoostBpm,
  ),
  pressureLimitMode: settings.pressureLimitMode,
);

/// JS `settings.booster` as read by `simulateCompareProtocol`
/// (`thermalBoosterSettings`). Each absent field falls back to its default
/// inside the simulator.
BoosterSettings boosterSettingsOf(Settings settings) => BoosterSettings(
  cylinderVolumeCm3: settings.booster.cylinderVolumeCm3,
  oxygenBoostBpm: settings.booster.oxygenBoostBpm,
  otherBoostBpm: settings.booster.otherBoostBpm,
  oxygenDecantRateBarPerMin: settings.booster.oxygenDecantRateBarPerMin,
  otherDecantRateBarPerMin: settings.booster.otherDecantRateBarPerMin,
  drainingRateBarPerMin: settings.booster.drainingRateBarPerMin,
  compressorInletFlowLPerMin: settings.booster.compressorInletFlowLPerMin,
  boosterTemperatureModifierC: settings.booster.boosterTemperatureModifierC,
  compressorTemperatureModifierC:
      settings.booster.compressorTemperatureModifierC,
);

/// Adapter: `buildCompareProtocol` returns [CompareStep]; the simulator
/// consumes [ProtocolStep]. Copies every field the simulator reads. JS compare
/// steps never set `sourcePressureBar`, so it stays null here.
ProtocolStep protocolStepOf(CompareStep step) => ProtocolStep(
  type: step.type,
  operation: step.operation,
  title: step.title,
  method: step.method,
  receiverStartPressureBar: step.receiverStartPressureBar,
  receiverEndPressureBar: step.receiverEndPressureBar,
  resultingPressureBar: step.resultingPressureBar,
  resultingMix: step.resultingMix,
  sourceStartPressureBar: step.sourceStartPressureBar,
  sourceEndPressureBar: step.sourceEndPressureBar,
  sourceOxygenPercent: step.sourceOxygenPercent,
  sourceHeliumPercent: step.sourceHeliumPercent,
  waitMode: step.waitMode,
  waitMinutes: step.waitMinutes,
  targetTemperatureC: step.targetTemperatureC,
  costOperation: step.costOperation,
  costOperationId: step.costOperationId,
  sourceConsumedMoles: step.sourceConsumedMoles,
  recipeAction: step.recipeAction,
  recipeGas: step.recipeGas,
  recipeLabel: step.recipeLabel,
  sourceBankId: step.sourceBankId,
  oxygenCompressionRatio: step.oxygenCompressionRatio,
);

/// Port of `compareWaitStates` (`js/main.js` lines 1125-1171).
///
/// For each `wait` row, builds the protocol through that row, simulates it,
/// and records the recipe-end state. The shared map accumulates, so a later
/// wait row sees the states of earlier wait rows, as in JS. A row whose
/// protocol or simulation throws is omitted; the recipe validator reports the
/// underlying row error.
Map<String, CompareWaitState> compareWaitStates(
  CompareRunInputs input,
  List<CompareRow> rows,
) {
  final compareSettings = compareSettingsOf(input.settings);
  final booster = boosterSettingsOf(input.settings);
  final waitStates = <String, CompareWaitState>{};
  for (var index = 0; index < rows.length; index += 1) {
    final row = rows[index];
    if (row.type != 'wait') {
      continue;
    }
    try {
      final protocol = buildCompareProtocol(
        rows.sublist(0, index + 1),
        cylinder: input.compareCylinder,
        physics: input.physics,
        banks: input.banks,
        settings: compareSettings,
        waitStates: waitStates,
      );
      final simulation = simulateCompareProtocol(
        protocolSteps: protocol.protocolSteps.map(protocolStepOf).toList(),
        cylinder: input.cylinder,
        physics: input.physics,
        thermal: input.thermal,
        booster: booster,
      );
      final recipeEnd = simulation.finalSummary.recipeEnd;
      final totalMoles =
          calcMolarDensity(
            recipeEnd.pressureBar,
            recipeEnd.oxygenPercent,
            recipeEnd.heliumPercent,
            recipeEnd.temperatureC,
            input.physics.model == 'vdw',
          ) *
          input.cylinder.volumeL;
      waitStates[row.id] = CompareWaitState(
        pressureBar: recipeEnd.pressureBar,
        temperatureC: recipeEnd.temperatureC,
        totalMoles: totalMoles,
        oxygenMoles: totalMoles * (recipeEnd.oxygenPercent / 100),
        heliumMoles: totalMoles * (recipeEnd.heliumPercent / 100),
        mix: GasMixPercent(
          oxygenPercent: recipeEnd.oxygenPercent,
          heliumPercent: recipeEnd.heliumPercent,
        ),
      );
    } on Object {
      // The recipe validator reports the underlying row error; an unavailable
      // wait state is left out, as in JS.
    }
  }
  return waitStates;
}

/// Port of `comparePressureStarts` (`js/main.js` lines 1173-1189).
///
/// Returns the receiver pressure at the start of each `add` row, keyed by row
/// id. The running pressure follows the rows in order: an `add` row moves it to
/// its normalized target, a `drain` row to its target, and a `wait` row to the
/// pressure its wait state recorded. A value JS would leave `null` or
/// `undefined` is `double.nan` here.
Map<String, double> comparePressureStarts(
  CompareRunInputs input,
  List<CompareRow> rows,
) {
  final starts = <String, double>{};
  final waitStates = compareWaitStates(input, rows);
  var currentPressure = input.cylinder.initialPressureBar ?? double.nan;
  for (final row in rows) {
    if (row.type == 'add') {
      starts[row.id] = currentPressure;
      final normalized = normalizeComparePressureFields(row, currentPressure);
      if (normalized.targetPressureBar.isFinite) {
        currentPressure = normalized.targetPressureBar;
      }
    } else if (row.type == 'drain') {
      final target = row.targetPressureBar;
      if (target != null && target.isFinite) {
        currentPressure = target;
      }
    } else if (row.type == 'wait') {
      final waitPressure = waitStates[row.id]?.pressureBar;
      if (waitPressure != null && waitPressure.isFinite) {
        currentPressure = waitPressure;
      }
    }
  }
  return starts;
}

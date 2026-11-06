import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/compare_recipe.dart';
import 'package:simplex_blender/src/domain/compare_run.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/domain/what_if_scenario.dart';

// Dropped JS cases:
// - "thermal tables classify explicit in-water projections as terminal points"
//   imports js/ui/thermal-charts.js (UI-only).
//
// Dropped JS assertions:
// - `'targetPressureBar' in start` / `'targetOxygenPercent' in start` and the
//   `input.cylinder.targetPressureBar` / `input.thermal.targetInWaterTemperatureC`
//   / `input.thermal.waitMinutes` undefined checks: WhatIfStart and WhatIfInput
//   have no such fields, so absence is enforced by the type.
// - `updated.result === priorResult`: WhatIfScenario has no result field; the
//   result is held by the controller.
// - `result.mode === 'what-if'`: the JS asserts a literal it assigned itself.
// - `result.compare.sourceBanks.length >= 0`: always true for any list.
//
// Adapted inputs:
// - JS `settings.uiOnly` has no Dart counterpart; `units` (not part of the
//   shared payload) is varied instead.
// - JS `physics.temperatureC` in settings: Dart PhysicsSettings carries only
//   `model`, matching js/settings.js which normalizes settings.physics to { model }.
// - JS partial cylinder presets and cylinder objects are full Dart records.
// - Dart validateCompareRecipe requires oxygen/helium start fields; test 9 uses
//   the Blending start values (21 / 0) for them.
//
WhatIfStart snapshotBlending() => snapshotWhatIfFromBlending(
  initialPressureBar: 50,
  initialOxygenPercent: 21,
  initialHeliumPercent: 0,
  cylinderPresetName: 'Catalina S80',
  ambientTemperatureC: 25,
  coolingMedium: 'water',
  waterSubmersionPercent: 40,
  targetInWaterTemperatureC: 10,
);

const CylinderPreset catalinaS80 = CylinderPreset(
  name: 'Catalina S80',
  volumeL: 11.1,
  material: 'aluminum',
  massKg: 14.3,
  workingPressureBar: 207,
  hotOverfillPercent: 2,
);

WhatIfScenario initializedScenario() => createWhatIfScenario().copyWith(
  initialized: true,
  start: snapshotBlending(),
);

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

CompareCylinder compareCylinderOf(WhatIfInput input) => CompareCylinder(
  volumeL: input.cylinderPreset!.volumeL,
  workingPressureBar: input.cylinderPreset!.workingPressureBar,
  initialPressureBar: input.initialPressureBar,
  initialOxygenPercent: input.initialOxygenPercent!,
  initialHeliumPercent: input.initialHeliumPercent!,
);

CylinderInput cylinderInputOf(WhatIfInput input) => CylinderInput(
  volumeL: input.cylinderPreset!.volumeL,
  initialPressureBar: input.initialPressureBar,
  initialOxygenPercent: input.initialOxygenPercent,
  initialHeliumPercent: input.initialHeliumPercent,
);

PhysicsInput physicsInputOf(WhatIfInput input) => PhysicsInput(
  model: input.physicsModel,
  temperatureC: input.physicsTemperatureC!,
);

ThermalInput thermalInputOf(WhatIfInput input) => ThermalInput(
  ambientTemperatureC: input.ambientTemperatureC!,
  tankMaterial: input.tankMaterial,
  coolingMedium: input.coolingMedium,
  waterSubmersionPercent: input.waterSubmersionPercent,
  tankMassKg: input.tankMassKg,
  inletTemperatureC: input.inletTemperatureC,
);

void main() {
  test('snapshots only What-if starting fields and omits all targets', () {
    final start = snapshotBlending();
    expect(start.pressureBar, 50);
    expect(start.oxygenPercent, 21);
    expect(start.heliumPercent, 0);
    expect(start.ambientTemperatureC, 25);
    expect(start.cylinderPresetName, 'Catalina S80');
    expect(start.coolingMedium, 'water');
    expect(start.waterSubmersionPercent, 40);
    expect(start.inWaterTemperatureC, 10);
  });

  test('scenario patches are independent and advance the draft revision', () {
    final initialized = createWhatIfScenario().copyWith(
      initialized: true,
      start: snapshotBlending(),
    );
    final updated = applyWhatIfStartPatch(
      initialized,
      const WhatIfStart(pressureBar: 80),
    );
    expect(updated.start?.pressureBar, 80);
    expect(initialized.start?.pressureBar, 50);
    expect(updated.draftRevision, initialized.draftRevision + 1);
    expect(updated.rows, isNot(same(initialized.rows)));
  });

  test('default What-if step adds Oxygen up to 60 bar from a 45 bar start', () {
    final step = createWhatIfScenario().rows.first;
    expect(step.type, 'add');
    expect(step.bankId, 'bank-oxygen');
    expect(step.pressureInputMode, 'target');
    final normalized = normalizeComparePressureFields(step, 45);
    expect(normalized.targetPressureBar, 60);
    expect(normalized.pressureAddedBar, 15);
  });

  test('scenario input resolves the selected shared cylinder but retains independent start values', () {
    final scenario = createWhatIfScenario().copyWith(
      initialized: true,
      start: snapshotBlending().merge(const WhatIfStart(pressureBar: 80)),
    );
    final settings = copySettings(DEFAULT_SETTINGS).copyWith(
      physics: const PhysicsSettings(model: 'ideal'),
      cylinderPresets: const <CylinderPreset>[catalinaS80],
    );
    final input = buildWhatIfInput(
      scenario,
      settings: settings,
      banks: const <Bank>[],
      inletTemperatureC: 33,
    );
    expect(input.initialPressureBar, 80);
    expect(input.cylinderPreset?.volumeL, 11.1);
    expect(input.tankMaterial, 'aluminum');
    expect(input.tankMassKg, 14.3);
    expect(input.inWaterTemperatureC, 10);
    expect(input.waterSubmersionPercent, 40);
    expect(input.inletTemperatureC, 33);
  });

  test('in-water projection uses the explicit scenario temperature', () {
    final projection = projectWhatIfInWater(
      const StateSnapshot(
        pressureBar: 200,
        temperatureC: 25,
        oxygenPercent: 18,
        heliumPercent: 45,
      ),
      inWaterTemperatureC: 10,
      volumeL: 11.1,
      useVdw: false,
    );
    expect(projection.temperatureC, 10);
    expect(projection.pressureBar, lessThan(200));
    expect(projection.oxygenPercent, 18);
    expect(projection.heliumPercent, 45);
  });

  test('signatures track draft behavior and shared behavior only', () {
    final scenario = initializedScenario();
    final edited = applyWhatIfStartPatch(
      scenario,
      const WhatIfStart(pressureBar: 81),
    );
    expect(whatIfDraftSignature(scenario), isNot(whatIfDraftSignature(edited)));

    final reordered = scenario.copyWith(
      rows: <CompareRow>[...scenario.rows.reversed, scenario.rows.first],
    );
    expect(
      whatIfDraftSignature(scenario),
      isNot(whatIfDraftSignature(reordered)),
    );

    final settings = copySettings(DEFAULT_SETTINGS)
        .copyWith(physics: const PhysicsSettings(model: 'ideal'));
    final shared = whatIfSharedInputSignature(
      settings: settings,
      banks: const <Bank>[],
      cylinderPresetName: 'Catalina S80',
    );
    // JS "uiOnly" variant: `units` is outside the shared payload, so it must
    // not change the shared signature.
    expect(
      shared,
      whatIfSharedInputSignature(
        settings: settings.copyWith(units: 'imperial'),
        banks: const <Bank>[],
        cylinderPresetName: 'Catalina S80',
      ),
    );
    expect(
      shared,
      isNot(
        whatIfSharedInputSignature(
          settings: settings,
          banks: const <Bank>[
            Bank(
              id: 'b',
              name: 'b',
              volumeL: 1,
              pressureBar: 200,
              oxygenPercent: 21,
              heliumPercent: 0,
              enabled: true,
            ),
          ],
          cylinderPresetName: 'Catalina S80',
        ),
      ),
    );
  });

  test(
    'assembles the complete What-if result contract through an explicit wait',
    () {
      final settings = copySettings(DEFAULT_SETTINGS).copyWith(
        physics: const PhysicsSettings(model: 'ideal'),
        cylinderPresets: const <CylinderPreset>[catalinaS80],
        booster: DEFAULT_SETTINGS.booster.copyWith(
          drainingRateBarPerMin: 5,
          oxygenDecantRateBarPerMin: 5,
          otherDecantRateBarPerMin: 5,
        ),
      );
      final scenario = initializedScenario().copyWith(
        rows: const <CompareRow>[
          CompareRow(id: 'drain', type: 'drain', targetPressureBar: 20),
          CompareRow(
            id: 'wait',
            type: 'wait',
            waitMode: 'minutes',
            waitMinutes: 7,
            targetTemperatureC: null,
          ),
        ],
      );
      final input = buildWhatIfInput(
        scenario,
        settings: settings,
        banks: const <Bank>[],
      );
      final protocol = buildCompareProtocol(
        scenario.rows,
        cylinder: compareCylinderOf(input),
        physics: physicsInputOf(input),
        banks: input.banks,
        settings: compareSettingsOf(settings),
      );
      final simulation = simulateCompareProtocol(
        protocolSteps: [
          for (final step in protocol.protocolSteps) protocolStepOf(step),
        ],
        cylinder: cylinderInputOf(input),
        physics: physicsInputOf(input),
        thermal: thermalInputOf(input),
        booster: boosterSettingsOf(settings),
      );
      final inWater = projectWhatIfInWater(
        simulation.finalSummary.ambientSettled,
        inWaterTemperatureC: input.inWaterTemperatureC!,
        volumeL: input.cylinderPreset!.volumeL,
        useVdw: false,
      );
      expect(inWater.temperatureC, 10);
      expect(inWater.pressureBar.isFinite, isTrue);
    },
  );

  test('excludes helium from a 98%-helium What-if source bank', () {
    final protocol = buildCompareProtocol(
      const <CompareRow>[
        CompareRow(
          id: 'add-98-helium',
          type: 'add',
          bankId: 'bank-98-helium',
          pressureInputMode: 'target',
          pressureAddedBar: 50,
          targetPressureBar: 100,
        ),
      ],
      cylinder: const CompareCylinder(
        volumeL: 12,
        workingPressureBar: 232,
        initialPressureBar: 50,
        initialOxygenPercent: 21,
        initialHeliumPercent: 0,
      ),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 20),
      banks: const <Bank>[
        Bank(
          id: 'bank-98-helium',
          name: '98% helium',
          volumeL: 50,
          pressureBar: 200,
          oxygenPercent: 0,
          heliumPercent: 98,
          enabled: true,
        ),
      ],
    );
    expect(protocol.summary.heliumSalvagedLitres, 0);
  });

  test('invalid scenario rows preserve the prior result while reporting row errors', () {
    final scenario = initializedScenario();
    final updated = scenario.copyWith(
      rows: const <CompareRow>[CompareRow(id: 'invalid-row', type: 'unknown')],
      draftRevision: scenario.draftRevision + 1,
    );
    final validation = validateCompareRecipe(
      updated.rows,
      cylinder: const CompareCylinder(
        volumeL: 11.1,
        workingPressureBar: 207,
        initialPressureBar: 50,
        initialOxygenPercent: 21,
        initialHeliumPercent: 0,
      ),
      physics: const PhysicsInput(model: 'ideal', temperatureC: 25),
      settings: const CompareSettings(booster: CompareBoosterSettings()),
    );
    expect(updated.draftRevision, 1);
    expect(validation.valid, isFalse);
    expect(validation.errors.first.rowId, 'invalid-row');
  });

  test('shared signatures change when What-if equipment or pressure policy changes', () {
    final base = copySettings(DEFAULT_SETTINGS).copyWith(
      physics: const PhysicsSettings(model: 'ideal'),
      cylinderPresets: const <CylinderPreset>[
        CylinderPreset(
          name: 'Catalina S80',
          volumeL: 11.1,
          material: 'aluminum',
          massKg: 14.3,
          workingPressureBar: 207,
          hotOverfillPercent: 2,
        ),
      ],
      pressureLimitMode: 'hard-stop',
      booster: DEFAULT_SETTINGS.booster.copyWith(
        drainingRateBarPerMin: 5,
        oxygenBoostBpm: 35,
        boosterTemperatureModifierC: 4,
        maxBoosterOutputPressureBar: 300,
      ),
    );
    String shared(Settings settings, {double inletTemperatureC = 25}) =>
        whatIfSharedInputSignature(
          settings: settings,
          banks: const <Bank>[],
          cylinderPresetName: 'Catalina S80',
          inletTemperatureC: inletTemperatureC,
        );

    final signature = shared(base);
    final changedEquipment = shared(
      base.copyWith(booster: base.booster.copyWith(drainingRateBarPerMin: 6)),
    );
    final changedPolicy = shared(base.copyWith(pressureLimitMode: 'warning'));
    final changedInlet = shared(base, inletTemperatureC: 26);
    expect(signature, isNot(changedEquipment));
    expect(signature, isNot(changedPolicy));
    expect(signature, isNot(changedInlet));
  });

  test(
    'What-if scenario transfers keep cost operation fields through simulation',
    () {
      final settings = copySettings(DEFAULT_SETTINGS).copyWith(
        physics: const PhysicsSettings(model: 'ideal'),
        cylinderPresets: const <CylinderPreset>[catalinaS80],
        booster: DEFAULT_SETTINGS.booster.copyWith(
          drainingRateBarPerMin: 5,
          oxygenDecantRateBarPerMin: 5,
          otherDecantRateBarPerMin: 5,
          oxygenBoostBpm: 35,
          otherBoostBpm: 50,
          compressorInletFlowLPerMin: 100,
        ),
      );
      const banks = <Bank>[
        Bank(
          id: 'bank-oxygen',
          name: 'Oxygen',
          volumeL: 50,
          pressureBar: 200,
          oxygenPercent: 100,
          heliumPercent: 0,
          enabled: true,
        ),
      ];
      final scenario = initializedScenario();
      final input = buildWhatIfInput(
        scenario,
        settings: settings,
        banks: banks,
        inletTemperatureC: 25,
      );
      final validation = validateCompareRecipe(
        scenario.rows,
        cylinder: compareCylinderOf(input),
        banks: input.banks,
        physics: physicsInputOf(input),
        settings: compareSettingsOf(settings),
      );
      expect(validation.valid, isTrue);
      final protocol = buildCompareProtocol(
        validation.normalizedRows,
        cylinder: compareCylinderOf(input),
        physics: physicsInputOf(input),
        banks: input.banks,
        settings: compareSettingsOf(settings),
      );
      final simulation = simulateCompareProtocol(
        protocolSteps: [
          for (final step in protocol.protocolSteps) protocolStepOf(step),
        ],
        cylinder: cylinderInputOf(input),
        physics: physicsInputOf(input),
        thermal: thermalInputOf(input),
        booster: boosterSettingsOf(settings),
      );
      final costed = simulation.protocolSteps
          .where((step) => step.costOperation != null)
          .toList();
      expect(costed, isNotEmpty);
      for (final step in costed) {
        expect(step.costOperationId, matches(RegExp(r'^op-\d+$')));
        expect(step.sourceConsumedMoles!, greaterThan(0));
      }
    },
  );

  test(
    'what-if shared signature ignores bank cost prices but not bank pressure',
    () {
      final settings = copySettings(DEFAULT_SETTINGS).copyWith(
        physics: const PhysicsSettings(model: 'ideal'),
        cylinderPresets: const <CylinderPreset>[],
        pressureLimitMode: 'hard-stop',
      );
      String shared(List<Bank> banks, [Settings? override]) =>
          whatIfSharedInputSignature(
            settings: override ?? settings,
            banks: banks,
            cylinderPresetName: 'X',
            inletTemperatureC: 25,
          );

      const bank = Bank(
        id: 'o2',
        name: 'o2',
        volumeL: 1,
        pressureBar: 200,
        oxygenPercent: 100,
        heliumPercent: 0,
        enabled: true,
        pricePerLitre: 0.02,
      );
      const repriced = Bank(
        id: 'o2',
        name: 'o2',
        volumeL: 1,
        pressureBar: 200,
        oxygenPercent: 100,
        heliumPercent: 0,
        enabled: true,
        pricePerLitre: 3,
      );
      const unpriced = Bank(
        id: 'o2',
        name: 'o2',
        volumeL: 1,
        pressureBar: 200,
        oxygenPercent: 100,
        heliumPercent: 0,
        enabled: true,
      );
      const lowerPressure = Bank(
        id: 'o2',
        name: 'o2',
        volumeL: 1,
        pressureBar: 180,
        oxygenPercent: 100,
        heliumPercent: 0,
        enabled: true,
      );

      expect(shared(const <Bank>[bank]), shared(const <Bank>[repriced]));
      expect(shared(const <Bank>[bank]), shared(const <Bank>[unpriced]));
      expect(
        shared(const <Bank>[bank]),
        isNot(shared(const <Bank>[lowerPressure])),
      );
      expect(
        shared(
          const <Bank>[bank],
          settings.copyWith(
            booster: settings.booster.copyWith(otherBoostBpm: 9),
          ),
        ),
        isNot(shared(const <Bank>[bank])),
      );
    },
  );

  test(
    'a present invalid What-if wait remains invalid instead of becoming zero',
    () {
      final first = createCompareRow('add', 'a');
      final rows = <CompareRow>[
        CompareRow(
          id: first.id,
          type: first.type,
          bankId: first.bankId,
          pressureAddedBar: first.pressureAddedBar,
          targetPressureBar: first.targetPressureBar,
          pressureInputMode: first.pressureInputMode,
          waitMinutes: double.nan,
        ),
        createCompareRow('add', 'b'),
      ];
      final wait = expandWhatIfRows(rows)
          .firstWhere((row) => row.type == 'wait');
      expect(wait.waitMinutes!.isFinite, isFalse);
    },
  );

  test('an omitted What-if wait still defaults to zero minutes', () {
    final rows = <CompareRow>[
      createCompareRow('add', 'a'),
      createCompareRow('add', 'b'),
    ];
    final wait = expandWhatIfRows(rows).firstWhere((row) => row.type == 'wait');
    expect(wait.waitMinutes, 0);
  });
}

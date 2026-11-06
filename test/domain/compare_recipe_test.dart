import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/compare_recipe.dart';
import 'package:simplex_blender/src/domain/physics.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

const CompareCylinder cylinder = CompareCylinder(
  volumeL: 12,
  workingPressureBar: 232,
  initialPressureBar: 50,
  initialOxygenPercent: 21,
  initialHeliumPercent: 0,
);

const PhysicsInput physics = PhysicsInput(model: 'ideal', temperatureC: 20);

const CompareSettings settings = CompareSettings(
  booster: CompareBoosterSettings(
    minimumSourcePressureBar: 5,
    maxCompressorPressureBar: 232,
    maxBoosterOutputPressureBar: 300,
    oxygenDecantRateBarPerMin: 5,
    otherDecantRateBarPerMin: 10,
    oxygenBoostBpm: 35,
    otherBoostBpm: 50,
  ),
);

const Bank heBank = Bank(
  id: 'he-bank',
  name: 'Helium supply',
  volumeL: 40,
  pressureBar: 200,
  oxygenPercent: 0,
  heliumPercent: 100,
  enabled: true,
);

const Bank disabledO2 = Bank(
  id: 'disabled-o2',
  name: 'Disabled oxygen',
  volumeL: 40,
  pressureBar: 200,
  oxygenPercent: 100,
  heliumPercent: 0,
  enabled: false,
);

const List<Bank> banks = [heBank, disabledO2];

const CompareRow compressorRow = CompareRow(
  id: 'air',
  type: 'add',
  bankId: 'compressor-air',
  pressureAddedBar: 150,
  targetPressureBar: 200,
  pressureInputMode: 'target',
);

const CompareRow heliumRow = CompareRow(
  id: 'add',
  type: 'add',
  bankId: 'he-bank',
  pressureAddedBar: 150,
  targetPressureBar: 200,
  pressureInputMode: 'target',
);

CompareRow addRow(
  String id,
  String bankId, {
  required double added,
  required double target,
  String mode = 'target',
}) {
  return CompareRow(
    id: id,
    type: 'add',
    bankId: bankId,
    pressureAddedBar: added,
    targetPressureBar: target,
    pressureInputMode: mode,
  );
}

CompareRecipeValidation validateRows(
  List<CompareRow> rows, {
  CompareCylinder cylinderInput = cylinder,
  List<Bank> bankList = banks,
  CompareSettings? settingsInput = settings,
}) {
  return validateCompareRecipe(
    rows,
    cylinder: cylinderInput,
    banks: bankList,
    physics: physics,
    settings: settingsInput,
  );
}

CompareProtocol buildRows(
  List<CompareRow> rows, {
  CompareCylinder cylinderInput = cylinder,
  List<Bank> bankList = banks,
  CompareSettings? settingsInput = settings,
  Map<String, CompareWaitState> waitStates = const <String, CompareWaitState>{},
}) {
  return buildCompareProtocol(
    rows,
    cylinder: cylinderInput,
    physics: physics,
    banks: bankList,
    settings: settingsInput,
    waitStates: waitStates,
  );
}

CompareProtocol planCompare(List<CompareRow> rows) {
  return buildRows(validateRows(rows).normalizedRows);
}

bool hasError(
  CompareRecipeValidation result, {
  String? rowId,
  required String field,
}) {
  return result.errors.any(
    (error) => error.field == field && (rowId == null || error.rowId == rowId),
  );
}

void main() {
  test('an add row at the current pressure is represented as a no-op', () {
    final protocol = planCompare([
      addRow('no-op', 'he-bank', added: 0, target: 50),
    ]);

    expect(protocol.protocolSteps, hasLength(1));
    expect(protocol.protocolSteps[0].type, 'keep');
    expect(protocol.protocolSteps[0].costOperation, isNull);
    expect(protocol.sourceBanks, isEmpty);
  });

  test('creates a drain row with a target pressure', () {
    final row = createCompareRow('drain', 'row-1');

    expect(row.id, 'row-1');
    expect(row.type, 'drain');
    expect(row.targetPressureBar, 0);
    expect(row.bankId, isNull);
    expect(row.pressureAddedBar, isNull);
  });

  test(
    'models a drain step at its target pressure while preserving gas mix',
    () {
      final protocol = buildRows(const [
        CompareRow(id: 'drain', type: 'drain', targetPressureBar: 20),
      ]);

      expect(protocol.protocolSteps, hasLength(1));
      final step = protocol.protocolSteps[0];
      expect(step.type, 'drain');
      expect(step.resultingPressureBar, closeTo(20, 1e-9));
      expect(step.resultingMix.oxygenPercent, closeTo(21, 1e-9));
      expect(step.resultingMix.heliumPercent, closeTo(0, 1e-9));
    },
  );

  test('accepts unlimited compressor Air without a supply-bank record', () {
    final validation = validateRows([compressorRow]);

    expect(validation.valid, isTrue);
    final air = validation.normalizedRows[0].sourceBank!;
    expect(air.id, 'compressor-air');
    expect(air.name, 'Compressor Air');
    expect(air.volumeL, 1);
    expect(air.pressureBar, 232);
    expect(air.oxygenPercent, 21);
    expect(air.heliumPercent, 0);
    expect(air.enabled, isTrue);
    expect(air.isCompressor, isTrue);

    final protocol = buildRows(validation.normalizedRows);
    expect(
      protocol.protocolSteps
          .map((s) => [s.type, s.method, s.operation])
          .toList(),
      [
        ['add', 'compressor', 'Top-up'],
      ],
    );
    expect(protocol.protocolSteps[0].sourceBankId, 'compressor-air');
    expect(protocol.protocolSteps[0].sourceEndPressureBar, isNull);
    expect(banks, hasLength(2));
  });

  test('reports deterministic finite source-bank summaries and excludes unused banks', () {
    final protocol = planCompare([
      addRow('add-he', 'he-bank', added: 150, target: 200),
    ]);

    expect(protocol.sourceBanks.map((b) => b.id).toList(), ['he-bank']);
    expect(protocol.sourceBanks[0].initial.pressureBar, 200);
    expect(protocol.sourceBanks[0].finalState.pressureBar!, lessThan(200));
    expect(heBank.pressureBar, 200);
    expect(protocol.sourceBanks.any((b) => b.id == 'disabled-o2'), isFalse);
  });

  test(
    'reports Compressor Air composition without finite inventory depletion',
    () {
      final protocol = planCompare([compressorRow]);

      expect(protocol.sourceBanks, hasLength(1));
      final summary = protocol.sourceBanks[0];
      expect(summary.id, 'compressor-air');
      expect(summary.name, 'Compressor Air');
      for (final snapshot in [summary.initial, summary.finalState]) {
        expect(snapshot.pressureBar, isNull);
        expect(snapshot.moles, isNull);
        expect(snapshot.oxygenPercent, 21);
        expect(snapshot.heliumPercent, 0);
      }
    },
  );

  test('creates independent keep rows', () {
    final first = createCompareRow('keep', 'row-1');
    final second = createCompareRow('keep', 'row-2');

    expect(first.id, 'row-1');
    expect(first.type, 'keep');
    expect(second.id, 'row-2');
    expect(second.type, 'keep');
    expect(second, isNot(same(first)));
  });

  test('creates a bank-backed add row and target-state wait row', () {
    final add = createCompareRow('add', 'row-1');

    expect(add.id, 'row-1');
    expect(add.type, 'add');
    expect(add.bankId, isNull);
    expect(add.pressureAddedBar, 0);
    expect(add.targetPressureBar, 0);
    expect(add.pressureInputMode, 'added');

    final wait = createCompareRow('wait', 'row-2');

    expect(wait.id, 'row-2');
    expect(wait.type, 'wait');
    expect(wait.waitMode, 'minutes');
    expect(wait.waitMinutes, 0);
    expect(wait.targetTemperatureC, isNull);
  });

  test('rejects an add row that does not select an enabled supply bank', () {
    final result = validateRows([
      addRow('add', 'missing', added: 50, target: 100, mode: 'added'),
    ]);

    expect(result.valid, isFalse);
    expect(hasError(result, field: 'bankId'), isTrue);
  });

  test('rejects disabled and duplicate supply bank IDs', () {
    final disabled = validateRows([
      addRow('add', 'disabled-o2', added: 50, target: 100, mode: 'added'),
    ]);

    expect(disabled.valid, isFalse);
    expect(hasError(disabled, field: 'bankId'), isTrue);

    final duplicateBanks = [...banks, heBank];
    final duplicate = validateRows([
      addRow('add', 'he-bank', added: 50, target: 100, mode: 'added'),
    ], bankList: duplicateBanks);

    expect(duplicate.valid, isFalse);
    expect(hasError(duplicate, field: 'bankId'), isTrue);
  });

  test(
    'synchronizes pressure-added and receiver-target values from the row start',
    () {
      final result = normalizeComparePressureFields(
        const CompareRow(
          id: 'row',
          type: 'add',
          pressureAddedBar: 100,
          targetPressureBar: 150,
          pressureInputMode: 'target',
        ),
        50,
      );

      expect(result.pressureAddedBar, 100);
      expect(result.targetPressureBar, 150);
      expect(result.pressureInputMode, 'target');
    },
  );

  test('normalizes an added-pressure row against the prior receiver state', () {
    final result = validateRows([
      addRow('add', 'he-bank', added: 50, target: 0, mode: 'added'),
    ]);

    expect(result.valid, isTrue);
    expect(result.normalizedRows[0].targetPressureBar, 100);
    expect(result.normalizedRows[0].pressureAddedBar, 50);
  });

  test(
    'plans decant equalize and boost stages without mutating bank inventory',
    () {
      final protocol = planCompare([
        addRow('add', 'he-bank', added: 150, target: 200),
      ]);
      final steps = protocol.protocolSteps;

      expect(steps.map((s) => s.type).toList(), ['equalize', 'boost']);
      expect(steps.every((s) => s.compareRowId == 'add'), isTrue);
      expect(steps.every((s) => s.sourceBankId == 'he-bank'), isTrue);
      expect(steps.every((s) => s.sourceStartPressureBar!.isFinite), isTrue);
      expect(steps.every((s) => s.sourceEndPressureBar!.isFinite), isTrue);
      expect(
        steps.last.sourceEndPressureBar!,
        lessThan(steps.first.sourceStartPressureBar!),
      );
      expect(heBank.pressureBar, 200);
    },
  );

  test('keeps wait and keep rows between planned transfer stages', () {
    final protocol = buildRows(const [
      CompareRow(id: 'keep', type: 'keep'),
      CompareRow(
        id: 'wait',
        type: 'wait',
        waitMode: 'minutes',
        waitMinutes: 5,
        targetPressureBar: null,
        targetTemperatureC: null,
      ),
      CompareRow(
        id: 'add',
        type: 'add',
        bankId: 'he-bank',
        pressureAddedBar: 50,
        targetPressureBar: 100,
        pressureInputMode: 'added',
      ),
    ]);
    final steps = protocol.protocolSteps;

    expect(steps.map((s) => s.type).toList(), ['keep', 'wait', 'decant']);
    expect(steps[1].waitMinutes, 5);
  });

  test('rejects a finite bank that cannot supply the requested addition', () {
    const smallBank = Bank(
      id: 'small-he',
      name: 'Small helium',
      volumeL: 2,
      pressureBar: 20,
      oxygenPercent: 0,
      heliumPercent: 100,
      enabled: true,
    );

    expect(
      () => buildRows(
        [addRow('add', 'small-he', added: 170, target: 220)],
        bankList: const [smallBank],
      ),
      throwsA(
        predicate(
          (error) => error.toString().toLowerCase().contains('supply bank'),
        ),
      ),
    );
  });

  test('plans an add after a wait from the modeled post-wait pressure', () {
    final protocol = buildRows(
      [
        const CompareRow(
          id: 'wait',
          type: 'wait',
          waitMode: 'minutes',
          waitMinutes: 10,
        ),
        addRow('add', 'he-bank', added: 0, target: 100),
      ],
      waitStates: {'wait': const CompareWaitState(pressureBar: 45)},
    );

    final add = protocol.protocolSteps.firstWhere(
      (s) => s.compareRowId == 'add',
    );
    expect(add.receiverStartPressureBar, 45);
  });

  test('uses the full modeled wait state when planning a following add', () {
    final totalMoles =
        calcMolarDensity(45, 21, 0, 15, false) * cylinder.volumeL;
    final waitState = CompareWaitState(
      pressureBar: 45,
      temperatureC: 15,
      totalMoles: totalMoles,
      oxygenMoles: totalMoles * 0.21,
      heliumMoles: 0,
      mix: const GasMixPercent(oxygenPercent: 21, heliumPercent: 0),
    );
    final rows = [
      const CompareRow(
        id: 'wait',
        type: 'wait',
        waitMode: 'minutes',
        waitMinutes: 10,
      ),
      addRow('add', 'he-bank', added: 0, target: 100),
    ];

    final partial = buildRows(
      rows,
      waitStates: {'wait': const CompareWaitState(pressureBar: 45)},
    );
    final full = buildRows(rows, waitStates: {'wait': waitState});

    final partialAdd = partial.protocolSteps.firstWhere(
      (s) => s.compareRowId == 'add',
    );
    final fullAdd = full.protocolSteps.firstWhere(
      (s) => s.compareRowId == 'add',
    );
    expect(
      fullAdd.resultingMix.heliumPercent,
      greaterThan(partialAdd.resultingMix.heliumPercent),
    );
  });

  test('consumes finite source moles at the modeled wait temperature for a following add', () {
    const waitTemperatureC = 15.0;
    final totalMoles =
        calcMolarDensity(45, 21, 0, waitTemperatureC, false) * cylinder.volumeL;
    final protocol = buildRows(
      [
        const CompareRow(
          id: 'wait',
          type: 'wait',
          waitMode: 'minutes',
          waitMinutes: 10,
        ),
        addRow('add', 'he-bank', added: 0, target: 100),
      ],
      waitStates: {
        'wait': CompareWaitState(
          pressureBar: 45,
          temperatureC: waitTemperatureC,
          totalMoles: totalMoles,
          oxygenMoles: totalMoles * 0.21,
          heliumMoles: 0,
          mix: const GasMixPercent(oxygenPercent: 21, heliumPercent: 0),
        ),
      },
    );

    final add = protocol.protocolSteps.firstWhere(
      (s) => s.compareRowId == 'add',
    );
    final initialSourceMoles =
        calcMolarDensity(200, 0, 100, physics.temperatureC, false) * 40;
    final expectedAddedMoles =
        (calcMolarDensity(100, 0, 100, waitTemperatureC, false) -
            calcMolarDensity(45, 21, 0, waitTemperatureC, false)) *
        cylinder.volumeL;
    expect(
      add.sourceMolesAfter!,
      closeTo(initialSourceMoles - expectedAddedMoles, 1e-9),
    );
  });

  test('accepts a target-temperature wait without a target pressure', () {
    final result = validateRows([
      const CompareRow(
        id: 'wait',
        type: 'wait',
        waitMode: 'target',
        targetTemperatureC: 20,
      ),
    ]);

    expect(result.valid, isTrue);
    expect(result.errors, isEmpty);
  });

  test('rejects pressure modes that would reduce receiver pressure or exceed the limit', () {
    final result = validateRows([
      addRow('low', 'he-bank', added: -1, target: 49, mode: 'added'),
      addRow('high', 'he-bank', added: 301, target: 351, mode: 'added'),
    ]);

    expect(result.valid, isFalse);
    expect(hasError(result, rowId: 'low', field: 'pressureAddedBar'), isTrue);
    expect(hasError(result, rowId: 'high', field: 'targetPressureBar'), isTrue);
  });

  test(
    'rejects an add target above the configured cylinder working pressure',
    () {
      final result = validateRows([
        addRow('over-working-pressure', 'he-bank', added: 183, target: 233),
      ]);

      expect(result.valid, isFalse);
      expect(
        result.errors.any(
          (error) =>
              error.rowId == 'over-working-pressure' &&
              error.field == 'targetPressureBar' &&
              RegExp(
                r'working pressure',
                caseSensitive: false,
              ).hasMatch(error.message),
        ),
        isTrue,
      );
    },
  );

  test('Compare Warning mode bypasses only cylinder pressure', () {
    const warningSettings = CompareSettings(
      booster: CompareBoosterSettings(
        minimumSourcePressureBar: 5,
        maxCompressorPressureBar: 232,
        maxBoosterOutputPressureBar: 300,
        oxygenDecantRateBarPerMin: 5,
        otherDecantRateBarPerMin: 10,
        oxygenBoostBpm: 35,
        otherBoostBpm: 50,
      ),
      pressureLimitMode: 'warning',
    );
    const warningCylinder = CompareCylinder(
      volumeL: 12,
      workingPressureBar: 100,
      initialPressureBar: 50,
      initialOxygenPercent: 21,
      initialHeliumPercent: 0,
    );
    const warningCylinder110 = CompareCylinder(
      volumeL: 12,
      workingPressureBar: 100,
      initialPressureBar: 110,
      initialOxygenPercent: 21,
      initialHeliumPercent: 0,
    );
    final addAt150 = addRow(
      'warning-add',
      'compressor-air',
      added: 100,
      target: 150,
    );

    final validation = validateRows(
      [addAt150],
      cylinderInput: warningCylinder,
      settingsInput: warningSettings,
    );
    expect(validation.valid, isTrue);

    final protocol = buildRows(
      [addAt150],
      cylinderInput: warningCylinder,
      settingsInput: warningSettings,
    );
    expect(protocol.trajectory.last.pressureBar, 150);

    final keepProtocol = buildRows(
      const [CompareRow(id: 'keep', type: 'keep')],
      cylinderInput: warningCylinder110,
      settingsInput: warningSettings,
    );
    expect(keepProtocol.trajectory[0].pressureBar, 110);

    final overCompressor = validateRows(
      [addRow('warning-add', 'compressor-air', added: 183, target: 233)],
      cylinderInput: warningCylinder,
      settingsInput: warningSettings,
    );
    expect(
      overCompressor.errors.any(
        (error) => RegExp(
          r'Compressor Air.*232 bar',
          caseSensitive: false,
        ).hasMatch(error.message),
      ),
      isTrue,
    );

    final overLimit = validateRows(
      [addRow('warning-add', 'compressor-air', added: 301, target: 351)],
      cylinderInput: warningCylinder,
      settingsInput: warningSettings,
    );
    expect(
      overLimit.errors.any(
        (error) => RegExp(
          r'between 0 and 350 bar',
          caseSensitive: false,
        ).hasMatch(error.message),
      ),
      isTrue,
    );
  });

  test('carries configured decant and booster rates on planned stages', () {
    final protocol = planCompare([
      addRow('add', 'he-bank', added: 150, target: 200),
    ]);
    final steps = protocol.protocolSteps;
    final equalize = steps[0];
    final boost = steps[1];

    final equalizeRate = equalize.transferRate!;
    expect(equalizeRate.source, 'decant');
    expect(equalizeRate.rateBarPerMin, 10);
    expect(
      equalizeRate.estimatedDurationMinutes!,
      closeTo(
        (equalize.receiverEndPressureBar - equalize.receiverStartPressureBar) /
            10,
        1e-12,
      ),
    );

    final boostRate = boost.transferRate!;
    expect(boostRate.source, 'booster');
    expect(boostRate.boosterBpm, 50);
    expect(boostRate.boosterCylinderVolumeCm3, 9);
    expect(boostRate.rateBarPerMin!.isFinite, isTrue);
    expect(boostRate.estimatedDurationMinutes!.isFinite, isTrue);
  });

  test(
    'reports the oxygen boost ratio for source gas above 40 percent oxygen',
    () {
      const oxygenRichBank = Bank(
        id: 'ean-50',
        name: 'EAN 50',
        volumeL: 50,
        pressureBar: 200,
        oxygenPercent: 50,
        heliumPercent: 0,
        enabled: true,
      );
      final protocol = buildRows(
        [addRow('oxygen-add', 'ean-50', added: 250, target: 300)],
        cylinderInput: const CompareCylinder(
          volumeL: 12,
          workingPressureBar: 350,
          initialPressureBar: 50,
          initialOxygenPercent: 21,
          initialHeliumPercent: 0,
        ),
        bankList: const [oxygenRichBank],
        settingsInput: const CompareSettings(
          booster: CompareBoosterSettings(
            minimumSourcePressureBar: 5,
            maxCompressorPressureBar: 232,
            maxBoosterOutputPressureBar: 350,
            oxygenDecantRateBarPerMin: 5,
            otherDecantRateBarPerMin: 10,
            oxygenBoostBpm: 35,
            otherBoostBpm: 50,
          ),
        ),
      );

      final boostSteps = protocol.protocolSteps
          .where((s) => s.type == 'boost')
          .toList();
      expect(boostSteps, isNotEmpty);
      final boost = boostSteps.first;
      expect(boost.oxygenCompressionRatio, isNotNull);
      expect(
        boost.oxygenCompressionRatio!,
        closeTo(
          boost.receiverEndPressureBar / boost.sourceEndPressureBar!,
          1e-12,
        ),
      );
    },
  );

  test('rejects a selected supply bank without a name', () {
    const namelessBank = Bank(
      id: 'nameless',
      name: '',
      volumeL: 40,
      pressureBar: 200,
      oxygenPercent: 0,
      heliumPercent: 100,
      enabled: true,
    );
    final result = validateRows(
      [addRow('add', 'nameless', added: 50, target: 100, mode: 'added')],
      bankList: const [namelessBank],
    );

    expect(result.valid, isFalse);
    expect(hasError(result, field: 'bankId'), isTrue);
  });

  test('compare steps carry cost fields; compressor add is topUp', () {
    final protocol = planCompare([compressorRow]);
    final costed = protocol.protocolSteps
        .where((step) => step.costOperation != null)
        .toList();

    expect(costed, hasLength(1));
    expect(costed[0].costOperation, 'topUp');
    for (final step in costed) {
      expect(step.sourceConsumedMoles!, greaterThan(0));
      expect(step.costOperationId, matches(RegExp(r'^op-\d+$')));
    }
  });

  test('equalize then boost are two operations whose moles sum to the required moles', () {
    final protocol = planCompare([heliumRow]);
    final costed = protocol.protocolSteps
        .where((step) => step.costOperation != null)
        .toList();
    expect(costed, hasLength(2));
    final equalize = costed[0];
    final boost = costed[1];

    expect(equalize.costOperation, 'equalize');
    expect(boost.costOperation, 'boost');
    expect(equalize.costOperationId, isNot(boost.costOperationId));

    final requiredMoles =
        calcMolarDensity(200, 0, 100, physics.temperatureC, false) * 40 -
        calcMolarDensity(
              protocol.protocolSteps.last.sourceEndPressureBar!,
              0,
              100,
              physics.temperatureC,
              false,
            ) *
            40;
    expect(
      equalize.sourceConsumedMoles! + boost.sourceConsumedMoles!,
      closeTo(requiredMoles, 1e-6),
    );
  });

  test('source consumed moles match the finite source pressure drop', () {
    final protocol = planCompare([heliumRow]);
    final costed = protocol.protocolSteps
        .where((step) => step.costOperation != null)
        .toList();
    final consumed = costed.fold<double>(
      0,
      (sum, step) => sum + step.sourceConsumedMoles!,
    );
    final bankStart =
        calcMolarDensity(200, 0, 100, physics.temperatureC, false) * 40;
    final bankEnd =
        calcMolarDensity(
          protocol.protocolSteps.last.sourceEndPressureBar!,
          0,
          100,
          physics.temperatureC,
          false,
        ) *
        40;
    expect(consumed, closeTo(bankStart - bankEnd, 1e-6));
  });

  test('compare summary reports retained helium ungated for a 98% helium initial mix', () {
    const heliumRich = CompareCylinder(
      volumeL: 12,
      workingPressureBar: 232,
      initialPressureBar: 80,
      initialOxygenPercent: 0,
      initialHeliumPercent: 98,
    );
    final protocol = buildRows(
      const [CompareRow(id: 'keep', type: 'keep')],
      cylinderInput: heliumRich,
      bankList: const <Bank>[],
    );

    expect(protocol.summary.heliumSalvagedLitres, 0);
    expect(
      protocol.summary.heliumRetainedLitres,
      closeTo(80 * 12 * 0.98, 1e-6),
    );
  });

  test('helium added from a leftover bank is scaled by a later drain in the summary', () {
    const halfHeliumBank = Bank(
      id: 'half-he',
      name: 'Half helium',
      volumeL: 40,
      pressureBar: 200,
      oxygenPercent: 0,
      heliumPercent: 50,
      enabled: true,
    );
    final validation = validateRows(
      [
        addRow('add', 'half-he', added: 100, target: 150),
        const CompareRow(id: 'drain', type: 'drain', targetPressureBar: 75),
      ],
      bankList: const [halfHeliumBank],
    );
    final summary = buildRows(
      validation.normalizedRows,
      bankList: const [halfHeliumBank],
    ).summary;

    expect(summary.retainedPercent, closeTo(50, 1e-6));
    expect(summary.ventedGasLitres, closeTo(300, 1e-6));
    expect(summary.heliumVentedLitres, closeTo(0, 1e-6));
    expect(summary.heliumRetainedLitres, closeTo(0, 1e-6));
    expect(summary.heliumSalvagedLitres, closeTo(300, 1e-6));
  });

  test(
    'bank transfers record the source bank volume and starting inventory',
    () {
      final protocol = planCompare([
        addRow('add', 'he-bank', added: 100, target: 150),
      ]);

      final transfer = protocol.protocolSteps.firstWhere(
        (step) => step.sourceBankId == 'he-bank',
      );
      expect(transfer.sourceVolumeL, heBank.volumeL);
      expect(
        transfer.sourceStartMoles,
        closeTo(
          calcMolarDensity(heBank.pressureBar, 0, 100, 20, false) *
              heBank.volumeL,
          1e-9,
        ),
      );
    },
  );

  test('compressor Air transfers have no source inventory', () {
    final protocol = planCompare([compressorRow]);

    final air = protocol.protocolSteps.firstWhere(
      (step) => step.sourceBankId == 'compressor-air',
    );
    expect(air.sourceStartMoles, isNull);
  });
}

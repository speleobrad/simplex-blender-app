import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/compare_recipe.dart';
import 'package:simplex_blender/src/domain/units.dart';
import 'package:simplex_blender/src/ui/shared/compare_recipe_editor.dart';

// Ported from tests/compare-recipe-ui.test.js and tests/compare-mode-markup.test.js
// (visible-behaviour assertions only; the markup-only assertions belong to the
// shell and are not ported here).

const Bank heliumBank = Bank(
  id: 'helium-bank',
  name: 'Helium bank',
  volumeL: 50,
  pressureBar: 200,
  oxygenPercent: 0,
  heliumPercent: 100,
  enabled: true,
);

const Bank unnamedBank = Bank(
  id: 'unnamed-bank',
  name: '  ',
  volumeL: 10,
  pressureBar: 200,
  oxygenPercent: 21,
  heliumPercent: 0,
  enabled: true,
);

const Bank disabledBank = Bank(
  id: 'disabled-bank',
  name: 'Disabled bank',
  volumeL: 10,
  pressureBar: 200,
  oxygenPercent: 21,
  heliumPercent: 0,
  enabled: false,
);

Future<void> pumpEditor(
  WidgetTester tester, {
  required List<CompareRow> rows,
  List<Bank> banks = const <Bank>[],
  List<CompareRecipeError> errors = const <CompareRecipeError>[],
  Map<String, double> pressureStarts = const <String, double>{},
  bool whatIf = false,
  ValueChanged<List<CompareRow>>? onRowsChanged,
}) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CompareRecipeEditor(
            rows: rows,
            banks: banks,
            errors: errors,
            pressureStarts: pressureStarts,
            units: metricUnits,
            whatIf: whatIf,
            onRowsChanged: onRowsChanged ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

Finder findTextMatching(RegExp pattern) {
  return find.byWidgetPredicate(
    (widget) => widget is Text && pattern.hasMatch(widget.data ?? ''),
  );
}

String fieldText(WidgetTester tester, Key key) {
  return tester.widget<TextField>(find.byKey(key)).controller!.text;
}

List<String> rowIds(List<CompareRow> rows) {
  return rows.map((row) => row.id).toList();
}

Future<void> chooseOption(
  WidgetTester tester,
  Key dropdownKey,
  String label,
) async {
  await tester.tap(find.byKey(dropdownKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

List<String?> dropdownValues(WidgetTester tester, Key dropdownKey) {
  final button = tester.widget<DropdownButton<String>>(find.byKey(dropdownKey));
  return button.items!.map((item) => item.value).toList();
}

void main() {
  // -------------------------------------------------------------------------
  // Rendering (tests/compare-recipe-ui.test.js).
  // -------------------------------------------------------------------------

  testWidgets(
    'renders enabled supply-bank controls and synchronized pressure fields for add rows',
    (tester) async {
      const rows = [
        CompareRow(id: 'keep-1', type: 'keep'),
        CompareRow(
          id: 'add-1',
          type: 'add',
          bankId: 'helium-bank',
          pressureAddedBar: 50,
          targetPressureBar: 100,
          pressureInputMode: 'added',
        ),
        CompareRow(
          id: 'wait-1',
          type: 'wait',
          waitMode: 'target',
          waitMinutes: 15,
          targetTemperatureC: 20,
        ),
      ];
      await pumpEditor(
        tester,
        rows: rows,
        banks: const [heliumBank, unnamedBank, disabledBank],
      );

      expect(find.byType(Card), findsNWidgets(3));
      expect(
        find.byKey(const ValueKey('compare-add-1-bankId')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('compare-add-1-pressureAddedBar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('compare-add-1-targetPressureBar')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('compare-add-1-method')), findsNothing);
      expect(
        find.byKey(const ValueKey('compare-add-1-sourcePressureBar')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('compare-add-1-oxygenPercent')),
        findsNothing,
      );

      expect(
        find.text('Helium bank: O₂ 0% · He 100% · 50 L · 200 bar'),
        findsOneWidget,
      );
      expect(findTextMatching(RegExp(r'O₂ 0%.*He 100%')), findsOneWidget);
      expect(findTextMatching(RegExp(r'50 L.*200 bar')), findsOneWidget);
      expect(
        fieldText(tester, const ValueKey('compare-add-1-targetPressureBar')),
        '100.00',
      );

      expect(find.textContaining('Disabled bank'), findsNothing);
      expect(find.textContaining('unnamed-bank'), findsNothing);
      expect(
        dropdownValues(tester, const ValueKey('compare-add-1-bankId')),
        <String?>['', COMPRESSOR_AIR_ID, 'helium-bank'],
      );
    },
  );

  testWidgets('limits add pressure controls to two decimal places', (
    tester,
  ) async {
    const rows = [
      CompareRow(
        id: 'precise-add',
        type: 'add',
        pressureAddedBar: 50.123,
        targetPressureBar: 100.456,
        pressureInputMode: 'added',
      ),
    ];
    await pumpEditor(
      tester,
      rows: rows,
      pressureStarts: const {'precise-add': 50},
    );

    expect(
      fieldText(tester, const ValueKey('compare-precise-add-pressureAddedBar')),
      '50.12',
    );
    expect(
      fieldText(
        tester,
        const ValueKey('compare-precise-add-targetPressureBar'),
      ),
      '100.46',
    );
  });

  testWidgets(
    'renders Compressor Air as an unlimited add source alongside finite banks',
    (tester) async {
      const rows = [
        CompareRow(id: 'air-1', type: 'add', bankId: COMPRESSOR_AIR_ID),
      ];
      await pumpEditor(tester, rows: rows, banks: const [heliumBank]);

      expect(find.textContaining('Compressor Air'), findsWidgets);
      expect(
        find.text('Compressor Air: O₂ 21% · He 0% · Infinite supply'),
        findsOneWidget,
      );
      expect(findTextMatching(RegExp(r'O₂ 21%.*He 0%')), findsOneWidget);
      expect(find.textContaining('Infinite supply'), findsOneWidget);
      expect(
        dropdownValues(tester, const ValueKey('compare-air-1-bankId')),
        contains(COMPRESSOR_AIR_ID),
      );
    },
  );

  testWidgets(
    'renders target-temperature wait controls and associates field errors',
    (tester) async {
      const rows = [
        CompareRow(id: 'keep-1', type: 'keep'),
        CompareRow(
          id: 'wait-1',
          type: 'wait',
          waitMode: 'target',
          waitMinutes: 15,
          targetTemperatureC: 20,
        ),
      ];
      const errors = [
        CompareRecipeError(
          rowId: 'wait-1',
          field: 'targetTemperatureC',
          message: 'Target temperature is unreachable.',
        ),
      ];
      await pumpEditor(tester, rows: rows, errors: errors);

      expect(
        find.byKey(const ValueKey('compare-wait-1-waitMode')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('compare-wait-1-targetTemperatureC')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('compare-wait-1-targetPressureBar')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('compare-wait-1-waitMinutes')),
        findsNothing,
      );

      final temperatureField = tester.widget<TextField>(
        find.byKey(const ValueKey('compare-wait-1-targetTemperatureC')),
      );
      expect(
        temperatureField.decoration!.errorText,
        'Target temperature is unreachable.',
      );
      expect(find.text('Target temperature is unreachable.'), findsOneWidget);
      expect(
        fieldText(tester, const ValueKey('compare-wait-1-targetTemperatureC')),
        '20',
      );

      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('move-up-keep-1')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('move-down-wait-1')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('renders a drain row with a target-pressure control', (
    tester,
  ) async {
    await pumpEditor(tester, rows: [createCompareRow('drain', 'drain-1')]);

    expect(
      find.byKey(const ValueKey('compare-drain-1-targetPressureBar')),
      findsOneWidget,
    );
    expect(find.textContaining('Drain target pressure'), findsWidgets);
  });

  // -------------------------------------------------------------------------
  // Blending (non-What-if) editing behaviour (main.js updateCompareRow,
  // moveCompareRow and the add/remove handlers).
  // -------------------------------------------------------------------------

  testWidgets('add row appends a drain row with a generated id', (
    tester,
  ) async {
    final emitted = <List<CompareRow>>[];
    await pumpEditor(
      tester,
      rows: const [CompareRow(id: 'keep-1', type: 'keep')],
      onRowsChanged: emitted.add,
    );

    await tester.tap(find.text('Add row'));
    await tester.pumpAndSettle();

    expect(emitted, hasLength(1));
    expect(rowIds(emitted.single), ['keep-1', 'compare-row-1']);
    expect(emitted.single.last.type, 'drain');
  });

  testWidgets('move down swaps the row with the next row', (tester) async {
    final emitted = <List<CompareRow>>[];
    await pumpEditor(
      tester,
      rows: const [
        CompareRow(id: 'keep-1', type: 'keep'),
        CompareRow(id: 'add-1', type: 'add'),
        CompareRow(id: 'wait-1', type: 'wait', waitMode: 'minutes'),
      ],
      onRowsChanged: emitted.add,
    );

    await tester.tap(find.byKey(const ValueKey('move-down-keep-1')));
    await tester.pumpAndSettle();

    expect(rowIds(emitted.single), ['add-1', 'keep-1', 'wait-1']);
  });

  testWidgets('remove deletes the row by id', (tester) async {
    final emitted = <List<CompareRow>>[];
    await pumpEditor(
      tester,
      rows: const [
        CompareRow(id: 'keep-1', type: 'keep'),
        CompareRow(id: 'add-1', type: 'add'),
        CompareRow(id: 'wait-1', type: 'wait', waitMode: 'minutes'),
      ],
      onRowsChanged: emitted.add,
    );

    await tester.tap(find.byKey(const ValueKey('remove-add-1')));
    await tester.pumpAndSettle();

    expect(rowIds(emitted.single), ['keep-1', 'wait-1']);
  });

  testWidgets('changing the operation replaces the row with the new type', (
    tester,
  ) async {
    final emitted = <List<CompareRow>>[];
    await pumpEditor(
      tester,
      rows: [createCompareRow('drain', 'drain-1')],
      onRowsChanged: emitted.add,
    );

    await chooseOption(
      tester,
      const ValueKey('compare-drain-1-type'),
      'Add gas',
    );

    expect(emitted, hasLength(1));
    expect(emitted.single.single.id, 'drain-1');
    expect(emitted.single.single.type, 'add');
  });

  testWidgets(
    'selecting a gas source stores the bank id and the blank option clears it',
    (tester) async {
      final emitted = <List<CompareRow>>[];
      await pumpEditor(
        tester,
        rows: const [
          CompareRow(id: 'add-1', type: 'add', bankId: 'helium-bank'),
        ],
        banks: const [heliumBank],
        onRowsChanged: emitted.add,
      );

      await chooseOption(
        tester,
        const ValueKey('compare-add-1-bankId'),
        'Compressor Air (infinite)',
      );
      expect(emitted.last.single.bankId, COMPRESSOR_AIR_ID);

      await chooseOption(
        tester,
        const ValueKey('compare-add-1-bankId'),
        'Select gas source',
      );
      expect(emitted.last.single.bankId, isNull);
    },
  );

  testWidgets(
    'editing the added pressure normalizes the receiver target from the start pressure',
    (tester) async {
      final emitted = <List<CompareRow>>[];
      await pumpEditor(
        tester,
        rows: const [
          CompareRow(
            id: 'add-1',
            type: 'add',
            bankId: 'helium-bank',
            pressureAddedBar: 50,
            targetPressureBar: 90,
            pressureInputMode: 'added',
          ),
        ],
        banks: const [heliumBank],
        pressureStarts: const {'add-1': 40},
        onRowsChanged: emitted.add,
      );

      await tester.enterText(
        find.byKey(const ValueKey('compare-add-1-pressureAddedBar')),
        '60',
      );

      final updated = emitted.last.single;
      expect(updated.pressureAddedBar, 60);
      expect(updated.targetPressureBar, 100);
      expect(updated.pressureInputMode, 'added');
    },
  );

  testWidgets(
    'editing the receiver target pressure derives the added pressure',
    (tester) async {
      final emitted = <List<CompareRow>>[];
      await pumpEditor(
        tester,
        rows: const [
          CompareRow(
            id: 'add-1',
            type: 'add',
            bankId: 'helium-bank',
            pressureAddedBar: 50,
            targetPressureBar: 90,
            pressureInputMode: 'added',
          ),
        ],
        banks: const [heliumBank],
        pressureStarts: const {'add-1': 40},
        onRowsChanged: emitted.add,
      );

      await tester.enterText(
        find.byKey(const ValueKey('compare-add-1-targetPressureBar')),
        '95',
      );

      final updated = emitted.last.single;
      expect(updated.targetPressureBar, 95);
      expect(updated.pressureAddedBar, 55);
      expect(updated.pressureInputMode, 'target');
    },
  );

  testWidgets('drain target pressure edit emits targetPressureBar', (
    tester,
  ) async {
    final emitted = <List<CompareRow>>[];
    await pumpEditor(
      tester,
      rows: [createCompareRow('drain', 'drain-1')],
      onRowsChanged: emitted.add,
    );

    await tester.enterText(
      find.byKey(const ValueKey('compare-drain-1-targetPressureBar')),
      '75',
    );

    expect(emitted.last.single.targetPressureBar, 75);
  });

  testWidgets('wait minutes edit emits waitMinutes', (tester) async {
    final emitted = <List<CompareRow>>[];
    await pumpEditor(
      tester,
      rows: const [
        CompareRow(
          id: 'wait-2',
          type: 'wait',
          waitMode: 'minutes',
          waitMinutes: 15,
        ),
      ],
      onRowsChanged: emitted.add,
    );

    expect(
      fieldText(tester, const ValueKey('compare-wait-2-waitMinutes')),
      '15',
    );
    await tester.enterText(
      find.byKey(const ValueKey('compare-wait-2-waitMinutes')),
      '30',
    );

    expect(emitted.last.single.waitMinutes, 30);
  });

  testWidgets('target temperature edit emits targetTemperatureC', (
    tester,
  ) async {
    final emitted = <List<CompareRow>>[];
    await pumpEditor(
      tester,
      rows: const [
        CompareRow(
          id: 'wait-1',
          type: 'wait',
          waitMode: 'target',
          targetTemperatureC: 20,
        ),
      ],
      onRowsChanged: emitted.add,
    );

    await tester.enterText(
      find.byKey(const ValueKey('compare-wait-1-targetTemperatureC')),
      '25',
    );

    expect(emitted.last.single.targetTemperatureC, 25);
  });

  testWidgets('wait mode change emits the selected mode', (tester) async {
    final emitted = <List<CompareRow>>[];
    await pumpEditor(
      tester,
      rows: const [
        CompareRow(
          id: 'wait-1',
          type: 'wait',
          waitMode: 'target',
          targetTemperatureC: 20,
        ),
      ],
      onRowsChanged: emitted.add,
    );

    await chooseOption(
      tester,
      const ValueKey('compare-wait-1-waitMode'),
      'Minutes',
    );

    expect(emitted.last.single.waitMode, 'minutes');
  });

  // -------------------------------------------------------------------------
  // What-if layout (tests/compare-recipe-ui.test.js What-if-adjacent markup
  // and the What-if branch of renderCompareRecipe / updateWhatIfRow /
  // handleDrop in js/ui/compare-recipe.js and js/main.js).
  // -------------------------------------------------------------------------

  testWidgets(
    'what-if hides wait rows and shows automatic waits between steps',
    (tester) async {
      await pumpEditor(
        tester,
        rows: [
          createCompareRow('drain', 'drain-1'),
          const CompareRow(
            id: 'wait-1',
            type: 'wait',
            waitMode: 'minutes',
            waitMinutes: 5,
          ),
          createCompareRow('drain', 'drain-2'),
        ],
        whatIf: true,
      );

      expect(
        find.byKey(const ValueKey('compare-wait-1-waitMode')),
        findsNothing,
      );
      expect(find.text('Step 1'), findsOneWidget);
      expect(find.text('Step 2'), findsNothing);
      expect(find.text('Step 3'), findsOneWidget);
      expect(
        find.text('Wait between step 1 and step 2 (minutes)'),
        findsOneWidget,
      );
      expect(
        find.text('Wait between step 2 and step 3 (minutes)'),
        findsNothing,
      );
      expect(
        find.text('Wait between step 3 and step 4 (minutes)'),
        findsNothing,
      );
    },
  );

  testWidgets('what-if operation list excludes Wait', (tester) async {
    await pumpEditor(
      tester,
      rows: [createCompareRow('drain', 'drain-1')],
      whatIf: true,
    );

    expect(
      dropdownValues(tester, const ValueKey('compare-drain-1-type')),
      <String?>['drain', 'add'],
    );
  });

  testWidgets(
    'what-if add button reads Add step and appends a drain step with zero wait',
    (tester) async {
      final emitted = <List<CompareRow>>[];
      await pumpEditor(
        tester,
        rows: [createCompareRow('drain', 'drain-1')],
        whatIf: true,
        onRowsChanged: emitted.add,
      );

      expect(find.text('Add row'), findsNothing);
      await tester.tap(find.text('Add step'));
      await tester.pumpAndSettle();

      expect(emitted, hasLength(1));
      expect(rowIds(emitted.single), ['drain-1', 'compare-row-1']);
      expect(emitted.single.last.type, 'drain');
      expect(emitted.single.last.waitMinutes, 0);
    },
  );

  testWidgets('what-if remove emits the list without the removed step', (
    tester,
  ) async {
    final emitted = <List<CompareRow>>[];
    await pumpEditor(
      tester,
      rows: [
        createCompareRow('drain', 'drain-1'),
        createCompareRow('drain', 'drain-2'),
      ],
      whatIf: true,
      onRowsChanged: emitted.add,
    );

    await tester.tap(find.byKey(const ValueKey('remove-drain-1')));
    await tester.pumpAndSettle();

    expect(rowIds(emitted.single), ['drain-2']);
  });

  testWidgets(
    'editing an automatic wait updates the preceding row waitMinutes',
    (tester) async {
      final emitted = <List<CompareRow>>[];
      await pumpEditor(
        tester,
        rows: [
          createCompareRow('drain', 'drain-1'),
          createCompareRow('drain', 'drain-2'),
        ],
        whatIf: true,
        onRowsChanged: emitted.add,
      );

      await tester.enterText(
        find.byKey(const ValueKey('compare-drain-1-waitMinutes')),
        '12',
      );

      expect(emitted.last.first.id, 'drain-1');
      expect(emitted.last.first.waitMinutes, 12);
    },
  );

  testWidgets('dragging a step onto another replaces it in JS splice order', (
    tester,
  ) async {
    final emitted = <List<CompareRow>>[];
    await pumpEditor(
      tester,
      rows: [
        createCompareRow('drain', 'drain-1'),
        createCompareRow('add', 'add-1'),
        createCompareRow('drain', 'drain-2'),
      ],
      whatIf: true,
      onRowsChanged: emitted.add,
    );

    final handle = tester.getCenter(find.byKey(const ValueKey('drag-drain-1')));
    final target = tester.getCenter(
      find.byKey(const ValueKey('compare-row-card-drain-2')),
    );
    final gesture = await tester.startGesture(handle);
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // JS handleDrop: splice(sourceIndex, 1), then splice(targetIndex, 0, row).
    expect(rowIds(emitted.single), ['add-1', 'drain-2', 'drain-1']);
  });
}

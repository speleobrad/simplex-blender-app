import 'package:flutter/material.dart';
import 'package:simplex_blender/src/controllers/what_if_controller.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/compare_recipe.dart';
import 'package:simplex_blender/src/domain/units.dart';
import 'package:simplex_blender/src/domain/what_if_scenario.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_format.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_number_field.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_select.dart';

const String _noSource = '';

/// Ordered What-if steps: drain and add operations with automatic waits
/// between them. Every edit goes through [WhatIfController].
class WhatIfStepEditor extends StatelessWidget {
  const WhatIfStepEditor({
    super.key,
    required this.controller,
    required this.banks,
    required this.units,
  });

  final WhatIfController controller;
  final List<Bank> banks;
  final String? units;

  List<Bank> get _enabledBanks => <Bank>[
    for (final bank in banks)
      if (bank.enabled && bank.name.trim().isNotEmpty) bank,
  ];

  /// Expanded rows with automatic waits removed from the operation order.
  List<CompareRow> _operations(List<CompareRow> expanded) => <CompareRow>[
    for (final row in expanded)
      if (row.type != 'wait') row,
  ];

  /// The automatic wait row that follows [operation], or null for the last.
  CompareRow? _waitAfter(List<CompareRow> expanded, String operationId) {
    final waitId = '$operationId-wait';
    for (final row in expanded) {
      if (row.id == waitId) {
        return row;
      }
    }
    return null;
  }

  void _reorder(List<CompareRow> operations, int oldIndex, int newIndex) {
    final delta = newIndex - oldIndex;
    if (delta == 0) {
      return;
    }
    controller.moveRow(operations[oldIndex].id, delta);
  }

  @override
  Widget build(BuildContext context) {
    final expanded = expandWhatIfRows(controller.scenario.rows);
    final operations = _operations(expanded);

    final items = <Widget>[
      for (var index = 0; index < operations.length; index += 1)
        _StepItem(
          key: ValueKey<String>(operations[index].id),
          index: index,
          operation: operations[index],
          waitAfter: _waitAfter(expanded, operations[index].id),
          stepIsLast: index == operations.length - 1,
          units: units,
          enabledBanks: _enabledBanks,
          controller: controller,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (operations.isNotEmpty)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) =>
                _reorder(operations, oldIndex, newIndex),
            children: items,
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: controller.addDrainRow,
            child: const Text('Add step'),
          ),
        ),
      ],
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    super.key,
    required this.index,
    required this.operation,
    required this.waitAfter,
    required this.stepIsLast,
    required this.units,
    required this.enabledBanks,
    required this.controller,
  });

  final int index;
  final CompareRow operation;
  final CompareRow? waitAfter;
  final bool stepIsLast;
  final String? units;
  final List<Bank> enabledBanks;
  final WhatIfController controller;

  @override
  Widget build(BuildContext context) {
    final stepNumber = index + 1;
    final card = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  'Step $stepNumber',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                Tooltip(
                  message: 'Drag to reorder',
                  child: Semantics(
                    label: 'Reorder step $stepNumber',
                    child: ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Remove step',
                  child: Semantics(
                    label: 'Remove step $stepNumber',
                    button: true,
                    child: IconButton(
                      onPressed: () => controller.removeRow(operation.id),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ],
            ),
            WhatIfSelect<String>(
              key: Key('what-if-step-$stepNumber-operation'),
              errorText: rowErrorText(controller, operation.id, 'type'),
              label: 'Operation',
              value: operation.type,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'drain', child: Text('Drain')),
                DropdownMenuItem<String>(value: 'add', child: Text('Add gas')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                controller.setRowType(operation.id, value);
              },
            ),
            _RowFieldError(
              controller: controller,
              rowId: operation.id,
              field: 'type',
            ),
            const SizedBox(height: 8),
            if (operation.type == 'add')
              ..._addFields(context, stepNumber)
            else
              _drainField(stepNumber),
          ],
        ),
      ),
    );

    final wait = waitAfter;
    if (stepIsLast || wait == null) {
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: card);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          card,
          const SizedBox(height: 8),
          WhatIfNumberField(
            key: Key('what-if-step-$stepNumber-wait'),
            errorText: rowErrorText(controller, wait.id, 'waitMinutes'),
            label:
                'Wait between step $stepNumber and step ${stepNumber + 1} (minutes)',
            suffixText: 'min',
            displayText: jsNumberText(wait.waitMinutes ?? 0),
            onCommit: (value) =>
                controller.setRowWaitMinutes(operation.id, value),
          ),
          _RowFieldError(
            controller: controller,
            rowId: wait.id,
            field: 'waitMinutes',
          ),
          _RowFieldError(
            controller: controller,
            rowId: wait.id,
            field: 'waitMode',
          ),
        ],
      ),
    );
  }

  List<Widget> _addFields(BuildContext context, int stepNumber) {
    final sourceId = operation.bankId ?? _noSource;
    final selected = _selectedBank(sourceId);
    final sourceItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: _noSource,
        child: Text('Select gas source'),
      ),
      const DropdownMenuItem<String>(
        value: COMPRESSOR_AIR_ID,
        child: Text('Compressor Air (infinite)'),
      ),
      for (final bank in enabledBanks)
        DropdownMenuItem<String>(value: bank.id, child: Text(bank.name)),
    ];
    final sourceKnown = sourceItems.any((item) => item.value == sourceId);

    return <Widget>[
      WhatIfSelect<String>(
        key: Key('what-if-step-$stepNumber-source'),
        errorText: rowErrorText(controller, operation.id, 'bankId'),
        label: 'Gas source',
        value: sourceKnown ? sourceId : null,
        items: sourceItems,
        onChanged: (value) {
          if (value == null) {
            return;
          }
          controller.setRowBankId(
            operation.id,
            value == _noSource ? null : value,
          );
        },
      ),
      _RowFieldError(
        controller: controller,
        rowId: operation.id,
        field: 'bankId',
      ),
      if (sourceId == COMPRESSOR_AIR_ID)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Compressor Air: O₂ 21% · He 0% · Infinite supply',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        )
      else if (selected != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${selected.name}: O₂ ${jsNumberText(selected.oxygenPercent)}% · '
            'He ${jsNumberText(selected.heliumPercent)}% · '
            '${jsNumberText(selected.volumeL)} L · '
            '${jsNumberText(selected.pressureBar)} bar',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      const SizedBox(height: 8),
      WhatIfNumberField(
        key: Key('what-if-step-$stepNumber-pressureAdded'),
        errorText: rowErrorText(controller, operation.id, 'pressureAddedBar'),
        label: 'Pressure added (${unitLabel('pressureBar', units)})',
        displayText: _pressureInputText(operation.pressureAddedBar),
        onCommit: (value) => controller.setRowPressureAddedBar(
          operation.id,
          convertFromDisplay(value, 'pressureBar', units),
          pressureInputMode: 'added',
        ),
      ),
      _RowFieldError(
        controller: controller,
        rowId: operation.id,
        field: 'pressureAddedBar',
      ),
      const SizedBox(height: 8),
      WhatIfNumberField(
        key: Key('what-if-step-$stepNumber-receiverTarget'),
        errorText: rowErrorText(controller, operation.id, 'targetPressureBar'),
        label: 'Receiver target pressure (${unitLabel('pressureBar', units)})',
        displayText: _pressureInputText(operation.targetPressureBar),
        onCommit: (value) => controller.setRowTargetPressureBar(
          operation.id,
          convertFromDisplay(value, 'pressureBar', units),
          pressureInputMode: 'target',
        ),
      ),
      _RowFieldError(
        controller: controller,
        rowId: operation.id,
        field: 'targetPressureBar',
      ),
      _RowFieldError(
        controller: controller,
        rowId: operation.id,
        field: 'pressureInputMode',
      ),
    ];
  }

  Widget _drainField(int stepNumber) {
    final target = operation.targetPressureBar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        WhatIfNumberField(
          key: Key('what-if-step-$stepNumber-drainTarget'),
          errorText: rowErrorText(
            controller,
            operation.id,
            'targetPressureBar',
          ),
          label: 'Drain target pressure (${unitLabel('pressureBar', units)})',
          displayText: target == null
              ? ''
              : scenarioInputText(target, 'pressureBar', units),
          onCommit: (value) => controller.setRowTargetPressureBar(
            operation.id,
            convertFromDisplay(value, 'pressureBar', units),
            pressureInputMode: 'target',
          ),
        ),
        _RowFieldError(
          controller: controller,
          rowId: operation.id,
          field: 'targetPressureBar',
        ),
        _RowFieldError(
          controller: controller,
          rowId: operation.id,
          field: 'pressureInputMode',
        ),
      ],
    );
  }

  /// JS `pressureInputValue`: display units with two decimals.
  String _pressureInputText(double? metricValue) {
    if (metricValue == null) {
      return '';
    }
    return convertToDisplay(
      metricValue,
      'pressureBar',
      units,
    ).toStringAsFixed(2);
  }

  Bank? _selectedBank(String id) {
    for (final bank in enabledBanks) {
      if (bank.id == id) {
        return bank;
      }
    }
    return null;
  }
}

/// Red text under a step control carrying a row-scoped message (JS
/// `compare-<rowId>-<field>-error`, `js/ui/compare-recipe.js` 19–31).
class _RowFieldError extends StatelessWidget {
  const _RowFieldError({
    required this.controller,
    required this.rowId,
    required this.field,
  });

  final WhatIfController controller;
  final String rowId;
  final String field;

  @override
  Widget build(BuildContext context) {
    final messages = <String>[
      for (final error in controller.fieldErrors)
        if (error.rowId == rowId && error.field == field) error.message,
    ];
    if (messages.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      messages.join(' '),
      key: Key('compare-$rowId-$field-error'),
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

/// Row-scoped error fields that the step editor renders under their controls.
/// Other row-scoped errors fall back to the result area's general list.
const Set<String> whatIfRowErrorFields = <String>{
  'type',
  'bankId',
  'pressureAddedBar',
  'targetPressureBar',
  'pressureInputMode',
  'waitMode',
  'waitMinutes',
};

/// The row-scoped error message for [field] on [rowId], or null. Joins all
/// matching messages, as JS `errorsFor` does for `compare-<rowId>-<field>`.
String? rowErrorText(WhatIfController controller, String rowId, String field) {
  final messages = <String>[
    for (final error in controller.fieldErrors)
      if (error.rowId == rowId && error.field == field) error.message,
  ];
  return messages.isEmpty ? null : messages.join(' ');
}

import 'package:flutter/material.dart';

import '../../domain/bank.dart';
import '../../domain/compare_recipe.dart';
import '../../domain/js_number.dart';
import '../../domain/units.dart';

const String _compressorAirLabel = 'Compressor Air (infinite)';
const String _compressorAirDetails =
    'Compressor Air: O₂ 21% · He 0% · Infinite supply';

final RegExp _leadingNumber = RegExp(
  r'^\s*[+-]?(?:Infinity|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)',
);

final RegExp _trailingZero = RegExp(r'\.0$');

/// Ordered compare recipe editor shared by Blending Compare mode and What-if.
///
/// Port of `js/ui/compare-recipe.js`. The widget never mutates [rows]; every
/// edit is reported through [onRowsChanged] with a full replacement list.
///
/// With [whatIf] the What-if layout is used: "Step N" cards, wait rows are
/// hidden, automatic waits are shown between steps (editing the preceding
/// row's `waitMinutes`), steps can be removed and reordered by drag.
class CompareRecipeEditor extends StatefulWidget {
  const CompareRecipeEditor({
    super.key,
    required this.rows,
    required this.banks,
    required this.errors,
    required this.pressureStarts,
    required this.units,
    required this.onRowsChanged,
    this.whatIf = false,
  });

  final List<CompareRow> rows;
  final List<Bank> banks;

  /// Row-scoped errors only (`rowId != null`). Global errors are shell-owned.
  final List<CompareRecipeError> errors;

  /// Receiver start pressure (bar) per row id, used to normalize add rows.
  final Map<String, double> pressureStarts;
  final String units;
  final ValueChanged<List<CompareRow>> onRowsChanged;
  final bool whatIf;

  @override
  State<CompareRecipeEditor> createState() => _CompareRecipeEditorState();
}

class _CompareRecipeEditorState extends State<CompareRecipeEditor> {
  int _nextRowNumber = 1;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var index = 0; index < widget.rows.length; index++) {
      final row = widget.rows[index];
      if (widget.whatIf && row.type == 'wait') {
        continue;
      }
      children.add(_buildRowCard(context, row, index));
      if (widget.whatIf && index < widget.rows.length - 1) {
        children.add(_buildAutomaticWait(context, row, index + 1));
      }
    }
    children.add(
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          key: const ValueKey('add-compare-row'),
          onPressed: _addRow,
          child: Text(widget.whatIf ? 'Add step' : 'Add row'),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  // -------------------------------------------------------------------------
  // Row-level actions (JS main.js `handleClick`, `moveCompareRow`, drop).
  // -------------------------------------------------------------------------

  void _addRow() {
    final id = _nextRowId();
    final created = createCompareRow('drain', id);
    final row = widget.whatIf ? _copyRow(created, waitMinutes: 0) : created;
    widget.onRowsChanged([...widget.rows, row]);
  }

  /// Monotonic `compare-row-N` id that does not collide with an existing row.
  String _nextRowId() {
    var number = _nextRowNumber;
    var id = 'compare-row-$number';
    while (widget.rows.any((row) => row.id == id)) {
      number += 1;
      id = 'compare-row-$number';
    }
    _nextRowNumber = number + 1;
    return id;
  }

  void _removeRow(CompareRow row) {
    widget.onRowsChanged(
      widget.rows.where((candidate) => candidate.id != row.id).toList(),
    );
  }

  void _moveRow(int index, int offset) {
    final destination = index + offset;
    if (index < 0 || destination < 0 || destination >= widget.rows.length) {
      return;
    }
    final rows = List<CompareRow>.of(widget.rows);
    final moved = rows[index];
    rows[index] = rows[destination];
    rows[destination] = moved;
    widget.onRowsChanged(rows);
  }

  /// Drop handling (JS `handleDrop`): remove the source and insert it at the
  /// target's index.
  void _reorder(String sourceId, String targetId) {
    if (sourceId == targetId) {
      return;
    }
    final rows = List<CompareRow>.of(widget.rows);
    final sourceIndex = rows.indexWhere((row) => row.id == sourceId);
    final targetIndex = rows.indexWhere((row) => row.id == targetId);
    if (sourceIndex < 0 || targetIndex < 0) {
      return;
    }
    final row = rows.removeAt(sourceIndex);
    rows.insert(targetIndex, row);
    widget.onRowsChanged(rows);
  }

  // -------------------------------------------------------------------------
  // Field edits (JS main.js `updateCompareRow`).
  // -------------------------------------------------------------------------

  void _replaceRow(CompareRow row, CompareRow updated) {
    final rows = List<CompareRow>.of(widget.rows);
    final index = rows.indexWhere((candidate) => candidate.id == row.id);
    if (index < 0) {
      return;
    }
    rows[index] = updated;
    widget.onRowsChanged(rows);
  }

  void _setType(CompareRow row, String type) {
    var updated = createCompareRow(type, row.id);
    if (widget.whatIf) {
      updated = _copyRow(updated, waitMinutes: row.waitMinutes ?? 0);
    }
    _replaceRow(row, updated);
  }

  void _setBank(CompareRow row, String value) {
    _replaceRow(row, _copyRow(row, bankId: value, clearBankId: value.isEmpty));
  }

  void _setPressure(CompareRow row, String field, String text) {
    final value = convertFromDisplay(
      _parseFloat(text),
      'pressureBar',
      widget.units,
    );
    final isAdded = field == 'pressureAddedBar';
    if (!isAdded && row.type != 'add') {
      _replaceRow(row, _copyRow(row, targetPressureBar: value));
      return;
    }
    final entered = isAdded
        ? _copyRow(row, pressureAddedBar: value, pressureInputMode: 'added')
        : _copyRow(row, targetPressureBar: value, pressureInputMode: 'target');
    final start = widget.pressureStarts[row.id] ?? double.nan;
    final normalized = normalizeComparePressureFields(entered, start);
    _replaceRow(
      row,
      _copyRow(
        entered,
        pressureAddedBar: normalized.pressureAddedBar,
        targetPressureBar: normalized.targetPressureBar,
        pressureInputMode: normalized.pressureInputMode,
      ),
    );
  }

  void _setWaitMode(CompareRow row, String value) {
    _replaceRow(row, _copyRow(row, waitMode: value));
  }

  void _setWaitMinutes(CompareRow row, String text) {
    _replaceRow(row, _copyRow(row, waitMinutes: _parseFloat(text)));
  }

  void _setTargetTemperature(CompareRow row, String text) {
    final value = convertFromDisplay(
      _parseFloat(text),
      'temperatureC',
      widget.units,
    );
    _replaceRow(row, _copyRow(row, targetTemperatureC: value));
  }

  // -------------------------------------------------------------------------
  // Layout.
  // -------------------------------------------------------------------------

  Widget _buildRowCard(BuildContext context, CompareRow row, int index) {
    final rowNumber = index + 1;
    final theme = Theme.of(context);
    final typeField = _selectField(
      fieldKey: ValueKey('compare-${row.id}-type'),
      labelText: 'Operation',
      semanticsLabel: 'Row $rowNumber Operation',
      options: widget.whatIf
          ? COMPARE_ROW_TYPES.where((option) => option.value != 'wait').toList()
          : COMPARE_ROW_TYPES,
      value: row.type,
      errorText: _errorText(row.id, 'type'),
      onChanged: (value) => _setType(row, value),
    );
    final legend = Text(
      '${widget.whatIf ? 'Step' : 'Row'} $rowNumber',
      style: theme.textTheme.titleSmall,
    );
    final fields = _rowFields(context, row, rowNumber);

    final Widget content;
    if (widget.whatIf) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: typeField),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: fields,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dragHandle(row, rowNumber),
              _whatIfRemove(row, rowNumber),
            ],
          ),
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          typeField,
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: ValueKey('move-up-${row.id}'),
                onPressed: index == 0 ? null : () => _moveRow(index, -1),
                child: const Text('Move up'),
              ),
              TextButton(
                key: ValueKey('move-down-${row.id}'),
                onPressed: index == widget.rows.length - 1
                    ? null
                    : () => _moveRow(index, 1),
                child: const Text('Move down'),
              ),
              TextButton(
                key: ValueKey('remove-${row.id}'),
                onPressed: () => _removeRow(row),
                child: const Text('Remove'),
              ),
            ],
          ),
          ...fields,
        ],
      );
    }

    final card = Card(
      key: ValueKey('compare-row-card-${row.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [legend, content],
        ),
      ),
    );

    final padded = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: card,
    );
    if (!widget.whatIf) {
      return padded;
    }
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != row.id,
      onAcceptWithDetails: (details) => _reorder(details.data, row.id),
      builder: (context, candidateData, rejectedData) => padded,
    );
  }

  Widget _dragHandle(CompareRow row, int rowNumber) {
    return Semantics(
      label: 'Reorder step $rowNumber',
      child: Tooltip(
        message: 'Drag to reorder',
        child: Draggable<String>(
          key: ValueKey('drag-${row.id}'),
          data: row.id,
          feedback: const Material(color: Colors.transparent, child: Text('⠿')),
          child: const Padding(padding: EdgeInsets.all(8), child: Text('⠿')),
        ),
      ),
    );
  }

  Widget _whatIfRemove(CompareRow row, int rowNumber) {
    return Semantics(
      label: 'Remove step $rowNumber',
      child: Tooltip(
        message: 'Remove step',
        child: TextButton(
          key: ValueKey('remove-${row.id}'),
          onPressed: () => _removeRow(row),
          child: const Text('×'),
        ),
      ),
    );
  }

  /// The automatic wait after a What-if step (JS `renderAutomaticWait`).
  /// [stepNumber] is the 1-based number of the step it follows.
  Widget _buildAutomaticWait(
    BuildContext context,
    CompareRow row,
    int stepNumber,
  ) {
    final label =
        'Wait between step $stepNumber and step ${stepNumber + 1} (minutes)';
    final message = _errorText('${row.id}-wait', 'waitMinutes');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text('Wait', style: Theme.of(context).textTheme.labelMedium),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _numberField(
                  fieldKey: ValueKey('compare-${row.id}-waitMinutes'),
                  labelText: label,
                  semanticsLabel: label,
                  text: _numberText(row.waitMinutes ?? 0),
                  errorText: null,
                  suffixText: 'min',
                  onChanged: (text) => _setWaitMinutes(row, text),
                ),
                if (message != null)
                  Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _rowFields(BuildContext context, CompareRow row, int rowNumber) {
    final units = widget.units;
    if (row.type == 'add') {
      return _addGasFields(context, row, rowNumber);
    }
    if (row.type == 'drain') {
      return [
        _numberField(
          fieldKey: ValueKey('compare-${row.id}-targetPressureBar'),
          labelText:
              'Drain target pressure (${unitLabel('pressureBar', units)})',
          semanticsLabel:
              'Row $rowNumber Drain target pressure (${unitLabel('pressureBar', units)})',
          text: _drainPressureText(row.targetPressureBar, units),
          errorText: _errorText(row.id, 'targetPressureBar'),
          onChanged: (text) => _setPressure(row, 'targetPressureBar', text),
        ),
      ];
    }
    if (row.type == 'wait') {
      final fields = <Widget>[
        _selectField(
          fieldKey: ValueKey('compare-${row.id}-waitMode'),
          labelText: 'Wait mode',
          semanticsLabel: 'Row $rowNumber Wait mode',
          options: const [
            CompareOption(value: 'minutes', label: 'Minutes'),
            CompareOption(value: 'target', label: 'Target state'),
          ],
          value: row.waitMode,
          errorText: _errorText(row.id, 'waitMode'),
          onChanged: (value) => _setWaitMode(row, value),
        ),
      ];
      if (row.waitMode == 'target') {
        fields.add(
          _numberField(
            fieldKey: ValueKey('compare-${row.id}-targetTemperatureC'),
            labelText:
                'Target medium temperature (${unitLabel('temperatureC', units)})',
            semanticsLabel:
                'Row $rowNumber Target medium temperature (${unitLabel('temperatureC', units)})',
            text: _temperatureText(row.targetTemperatureC, units),
            errorText: _errorText(row.id, 'targetTemperatureC'),
            onChanged: (text) => _setTargetTemperature(row, text),
          ),
        );
      } else {
        fields.add(
          _numberField(
            fieldKey: ValueKey('compare-${row.id}-waitMinutes'),
            labelText: 'Wait time (minutes)',
            semanticsLabel: 'Row $rowNumber Wait time (minutes)',
            text: _numberText(row.waitMinutes),
            errorText: _errorText(row.id, 'waitMinutes'),
            onChanged: (text) => _setWaitMinutes(row, text),
          ),
        );
      }
      return fields;
    }
    return const [];
  }

  List<Widget> _addGasFields(
    BuildContext context,
    CompareRow row,
    int rowNumber,
  ) {
    final units = widget.units;
    final enabledBanks = widget.banks
        .where((bank) => bank.enabled && bank.name.trim().isNotEmpty)
        .toList();
    final options = <CompareOption>[
      const CompareOption(value: '', label: 'Select gas source'),
      const CompareOption(value: COMPRESSOR_AIR_ID, label: _compressorAirLabel),
      for (final bank in enabledBanks)
        CompareOption(value: bank.id, label: bank.name),
    ];
    final details = _bankDetails(row, enabledBanks);
    final pressureLabel = unitLabel('pressureBar', units);
    return [
      _selectField(
        fieldKey: ValueKey('compare-${row.id}-bankId'),
        labelText: 'Gas source',
        semanticsLabel: 'Row $rowNumber Gas source',
        options: options,
        value: row.bankId ?? '',
        errorText: _errorText(row.id, 'bankId'),
        onChanged: (value) => _setBank(row, value),
      ),
      if (details != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(details, style: Theme.of(context).textTheme.bodySmall),
        ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _numberField(
              fieldKey: ValueKey('compare-${row.id}-pressureAddedBar'),
              labelText: 'Pressure added ($pressureLabel)',
              semanticsLabel: 'Row $rowNumber Pressure added ($pressureLabel)',
              text: _pressureText(row.pressureAddedBar, units),
              errorText: _errorText(row.id, 'pressureAddedBar'),
              onChanged: (text) => _setPressure(row, 'pressureAddedBar', text),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _numberField(
              fieldKey: ValueKey('compare-${row.id}-targetPressureBar'),
              labelText: 'Receiver target pressure ($pressureLabel)',
              semanticsLabel:
                  'Row $rowNumber Receiver target pressure ($pressureLabel)',
              text: _pressureText(row.targetPressureBar, units),
              errorText: _errorText(row.id, 'targetPressureBar'),
              onChanged: (text) => _setPressure(row, 'targetPressureBar', text),
            ),
          ),
        ],
      ),
    ];
  }

  /// JS `addGasFields` details line for the selected source.
  String? _bankDetails(CompareRow row, List<Bank> enabledBanks) {
    if (row.bankId == COMPRESSOR_AIR_ID) {
      return _compressorAirDetails;
    }
    final bank = _findBank(enabledBanks, row.bankId);
    if (bank == null) {
      return null;
    }
    return '${bank.name}: O₂ ${jsNumberString(bank.oxygenPercent)}% · '
        'He ${jsNumberString(bank.heliumPercent)}% · '
        '${jsNumberString(bank.volumeL)} L · '
        '${jsNumberString(bank.pressureBar)} bar';
  }

  // -------------------------------------------------------------------------
  // Field builders.
  // -------------------------------------------------------------------------

  Widget _selectField({
    required Key fieldKey,
    required String labelText,
    required String semanticsLabel,
    required List<CompareOption> options,
    required String? value,
    required String? errorText,
    required ValueChanged<String> onChanged,
  }) {
    final selected = options.any((option) => option.value == value)
        ? value
        : null;
    return Semantics(
      label: semanticsLabel,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: labelText,
          errorText: errorText,
          isDense: true,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: fieldKey,
            isExpanded: true,
            value: selected,
            items: [
              for (final option in options)
                DropdownMenuItem<String>(
                  value: option.value,
                  child: Text(option.label),
                ),
            ],
            onChanged: (next) {
              if (next != null) {
                onChanged(next);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _numberField({
    required Key fieldKey,
    required String labelText,
    required String semanticsLabel,
    required String text,
    required String? errorText,
    required ValueChanged<String> onChanged,
    String? suffixText,
  }) {
    return Semantics(
      label: semanticsLabel,
      child: _CompareNumberField(
        textFieldKey: fieldKey,
        labelText: labelText,
        text: text,
        errorText: errorText,
        suffixText: suffixText,
        onChanged: onChanged,
      ),
    );
  }

  /// JS `addFieldError`: messages for one field, joined with a space.
  String? _errorText(String rowId, String field) {
    final messages = widget.errors
        .where((error) => error.rowId == rowId && error.field == field)
        .map((error) => error.message)
        .toList();
    if (messages.isEmpty) {
      return null;
    }
    return messages.join(' ');
  }
}

/// Number field with the JS `input` / `change` behaviour: typing emits the
/// text immediately; when unfocused, the field shows the model's formatted
/// text.
class _CompareNumberField extends StatefulWidget {
  const _CompareNumberField({
    required this.textFieldKey,
    required this.labelText,
    required this.text,
    required this.errorText,
    required this.onChanged,
    this.suffixText,
  });

  final Key textFieldKey;
  final String labelText;
  final String text;
  final String? errorText;
  final String? suffixText;
  final ValueChanged<String> onChanged;

  @override
  State<_CompareNumberField> createState() => _CompareNumberFieldState();
}

class _CompareNumberFieldState extends State<_CompareNumberField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _CompareNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncText();
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _syncText();
    }
  }

  void _syncText() {
    if (_focusNode.hasFocus) {
      return;
    }
    if (_controller.text != widget.text) {
      _controller.value = TextEditingValue(text: widget.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.textFieldKey,
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.labelText,
        errorText: widget.errorText,
        suffixText: widget.suffixText,
        isDense: true,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers (pure).
// ---------------------------------------------------------------------------

/// JS `Number.parseFloat`: the longest leading numeric prefix, else NaN.
double _parseFloat(String text) {
  final match = _leadingNumber.firstMatch(text);
  if (match == null) {
    return double.nan;
  }
  final literal = match.group(0)!.trim();
  if (literal.endsWith('Infinity')) {
    return literal.startsWith('-') ? double.negativeInfinity : double.infinity;
  }
  return double.tryParse(literal) ?? double.nan;
}

/// JS `${value}` for a raw number field; non-finite values show as empty
/// (a browser number input cannot display them).
String _numberText(double? value) {
  if (value == null || !value.isFinite) {
    return '';
  }
  return jsNumberString(value);
}

/// JS `pressureInputValue`: display units, two decimals.
String _pressureText(double? value, String units) {
  if (value == null || !value.isFinite) {
    return '';
  }
  return convertToDisplay(value, 'pressureBar', units).toStringAsFixed(2);
}

/// JS drain field: `formatInputValue` in display units.
String _drainPressureText(double? value, String units) {
  if (value == null || !value.isFinite) {
    return '';
  }
  return formatInputValue(value, 'pressureBar', units);
}

/// JS `formatCompareInputValue` for temperatures (drops a trailing `.0`).
String _temperatureText(double? value, String units) {
  if (value == null || !value.isFinite) {
    return '';
  }
  return formatInputValue(
    value,
    'temperatureC',
    units,
  ).replaceFirst(_trailingZero, '');
}

Bank? _findBank(List<Bank> banks, String? id) {
  if (id == null) {
    return null;
  }
  for (final bank in banks) {
    if (bank.id == id) {
      return bank;
    }
  }
  return null;
}

/// Copies [row] with the given fields replaced. Fields that are not passed
/// keep their current value. Pass [clearBankId] to set `bankId` to null.
CompareRow _copyRow(
  CompareRow row, {
  String? bankId,
  bool clearBankId = false,
  double? pressureAddedBar,
  double? targetPressureBar,
  String? pressureInputMode,
  String? waitMode,
  double? waitMinutes,
  double? targetTemperatureC,
}) {
  return CompareRow(
    id: row.id,
    type: row.type,
    bankId: clearBankId ? null : (bankId ?? row.bankId),
    pressureAddedBar: pressureAddedBar ?? row.pressureAddedBar,
    targetPressureBar: targetPressureBar ?? row.targetPressureBar,
    pressureInputMode: pressureInputMode ?? row.pressureInputMode,
    waitMode: waitMode ?? row.waitMode,
    waitMinutes: waitMinutes ?? row.waitMinutes,
    targetTemperatureC: targetTemperatureC ?? row.targetTemperatureC,
    sourceBank: row.sourceBank,
  );
}

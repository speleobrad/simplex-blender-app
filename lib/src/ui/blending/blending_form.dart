import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/cylinder_preset_text.dart';
import 'package:simplex_blender/src/domain/gas_input.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/domain/units.dart';
import 'package:simplex_blender/src/ui/shared/number_input.dart';
import 'package:simplex_blender/src/ui/shell/tour_targets.dart';

const String _customPreset = 'custom';
const double _litresPerCuFtAtOneBar = 28.316846592 * 1.01325;
final RegExp _numericCharacters = RegExp(r'[0-9eE.+\-]');

/// Blending input form: working tank (current and target), cylinder, cooling
/// medium, and wait settings (JS `index.html` blending column and the form
/// handlers in `js/main.js`).
///
/// Every edit is written with `controller.setInputs(...)`, which recalculates.
/// The transfer (inlet) temperature is not part of this form; it is carried
/// through unchanged from `controller.inputs`.
class BlendingForm extends StatefulWidget {
  const BlendingForm({super.key, required this.controller, required this.app});

  final BlendController controller;
  final AppController app;

  @override
  State<BlendingForm> createState() => _BlendingFormState();
}

class _BlendingFormState extends State<BlendingForm> {
  final GlobalKey<_NumberFieldState> _initOxygenKey = GlobalKey();
  final GlobalKey<_NumberFieldState> _initHeliumKey = GlobalKey();
  final GlobalKey<_NumberFieldState> _targetOxygenKey = GlobalKey();
  final GlobalKey<_NumberFieldState> _targetHeliumKey = GlobalKey();

  /// Gas preset select values chosen by the user (JS `select.value`). Null
  /// means "derive from the gas values", as `renderPresetOptions` does.
  String? _initialPresetChoice;
  String? _targetPresetChoice;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[widget.controller, widget.app]),
      builder: (context, _) => _buildForm(context),
    );
  }

  Widget _buildForm(BuildContext context) {
    final inputs = widget.controller.inputs;
    final settings = widget.app.settings;
    final units = settings.units;
    final textTheme = Theme.of(context).textTheme;
    final hintColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final tour = TourTargetsScope.of(context);

    final presetItems = _gasPresetItems(settings.gasPresets);
    final initialPresetValue = _gasPresetValue(
      _initialPresetChoice,
      inputs.initialOxygenPercent,
      inputs.initialHeliumPercent,
      settings.gasPresets,
    );
    final targetPresetValue = _gasPresetValue(
      _targetPresetChoice,
      inputs.targetOxygenPercent,
      inputs.targetHeliumPercent,
      settings.gasPresets,
    );

    return Column(
      key: tour.keyFor('working-tank-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('Working tank', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('CURRENT', style: textTheme.labelLarge),
        Row(
          children: <Widget>[
            Expanded(
              child: _NumberField(
                label: 'Start pressure:',
                semanticsLabel:
                    'Start pressure in ${unitLabel('pressureBar', units)}',
                suffix: unitLabel('pressureBar', units),
                numeric: true,
                reformatOnInput: true,
                value: inputs.initialPressureBar,
                format: (value) => _displayText(value, 'pressureBar', units),
                parse: (text) => _fromDisplay(text, 'pressureBar', units),
                onCommit: (value) => _update(
                  (current) => current.copyWith(initialPressureBar: value),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumberField(
                key: tour.keyFor('ambient-temperature'),
                label: 'Ambient temperature:',
                suffix: unitLabel('temperatureC', units),
                numeric: true,
                value: inputs.ambientTemperatureC,
                format: (value) => _displayText(value, 'temperatureC', units),
                parse: (text) => _fromDisplay(text, 'temperatureC', units),
                onCommit: (value) => _update(
                  (current) => current.copyWith(ambientTemperatureC: value),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: _dropdown<String>(
                label: 'Gas preset',
                semanticsLabel: 'Current gas preset',
                value: initialPresetValue,
                items: presetItems,
                onChanged: (value) =>
                    _selectGasPreset(initial: true, value: value),
              ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: Focus(
                onKeyEvent: (node, event) =>
                    _gasShortcut(event, _initHeliumKey),
                child: _NumberField(
                  key: _initOxygenKey,
                  label: '% O₂',
                  semanticsLabel: 'Current oxygen percentage',
                  value: inputs.initialOxygenPercent,
                  format: _plainNumber,
                  parse: parseNumericInput,
                  onCommit: (value) => _editGas(initial: true, oxygen: value),
                  onSplit: (split) => _pasteGas(
                    initial: true,
                    split: split,
                    heliumKey: _initHeliumKey,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumberField(
                key: _initHeliumKey,
                label: '% He',
                semanticsLabel: 'Current helium percentage',
                value: inputs.initialHeliumPercent,
                format: _plainNumber,
                parse: parseNumericInput,
                onCommit: (value) => _editGas(initial: true, helium: value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('TARGET', style: textTheme.labelLarge),
        Row(
          children: <Widget>[
            Expanded(
              child: _NumberField(
                label: 'Target pressure:',
                semanticsLabel:
                    'Target pressure in ${unitLabel('pressureBar', units)}',
                suffix: unitLabel('pressureBar', units),
                numeric: true,
                reformatOnInput: true,
                value: inputs.targetPressureBar,
                format: (value) => _displayText(value, 'pressureBar', units),
                parse: (text) => _fromDisplay(text, 'pressureBar', units),
                onCommit: (value) => _update(
                  (current) => current.copyWith(targetPressureBar: value),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumberField(
                key: tour.keyFor('dive-site-temperature'),
                label: 'Dive site temperature:',
                suffix: unitLabel('temperatureC', units),
                numeric: true,
                value: inputs.targetInWaterTemperatureC,
                format: (value) => _displayText(value, 'temperatureC', units),
                parse: (text) => _fromDisplay(text, 'temperatureC', units),
                onCommit: (value) => _update(
                  (current) =>
                      current.copyWith(targetInWaterTemperatureC: value),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: _dropdown<String>(
                label: 'Gas preset',
                semanticsLabel: 'Target gas preset',
                value: targetPresetValue,
                items: presetItems,
                onChanged: (value) =>
                    _selectGasPreset(initial: false, value: value),
              ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: Focus(
                onKeyEvent: (node, event) =>
                    _gasShortcut(event, _targetHeliumKey),
                child: _NumberField(
                  key: _targetOxygenKey,
                  label: '% O₂',
                  semanticsLabel: 'Target oxygen percentage',
                  value: inputs.targetOxygenPercent,
                  format: _plainNumber,
                  parse: parseNumericInput,
                  onCommit: (value) => _editGas(initial: false, oxygen: value),
                  onSplit: (split) => _pasteGas(
                    initial: false,
                    split: split,
                    heliumKey: _targetHeliumKey,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumberField(
                key: _targetHeliumKey,
                label: '% He',
                semanticsLabel: 'Target helium percentage',
                value: inputs.targetHeliumPercent,
                format: _plainNumber,
                parse: parseNumericInput,
                onCommit: (value) => _editGas(initial: false, helium: value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _dropdown<String>(
          label: 'Cylinder',
          semanticsLabel: 'Working tank cylinder preset',
          value: _cylinderValue(inputs.cylinderPreset.name, settings),
          items: <DropdownMenuItem<String>>[
            for (final entry in sortCylinderPresetEntries(
              settings.cylinderPresets,
            ))
              DropdownMenuItem<String>(
                value: entry.preset.name,
                enabled: entry.preset.isComplete,
                child: Text(
                  entry.preset.isComplete
                      ? entry.preset.name
                      : '${entry.preset.name} (needs dimensions)',
                ),
              ),
          ],
          onChanged: _selectCylinder,
        ),
        const SizedBox(height: 4),
        Text(
          _cylinderRatingHint(inputs.cylinderPreset, units),
          style: textTheme.bodySmall?.copyWith(color: hintColor),
        ),
        const SizedBox(height: 12),
        _dropdown<String>(
          label: 'Surrounding medium',
          value: inputs.coolingMedium,
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(value: 'air', child: Text('Air')),
            DropdownMenuItem<String>(value: 'water', child: Text('Water')),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            _update((current) => current.copyWith(coolingMedium: value));
          },
        ),
        if (inputs.coolingMedium == 'water') ...<Widget>[
          const SizedBox(height: 12),
          _dropdown<double>(
            label: 'Tank submerged',
            value:
                waterSubmersionPercentOptions.contains(
                  inputs.waterSubmersionPercent,
                )
                ? inputs.waterSubmersionPercent
                : null,
            items: <DropdownMenuItem<double>>[
              for (final percent in waterSubmersionPercentOptions)
                DropdownMenuItem<double>(
                  value: percent,
                  child: Text('${percent.toStringAsFixed(0)}%'),
                ),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              _update(
                (current) => current.copyWith(waterSubmersionPercent: value),
              );
            },
          ),
        ],
        const SizedBox(height: 12),
        _dropdown<String>(
          label: 'Wait between fills',
          value: inputs.waitMode,
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(
              value: 'minutes',
              child: Text('Fixed minutes'),
            ),
            DropdownMenuItem<String>(
              value: 'temperature',
              child: Text('Target temperature'),
            ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            _update((current) => current.copyWith(waitMode: value));
          },
        ),
        if (inputs.waitMode == 'minutes') ...<Widget>[
          const SizedBox(height: 12),
          _NumberField(
            label: 'Wait time',
            suffix: 'min',
            numeric: true,
            value: inputs.waitMinutes,
            format: _plainNumber,
            parse: parseNumericInput,
            onCommit: (value) =>
                _update((current) => current.copyWith(waitMinutes: value)),
          ),
        ] else ...<Widget>[
          const SizedBox(height: 12),
          _NumberField(
            label: 'Target medium temperature',
            suffix: unitLabel('temperatureC', units),
            numeric: true,
            value: inputs.waitTargetTemperatureC,
            format: (value) => _displayText(value, 'temperatureC', units),
            parse: (text) => _fromDisplay(text, 'temperatureC', units),
            onCommit: (value) => _update(
              (current) => current.copyWith(waitTargetTemperatureC: value),
            ),
          ),
        ],
      ],
    );
  }

  void _update(BlendInputs Function(BlendInputs current) change) {
    widget.controller.setInputs(change(widget.controller.inputs));
  }

  void _setPresetChoice({required bool initial, required String value}) {
    setState(() {
      if (initial) {
        _initialPresetChoice = value;
      } else {
        _targetPresetChoice = value;
      }
    });
  }

  /// JS `markGasPresetCustom` on any gas input edit.
  void _editGas({required bool initial, double? oxygen, double? helium}) {
    _setPresetChoice(initial: initial, value: _customPreset);
    _update((current) {
      if (initial) {
        return current.copyWith(
          initialOxygenPercent: oxygen,
          initialHeliumPercent: helium,
        );
      }
      return current.copyWith(
        targetOxygenPercent: oxygen,
        targetHeliumPercent: helium,
      );
    });
  }

  /// JS `applyCylinderGasPreset`: only `gas:` values apply a preset.
  void _selectGasPreset({required bool initial, required String? value}) {
    if (value == null) {
      return;
    }
    _setPresetChoice(initial: initial, value: value);
    if (!value.startsWith('gas:')) {
      return;
    }
    final name = value.substring('gas:'.length);
    GasPreset? preset;
    for (final candidate in widget.app.settings.gasPresets) {
      if (candidate.name == name) {
        preset = candidate;
        break;
      }
    }
    if (preset == null) {
      return;
    }
    final found = preset;
    _update((current) {
      if (initial) {
        return current.copyWith(
          initialOxygenPercent: found.oxygenPercent,
          initialHeliumPercent: found.heliumPercent,
        );
      }
      return current.copyWith(
        targetOxygenPercent: found.oxygenPercent,
        targetHeliumPercent: found.heliumPercent,
      );
    });
  }

  /// JS `handleGasPaste`: a pasted `O2/He` text fills both gas fields.
  void _pasteGas({
    required bool initial,
    required GasInputSplit split,
    required GlobalKey<_NumberFieldState> heliumKey,
  }) {
    final inputs = widget.controller.inputs;
    final heliumText = split.heliumText;
    final heliumState = heliumKey.currentState;
    if (heliumText.isNotEmpty) {
      heliumState?.setText(heliumText);
    }
    final oxygen = parseNumericInput(split.oxygenText);
    final helium = heliumText.isNotEmpty
        ? parseNumericInput(heliumText)
        : (initial ? inputs.initialHeliumPercent : inputs.targetHeliumPercent);
    _setPresetChoice(initial: initial, value: _customPreset);
    _update((current) {
      if (initial) {
        return current.copyWith(
          initialOxygenPercent: oxygen,
          initialHeliumPercent: helium,
        );
      }
      return current.copyWith(
        targetOxygenPercent: oxygen,
        targetHeliumPercent: helium,
      );
    });
    heliumState?.focus();
  }

  /// JS `handleGasShortcut`: `/` typed in an oxygen field moves to helium.
  KeyEventResult _gasShortcut(
    KeyEvent event,
    GlobalKey<_NumberFieldState> heliumKey,
  ) {
    if (event is KeyDownEvent && event.character == '/') {
      heliumKey.currentState?.focusAndSelectAll();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _selectCylinder(String? name) {
    if (name == null) {
      return;
    }
    CylinderPreset? preset;
    for (final candidate in widget.app.settings.cylinderPresets) {
      if (candidate.name == name) {
        preset = candidate;
        break;
      }
    }
    if (preset == null) {
      return;
    }
    final found = preset;
    _update((current) => current.copyWith(cylinderPreset: found));
  }
}

/// Text field for one numeric value. It keeps its own text while the user
/// types, and only replaces that text when the model value changes elsewhere.
class _NumberField extends StatefulWidget {
  const _NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.format,
    required this.parse,
    required this.onCommit,
    this.semanticsLabel,
    this.suffix,
    this.numeric = false,
    this.reformatOnInput = false,
    this.onSplit,
  });

  final String label;
  final String? semanticsLabel;
  final String? suffix;

  /// Model value (internal metric units). NaN when the text is invalid.
  final double value;

  /// Model value to display text.
  final String Function(double value) format;

  /// Display text to model value. Returns NaN when the text is invalid.
  final double Function(String text) parse;

  /// Called with each new model value while the user types.
  final void Function(double value) onCommit;

  /// Restrict typed characters to those of an HTML `type="number"` input.
  final bool numeric;

  /// Re-format the text as it is typed (JS pressure `input` handler).
  final bool reformatOnInput;

  /// Called with a pasted `O2/He` text; the field keeps only the O2 part.
  final void Function(GasInputSplit split)? onSplit;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _text;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.format(widget.value));
  }

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameNumber(widget.parse(_text.text), widget.value)) {
      _setText(widget.format(widget.value));
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void setText(String text) => _setText(text);

  void focus() => _focusNode.requestFocus();

  void focusAndSelectAll() {
    _focusNode.requestFocus();
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _text.text.length,
    );
  }

  void _setText(String text) {
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onChanged(String text) {
    final onSplit = widget.onSplit;
    if (onSplit != null && text.contains('/')) {
      final split = splitGasInput(text);
      if (split != null) {
        _setText(split.oxygenText);
        onSplit(split);
        return;
      }
    }
    final parsed = widget.parse(text);
    if (widget.reformatOnInput && parsed.isFinite) {
      final reformatted = widget.format(parsed);
      if (reformatted != text) {
        _setText(reformatted);
      }
    }
    widget.onCommit(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _text,
      focusNode: _focusNode,
      keyboardType: signedDecimalKeyboard,
      inputFormatters: widget.numeric
          ? <TextInputFormatter>[
              FilteringTextInputFormatter.allow(_numericCharacters),
            ]
          : null,
      onChanged: _onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffix,
        isDense: true,
      ),
    );
    final semanticsLabel = widget.semanticsLabel;
    if (semanticsLabel == null) {
      return field;
    }
    return Semantics(label: semanticsLabel, child: field);
  }
}

Widget _dropdown<T>({
  required String label,
  String? semanticsLabel,
  required T? value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
}) {
  final decorated = InputDecorator(
    decoration: InputDecoration(labelText: label, isDense: true),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        items: items,
        onChanged: onChanged,
      ),
    ),
  );
  if (semanticsLabel == null) {
    return decorated;
  }
  return Semantics(label: semanticsLabel, child: decorated);
}

List<DropdownMenuItem<String>> _gasPresetItems(List<GasPreset> presets) {
  return <DropdownMenuItem<String>>[
    const DropdownMenuItem<String>(value: _customPreset, child: Text('Custom')),
    for (final entry in sortGasPresetEntries(presets))
      DropdownMenuItem<String>(
        value: 'gas:${entry.preset.name}',
        child: Text(entry.preset.name),
      ),
  ];
}

/// Select value for a gas preset dropdown: the user's choice when it is still
/// valid, otherwise the preset whose gas matches, otherwise Custom.
String _gasPresetValue(
  String? choice,
  double oxygen,
  double helium,
  List<GasPreset> presets,
) {
  if (choice == _customPreset) {
    return _customPreset;
  }
  if (choice != null &&
      presets.any((preset) => 'gas:${preset.name}' == choice)) {
    return choice;
  }
  for (final preset in presets) {
    if ((preset.oxygenPercent - oxygen).abs() < 1e-9 &&
        (preset.heliumPercent - helium).abs() < 1e-9) {
      return 'gas:${preset.name}';
    }
  }
  return _customPreset;
}

String? _cylinderValue(String name, Settings settings) {
  for (final preset in settings.cylinderPresets) {
    if (preset.name == name) {
      return name;
    }
  }
  return null;
}

/// JS `updateCylinderRatingHint`.
String _cylinderRatingHint(CylinderPreset preset, String units) {
  final imperial = normalizeUnits(units) == imperialUnits;
  final displayVolume = imperial
      ? preset.volumeL * preset.workingPressureBar / _litresPerCuFtAtOneBar
      : preset.volumeL;
  final volumeText =
      '${displayVolume.toStringAsFixed(2)} ${unitLabel('volumeL', units)}';
  final material = materialLabel(preset.material, units).toLowerCase();
  final mass = _equipmentValue(preset.massKg, 'massKg', units);
  final pressure = _equipmentValue(
    preset.workingPressureBar,
    'pressureBar',
    units,
  );
  final rating =
      '$volumeText $material cylinder, $mass empty assembly, '
      'rated to $pressure.';
  final geometry = cylinderGeometryText(preset);
  return geometry == null
      ? '$rating Needs diameter and length in Settings.'
      : '$rating $geometry';
}

String _equipmentValue(double value, String quantity, String units) {
  final display = convertToDisplay(value, quantity, units);
  return '${display.toStringAsFixed(2)} ${unitLabel(quantity, units)}';
}

/// Display text for a model value. Digit rules (pressure and temperature
/// in imperial units, temperature always one decimal) come from
/// [formatInputValue], as JS `formatMainInputValue` does.
String _displayText(double value, String quantity, String units) {
  return formatInputValue(value, quantity, units);
}

/// Display text to model value (JS `canonicalNumberValue`).
double _fromDisplay(String text, String quantity, String units) {
  return convertFromDisplay(parseNumericInput(text), quantity, units);
}

/// Plain number text, like JS `String(number)`.
String _plainNumber(double value) {
  if (!value.isFinite) {
    return '';
  }
  if (value == value.truncateToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toString();
}

bool _sameNumber(double left, double right) {
  return left == right || (left.isNaN && right.isNaN);
}

import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../../controllers/blend_controller.dart';
import '../../domain/gas_input.dart';
import '../../domain/units.dart';

/// Transfer conditions: the inventory-gas temperature field and its "Same as
/// ambient" checkbox (JS `#inlet-gas-temperature`, `#inlet-gas-same-as-ambient`,
/// index.html lines 823-837; `js/main.js` `effectiveInletTemperatureC` and
/// `syncInletGasTemperatureControl`).
///
/// [BlendInputs.inletTemperatureC] is the effective inlet temperature, so this
/// widget keeps it equal to the ambient temperature while "Same as ambient" is
/// checked. The checkbox state is widget state only; `BlendInputs` has no field
/// for it.
class TransferConditions extends StatefulWidget {
  const TransferConditions({
    super.key,
    required this.controller,
    required this.app,
  });

  final BlendController controller;
  final AppController app;

  @override
  State<TransferConditions> createState() => _TransferConditionsState();
}

class _TransferConditionsState extends State<TransferConditions> {
  final TextEditingController _text = TextEditingController();
  bool _sameAsAmbient = false;
  late String _shownUnits;

  @override
  void initState() {
    super.initState();
    _shownUnits = normalizeUnits(widget.app.settings.units);
    _text.text = _displayText(
      widget.controller.inputs.inletTemperatureC,
      _shownUnits,
    );
    widget.controller.addListener(_onModelChanged);
    widget.app.addListener(_onModelChanged);
  }

  @override
  void didUpdateWidget(TransferConditions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.app != widget.app) {
      oldWidget.controller.removeListener(_onModelChanged);
      oldWidget.app.removeListener(_onModelChanged);
      widget.controller.addListener(_onModelChanged);
      widget.app.addListener(_onModelChanged);
      // Resync after this build; the listener may notify and must not run
      // during the parent's build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _onModelChanged();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onModelChanged);
    widget.app.removeListener(_onModelChanged);
    _text.dispose();
    super.dispose();
  }

  /// Keeps the resolved inlet temperature and the field text in step with the
  /// controller (JS reads ambient live in `effectiveInletTemperatureC`, and
  /// `syncInletGasTemperatureControl` copies ambient into the field).
  void _onModelChanged() {
    if (!mounted) {
      return;
    }
    final inputs = widget.controller.inputs;
    if (_sameAsAmbient &&
        !_sameNumber(inputs.inletTemperatureC, inputs.ambientTemperatureC)) {
      widget.controller.setInputs(
        inputs.copyWith(inletTemperatureC: inputs.ambientTemperatureC),
      );
      return;
    }
    final units = normalizeUnits(widget.app.settings.units);
    final unitsChanged = units != _shownUnits;
    _shownUnits = units;
    if (_sameAsAmbient ||
        unitsChanged ||
        !_fieldMatches(inputs.inletTemperatureC, units)) {
      _text.text = _displayText(inputs.inletTemperatureC, units);
    }
  }

  void _onTextChanged(String text) {
    final inputs = widget.controller.inputs;
    widget.controller.setInputs(
      inputs.copyWith(inletTemperatureC: _canonicalFromText(text, _shownUnits)),
    );
  }

  void _onSameAsAmbientChanged(bool? value) {
    final checked = value ?? false;
    setState(() {
      _sameAsAmbient = checked;
    });
    if (checked) {
      final inputs = widget.controller.inputs;
      widget.controller.setInputs(
        inputs.copyWith(inletTemperatureC: inputs.ambientTemperatureC),
      );
    }
  }

  /// NaN equals NaN here, so a blank ambient does not keep the listener looping.
  static bool _sameNumber(double left, double right) {
    return left == right || (left.isNaN && right.isNaN);
  }

  /// JS `numberValue` + `canonicalNumberValue`: blank or malformed text gives
  /// NaN, which validation reports.
  static double _canonicalFromText(String text, String units) {
    final parsed = parseNumericInput(text);
    if (parsed.isNaN) {
      return double.nan;
    }
    return convertFromDisplay(parsed, 'temperatureC', units);
  }

  /// True when the field text already shows [canonicalC], so the text is kept
  /// as typed (for example "21." while typing).
  bool _fieldMatches(double canonicalC, String units) {
    final typed = _canonicalFromText(_text.text, units);
    if (typed.isNaN || canonicalC.isNaN) {
      return typed.isNaN && canonicalC.isNaN;
    }
    return (typed - canonicalC).abs() < 1e-9;
  }

  static String _displayText(double canonicalC, String units) {
    if (canonicalC.isNaN) {
      return '';
    }
    final shown = convertToDisplay(canonicalC, 'temperatureC', units);
    final fixed = shown.toStringAsFixed(2);
    if (!fixed.contains('.')) {
      return fixed;
    }
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) {
        final units = normalizeUnits(widget.app.settings.units);
        return Material(
          color: colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Transfer conditions', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _text,
                    enabled: !_sameAsAmbient,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Temperature of inventory gases',
                      suffixText: unitLabel('temperatureC', units),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: _onTextChanged,
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Same as ambient'),
                  value: _sameAsAmbient,
                  onChanged: _onSameAsAmbientChanged,
                ),
                const SizedBox(height: 4),
                Text(
                  'The temperature at which inventory gases are assumed to be '
                  'stored; compressor and source-specific temperature '
                  'modifiers still apply.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

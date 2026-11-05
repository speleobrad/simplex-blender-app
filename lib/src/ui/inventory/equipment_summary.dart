import 'package:flutter/material.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/domain/equipment_presets.dart';
import 'package:simplex_blender/src/domain/js_number.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/units.dart';

/// Inventory equipment summary (JS `renderEquipmentSummary`,
/// `js/ui/equipment-summary.js`): compressor and booster preset selectors, the
/// active equipment details, and a note pointing to Settings.
///
/// [onEquipmentChanged] runs after a preset selection is saved (JS
/// `selectInventoryEquipmentPreset` recalculates after saving).
class EquipmentSummary extends StatelessWidget {
  const EquipmentSummary({
    super.key,
    required this.app,
    this.onEquipmentChanged,
  });

  final AppController app;
  final VoidCallback? onEquipmentChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final settings = app.settings;
        final units = settings.units;
        final active = settings.booster;
        final compressorName = compressorDisplayName(
          active,
          settings.compressorPresets,
        );
        final boosterName = boosterDisplayName(active, settings.boosterPresets);
        final compressorNames = <String>[
          for (final preset in settings.compressorPresets) preset.name,
        ];
        final boosterNames = <String>[
          for (final preset in settings.boosterPresets) preset.name,
        ];
        final textTheme = Theme.of(context).textTheme;
        final muted = Theme.of(context).colorScheme.onSurfaceVariant;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PresetField(
              label: 'Compressor',
              value: compressorNames.contains(compressorName)
                  ? compressorName
                  : null,
              names: compressorNames,
              onChanged: (name) => _select(EquipmentCategory.compressor, name),
            ),
            const SizedBox(height: 8),
            _PresetField(
              label: 'Booster',
              value: boosterNames.contains(boosterName) ? boosterName : null,
              names: boosterNames,
              onChanged: (name) => _select(EquipmentCategory.booster, name),
            ),
            const SizedBox(height: 8),
            _DetailRow(
              label: 'Compressor details',
              value:
                  '$compressorName · '
                  '${_equipmentValue(active.compressorInletFlowLPerMin, 'flowLPerMin', units)} · '
                  '${_equipmentValue(active.maxCompressorPressureBar, 'pressureBar', units)}',
            ),
            const SizedBox(height: 4),
            _DetailRow(
              label: 'Booster details',
              value:
                  '$boosterName · '
                  'boost ${jsNumberString(active.oxygenBoostBpm)}/'
                  '${jsNumberString(active.otherBoostBpm)} BPM · '
                  'decant ${_rateValue(active.oxygenDecantRateBarPerMin, units)}/'
                  '${_rateValue(active.otherDecantRateBarPerMin, units)} '
                  '${unitLabel('pressureBar', units)}/min · '
                  '${_equipmentValue(active.maxBoosterOutputPressureBar, 'pressureBar', units)}',
            ),
            const SizedBox(height: 8),
            Text(
              'Choose available equipment here; equipment lists and properties '
              'can also be changed in Settings.',
              style: textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        );
      },
    );
  }

  void _select(EquipmentCategory category, String? name) {
    if (name == null) {
      return;
    }
    final next = selectEquipmentPreset(app.settings, category, name);
    if (next == null) {
      return;
    }
    app.applySettings(next);
    onEquipmentChanged?.call();
  }
}

/// JS `equipmentValue`: metric shows the raw number with its label; imperial
/// converts and formats with one decimal.
String _equipmentValue(double value, String quantity, String units) {
  if (normalizeUnits(units) == metricUnits) {
    return '${jsNumberString(value)} ${unitLabel(quantity, units)}';
  }
  return formatUnitValue(value, quantity, units);
}

/// JS `rateValue`: pressure rate in display units, 0 decimals metric and 1
/// decimal imperial.
String _rateValue(double value, String units) {
  final digits = normalizeUnits(units) == metricUnits ? 0 : 1;
  return convertToDisplay(value, 'pressureBar', units).toStringAsFixed(digits);
}

class _PresetField extends StatelessWidget {
  const _PresetField({
    required this.label,
    required this.value,
    required this.names,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> names;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      isEmpty: value == null,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          items: [
            for (final name in names)
              DropdownMenuItem<String>(value: name, child: Text(name)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 2,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant,
          ),
        ),
        Text(value),
      ],
    );
  }
}

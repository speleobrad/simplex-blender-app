import 'package:flutter/material.dart';
import 'package:simplex_blender/src/controllers/what_if_controller.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/domain/units.dart';
import 'package:simplex_blender/src/domain/what_if_scenario.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_format.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_number_field.dart';
import 'package:simplex_blender/src/ui/what_if/what_if_select.dart';

const String _customGas = 'custom';
const String _gasPrefix = 'gas:';

/// Starting-state editor: CURRENT card, SCENARIO card, and cylinder select.
/// Every edit goes straight to the controller, which re-runs the scenario.
class WhatIfStartFields extends StatelessWidget {
  const WhatIfStartFields({
    super.key,
    required this.controller,
    required this.settings,
    required this.onCopyFromBlending,
  });

  final WhatIfController controller;
  final Settings settings;
  final VoidCallback onCopyFromBlending;

  @override
  Widget build(BuildContext context) {
    final scenario = controller.scenario;
    final start = scenario.start ?? const WhatIfStart();
    final units = settings.units;
    final colors = Theme.of(context).colorScheme;

    final selectedCylinder = findCylinderPreset(
      settings.cylinderPresets,
      start.cylinderPresetName,
    );

    final current = _Card(
      title: 'CURRENT',
      titleColor: colors.secondary,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: WhatIfNumberField(
                key: const Key('what-if-field-pressureBar'),
                label: 'Start pressure:',
                suffixText: unitLabel('pressureBar', units),
                displayText: scenarioInputText(
                  start.pressureBar ?? 0,
                  'pressureBar',
                  units,
                ),
                onCommit: (value) => controller.applyStartPatch(
                  WhatIfStart(
                    pressureBar: convertFromDisplay(
                      value,
                      'pressureBar',
                      units,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: WhatIfNumberField(
                key: const Key('what-if-field-ambientTemperatureC'),
                label: 'Ambient temperature:',
                suffixText: unitLabel('temperatureC', units),
                displayText: scenarioInputText(
                  start.ambientTemperatureC ?? 0,
                  'temperatureC',
                  units,
                ),
                onCommit: (value) => controller.applyStartPatch(
                  WhatIfStart(
                    ambientTemperatureC: convertFromDisplay(
                      value,
                      'temperatureC',
                      units,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        _FieldError(controller, 'pressureBar'),
        _FieldError(controller, 'ambientTemperatureC'),
        const SizedBox(height: 8),
        WhatIfSelect<String>(
          key: const Key('what-if-field-gasPreset'),
          label: 'Gas preset',
          value: _selectedGasValue(start),
          items: <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(
              value: _customGas,
              child: Text('Custom'),
            ),
            for (final preset in settings.gasPresets)
              DropdownMenuItem<String>(
                value: '$_gasPrefix${preset.name}',
                child: Text(preset.name),
              ),
          ],
          onChanged: (value) {
            if (value == null || !value.startsWith(_gasPrefix)) {
              return;
            }
            controller.applyGasPreset(value.substring(_gasPrefix.length));
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: WhatIfNumberField(
                key: const Key('what-if-field-oxygenPercent'),
                label: '% O₂',
                displayText: jsNumberText(start.oxygenPercent ?? 0),
                onCommit: (value) => controller.applyStartPatch(
                  WhatIfStart(oxygenPercent: value),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: WhatIfNumberField(
                key: const Key('what-if-field-heliumPercent'),
                label: '% He',
                displayText: jsNumberText(start.heliumPercent ?? 0),
                onCommit: (value) => controller.applyStartPatch(
                  WhatIfStart(heliumPercent: value),
                ),
              ),
            ),
          ],
        ),
        _FieldError(controller, 'oxygenPercent'),
        _FieldError(controller, 'heliumPercent'),
      ],
    );

    final isWater = start.coolingMedium == 'water';
    final submersion =
        start.waterSubmersionPercent ?? defaultWaterSubmersionPercent;

    final scenarioCard = _Card(
      title: 'SCENARIO',
      titleColor: colors.primary,
      children: <Widget>[
        OutlinedButton(
          onPressed: onCopyFromBlending,
          child: const Text('Copy from Blending'),
        ),
        const SizedBox(height: 8),
        WhatIfSelect<String>(
          key: const Key('what-if-field-coolingMedium'),
          label: 'Surrounding medium:',
          value: start.coolingMedium,
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(value: 'air', child: Text('Air')),
            DropdownMenuItem<String>(value: 'water', child: Text('Water')),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            controller.applyStartPatch(WhatIfStart(coolingMedium: value));
          },
        ),
        _FieldError(controller, 'coolingMedium'),
        if (isWater) ...<Widget>[
          const SizedBox(height: 8),
          WhatIfSelect<double>(
            key: const Key('what-if-field-waterSubmersionPercent'),
            label: 'Tank submerged:',
            value: waterSubmersionPercentOptions.contains(submersion)
                ? submersion
                : null,
            items: <DropdownMenuItem<double>>[
              for (final option in waterSubmersionPercentOptions)
                DropdownMenuItem<double>(
                  value: option,
                  child: Text('${jsNumberText(option)}%'),
                ),
            ],
            onChanged: (value) {
              if (value == null) {
                return;
              }
              controller.applyStartPatch(
                WhatIfStart(waterSubmersionPercent: value),
              );
            },
          ),
          _FieldError(controller, 'waterSubmersionPercent'),
        ],
        const SizedBox(height: 8),
        WhatIfNumberField(
          key: const Key('what-if-field-inWaterTemperatureC'),
          label: 'Dive site temperature:',
          suffixText: unitLabel('temperatureC', units),
          displayText: scenarioInputText(
            start.inWaterTemperatureC ?? 0,
            'temperatureC',
            units,
          ),
          onCommit: (value) => controller.applyStartPatch(
            WhatIfStart(
              inWaterTemperatureC: convertFromDisplay(
                value,
                'temperatureC',
                units,
              ),
            ),
          ),
        ),
        _FieldError(controller, 'inWaterTemperatureC'),
      ],
    );

    final cylinder = _Card(
      children: <Widget>[
        WhatIfSelect<String>(
          key: const Key('what-if-field-cylinderPresetName'),
          label: 'Cylinder:',
          value: selectedCylinder?.name,
          items: <DropdownMenuItem<String>>[
            for (final preset in settings.cylinderPresets)
              DropdownMenuItem<String>(
                value: preset.name,
                child: Text(preset.name),
              ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            controller.applyStartPatch(WhatIfStart(cylinderPresetName: value));
          },
        ),
        _FieldError(controller, 'cylinderPresetName'),
        if (selectedCylinder != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            _cylinderHint(selectedCylinder, units),
            key: const Key('what-if-cylinder-hint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );

    final copyStatus = scenario.initialized
        ? 'Starting state copied from Blending; edits are independent.'
        : 'Starting state not copied yet.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(copyStatus, key: const Key('what-if-copy-status')),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 600) {
              return Column(
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: current),
                      const SizedBox(width: 12),
                      Expanded(child: scenarioCard),
                    ],
                  ),
                  const SizedBox(height: 12),
                  cylinder,
                ],
              );
            }
            return Column(
              children: <Widget>[
                current,
                const SizedBox(height: 12),
                scenarioCard,
                const SizedBox(height: 12),
                cylinder,
              ],
            );
          },
        ),
      ],
    );
  }

  String _selectedGasValue(WhatIfStart start) {
    for (final preset in settings.gasPresets) {
      if (preset.oxygenPercent == start.oxygenPercent &&
          preset.heliumPercent == start.heliumPercent) {
        return '$_gasPrefix${preset.name}';
      }
    }
    return _customGas;
  }
}

/// JS cylinder hint. Converts stored metric values to display units and
/// prints them as JS numbers.
String _cylinderHint(CylinderPreset preset, String? units) {
  final volume = jsNumberText(
    convertToDisplay(preset.volumeL, 'volumeL', units),
  );
  final mass = jsNumberText(convertToDisplay(preset.massKg, 'massKg', units));
  final working = jsNumberText(
    convertToDisplay(preset.workingPressureBar, 'pressureBar', units),
  );
  return '$volume ${unitLabel('volumeL', units)} · '
      '${materialLabel(preset.material, units)} · '
      '$mass ${unitLabel('massKg', units)} · '
      '$working ${unitLabel('pressureBar', units)} working pressure';
}

class _Card extends StatelessWidget {
  const _Card({this.title, this.titleColor, required this.children});

  final String? title;
  final Color? titleColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (title != null) ...<Widget>[
              Text(
                title!,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: titleColor, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Field keys whose errors render under a start-field control. Other
/// field-keyed errors are shown in the result area's flat error list.
const Set<String> whatIfStartErrorFields = <String>{
  'pressureBar',
  'ambientTemperatureC',
  'oxygenPercent',
  'heliumPercent',
  'coolingMedium',
  'waterSubmersionPercent',
  'inWaterTemperatureC',
  'cylinderPresetName',
};

/// Red text under a start control carrying the controller's field-keyed
/// message (JS `what-if-<field>-error`). Renders nothing without an error.
class _FieldError extends StatelessWidget {
  const _FieldError(this.controller, this.field);

  final WhatIfController controller;
  final String field;

  @override
  Widget build(BuildContext context) {
    final messages = <String>[
      for (final error in controller.fieldErrors)
        if (error.rowId == null && error.field == field) error.message,
    ];
    if (messages.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      messages.join(' '),
      key: Key('what-if-$field-error'),
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

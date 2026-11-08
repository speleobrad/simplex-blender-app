part of '../settings_screen.dart';

extension _CylinderPresetSection on _SettingsScreenState {
  // Cylinder presets -------------------------------------------------------

  Widget _cylinderSection() {
    final presets = _draft.cylinderPresets;
    return _section('Cylinder presets', <Widget>[
      const Text(
        'Each preset defines volume, material, assembly mass, working '
        'pressure, permitted transient hot overfill, and the body diameter and '
        'length (without valve) used for the heat-transfer surface. '
        'Ambient-settled and target-temperature pressures remain limited to '
        'working pressure.',
      ),
      for (final entry in sortCylinderPresetEntries(presets))
        _cylinderCard(entry.index, entry.preset, presets.length),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          key: const ValueKey<String>('add-cylinder-preset'),
          onPressed: _addCylinder,
          child: const Text('Add cylinder'),
        ),
      ),
    ]);
  }

  Widget _cylinderCard(int index, CylinderPreset preset, int count) {
    final units = _draft.units;
    final label = preset.name.isEmpty ? 'Cylinder' : preset.name;
    final volumeUnit = units == imperialUnits ? 'cu ft' : 'L';
    final massUnit = unitLabel('massKg', units);
    final pressureUnit = unitLabel('pressureBar', units);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    key: _key('cyl-name-$index'),
                    initialValue: preset.name,
                    decoration: const InputDecoration(
                      labelText: 'Cylinder preset name',
                      isDense: true,
                    ),
                    onChanged: (text) =>
                        _replaceCylinder(index, preset.copyWith(name: text)),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove $label',
                  onPressed: count <= 1 ? null : () => _removeCylinder(index),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _dropdown<String>(
              key: _key('cyl-material-$index'),
              label: 'Material',
              value: preset.material,
              items: <(String, String)>[
                for (final material in materialValues)
                  (material, materialLabel(material, units)),
              ],
              onChanged: (material) =>
                  _replaceCylinder(index, preset.copyWith(material: material)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _cylinderNumber(
                  id: 'cyl-volume-$index',
                  label: 'Volume ($volumeUnit)',
                  value: _cylinderVolumeDisplay(preset),
                  onChanged: (value) => _replaceCylinder(
                    index,
                    preset.copyWith(
                      volumeL: _cylinderVolumeFromDisplay(preset, value),
                    ),
                  ),
                ),
                _cylinderNumber(
                  id: 'cyl-mass-$index',
                  label: 'Mass ($massUnit)',
                  value: convertToDisplay(preset.massKg, 'massKg', units),
                  onChanged: (value) => _replaceCylinder(
                    index,
                    preset.copyWith(
                      massKg: convertFromDisplay(value, 'massKg', units),
                    ),
                  ),
                ),
                _cylinderNumber(
                  id: 'cyl-pressure-$index',
                  label: 'Working pressure ($pressureUnit)',
                  value: convertToDisplay(
                    preset.workingPressureBar,
                    'pressureBar',
                    units,
                  ),
                  onChanged: (value) => _replaceCylinder(
                    index,
                    preset.copyWith(
                      workingPressureBar: convertFromDisplay(
                        value,
                        'pressureBar',
                        units,
                      ),
                    ),
                  ),
                ),
                _cylinderNumber(
                  id: 'cyl-overfill-$index',
                  label: 'Hot overfill (%)',
                  value: preset.hotOverfillPercent,
                  onChanged: (value) => _replaceCylinder(
                    index,
                    preset.copyWith(hotOverfillPercent: value),
                  ),
                ),
                _cylinderNumber(
                  id: 'cyl-diameter-$index',
                  label: 'Diameter (mm)',
                  value: preset.diameterMm ?? double.nan,
                  display: _formatDimension,
                  onChanged: (value) => _replaceCylinder(
                    index,
                    preset.copyWith(diameterMm: value),
                  ),
                ),
                _cylinderNumber(
                  id: 'cyl-length-$index',
                  label: 'Length, no valve (mm)',
                  value: preset.lengthMm ?? double.nan,
                  display: _formatDimension,
                  onChanged: (value) =>
                      _replaceCylinder(index, preset.copyWith(lengthMm: value)),
                ),
              ],
            ),
            ..._cylinderGeometryNotes(index, preset),
          ],
        ),
      ),
    );
  }

  /// Surface for a complete preset, a needs-dimensions marker otherwise, and
  /// the advisory plausibility warning.
  List<Widget> _cylinderGeometryNotes(int index, CylinderPreset preset) {
    final scheme = Theme.of(context).colorScheme;
    final warning = cylinderPlausibilityMessage(
      volumeL: preset.volumeL,
      diameterMm: preset.diameterMm,
      lengthMm: preset.lengthMm,
    );
    return <Widget>[
      const SizedBox(height: 8),
      if (preset.isComplete)
        Text(
          'Heat-transfer surface: ${preset.surfaceAreaM2.toStringAsFixed(3)} m²',
          key: ValueKey<String>('cyl-surface-$index'),
        )
      else
        Text(
          'Needs diameter and length (body without valve, mm). Until then this '
          'preset cannot be used in calculations.',
          key: ValueKey<String>('cyl-incomplete-$index'),
          style: TextStyle(color: scheme.error),
        ),
      if (warning != null)
        Text(
          warning,
          key: ValueKey<String>('cyl-plausibility-$index'),
          style: TextStyle(color: scheme.error),
        ),
    ];
  }

  Widget _cylinderNumber({
    required String id,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    String Function(double)? display,
  }) {
    return SizedBox(
      width: 150,
      child: _NumberField(
        key: _key(id),
        label: label,
        value: value,
        display: display,
        onChanged: onChanged,
      ),
    );
  }

  /// Imperial volume is shown in cubic feet at working pressure (JS
  /// `cylinderDisplayValue`); metric volume is shown in litres.
  double _cylinderVolumeDisplay(CylinderPreset preset) {
    if (_draft.units == imperialUnits) {
      return preset.volumeL *
          preset.workingPressureBar /
          _litresPerCuFtAtOneBar;
    }
    return convertToDisplay(preset.volumeL, 'volumeL', _draft.units);
  }

  double _cylinderVolumeFromDisplay(CylinderPreset preset, double value) {
    if (_draft.units == imperialUnits) {
      return value * _litresPerCuFtAtOneBar / preset.workingPressureBar;
    }
    return convertFromDisplay(value, 'volumeL', _draft.units);
  }

  void _replaceCylinder(int index, CylinderPreset preset) {
    _update(
      _draft.copyWith(
        cylinderPresets: _replace(_draft.cylinderPresets, index, preset),
      ),
    );
  }

  void _addCylinder() {
    final name = createUniquePresetName(
      'New cylinder',
      _draft.cylinderPresets.map((preset) => preset.name),
    );
    _update(
      _draft.copyWith(
        cylinderPresets: <CylinderPreset>[
          ..._draft.cylinderPresets,
          CylinderPreset(
            name: name,
            volumeL: 12,
            material: 'steel',
            massKg: 14,
            workingPressureBar: 232,
            hotOverfillPercent: 2,
            diameterMm: double.nan,
            lengthMm: double.nan,
          ),
        ],
      ),
      structural: true,
    );
  }

  void _removeCylinder(int index) {
    if (_draft.cylinderPresets.length <= 1) {
      return;
    }
    final presets = List<CylinderPreset>.of(_draft.cylinderPresets)
      ..removeAt(index);
    _update(_draft.copyWith(cylinderPresets: presets), structural: true);
  }
}

part of '../settings_screen.dart';

extension _EquipmentSection on _SettingsScreenState {
  // Equipment --------------------------------------------------------------

  Widget _equipmentSection() {
    return _section('Equipment', <Widget>[_compressorBlock(), _boosterBlock()]);
  }

  Widget _compressorBlock() {
    final presets = _draft.compressorPresets;
    final selected = _activeCompressorName();
    final booster = _draft.booster;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 12),
        Text('Compressor', style: Theme.of(context).textTheme.titleSmall),
        _presetPicker(
          key: _key('compressor-select'),
          label: 'Compressor preset',
          names: <String>[for (final preset in presets) preset.name],
          selected: selected,
          addLabel: 'New compressor',
          addKey: const ValueKey<String>('add-compressor-preset'),
          removeKey: const ValueKey<String>('remove-compressor-preset'),
          canRemove: presets.length > 1,
          onSelect: (name) {
            final next = selectEquipmentPreset(
              _draft,
              EquipmentCategory.compressor,
              name,
            );
            if (next != null) {
              _update(next);
            }
          },
          onAdd: () => _addEquipment(EquipmentCategory.compressor),
          onRemove: () => _removeEquipment(EquipmentCategory.compressor),
        ),
        _equipmentNumber(
          id: 'compressor-inlet-flow',
          label: 'Compressor inlet flow',
          quantity: 'flowLPerMin',
          value: booster.compressorInletFlowLPerMin,
          onChanged: (value) => _setBooster(
            (current) => current.copyWith(compressorInletFlowLPerMin: value),
          ),
        ),
        _equipmentNumber(
          id: 'compressor-max-pressure',
          label: 'Max compressor pressure',
          quantity: 'pressureBar',
          value: booster.maxCompressorPressureBar,
          onChanged: (value) => _setBooster(
            (current) => current.copyWith(maxCompressorPressureBar: value),
          ),
        ),
        _equipmentNumber(
          id: 'compressor-temperature',
          label: 'Compressor temperature modifier',
          quantity: 'temperatureDeltaC',
          value: booster.compressorTemperatureModifierC,
          onChanged: (value) => _setBooster(
            (current) =>
                current.copyWith(compressorTemperatureModifierC: value),
          ),
        ),
      ],
    );
  }

  Widget _boosterBlock() {
    final presets = _draft.boosterPresets;
    final selected = _activeBoosterName();
    final booster = _draft.booster;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 12),
        Text('Booster', style: Theme.of(context).textTheme.titleSmall),
        _presetPicker(
          key: _key('booster-select'),
          label: 'Booster preset',
          names: <String>[for (final preset in presets) preset.name],
          selected: selected,
          addLabel: 'New booster',
          addKey: const ValueKey<String>('add-booster-preset'),
          removeKey: const ValueKey<String>('remove-booster-preset'),
          canRemove: presets.length > 1,
          onSelect: (name) {
            final next = selectEquipmentPreset(
              _draft,
              EquipmentCategory.booster,
              name,
            );
            if (next != null) {
              _update(next);
            }
          },
          onAdd: () => _addEquipment(EquipmentCategory.booster),
          onRemove: () => _removeEquipment(EquipmentCategory.booster),
        ),
        _equipmentNumber(
          id: 'booster-cylinder-volume',
          label: 'Booster cylinder volume',
          quantity: 'volumeCm3',
          value: booster.cylinderVolumeCm3,
          onChanged: (value) => _setBooster(
            (current) => current.copyWith(cylinderVolumeCm3: value),
          ),
        ),
        _equipmentNumber(
          id: 'booster-min-source',
          label: 'Mix source gas minimum pressure',
          quantity: 'pressureBar',
          value: booster.minimumSourcePressureBar,
          onChanged: (value) => _setBooster(
            (current) => current.copyWith(minimumSourcePressureBar: value),
          ),
        ),
        _equipmentNumber(
          id: 'booster-oxygen-boost',
          label: 'Oxygen boost speed (BPM)',
          quantity: null,
          value: booster.oxygenBoostBpm,
          onChanged: (value) =>
              _setBooster((current) => current.copyWith(oxygenBoostBpm: value)),
        ),
        _equipmentNumber(
          id: 'booster-other-boost',
          label: 'Other-gas boost speed (BPM)',
          quantity: null,
          value: booster.otherBoostBpm,
          onChanged: (value) =>
              _setBooster((current) => current.copyWith(otherBoostBpm: value)),
        ),
        _equipmentNumber(
          id: 'booster-max-output',
          label: 'Max booster output pressure',
          quantity: 'pressureBar',
          value: booster.maxBoosterOutputPressureBar,
          onChanged: (value) => _setBooster(
            (current) => current.copyWith(maxBoosterOutputPressureBar: value),
          ),
        ),
        _equipmentNumber(
          id: 'booster-temperature',
          label: 'Booster temperature modifier',
          quantity: 'temperatureDeltaC',
          value: booster.boosterTemperatureModifierC,
          onChanged: (value) => _setBooster(
            (current) => current.copyWith(boosterTemperatureModifierC: value),
          ),
        ),
        _equipmentNumber(
          id: 'booster-oxygen-decant',
          label: 'Oxygen manual decant rate',
          quantity: 'pressureBarPerMin',
          value: booster.oxygenDecantRateBarPerMin,
          onChanged: (value) => _setBooster(
            (current) => current.copyWith(oxygenDecantRateBarPerMin: value),
          ),
        ),
        _equipmentNumber(
          id: 'booster-other-decant',
          label: 'Other-gas manual decant rate',
          quantity: 'pressureBarPerMin',
          value: booster.otherDecantRateBarPerMin,
          onChanged: (value) => _setBooster(
            (current) => current.copyWith(otherDecantRateBarPerMin: value),
          ),
        ),
        _equipmentNumber(
          id: 'booster-draining',
          label: 'Draining rate',
          quantity: 'pressureBarPerMin',
          value: booster.drainingRateBarPerMin,
          onChanged: (value) => _setBooster(
            (current) => current.copyWith(drainingRateBarPerMin: value),
          ),
        ),
      ],
    );
  }

  /// Name of the compressor preset whose fields match the active booster
  /// fields, falling back to the first preset (JS `renderEquipmentPresetSelector`).
  String? _activeCompressorName() {
    final booster = _draft.booster;
    for (final preset in _draft.compressorPresets) {
      if (preset.inletFlowLPerMin == booster.compressorInletFlowLPerMin &&
          preset.maxPressureBar == booster.maxCompressorPressureBar &&
          preset.temperatureModifierC ==
              booster.compressorTemperatureModifierC) {
        return preset.name;
      }
    }
    return _draft.compressorPresets.isEmpty
        ? null
        : _draft.compressorPresets.first.name;
  }

  String? _activeBoosterName() {
    final booster = _draft.booster;
    for (final preset in _draft.boosterPresets) {
      if (preset.minimumSourcePressureBar == booster.minimumSourcePressureBar &&
          preset.cylinderVolumeCm3 == booster.cylinderVolumeCm3 &&
          preset.oxygenBoostBpm == booster.oxygenBoostBpm &&
          preset.otherBoostBpm == booster.otherBoostBpm &&
          preset.oxygenDecantRateBarPerMin ==
              booster.oxygenDecantRateBarPerMin &&
          preset.otherDecantRateBarPerMin == booster.otherDecantRateBarPerMin &&
          preset.maxOutputPressureBar == booster.maxBoosterOutputPressureBar &&
          preset.temperatureModifierC == booster.boosterTemperatureModifierC &&
          preset.drainingRateBarPerMin == booster.drainingRateBarPerMin) {
        return preset.name;
      }
    }
    return _draft.boosterPresets.isEmpty
        ? null
        : _draft.boosterPresets.first.name;
  }

  Widget _presetPicker({
    required Key key,
    required String label,
    required List<String> names,
    required String? selected,
    required String addLabel,
    required Key addKey,
    required Key removeKey,
    required bool canRemove,
    required ValueChanged<String> onSelect,
    required VoidCallback onAdd,
    required VoidCallback onRemove,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _dropdown<String>(
              key: key,
              label: label,
              value: selected,
              items: <(String, String)>[for (final name in names) (name, name)],
              onChanged: onSelect,
            ),
          ),
          TextButton(key: addKey, onPressed: onAdd, child: Text(addLabel)),
          TextButton(
            key: removeKey,
            onPressed: canRemove ? onRemove : null,
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _addEquipment(EquipmentCategory category) {
    switch (category) {
      case EquipmentCategory.compressor:
        _addCompressor();
      case EquipmentCategory.booster:
        _addBooster();
    }
  }

  void _addCompressor() {
    final draft = _draft;
    final name = createUniquePresetName(
      'New compressor',
      draft.compressorPresets.map((preset) => preset.name),
    );
    _update(
      draft.copyWith(
        compressorPresets: <CompressorPreset>[
          ...draft.compressorPresets,
          createCompressorPreset(draft, name),
        ],
      ),
    );
  }

  void _addBooster() {
    final draft = _draft;
    final name = createUniquePresetName(
      'New booster',
      draft.boosterPresets.map((preset) => preset.name),
    );
    _update(
      draft.copyWith(
        boosterPresets: <BoosterPreset>[
          ...draft.boosterPresets,
          createBoosterPreset(draft, name),
        ],
      ),
    );
  }

  void _removeEquipment(EquipmentCategory category) {
    switch (category) {
      case EquipmentCategory.compressor:
        _removeCompressor();
      case EquipmentCategory.booster:
        _removeBooster();
    }
  }

  /// Removes the active compressor preset (JS removeSelectedEquipmentPreset).
  void _removeCompressor() {
    final selected = _activeCompressorName();
    if (_draft.compressorPresets.length <= 1 || selected == null) {
      return;
    }
    final list = List<CompressorPreset>.of(_draft.compressorPresets)
      ..removeWhere((preset) => preset.name == selected);
    _update(_draft.copyWith(compressorPresets: list), structural: true);
  }

  void _removeBooster() {
    final selected = _activeBoosterName();
    if (_draft.boosterPresets.length <= 1 || selected == null) {
      return;
    }
    final list = List<BoosterPreset>.of(_draft.boosterPresets)
      ..removeWhere((preset) => preset.name == selected);
    _update(_draft.copyWith(boosterPresets: list), structural: true);
  }

  void _setBooster(SettingsBooster Function(SettingsBooster) change) {
    _update(_draft.copyWith(booster: change(_draft.booster)));
  }

  Widget _equipmentNumber({
    required String id,
    required String label,
    required String? quantity,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final units = _draft.units;
    final unit = quantity == null ? 'BPM' : unitLabel(quantity, units);
    return _NumberField(
      key: _key(id),
      label: quantity == null ? label : '$label ($unit)',
      value: quantity == null
          ? value
          : convertToDisplay(value, quantity, units),
      onChanged: (display) => onChanged(
        quantity == null
            ? display
            : convertFromDisplay(display, quantity, units),
      ),
    );
  }
}

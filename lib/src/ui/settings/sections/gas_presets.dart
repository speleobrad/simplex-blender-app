part of '../settings_screen.dart';

extension _GasPresetSection on _SettingsScreenState {
  // Gas presets ------------------------------------------------------------

  Widget _gasPresetSection() {
    final presets = _draft.gasPresets;
    return _section('Gas presets', <Widget>[
      for (final entry in sortGasPresetEntries(presets))
        _gasRow(entry.index, entry.preset, presets.length),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          key: const ValueKey<String>('add-gas-preset'),
          onPressed: _addGas,
          child: const Text('Add gas'),
        ),
      ),
    ]);
  }

  Widget _gasRow(int index, GasPreset preset, int count) {
    final label = preset.name.isEmpty ? 'Gas' : preset.name;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextFormField(
              key: _key('gas-name-$index'),
              initialValue: preset.name,
              decoration: const InputDecoration(
                labelText: 'Gas preset name',
                isDense: true,
              ),
              onChanged: (text) =>
                  _replaceGas(index, preset.copyWith(name: text)),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: _NumberField(
              key: _key('gas-o2-$index'),
              label: '$label oxygen percentage',
              value: preset.oxygenPercent,
              onChanged: (value) =>
                  _replaceGas(index, preset.copyWith(oxygenPercent: value)),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: _NumberField(
              key: _key('gas-he-$index'),
              label: '$label helium percentage',
              value: preset.heliumPercent,
              onChanged: (value) =>
                  _replaceGas(index, preset.copyWith(heliumPercent: value)),
            ),
          ),
          IconButton(
            tooltip: 'Remove $label',
            onPressed: count <= 1 ? null : () => _removeGas(index),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  void _replaceGas(int index, GasPreset preset) {
    _update(
      _draft.copyWith(gasPresets: _replace(_draft.gasPresets, index, preset)),
    );
  }

  void _addGas() {
    final name = createUniquePresetName(
      'New gas',
      _draft.gasPresets.map((preset) => preset.name),
    );
    _update(
      _draft.copyWith(
        gasPresets: <GasPreset>[
          ..._draft.gasPresets,
          GasPreset(name: name, oxygenPercent: 21, heliumPercent: 0),
        ],
      ),
      structural: true,
    );
  }

  void _removeGas(int index) {
    if (_draft.gasPresets.length <= 1) {
      return;
    }
    final presets = List<GasPreset>.of(_draft.gasPresets)..removeAt(index);
    _update(_draft.copyWith(gasPresets: presets), structural: true);
  }
}

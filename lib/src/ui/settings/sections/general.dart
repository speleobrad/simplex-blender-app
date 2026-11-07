part of '../settings_screen.dart';

extension _GeneralSection on _SettingsScreenState {
  // General --------------------------------------------------------------

  Widget _generalSection() {
    final draft = _draft;
    final warningUnlocked = draft.pressureWarningUnlocked;
    return _section('General', <Widget>[
      _dropdown<String>(
        key: _key('gas-model'),
        label: 'Gas model',
        value: draft.physics.model,
        items: const <(String, String)>[
          ('vdw', 'Van der Waals (real gas)'),
          ('ideal', 'Ideal gas'),
        ],
        onChanged: (model) =>
            _update(draft.copyWith(physics: PhysicsSettings(model: model))),
      ),
      const SizedBox(height: 12),
      _dropdown<String>(
        key: _key('units'),
        label: 'Units',
        value: draft.units,
        items: const <(String, String)>[
          ('metric', 'Metric'),
          ('imperial', 'Imperial'),
        ],
        onChanged: (units) => _update(draft.copyWith(units: units)),
      ),
      const SizedBox(height: 12),
      const Text('Cylinder pressure limit behavior'),
      const Text(
        'Hard stop prevents pressures above the cylinder rating. Warning '
        'mode allows them after confirmation.',
      ),
      _dropdown<String>(
        key: _key('pressure-mode'),
        label: 'Cylinder pressure limit behavior',
        value: draft.pressureLimitMode,
        items: const <(String, String)>[
          ('hard-stop', 'Hard stop'),
          ('warning', 'Warning'),
        ],
        onChanged: (mode) {
          if (mode == 'warning' && !warningUnlocked) {
            return;
          }
          _update(draft.copyWith(pressureLimitMode: mode));
        },
      ),
      if (draft.pressureLimitMode == 'warning')
        Text(
          _warningNotice,
          key: const ValueKey<String>('settings-pressure-warning-notice'),
        ),
      if (!warningUnlocked) _unlockControls(),
      const SizedBox(height: 12),
      _NumberField(
        key: _key('interim-tolerance'),
        label: 'Interim pressure tolerance (%)',
        value: draft.interimPressureTolerancePercent,
        onChanged: (value) =>
            _update(draft.copyWith(interimPressureTolerancePercent: value)),
      ),
      const Text(
        'A recorded interim pressure must be within this percentage of the '
        'planned pressure at the recorded temperature. Applies to Optimize '
        'readings only.',
      ),
      const SizedBox(height: 12),
      SwitchListTile(
        key: const ValueKey<String>('settings-analytics'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Send anonymous usage analytics'),
        value: widget.app.analyticsEnabled,
        onChanged: (enabled) {
          widget.app.setAnalyticsEnabled(enabled: enabled);
          _rebuild();
        },
      ),
    ]);
  }

  Widget _unlockControls() {
    final phraseMatches = matchesPressureWarningUnlockPhrase(
      _unlockController.text,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Type $PRESSURE_WARNING_UNLOCK_PHRASE to unlock Warning mode. '
            'Matching is case-insensitive; the apostrophe may be a single '
            'quote, backtick, or double quote.',
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey<String>('pressure-warning-confirmation'),
            controller: _unlockController,
            decoration: const InputDecoration(
              labelText: "Type I KNOW WHAT I'M DOING",
              isDense: true,
            ),
            onChanged: (_) => _rebuild(),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey<String>('unlock-pressure-warning'),
            onPressed: phraseMatches ? _unlockWarning : null,
            child: const Text('Unlock warning mode'),
          ),
        ],
      ),
    );
  }

  void _unlockWarning() {
    _unlockController.clear();
    _update(_draft.copyWith(pressureWarningUnlocked: true));
  }
}

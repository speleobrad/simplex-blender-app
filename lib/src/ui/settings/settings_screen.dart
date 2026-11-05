import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../analytics/analytics_events.dart';
import '../../controllers/app_controller.dart';
import '../../data/preset_source.dart';
import '../../domain/cost.dart';
import '../../domain/materials.dart';
import '../../domain/preset_import.dart';
import '../../domain/settings.dart';
import '../../domain/units.dart';
import '../shell/tour_targets.dart';

/// Litres per cubic foot at one bar used by the imperial cylinder volume
/// (JS `LITRES_PER_CU_FT_AT_ONE_BAR`, js/ui/settings-dialog.js:206).
const double _litresPerCuFtAtOneBar = 28.316846592 * 1.01325;

const String _factoryResetPrompt =
    'Reset all saved app data to factory settings? This cannot be undone.';
const String _factoryResetFailedMessage =
    'Factory reset failed. Saved data was not changed. Check that browser '
    'storage is enabled and try again.';
const String _factoryResetDoneMessage = 'Factory settings restored.';
const String _warningNotice =
    'Warning mode selected: cylinder limits are not enforced. Use caution.';

/// Settings editor: port of the Settings dialog (js/ui/settings-dialog.js and
/// js/main.js settings draft handling).
///
/// Edits accumulate in a local draft. Save applies the draft through
/// [AppController.applySettings]; Cancel discards it.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.app,
    this.onFactoryReset,
    this.filePicker,
    this.httpClient,
  });

  final AppController app;

  /// Runs after a factory reset succeeds (the shell clears What-if state, JS
  /// `resetFactorySettings`). Not called on cancel or failure.
  final VoidCallback? onFactoryReset;

  /// Replaces the native file picker (tests). Defaults to [pickPresetFile].
  final Future<PresetSourceText?> Function()? filePicker;

  /// Client for online preset URLs. Null uses a fresh client per request.
  final http.Client? httpClient;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Settings _draft = copySettings(widget.app.settings);
  final TextEditingController _unlockController = TextEditingController();
  List<String> _saveErrors = const <String>[];
  String? _status;
  int _generation = 0;

  // Preset import (JS `state.settingsImport`); local to this section.
  String _importCategory = 'gas';
  final TextEditingController _importUrlController = TextEditingController(
    text: PRESET_IMPORT_DEFAULT_URLS['gas'],
  );
  bool _importUrlTouched = false;
  List<PresetCandidate> _importCandidates = const <PresetCandidate>[];
  List<String> _importSelectedIds = const <String>[];
  String _importStatus = '';
  bool _importError = false;
  bool _importLoading = false;
  int _importRequestId = 0;
  AnalyticsPresetSource _importSource = AnalyticsPresetSource.file;

  @override
  void dispose() {
    _unlockController.dispose();
    _importUrlController.dispose();
    super.dispose();
  }

  ValueKey<String> _key(String id) =>
      ValueKey<String>('$_generation/${_draft.units}/$id');

  /// Replaces the draft with the saved settings and rebuilds every field.
  void _reload() {
    _draft = copySettings(widget.app.settings);
    _saveErrors = const <String>[];
    _status = null;
    _generation++;
    _unlockController.clear();
  }

  void _update(Settings next, {bool structural = false}) {
    setState(() {
      _draft = next;
      _saveErrors = const <String>[];
      _status = null;
      if (structural) {
        _generation++;
      }
    });
  }

  void _save() {
    final errors = widget.app.applySettings(_draft);
    setState(() {
      if (errors.isEmpty) {
        _reload();
      } else {
        _saveErrors = errors;
      }
    });
  }

  void _cancel() {
    setState(_reload);
  }

  Future<void> _confirmFactoryReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: const Text(_factoryResetPrompt),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final outcome = widget.app.factoryReset(confirm: () => true);
    setState(() {
      switch (outcome) {
        case FactoryResetOutcome.reset:
          _reload();
          _resetImportState();
          widget.onFactoryReset?.call();
          _status = _factoryResetDoneMessage;
        case FactoryResetOutcome.failed:
          _status = _factoryResetFailedMessage;
        case FactoryResetOutcome.cancelled:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final liveErrors = validateSettings(_draft);
    final shownErrors = liveErrors.isNotEmpty ? liveErrors : _saveErrors;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Settings', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text(
          'Configure units, presets, and equipment used by the calculator.',
        ),
        const SizedBox(height: 16),
        _categoryNav(),
        _selectedPane(),
        if (shownErrors.isNotEmpty) _errorBox(shownErrors, theme),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _status!,
              key: const ValueKey<String>('settings-status'),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            OutlinedButton(
              key: const ValueKey<String>('settings-cancel'),
              onPressed: _cancel,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey<String>('settings-save'),
              onPressed: _save,
              child: const Text('Save settings'),
            ),
          ],
        ),
      ],
    );
  }

  /// Category ids and labels in JS display order (index.html 74-79).
  static const List<(String, String)> _categories = <(String, String)>[
    ('general', 'General'),
    ('gas-presets', 'Gas presets'),
    ('cylinder-presets', 'Cylinder presets'),
    ('equipment', 'Equipment'),
    ('costs', 'Costs'),
    ('preset-management', 'Preset management'),
  ];

  /// Category buttons. The selection is read from the app, so the guided tour
  /// can change it.
  Widget _categoryNav() {
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) {
        final selected = widget.app.settingsCategory;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final entry in _categories)
              _categoryButton(entry.$1, entry.$2, selected == entry.$1),
          ],
        );
      },
    );
  }

  Widget _categoryButton(String id, String label, bool isSelected) {
    final Key key = id == 'equipment'
        ? TourTargetsScope.of(context).keyFor('settings-category-equipment')
        : ValueKey<String>('settings-category-$id');
    void onPressed() => widget.app.setSettingsCategory(id);
    return Semantics(
      selected: isSelected,
      child: isSelected
          ? FilledButton(key: key, onPressed: onPressed, child: Text(label))
          : OutlinedButton(key: key, onPressed: onPressed, child: Text(label)),
    );
  }

  /// The pane for the selected category. Only one pane is shown at a time.
  Widget _selectedPane() {
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) {
        final id = widget.app.settingsCategory;
        final Key paneKey = id == 'equipment'
            ? TourTargetsScope.of(context).keyFor('settings-pane-equipment')
            : ValueKey<String>('settings-pane-$id');
        final Widget pane = switch (id) {
          'gas-presets' => _gasPresetSection(),
          'cylinder-presets' => _cylinderSection(),
          'equipment' => _equipmentSection(),
          'costs' => _costsSection(),
          'preset-management' => _presetManagementSection(),
          _ => _generalSection(),
        };
        return KeyedSubtree(key: paneKey, child: pane);
      },
    );
  }

  Widget _errorBox(List<String> errors, ThemeData theme) {
    return Container(
      key: const ValueKey<String>('settings-errors'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.error),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final error in errors)
            Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

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
          setState(() {});
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
            onChanged: (_) => setState(() {}),
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

  // Costs ------------------------------------------------------------------

  Widget _costsSection() {
    final costs = _draft.costs;
    final prices = costs.operationPrices;
    return _section('Costs', <Widget>[
      TextFormField(
        key: _key('cost-currency'),
        initialValue: costs.currencySymbol,
        maxLength: 8,
        decoration: const InputDecoration(
          labelText: 'Currency symbol',
          isDense: true,
        ),
        onChanged: (text) => _update(_withCosts(currencySymbol: text)),
      ),
      _NumberField(
        key: _key('cost-discount'),
        label: 'Leftover gas discount (%)',
        value: costs.leftoverDiscountPercent,
        onChanged: (value) => _update(_withCosts(discountPercent: value)),
      ),
      _NumberField(
        key: _key('cost-boost'),
        label: 'Boost (per operation)',
        value: prices.boost,
        display: _formatFee,
        onChanged: (value) => _update(_withCosts(boost: _roundFee(value))),
      ),
      _NumberField(
        key: _key('cost-decant'),
        label: 'Decant incl. equalize (per operation)',
        value: prices.decant,
        display: _formatFee,
        onChanged: (value) => _update(_withCosts(decant: _roundFee(value))),
      ),
      _NumberField(
        key: _key('cost-topup'),
        label: 'Top-up (per operation, includes compressor air)',
        value: prices.topUp,
        display: _formatFee,
        onChanged: (value) => _update(_withCosts(topUp: _roundFee(value))),
      ),
    ]);
  }

  Settings _withCosts({
    String? currencySymbol,
    double? discountPercent,
    double? boost,
    double? decant,
    double? topUp,
  }) {
    final costs = _draft.costs;
    final prices = costs.operationPrices;
    return _draft.copyWith(
      costs: Costs(
        currencySymbol: currencySymbol ?? costs.currencySymbol,
        leftoverDiscountPercent:
            discountPercent ?? costs.leftoverDiscountPercent,
        operationPrices: OperationPrices(
          boost: boost ?? prices.boost,
          decant: decant ?? prices.decant,
          topUp: topUp ?? prices.topUp,
        ),
      ),
    );
  }

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

  // Cylinder presets -------------------------------------------------------

  Widget _cylinderSection() {
    final presets = _draft.cylinderPresets;
    return _section('Cylinder presets', <Widget>[
      const Text(
        'Each preset defines volume, material, assembly mass, working '
        'pressure, and permitted transient hot overfill. Ambient-settled and '
        'target-temperature pressures remain limited to working pressure.',
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cylinderNumber({
    required String id,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return SizedBox(
      width: 150,
      child: _NumberField(
        key: _key(id),
        label: label,
        value: value,
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

  // Preset management ------------------------------------------------------

  Widget _presetManagementSection() {
    final theme = Theme.of(context);
    final canConfirm = !_importLoading && _importCandidates.any(_isImportable);
    return _section('Preset management', <Widget>[
      const Text(
        'Load compatible JSON files, review the proposed entries, then import '
        'only the new presets you select.',
      ),
      const SizedBox(height: 8),
      _dropdown<String>(
        key: const ValueKey<String>('settings-preset-import-category'),
        label: 'Preset type',
        value: _importCategory,
        items: const <(String, String)>[
          ('gas', 'Gas presets'),
          ('cylinders', 'Cylinder presets'),
          ('equipment', 'Equipment presets'),
        ],
        onChanged: _selectImportCategory,
      ),
      const SizedBox(height: 8),
      const Text('Local JSON file'),
      const SizedBox(height: 4),
      OutlinedButton(
        key: const ValueKey<String>('settings-preset-import-file'),
        onPressed: _loadLocalFile,
        child: const Text('Choose JSON file'),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey<String>('settings-preset-import-url'),
        controller: _importUrlController,
        decoration: const InputDecoration(
          labelText: 'Online JSON URL',
          isDense: true,
        ),
        onChanged: (_) {
          _importUrlTouched = true;
        },
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        key: const ValueKey<String>('settings-preset-import-load-url'),
        onPressed: _loadOnline,
        child: const Text('Load online'),
      ),
      if (_importStatus.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        Text(
          _importStatus,
          key: const ValueKey<String>('settings-preset-import-status'),
          style: _importError
              ? TextStyle(color: theme.colorScheme.error)
              : null,
        ),
      ],
      if (_importCandidates.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        Column(
          key: const ValueKey<String>('settings-preset-import-candidates'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final candidate in _importCandidates)
              _importCandidateRow(candidate),
          ],
        ),
      ],
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          OutlinedButton(
            key: const ValueKey<String>('settings-preset-import-cancel'),
            onPressed: _cancelImport,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey<String>('settings-preset-import-button'),
            onPressed: canConfirm ? _confirmImport : null,
            child: Text(_importLoading ? 'Loading…' : 'Import selected'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'Reset presets, Inventory, and theme to the built-in defaults. This '
        'clears all saved app data.',
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        key: const ValueKey<String>('settings-factory-reset'),
        onPressed: _confirmFactoryReset,
        child: const Text('Reset to factory settings'),
      ),
    ]);
  }

  bool _isImportable(PresetCandidate candidate) =>
      candidate.status == 'new' && candidate.selectable;

  AnalyticsPresetCategory get _importAnalyticsCategory =>
      switch (_importCategory) {
        'cylinders' => AnalyticsPresetCategory.cylinder,
        'equipment' => AnalyticsPresetCategory.equipment,
        _ => AnalyticsPresetCategory.gas,
      };

  bool _isCurrentImportRequest(int requestId) =>
      mounted && requestId == _importRequestId;

  void _setImportStatus(String message, {bool error = false}) {
    _importStatus = message;
    _importError = error;
    _importLoading = false;
  }

  void _clearImportPreview() {
    _importCandidates = const <PresetCandidate>[];
    _importSelectedIds = const <String>[];
    _setImportStatus('');
  }

  /// JS `selectPresetImportCategory`: a new category drops the preview and
  /// discards any load still in flight.
  void _selectImportCategory(String category) {
    if (!PRESET_IMPORT_DEFAULT_URLS.containsKey(category)) {
      return;
    }
    setState(() {
      _importCategory = category;
      if (!_importUrlTouched) {
        _importUrlController.text = PRESET_IMPORT_DEFAULT_URLS[category] ?? '';
      }
      _importRequestId++;
      _clearImportPreview();
    });
  }

  /// JS `resetPresetImportState`, run after a factory reset.
  void _resetImportState() {
    _importCategory = 'gas';
    _importUrlTouched = false;
    _importUrlController.text = PRESET_IMPORT_DEFAULT_URLS['gas'] ?? '';
    _importRequestId++;
    _clearImportPreview();
  }

  /// Cancel discards the preview. A load still in flight is dropped by
  /// bumping the request id, so its result is ignored when it arrives.
  void _cancelImport() {
    setState(() {
      _importRequestId++;
      _clearImportPreview();
    });
  }

  /// JS `loadPresetFile`: a cancelled picker changes nothing.
  Future<void> _loadLocalFile() async {
    final pick = widget.filePicker ?? pickPresetFile;
    PresetSourceText? file;
    try {
      file = await pick();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _setImportStatus(
            'Could not load the local JSON file: ${_errorText(error)}',
            error: true,
          );
        });
      }
      return;
    }
    if (file == null || !mounted) {
      return;
    }
    final text = file.text;
    await _loadPresetText(
      sourceLabel: file.name,
      importSource: AnalyticsPresetSource.file,
      readText: () async => text,
    );
  }

  /// JS `loadPresetUrl`.
  Future<void> _loadOnline() async {
    final url = _importUrlController.text.trim();
    _importUrlController.text = url;
    if (url.isEmpty) {
      setState(() {
        _setImportStatus('Enter an online JSON URL before loading.');
      });
      return;
    }
    final client = widget.httpClient;
    await _loadPresetText(
      sourceLabel: url,
      importSource: AnalyticsPresetSource.url,
      readText: () => fetchPresetUrl(Uri.parse(url), client: client),
    );
  }

  /// JS `loadPresetText`: reads, parses, and previews. A result from a
  /// superseded request is dropped.
  Future<void> _loadPresetText({
    required String sourceLabel,
    required AnalyticsPresetSource importSource,
    required Future<String> Function() readText,
  }) async {
    final requestId = _importRequestId + 1;
    setState(() {
      _importRequestId = requestId;
      _importCandidates = const <PresetCandidate>[];
      _importSelectedIds = const <String>[];
      _importSource = importSource;
      _importStatus = 'Loading $sourceLabel…';
      _importError = false;
      _importLoading = true;
    });
    try {
      final text = await readText();
      if (!_isCurrentImportRequest(requestId)) {
        return;
      }
      final decoded = _decodePresetJson(text);
      if (!_isCurrentImportRequest(requestId)) {
        return;
      }
      _previewPresetImport(decoded);
    } on Object catch (error) {
      if (!_isCurrentImportRequest(requestId)) {
        return;
      }
      setState(() {
        _setImportStatus(
          'Could not load $sourceLabel: ${_errorText(error)}',
          error: true,
        );
      });
    }
  }

  /// Parses preset text, raising the JS message for invalid JSON.
  Object? _decodePresetJson(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      throw const FormatException(
        'The selected preset file is not valid JSON.',
      );
    }
  }

  /// JS `previewPresetImport`: summarizes the analysis and selects every new
  /// entry.
  void _previewPresetImport(Object? source) {
    final analysis = analyzePresetSource(
      _importCategory,
      source,
      widget.app.settings,
    );
    final candidates = analysis.candidates;
    final newCount = candidates.where((c) => c.status == 'new').length;
    final duplicateCount = candidates
        .where((c) => c.status == 'duplicate')
        .length;
    final invalidCount = candidates.where((c) => c.status == 'invalid').length;
    final summary =
        'Loaded ${candidates.length} entries. $newCount new '
        '$duplicateCount already present $invalidCount rejected';
    setState(() {
      _importCandidates = candidates;
      _importSelectedIds = <String>[
        for (final candidate in candidates)
          if (candidate.status == 'new') candidate.id,
      ];
      _setImportStatus(
        analysis.errors.isEmpty
            ? summary
            : '$summary ${analysis.errors.join(' ')}',
        error: analysis.errors.isNotEmpty,
      );
    });
  }

  void _toggleImportCandidate(PresetCandidate candidate, bool checked) {
    if (!candidate.selectable) {
      return;
    }
    final ids = <String>[..._importSelectedIds];
    if (checked) {
      if (!ids.contains(candidate.id)) {
        ids.add(candidate.id);
      }
    } else {
      ids.remove(candidate.id);
    }
    setState(() {
      _importSelectedIds = ids;
    });
  }

  /// JS `importSelectedPresets`.
  void _confirmImport() {
    final selectedIds = _importSelectedIds;
    if (selectedIds.isEmpty) {
      return;
    }
    try {
      widget.app.applyPresetImport(
        candidates: _importCandidates,
        selectedIds: selectedIds,
        category: _importAnalyticsCategory,
        source: _importSource,
      );
    } on Object catch (error) {
      setState(() {
        _setImportStatus(
          'Presets were not imported: ${_errorText(error)}',
          error: true,
        );
      });
      return;
    }
    final count = selectedIds.length;
    setState(() {
      _clearImportPreview();
      _importStatus = 'Imported $count preset${count == 1 ? '' : 's'}.';
      // The draft must pick up the saved presets, or Save would write back
      // the stale list.
      _reload();
    });
  }

  Widget _importCandidateRow(PresetCandidate candidate) {
    final enabled = _isImportable(candidate);
    final units = widget.app.settings.units;
    return Semantics(
      label: 'Import ${_candidateName(candidate.preset)}',
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: CheckboxListTile(
          key: ValueKey<String>(
            'settings-preset-import-candidate-${candidate.id}',
          ),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: enabled && _importSelectedIds.contains(candidate.id),
          onChanged: enabled && !_importLoading
              ? (checked) => _toggleImportCandidate(candidate, checked ?? false)
              : null,
          title: Text(_presetImportLabel(candidate, units)),
          subtitle: Text(
            '${_candidateStatusLabel(candidate)} — ${candidate.reason}',
          ),
        ),
      ),
    );
  }

  /// JS `presetImportLabel`.
  String _presetImportLabel(PresetCandidate candidate, String? units) {
    final preset = candidate.preset;
    final name = _jsText(preset['name']);
    return switch (candidate.category) {
      'gas' =>
        '$name — ${_jsText(preset['oxygenPercent'])}% O₂ / '
            '${_jsText(preset['heliumPercent'])}% He',
      'cylinders' =>
        '$name — ${_jsText(preset['volumeL'])} L / '
            '${materialLabel(_jsText(preset['material']), units)} / '
            '${_jsText(preset['workingPressureBar'])} bar',
      _ => _importEquipmentLabel(preset, name),
    };
  }

  /// JS `presetImportLabel` equipment branch: a booster has no inlet flow.
  String _importEquipmentLabel(Map<String, Object?> preset, String name) {
    final kind = preset['inletFlowLPerMin'] == null ? 'Booster' : 'Compressor';
    return '$kind: $name';
  }

  /// JS `candidate.preset.name || 'unnamed preset'`.
  String _candidateName(Map<String, Object?> preset) {
    final name = preset['name'];
    if (name == null || name == false || name == 0 || name == '') {
      return 'unnamed preset';
    }
    return _jsText(name);
  }

  /// JS `candidateStatusLabel`.
  String _candidateStatusLabel(PresetCandidate candidate) =>
      switch (candidate.status) {
        'duplicate' => 'Already exists',
        'invalid' => 'Rejected',
        _ => 'New',
      };

  /// Formats a decoded preset value the way a JS template literal does.
  String _jsText(Object? value) {
    if (value == null) {
      return 'undefined';
    }
    if (value is double &&
        value.isFinite &&
        value.abs() < 9e15 &&
        value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    return '$value';
  }

  /// Text of a thrown error, without the exception class prefix.
  String _errorText(Object error) => switch (error) {
    ArgumentError(:final message) => '$message',
    StateError(:final message) => message,
    FormatException(:final message) => message,
    http.ClientException(:final message) => message,
    _ => '$error',
  };

  // Shared helpers ---------------------------------------------------------

  Widget _dropdown<T>({
    required Key key,
    required String label,
    required T? value,
    required List<(T, String)> items,
    required ValueChanged<T> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          key: key,
          isExpanded: true,
          value: value,
          items: <DropdownMenuItem<T>>[
            for (final (itemValue, text) in items)
              DropdownMenuItem<T>(value: itemValue, child: Text(text)),
          ],
          onChanged: (next) {
            if (next != null) {
              onChanged(next);
            }
          },
        ),
      ),
    );
  }

  List<T> _replace<T>(List<T> items, int index, T value) {
    final copy = List<T>.of(items);
    copy[index] = value;
    return copy;
  }
}

/// Number text field: parses with `parseFloat` semantics (NaN for blank or
/// non-numeric text, which validation rejects).
class _NumberField extends StatelessWidget {
  const _NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.display,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String Function(double)? display;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: (display ?? _formatSettingNumber)(value),
      decoration: InputDecoration(labelText: label, isDense: true),
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      onChanged: (text) => onChanged(_parseNumber(text)),
    );
  }
}

double _parseNumber(String text) => double.tryParse(text.trim()) ?? double.nan;

String _formatSettingNumber(double value) =>
    value.isFinite ? value.toStringAsFixed(2) : value.toString();

String _formatFee(double value) =>
    value.isFinite ? value.toStringAsFixed(2) : '';

/// JS `Math.round(value * 100) / 100` for flat operation fees.
double _roundFee(double value) =>
    value.isFinite ? (value * 100 + 0.5).floorToDouble() / 100 : value;

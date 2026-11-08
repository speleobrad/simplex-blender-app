import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../analytics/analytics_events.dart';
import '../../controllers/app_controller.dart';
import '../../data/preset_source.dart';
import '../../domain/cost.dart';
import '../../domain/cylinder_geometry.dart';
import '../../domain/materials.dart';
import '../../domain/preset_import.dart';
import '../../domain/settings.dart';
import '../../domain/units.dart';
import '../shared/number_input.dart';
import '../shell/tour_targets.dart';

part 'sections/costs.dart';
part 'sections/cylinder_presets.dart';
part 'sections/equipment.dart';
part 'sections/gas_presets.dart';
part 'sections/general.dart';
part 'sections/number_field.dart';
part 'sections/preset_import.dart';

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

class _SettingsScreenState extends State<SettingsScreen>
    with _PresetImportSection {
  late Settings _draft = copySettings(widget.app.settings);
  final TextEditingController _unlockController = TextEditingController();
  List<String> _saveErrors = const <String>[];
  String? _status;
  int _generation = 0;

  @override
  void dispose() {
    _unlockController.dispose();
    _importUrlController.dispose();
    super.dispose();
  }

  ValueKey<String> _key(String id) =>
      ValueKey<String>('$_generation/${_draft.units}/$id');

  /// Replaces the draft with the saved settings and rebuilds every field.
  @override
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

  void _rebuild() => setState(() {});

  @override
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

  @override
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

  // Shared helpers ---------------------------------------------------------

  @override
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

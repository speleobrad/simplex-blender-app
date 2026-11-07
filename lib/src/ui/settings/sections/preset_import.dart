part of '../settings_screen.dart';

mixin _PresetImportSection on State<SettingsScreen> {
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

  // Provided by _SettingsScreenState.
  void _reload();
  Future<void> _confirmFactoryReset();
  Widget _section(String title, List<Widget> children);
  Widget _dropdown<T>({
    required Key key,
    required String label,
    required T? value,
    required List<(T, String)> items,
    required ValueChanged<T> onChanged,
  });

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
}

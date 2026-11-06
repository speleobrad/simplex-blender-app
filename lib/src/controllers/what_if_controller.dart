import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../analytics/analytics.dart';
import '../analytics/analytics_events.dart';
import '../domain/bank.dart';
import '../domain/compare_recipe.dart';
import '../domain/compare_run.dart';
import '../domain/domain_error.dart';
import '../domain/gas_input.dart';
import '../domain/input_validation.dart';
import '../domain/pressure_limits.dart';
import '../domain/pressure_warnings.dart';
import '../domain/settings.dart';
import '../domain/thermodynamics.dart';
import '../domain/what_if_scenario.dart';

const String _selectPresetMessage = 'Select an available cylinder preset.';
const String _gasCompositionMessage =
    'Initial oxygen and helium percentages must total no more than 100%.';
const String _physicsModelMessage = 'Physics model must be ideal or vdw.';
const String _correctionStatus =
    'Correct the highlighted scenario inputs before updating the scenario.';
const String _updatedStatus = 'Scenario updated.';
const String _simulationFailedStatus = 'Scenario simulation failed.';

/// JS `scenarioSharedInputErrors` prefix mapping: the input field a calculator
/// validation message belongs to. Messages with no mapping go to `scenario`.
String _sharedInputField(String message) {
  if (message.startsWith('Initial pressure') ||
      message.startsWith('Target pressure') ||
      message.startsWith('Cylinder working pressure')) {
    return 'pressureBar';
  }
  if (message.startsWith('Thermal ambient temperature') ||
      message.startsWith('Thermal target-medium temperature')) {
    return 'ambientTemperatureC';
  }
  if (message.startsWith('Thermal dive site temperature')) {
    return 'inWaterTemperatureC';
  }
  if (message.startsWith('Thermal cooling medium')) {
    return 'coolingMedium';
  }
  if (message.startsWith('Thermal water submersion')) {
    return 'waterSubmersionPercent';
  }
  return 'scenario';
}

/// One error of the What-if scenario. [rowId] is set only for errors on a
/// recipe row. [field] names the input the error belongs to, or `scenario`
/// when no input owns it (JS `scenarioError`).
class WhatIfError {
  const WhatIfError({
    required this.rowId,
    required this.field,
    required this.message,
  });

  final String? rowId;
  final String? field;
  final String message;
}

/// Inputs and results of the last successful What-if run. Mirrors `CompareRun`
/// in `blend_controller.dart`.
class WhatIfRun {
  const WhatIfRun({
    required this.input,
    required this.protocol,
    required this.simulation,
    required this.pressureLimitWarnings,
  });

  final WhatIfInput input;
  final CompareProtocol protocol;
  final ThermalCompareResult simulation;
  final List<CylinderPressureWarning> pressureLimitWarnings;
}

/// Controller for the What-if screen. Port of the JS `runWhatIf` flow and its
/// row and start-field handlers in `js/main.js`.
///
/// Invariants (from `docs/architecture.md`):
/// - A failed run keeps the last valid [result] and [warnings], and still
///   sets [hasRun] (JS `runWhatIf` validation and catch branches).
/// - [isStale] is derived: a result is stale once the draft revision or the
///   shared-input signature differs from the run that produced it, after a
///   successful run or a failed one alike (JS `whatIfResultIsStale`).
/// - Bank prices are excluded from the shared-input signature, so a price-only
///   change never marks the projection stale.
class WhatIfController extends ChangeNotifier {
  WhatIfController({
    required Analytics analytics,
    required List<Bank> banks,
    required Settings settings,
    double? inletTemperatureC,
    WhatIfScenario? scenario,
  }) : _analytics = analytics,
       _banks = banks,
       _settings = settings,
       _inletTemperatureC = inletTemperatureC,
       _scenario = scenario ?? createWhatIfScenario();

  final Analytics _analytics;
  List<Bank> _banks;
  Settings _settings;
  double? _inletTemperatureC;
  WhatIfScenario _scenario;

  WhatIfProjection? _result;
  List<CylinderPressureWarning> _warnings = const <CylinderPressureWarning>[];
  List<WhatIfError> _fieldErrors = const <WhatIfError>[];
  WhatIfRun? _lastRun;
  bool _hasRun = false;
  String _status = '';
  int _nextRowNumber = 1;

  WhatIfScenario get scenario => _scenario;

  /// Last valid projection. Kept unchanged by a failed run.
  WhatIfProjection? get result => _result;

  /// Pressure-limit warnings for [result]. Empty unless the pressure limit
  /// mode is `warning`.
  List<CylinderPressureWarning> get warnings => _warnings;

  /// Message text of [fieldErrors], in the same order.
  List<String> get errors => <String>[
    for (final error in _fieldErrors) error.message,
  ];

  /// Errors of the last run, with the row and field the domain reports.
  List<WhatIfError> get fieldErrors => _fieldErrors;

  /// Last successful run. Kept unchanged by a failed run, as [result] is.
  WhatIfRun? get lastRun => _lastRun;

  bool get hasRun => _hasRun;

  /// JS `whatIfResultIsStale`: the result is stale when the shared inputs or
  /// the draft changed since the run that produced it.
  bool get isStale => sharedInputChanged || draftChanged;

  /// The shared-input signature differs from the one captured at the last
  /// successful run (JS `sharedInputChanged`). False when no result exists.
  bool get sharedInputChanged {
    if (_result == null) {
      return false;
    }
    return _scenario.sharedInputSignature != _sharedSignature();
  }

  /// The draft revision differs from the result revision: rows or start fields
  /// were edited after the run that produced the result. False when no result
  /// exists.
  bool get draftChanged {
    if (_result == null) {
      return false;
    }
    return _scenario.resultRevision != _scenario.draftRevision;
  }

  String get status => _status;

  /// Stores new shared inputs. `isStale` is derived, so a change to the shared
  /// signature after a run marks the projection stale. Prices are not part of
  /// the signature, so a price-only change does not mark it stale.
  void updateSharedInputs({
    required List<Bank> banks,
    required Settings settings,
  }) {
    final changed =
        !identical(banks, _banks) || !identical(settings, _settings);
    _banks = banks;
    _settings = settings;
    if (changed) {
      notifyListeners();
    }
  }

  void setInletTemperatureC(double? inletTemperatureC) {
    if (inletTemperatureC == _inletTemperatureC) {
      return;
    }
    _inletTemperatureC = inletTemperatureC;
    notifyListeners();
  }

  /// JS `initializeWhatIfScenario`. Does nothing once the scenario is
  /// initialized. Does not run the scenario.
  void initializeScenario({
    required double? initialPressureBar,
    required double? initialOxygenPercent,
    required double? initialHeliumPercent,
    required String? cylinderPresetName,
    required double? ambientTemperatureC,
    required String? coolingMedium,
    required double? waterSubmersionPercent,
    required double? targetInWaterTemperatureC,
  }) {
    if (_scenario.initialized) {
      return;
    }
    _scenario = _scenario.copyWith(
      initialized: true,
      start: snapshotWhatIfFromBlending(
        initialPressureBar: initialPressureBar,
        initialOxygenPercent: initialOxygenPercent,
        initialHeliumPercent: initialHeliumPercent,
        cylinderPresetName: cylinderPresetName,
        ambientTemperatureC: ambientTemperatureC,
        coolingMedium: coolingMedium,
        waterSubmersionPercent: waterSubmersionPercent,
        targetInWaterTemperatureC: targetInWaterTemperatureC,
      ),
    );
    notifyListeners();
  }

  /// JS `copyWhatIfFromBlending`. Copies the blending start values into the
  /// scenario and runs it. Every run sets `hasRun`, whether it succeeds or
  /// fails.
  void copyFromBlending({
    required double? initialPressureBar,
    required double? initialOxygenPercent,
    required double? initialHeliumPercent,
    required String? cylinderPresetName,
    required double? ambientTemperatureC,
    required String? coolingMedium,
    required double? waterSubmersionPercent,
    required double? targetInWaterTemperatureC,
  }) {
    final snapshot = snapshotWhatIfFromBlending(
      initialPressureBar: initialPressureBar,
      initialOxygenPercent: initialOxygenPercent,
      initialHeliumPercent: initialHeliumPercent,
      cylinderPresetName: cylinderPresetName,
      ambientTemperatureC: ambientTemperatureC,
      coolingMedium: coolingMedium,
      waterSubmersionPercent: waterSubmersionPercent,
      targetInWaterTemperatureC: targetInWaterTemperatureC,
    );
    _scenario = applyWhatIfStartPatch(
      _scenario,
      snapshot,
    ).copyWith(initialized: true);
    _fieldErrors = const <WhatIfError>[];
    runWhatIf();
  }

  /// Merges [patch] into the scenario start and runs it.
  ///
  /// `WhatIfStart.merge` keeps only the non-null fields of [patch]. A field
  /// cannot be cleared to null through this method.
  void applyStartPatch(WhatIfStart patch) {
    _scenario = applyWhatIfStartPatch(_scenario, patch);
    _fieldErrors = const <WhatIfError>[];
    runWhatIf();
  }

  /// JS `resetFactorySettings` (`js/main.js` 723-725): restores the default
  /// scenario, clears the field errors, and clears `hasRun`. The stored result
  /// is left as JS leaves it.
  void resetForFactoryReset() {
    _scenario = createWhatIfScenario();
    _fieldErrors = const <WhatIfError>[];
    _hasRun = false;
    notifyListeners();
  }

  /// JS `applyWhatIfGasPreset`. Sets the oxygen and helium start fields from
  /// the named gas preset. Does nothing when the preset name is unknown.
  void applyGasPreset(String presetName) {
    GasPreset? preset;
    for (final candidate in _settings.gasPresets) {
      if (candidate.name == presetName) {
        preset = candidate;
        break;
      }
    }
    if (preset == null) {
      return;
    }
    applyStartPatch(
      WhatIfStart(
        oxygenPercent: preset.oxygenPercent,
        heliumPercent: preset.heliumPercent,
      ),
    );
  }

  /// Replaces every recipe row and runs the scenario.
  void updateRows(List<CompareRow> rows) {
    _scenario = _scenario.copyWith(
      rows: List<CompareRow>.of(rows),
      draftRevision: _scenario.draftRevision + 1,
    );
    _fieldErrors = const <WhatIfError>[];
    runWhatIf();
  }

  /// Appends a drain row with a fresh id and zero wait minutes.
  void addDrainRow() {
    final used = <String>{for (final row in _scenario.rows) row.id};
    final id = _nextRowId(used);
    final drain = createCompareRow('drain', id);
    updateRows(<CompareRow>[..._scenario.rows, _withWaitMinutes(drain, 0.0)]);
  }

  void removeRow(String id) {
    updateRows(<CompareRow>[
      for (final row in _scenario.rows)
        if (row.id != id) row,
    ]);
  }

  /// Moves the row by [delta] positions. Does nothing when the row is missing
  /// or the destination is out of range.
  void moveRow(String id, int delta) {
    final index = _scenario.rows.indexWhere((row) => row.id == id);
    final destination = index + delta;
    if (index < 0 || destination < 0 || destination >= _scenario.rows.length) {
      return;
    }
    final rows = List<CompareRow>.of(_scenario.rows);
    final moved = rows.removeAt(index);
    rows.insert(destination, moved);
    updateRows(rows);
  }

  /// JS `updateWhatIfRow` for `type`. Keeps the existing wait minutes.
  void setRowType(String id, String type) {
    _editRow(
      id,
      (row) => _withWaitMinutes(
        createCompareRow(type, row.id),
        row.waitMinutes ?? 0.0,
      ),
    );
  }

  void setRowBankId(String id, String? bankId) {
    _editRow(
      id,
      (row) => CompareRow(
        id: row.id,
        type: row.type,
        bankId: bankId,
        pressureAddedBar: row.pressureAddedBar,
        targetPressureBar: row.targetPressureBar,
        pressureInputMode: row.pressureInputMode,
        waitMode: row.waitMode,
        waitMinutes: row.waitMinutes,
        targetTemperatureC: row.targetTemperatureC,
        sourceBank: row.sourceBank,
      ),
    );
  }

  /// Values are already in bar. On an `add` row the paired pressure field is
  /// recomputed by `normalizeComparePressureFields`.
  void setRowPressureAddedBar(
    String id,
    double? pressureAddedBar, {
    String? pressureInputMode,
  }) {
    _editPressureRow(
      id,
      (row) => _pressureRow(
        row,
        pressureAddedBar: pressureAddedBar,
        targetPressureBar: row.targetPressureBar,
        pressureInputMode: pressureInputMode ?? row.pressureInputMode,
      ),
    );
  }

  /// Values are already in bar. On an `add` row the paired pressure field is
  /// recomputed by `normalizeComparePressureFields`.
  void setRowTargetPressureBar(
    String id,
    double? targetPressureBar, {
    String? pressureInputMode,
  }) {
    _editPressureRow(
      id,
      (row) => _pressureRow(
        row,
        pressureAddedBar: row.pressureAddedBar,
        targetPressureBar: targetPressureBar,
        pressureInputMode: pressureInputMode ?? row.pressureInputMode,
      ),
    );
  }

  void setRowWaitMode(String id, String? waitMode) {
    _editRow(
      id,
      (row) => CompareRow(
        id: row.id,
        type: row.type,
        bankId: row.bankId,
        pressureAddedBar: row.pressureAddedBar,
        targetPressureBar: row.targetPressureBar,
        pressureInputMode: row.pressureInputMode,
        waitMode: waitMode,
        waitMinutes: row.waitMinutes,
        targetTemperatureC: row.targetTemperatureC,
        sourceBank: row.sourceBank,
      ),
    );
  }

  void setRowTargetTemperatureC(String id, double? targetTemperatureC) {
    _editRow(
      id,
      (row) => CompareRow(
        id: row.id,
        type: row.type,
        bankId: row.bankId,
        pressureAddedBar: row.pressureAddedBar,
        targetPressureBar: row.targetPressureBar,
        pressureInputMode: row.pressureInputMode,
        waitMode: row.waitMode,
        waitMinutes: row.waitMinutes,
        targetTemperatureC: targetTemperatureC,
        sourceBank: row.sourceBank,
      ),
    );
  }

  void setRowWaitMinutes(String id, double? waitMinutes) {
    _editRow(
      id,
      (row) => CompareRow(
        id: row.id,
        type: row.type,
        bankId: row.bankId,
        pressureAddedBar: row.pressureAddedBar,
        targetPressureBar: row.targetPressureBar,
        pressureInputMode: row.pressureInputMode,
        waitMode: row.waitMode,
        waitMinutes: waitMinutes,
        targetTemperatureC: row.targetTemperatureC,
        sourceBank: row.sourceBank,
      ),
    );
  }

  /// JS `runWhatIf`. Returns null on success and the status text on failure.
  String? runWhatIf() {
    final input = buildWhatIfInput(
      _scenario,
      settings: _settings,
      banks: _banks,
      inletTemperatureC: _inletTemperatureC,
    );
    final errors = _sharedInputErrors(input);
    final runInputs = _compareRunInputs(input);
    if (runInputs == null) {
      return _rejectRun(errors);
    }

    final rows = expandWhatIfRows(_scenario.rows);
    final waitStates = compareWaitStates(runInputs, rows);
    final validation = validateCompareRecipe(
      rows,
      cylinder: runInputs.compareCylinder,
      banks: _banks,
      physics: runInputs.physics,
      settings: compareSettingsOf(_settings),
      waitStates: waitStates,
    );
    errors.addAll(<WhatIfError>[
      for (final error in validation.errors)
        WhatIfError(
          rowId: error.rowId,
          field: error.field,
          message: error.message,
        ),
    ]);
    if (errors.isNotEmpty) {
      return _rejectRun(errors);
    }

    try {
      final protocol = buildCompareProtocol(
        validation.normalizedRows,
        cylinder: runInputs.compareCylinder,
        physics: runInputs.physics,
        banks: _banks,
        settings: compareSettingsOf(_settings),
        waitStates: waitStates,
      );
      final simulation = simulateCompareProtocol(
        protocolSteps: <ProtocolStep>[
          for (final step in protocol.protocolSteps) protocolStepOf(step),
        ],
        cylinder: runInputs.cylinder,
        physics: runInputs.physics,
        thermal: runInputs.thermal,
        booster: boosterSettingsOf(_settings),
      );
      final inWaterTemperatureC = input.inWaterTemperatureC;
      if (inWaterTemperatureC == null) {
        throw StateError('Target in-water temperature is missing.');
      }
      final projection = projectWhatIfInWater(
        simulation.finalSummary.ambientSettled,
        inWaterTemperatureC: inWaterTemperatureC,
        volumeL: runInputs.cylinder.volumeL,
        useVdw: input.physicsModel == 'vdw',
      );
      final warnings = collectPressureWarnings(
        pressureLimitMode: input.settings.pressureLimitMode,
        cylinder: CylinderPressureSpec(
          workingPressureBar: input.cylinderPreset?.workingPressureBar,
          hotOverfillPercent: input.cylinderPreset?.hotOverfillPercent,
        ),
        observations: pressureWarningObservationsForWhatIf(
          initialPressureBar: input.initialPressureBar,
          ambientTemperatureC: input.ambientTemperatureC,
          compare: simulation,
          inWaterPressureBar: projection.pressureBar,
        ),
      );
      return _acceptRun(
        input: input,
        protocol: protocol,
        simulation: simulation,
        projection: projection,
        warnings: warnings,
      );
    } on DomainError catch (error) {
      return _rejectSimulation(_scenarioError(_messageOf(error.message)));
    } on CompareSimulationError catch (error) {
      return _rejectSimulation(_simulationError(error));
    } on RangeError catch (error) {
      return _rejectSimulation(_scenarioError(_messageOf(error.message)));
    } on StateError catch (error) {
      return _rejectSimulation(_scenarioError(_messageOf(error.message)));
    }
  }

  String? _acceptRun({
    required WhatIfInput input,
    required CompareProtocol protocol,
    required ThermalCompareResult simulation,
    required WhatIfProjection projection,
    required List<CylinderPressureWarning> warnings,
  }) {
    _result = projection;
    _warnings = List<CylinderPressureWarning>.unmodifiable(warnings);
    _lastRun = WhatIfRun(
      input: input,
      protocol: protocol,
      simulation: simulation,
      pressureLimitWarnings: _warnings,
    );
    _fieldErrors = const <WhatIfError>[];
    _hasRun = true;
    _status = _updatedStatus;
    _scenario = _scenario.copyWith(
      resultRevision: _scenario.draftRevision,
      sharedInputSignature: _sharedSignature(),
    );
    _track(AnalyticsOutcome.feasible);
    notifyListeners();
    return null;
  }

  /// Validation failure: the scenario inputs are invalid, so no simulation
  /// ran. Sets `hasRun` (JS `runWhatIf` validation branch). The last valid
  /// result is kept.
  String _rejectRun(List<WhatIfError> errors) {
    _hasRun = true;
    _fieldErrors = List<WhatIfError>.unmodifiable(errors);
    _status = _correctionStatus;
    _track(AnalyticsOutcome.invalidInput);
    notifyListeners();
    return _status;
  }

  /// Simulation failure: the run raised an error. Sets `hasRun` (JS
  /// `runWhatIf` catch branch). The error message becomes the status and the
  /// single entry in `fieldErrors`.
  String _rejectSimulation(WhatIfError error) {
    _hasRun = true;
    _fieldErrors = <WhatIfError>[error];
    _status = error.message;
    _track(AnalyticsOutcome.infeasible);
    notifyListeners();
    return error.message;
  }

  /// JS `scenarioError` for an error not tied to one input.
  WhatIfError _scenarioError(String message) =>
      WhatIfError(rowId: null, field: 'scenario', message: message);

  /// JS `scenarioSimulationError`. An unreachable target wait is attached to
  /// the first target-mode wait row whose target matches the reported one (or
  /// any target when the reported one is not finite). Other errors, and
  /// unreachable errors with no matching row, go to `scenario`.
  WhatIfError _simulationError(CompareSimulationError error) {
    final message = _messageOf(error.message);
    if (error.code == 'COMPARE_TARGET_STATE_UNREACHABLE') {
      final raw = error.details['targetTemperatureC'];
      final target = raw is num ? raw.toDouble() : double.nan;
      for (final row in _scenario.rows) {
        if (row.type == 'wait' &&
            row.waitMode == 'target' &&
            (!target.isFinite || row.targetTemperatureC == target)) {
          return WhatIfError(
            rowId: row.id,
            field: 'targetTemperatureC',
            message: message,
          );
        }
      }
    }
    return _scenarioError(message);
  }

  /// JS `scenarioSharedInputErrors`. Returns errors in the JS order. The
  /// gas composition message is reported under both oxygen and helium.
  List<WhatIfError> _sharedInputErrors(WhatIfInput input) {
    final preset = input.cylinderPreset;
    final initialPressureBar = input.initialPressureBar;
    final ambientTemperatureC = input.ambientTemperatureC;
    final errors = <WhatIfError>[
      if (preset == null)
        const WhatIfError(
          rowId: null,
          field: 'cylinderPresetName',
          message: _selectPresetMessage,
        ),
      for (final message in validateCalculatorInputs(
        CalculatorCylinder(
          volumeL: preset?.volumeL,
          initialPressureBar: initialPressureBar,
          targetPressureBar: initialPressureBar == null
              ? null
              : math.max(10.0, initialPressureBar),
          workingPressureBar: preset?.workingPressureBar,
          hotOverfillPercent: preset?.hotOverfillPercent,
        ),
        CalculatorPhysics(temperatureC: input.physicsTemperatureC),
        CalculatorThermal(
          ambientTemperatureC: ambientTemperatureC,
          tankMaterial: input.tankMaterial,
          coolingMedium: input.coolingMedium,
          waterSubmersionPercent: input.waterSubmersionPercent,
          inletTemperatureC: input.inletTemperatureC,
          targetMediumTemperatureC: ambientTemperatureC,
          targetInWaterTemperatureC: input.inWaterTemperatureC,
        ),
        pressureLimitMode: input.settings.pressureLimitMode,
      ))
        WhatIfError(
          rowId: null,
          field: _sharedInputField(message),
          message: message,
        ),
    ];
    if (!isValidGasComposition(
      input.initialOxygenPercent,
      input.initialHeliumPercent,
    )) {
      errors.addAll(const <WhatIfError>[
        WhatIfError(
          rowId: null,
          field: 'oxygenPercent',
          message: _gasCompositionMessage,
        ),
        WhatIfError(
          rowId: null,
          field: 'heliumPercent',
          message: _gasCompositionMessage,
        ),
      ]);
    }
    if (input.physicsModel != 'ideal' && input.physicsModel != 'vdw') {
      errors.add(
        const WhatIfError(
          rowId: null,
          field: 'scenario',
          message: _physicsModelMessage,
        ),
      );
    }
    return errors;
  }

  /// Builds the compare inputs for a run. Returns null when a value the
  /// compare engine requires is missing. In that case [_sharedInputErrors]
  /// always reports at least one message.
  CompareRunInputs? _compareRunInputs(WhatIfInput input) {
    final preset = input.cylinderPreset;
    final oxygen = input.initialOxygenPercent;
    final helium = input.initialHeliumPercent;
    final ambient = input.ambientTemperatureC;
    if (preset == null || oxygen == null || helium == null || ambient == null) {
      return null;
    }
    final initialPressureBar = input.initialPressureBar;
    return CompareRunInputs(
      compareCylinder: CompareCylinder(
        volumeL: preset.volumeL,
        workingPressureBar: preset.workingPressureBar,
        initialPressureBar: initialPressureBar,
        initialOxygenPercent: oxygen,
        initialHeliumPercent: helium,
      ),
      cylinder: CylinderInput(
        volumeL: preset.volumeL,
        initialPressureBar: initialPressureBar,
        initialOxygenPercent: oxygen,
        initialHeliumPercent: helium,
      ),
      physics: PhysicsInput(model: input.physicsModel, temperatureC: ambient),
      thermal: ThermalInput(
        ambientTemperatureC: ambient,
        tankMaterial: input.tankMaterial,
        coolingMedium: input.coolingMedium,
        waterSubmersionPercent: input.waterSubmersionPercent,
        tankMassKg: input.tankMassKg,
        inletTemperatureC: input.inletTemperatureC,
        targetMediumTemperatureC: ambient,
        targetInWaterTemperatureC: input.inWaterTemperatureC,
      ),
      banks: input.banks,
      settings: input.settings,
    );
  }

  void _editRow(String id, CompareRow Function(CompareRow row) edit) {
    final index = _scenario.rows.indexWhere((row) => row.id == id);
    if (index < 0) {
      return;
    }
    final rows = List<CompareRow>.of(_scenario.rows);
    rows[index] = edit(rows[index]);
    updateRows(rows);
  }

  /// Like [_editRow], but on an `add` row the pressure pair is normalized
  /// against the receiver start pressure, as in JS `updateWhatIfRow`. When the
  /// compare inputs are incomplete, the start pressure is unavailable and the
  /// edited values are stored unchanged. The next run then reports the errors.
  void _editPressureRow(String id, CompareRow Function(CompareRow row) edit) {
    _editRow(id, (row) {
      final edited = edit(row);
      if (edited.type != 'add') {
        return edited;
      }
      final runInputs = _compareRunInputs(
        buildWhatIfInput(
          _scenario,
          settings: _settings,
          banks: _banks,
          inletTemperatureC: _inletTemperatureC,
        ),
      );
      if (runInputs == null) {
        return edited;
      }
      final starts = comparePressureStarts(
        runInputs,
        expandWhatIfRows(_scenario.rows),
      );
      final start = starts[id];
      if (start == null) {
        return edited;
      }
      final fields = normalizeComparePressureFields(edited, start);
      return _pressureRow(
        edited,
        pressureAddedBar: fields.pressureAddedBar,
        targetPressureBar: fields.targetPressureBar,
        pressureInputMode: fields.pressureInputMode,
      );
    });
  }

  CompareRow _pressureRow(
    CompareRow row, {
    required double? pressureAddedBar,
    required double? targetPressureBar,
    required String? pressureInputMode,
  }) {
    return CompareRow(
      id: row.id,
      type: row.type,
      bankId: row.bankId,
      pressureAddedBar: pressureAddedBar,
      targetPressureBar: targetPressureBar,
      pressureInputMode: pressureInputMode,
      waitMode: row.waitMode,
      waitMinutes: row.waitMinutes,
      targetTemperatureC: row.targetTemperatureC,
      sourceBank: row.sourceBank,
    );
  }

  CompareRow _withWaitMinutes(CompareRow row, double waitMinutes) {
    return CompareRow(
      id: row.id,
      type: row.type,
      bankId: row.bankId,
      pressureAddedBar: row.pressureAddedBar,
      targetPressureBar: row.targetPressureBar,
      pressureInputMode: row.pressureInputMode,
      waitMode: row.waitMode,
      waitMinutes: waitMinutes,
      targetTemperatureC: row.targetTemperatureC,
      sourceBank: row.sourceBank,
    );
  }

  String _nextRowId(Set<String> used) {
    while (true) {
      final id = 'compare-row-${_nextRowNumber++}';
      if (!used.contains(id)) {
        return id;
      }
    }
  }

  String _sharedSignature() {
    return whatIfSharedInputSignature(
      settings: _settings,
      banks: _banks,
      cylinderPresetName: _scenario.start?.cylinderPresetName,
      inletTemperatureC: _inletTemperatureC,
    );
  }

  void _track(AnalyticsOutcome outcome) {
    trackBlendCalculated(
      _analytics,
      mode: AnalyticsBlendMode.whatIf,
      outcome: outcome,
    );
  }

  /// Reads an error message. Non-string messages fall back to the generic
  /// text.
  String _messageOf(Object? message) {
    return message is String ? message : _simulationFailedStatus;
  }
}

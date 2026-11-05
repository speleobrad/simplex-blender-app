/// Canonical app state, ported from the shared handlers in `js/main.js`.
///
/// Owns the Inventory banks, saved settings, theme preference, tour state,
/// primary screen, and storage warning flags. Other controllers receive the
/// banks and settings from here; this class imports no other controller.
library;

import 'package:flutter/foundation.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/analytics/analytics_events.dart';
import 'package:simplex_blender/src/data/analytics_storage.dart';
import 'package:simplex_blender/src/data/bank_storage.dart';
import 'package:simplex_blender/src/data/factory_reset_storage.dart';
import 'package:simplex_blender/src/data/key_value_storage.dart';
import 'package:simplex_blender/src/data/onboarding_storage.dart';
import 'package:simplex_blender/src/data/settings_storage.dart';
import 'package:simplex_blender/src/data/theme_storage.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/factory_reset.dart';
import 'package:simplex_blender/src/domain/input_validation.dart';
import 'package:simplex_blender/src/domain/navigation.dart';
import 'package:simplex_blender/src/domain/onboarding.dart';
import 'package:simplex_blender/src/domain/preset_import.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/storage_warning.dart';
import 'package:simplex_blender/src/domain/theme.dart';

/// Shown in the Settings dialog when saving the settings fails
/// (JS `saveSettingsDraft`).
const String settingsSaveFailureMessage =
    'Settings were not saved. Check that browser storage is enabled and has '
    'space, then try again.';

/// Outcome of [AppController.factoryReset].
enum FactoryResetOutcome {
  /// The user confirmed and every stored value was cleared and reloaded.
  reset,

  /// The user declined; nothing was changed.
  cancelled,

  /// Clearing or reloading storage threw; the in-memory state is unchanged.
  failed,
}

class AppController extends ChangeNotifier {
  AppController({
    required KeyValueStorage storage,
    required Analytics analytics,
  }) : _storage = storage,
       _analytics = GatedAnalytics(
         analytics,
         enabled: loadAnalyticsEnabled(storage),
       ) {
    _banks = loadSupplyBanks(
      _storage,
      onFallback: (_) {
        _banksLoadFailure = true;
      },
    );
    _settings = loadSettings(
      _storage,
      onFallback: (_) {
        _settingsLoadFailure = true;
      },
    );
    _themePreference = loadThemePreference(_storage);
    _onboarding = loadOnboardingState(
      _storage,
      onFallback: (_) {
        _onboardingLoadFailure = true;
      },
    );
  }

  final KeyValueStorage _storage;
  final GatedAnalytics _analytics;

  /// Sink that blend, what-if, and navigation controllers must report through.
  /// It drops every event while analytics is turned off.
  Analytics get analytics => _analytics;

  /// Whether analytics events are sent (Settings → General switch).
  bool get analyticsEnabled => _analytics.enabled;

  /// Turns analytics on or off and saves the choice. A failed save keeps the
  /// in-memory choice for this launch.
  void setAnalyticsEnabled({required bool enabled}) {
    _analytics.enabled = enabled;
    try {
      saveAnalyticsEnabled(enabled, _storage);
    } on Object {
      // Best effort: the in-memory choice still applies this launch.
    }
    notifyListeners();
  }

  late List<Bank> _banks;
  late Settings _settings;
  late String _themePreference;
  late OnboardingState _onboarding;
  String _primaryScreen = 'blending';
  String _settingsCategory = 'general';

  bool _settingsLoadFailure = false;
  bool _settingsSaveFailure = false;
  bool _banksLoadFailure = false;
  bool _bankSaveFailure = false;
  bool _onboardingLoadFailure = false;

  /// Rejection message of the last rejected Inventory edit, already prefixed
  /// with the bank name as in JS `rejectBankEdit`.
  String? _bankInputFailure;
  String? _bankInputFailureBankId;

  bool _startupTracked = false;

  /// Inventory banks, in display order. The list is read-only.
  List<Bank> get banks => List<Bank>.unmodifiable(_banks);

  Settings get settings => _settings;

  String get themePreference => _themePreference;

  OnboardingState get onboarding => _onboarding;

  String get primaryScreen => _primaryScreen;

  bool get settingsLoadFailure => _settingsLoadFailure;

  bool get settingsSaveFailure => _settingsSaveFailure;

  bool get banksLoadFailure => _banksLoadFailure;

  bool get bankSaveFailure => _bankSaveFailure;

  bool get onboardingLoadFailure => _onboardingLoadFailure;

  /// Message of the last rejected Inventory edit, or null when none is active.
  String? get bankInputFailure => _bankInputFailure;

  /// Storage warning lines for the current failure flags, in JS display order.
  List<String> get storageWarning => getStorageWarningMessages(
    settingsLoadFailure: _settingsLoadFailure,
    banksLoadFailure: _banksLoadFailure,
    bankSaveFailure: _bankSaveFailure,
    onboardingLoadFailure: _onboardingLoadFailure,
    bankInputFailureMessage: _bankInputFailure,
  );

  /// Sends `app_started`. Only the first call sends it, so one launch sends
  /// exactly one event.
  void startup() {
    if (_startupTracked) {
      return;
    }
    _startupTracked = true;
    trackAppStarted(_analytics);
  }

  /// Appends a default Inventory bank (JS `addBank`).
  void addBank() {
    final bank = Bank(
      id: 'bank-${DateTime.now().millisecondsSinceEpoch}',
      name: 'New Mix',
      volumeL: 50,
      pressureBar: 200,
      maxPressureBar: 200,
      oxygenPercent: 32,
      heliumPercent: 0,
      enabled: true,
    );
    _banks = <Bank>[..._banks, bank];
    _persistBanks();
  }

  /// Replaces the bank with the same id as [updated] (JS `commitBankUpdate`).
  ///
  /// A rejected edit leaves [banks] unchanged and sets [bankInputFailure].
  /// An accepted edit clears any earlier rejection for that bank.
  void updateBank(Bank updated) {
    final index = _indexOfBank(updated.id);
    if (index < 0) {
      return;
    }
    final current = _banks[index];
    if (updated.oxygenPercent == 21 && updated.heliumPercent == 0) {
      rejectBankEdit(
        current,
        'Air is supplied by the compressor and cannot be a finite supply bank.',
      );
      return;
    }
    final errors = validateSupplyBankInput(bankToRecord(updated));
    if (errors.isNotEmpty) {
      rejectBankEdit(current, errors.first);
      return;
    }
    clearBankInputFailure(updated.id);
    _banks = <Bank>[
      for (final bank in _banks)
        if (bank.id == updated.id) updated else bank,
    ];
    _persistBanks();
  }

  /// Enables or disables a bank (JS `toggle-bank`). Never rejected.
  void setBankEnabled(String bankId, {required bool enabled}) {
    final index = _indexOfBank(bankId);
    if (index < 0) {
      return;
    }
    _banks = <Bank>[
      for (final bank in _banks)
        if (bank.id == bankId) bank.copyWith(enabled: enabled) else bank,
    ];
    _persistBanks();
  }

  /// Removes a bank (JS `removeBank`).
  void removeBank(String bankId) {
    final index = _indexOfBank(bankId);
    if (index < 0) {
      return;
    }
    clearBankInputFailure(bankId);
    _banks = <Bank>[
      for (final bank in _banks)
        if (bank.id != bankId) bank,
    ];
    _persistBanks();
  }

  /// Validates and saves [next] (JS `saveSettingsDraft`).
  ///
  /// Returns the validation errors and leaves the settings unchanged when
  /// they are invalid. When the save fails, returns
  /// [settingsSaveFailureMessage], sets [settingsSaveFailure], and keeps the
  /// previous settings in memory. Returns an empty list when applied.
  List<String> applySettings(Settings next) {
    final errors = validateSettings(next);
    if (errors.isNotEmpty) {
      return errors;
    }
    try {
      saveSettings(next, _storage);
    } on Object {
      _settingsSaveFailure = true;
      notifyListeners();
      return const <String>[settingsSaveFailureMessage];
    }
    _settingsSaveFailure = false;
    _settingsLoadFailure = false;
    _settings = copySettings(next);
    notifyListeners();
    return const <String>[];
  }

  /// Saves the theme preference (JS `toggleTheme`).
  ///
  /// The new theme is kept in memory even when saving fails, as in the web
  /// app. Returns false for an unknown theme or a failed save; returns true
  /// when the preference was stored.
  bool setThemePreference(String theme) {
    if (!isThemePreference(theme)) {
      return false;
    }
    _themePreference = theme;
    notifyListeners();
    try {
      saveThemePreference(theme, _storage);
    } on Object {
      return false;
    }
    return true;
  }

  /// Records that the tour was seen (Done, Skip, or Escape). Stores only
  /// `wizardSeen`; there is no consent state.
  void markTourSeen() {
    final next = _onboarding.copyWith(wizardSeen: true);
    try {
      saveOnboardingState(next, _storage);
    } on Object {
      // The dismissal still applies for this session when storage is
      // unavailable, as in the web app.
    }
    _onboarding = next;
    notifyListeners();
  }

  /// Switches the primary screen (JS `selectScreen`). Returns false for an
  /// unknown screen. Sends `screen_view` only when the screen changes.
  bool setPrimaryScreen(String screenId) {
    if (!isPrimaryScreen(screenId)) {
      return false;
    }
    if (screenId == _primaryScreen) {
      return true;
    }
    _primaryScreen = screenId;
    trackScreenView(_analytics, _analyticsScreen(screenId));
    notifyListeners();
    return true;
  }

  /// Settings category currently shown (JS `state.settingsCategory`). It
  /// persists across Settings openings.
  String get settingsCategory => _settingsCategory;

  /// Selects a Settings category (JS `setSettingsCategory`). An unknown
  /// category is ignored.
  void setSettingsCategory(String category) {
    if (!isSettingsCategory(category) || category == _settingsCategory) {
      return;
    }
    _settingsCategory = category;
    notifyListeners();
  }

  /// Navigates as JS `onNavigate` does (`js/main.js` 237-245). A destination
  /// with a settings category opens Settings and selects that category;
  /// otherwise the primary screen is selected. The category is applied only
  /// when it is known, while Settings still opens, matching JS.
  void navigate({required String screen, String? settingsCategory}) {
    if (settingsCategory == null) {
      setPrimaryScreen(screen);
      return;
    }
    setPrimaryScreen('settings');
    setSettingsCategory(settingsCategory);
  }

  /// Runs the factory reset after [confirm] returns true (JS
  /// `resetFactorySettings`). Storage is cleared and every value is reloaded
  /// from defaults. Cancel and failure leave the state unchanged.
  FactoryResetOutcome factoryReset({required bool Function() confirm}) {
    final state = FactoryResetState(
      settings: _settings,
      banks: _banks,
      theme: _themePreference,
      onboarding: _onboarding,
    );
    try {
      final didReset = resetApplicationState(
        state,
        confirm,
        () => resetApplicationData(_storage),
      );
      if (!didReset) {
        return FactoryResetOutcome.cancelled;
      }
    } on Object {
      return FactoryResetOutcome.failed;
    }
    _settings = state.settings;
    _banks = state.banks;
    _themePreference = state.theme;
    _onboarding = state.onboarding;
    _settingsLoadFailure = false;
    _settingsSaveFailure = false;
    _banksLoadFailure = false;
    _bankSaveFailure = false;
    _onboardingLoadFailure = false;
    _bankInputFailure = null;
    _bankInputFailureBankId = null;
    trackFactoryReset(_analytics);
    _analytics.enabled = true;
    notifyListeners();
    return FactoryResetOutcome.reset;
  }

  /// Writes the selected presets from a preset import (JS
  /// `importSelectedPresets`). Nothing is selected: no change.
  ///
  /// Throws [RangeError] when the selection is not importable, and rethrows
  /// the storage error when the save fails. In both cases the settings stay
  /// unchanged.
  void applyPresetImport({
    required List<PresetCandidate> candidates,
    required Iterable<String> selectedIds,
    required AnalyticsPresetCategory category,
    required AnalyticsPresetSource source,
  }) {
    final selected = selectedIds.toSet();
    if (selected.isEmpty) {
      return;
    }
    final merged = mergeSelectedPresets(_settings, candidates, selected);
    saveSettings(merged, _storage);
    _settings = copySettings(merged);
    _settingsLoadFailure = false;
    _settingsSaveFailure = false;
    trackPresetImported(
      _analytics,
      category: category,
      source: source,
      count: selected.length,
    );
    notifyListeners();
  }

  int _indexOfBank(String bankId) =>
      _banks.indexWhere((bank) => bank.id == bankId);

  /// JS `rejectBankEdit`: records the message without changing [banks].
  void rejectBankEdit(Bank bank, String message) {
    _bankInputFailureBankId = bank.id;
    _bankInputFailure = '${bank.name}: $message';
    notifyListeners();
  }

  /// JS `clearBankInputFailure`: clears only a rejection for [bankId].
  void clearBankInputFailure(String bankId) {
    if (_bankInputFailureBankId != bankId) {
      return;
    }
    _bankInputFailureBankId = null;
    _bankInputFailure = null;
  }

  /// JS `persistSupplyBanks`. The in-memory edit is kept even when the save
  /// fails, so the user keeps working and sees the warning.
  void _persistBanks() {
    try {
      saveSupplyBanks(_banks, _storage);
      _banksLoadFailure = false;
      _bankSaveFailure = false;
    } on Object {
      _bankSaveFailure = true;
    }
    notifyListeners();
  }

  AnalyticsScreen _analyticsScreen(String screenId) => switch (screenId) {
    'blending' => AnalyticsScreen.blending,
    'what-if' => AnalyticsScreen.whatIf,
    'inventory' => AnalyticsScreen.inventory,
    'settings' => AnalyticsScreen.settings,
    'about' => AnalyticsScreen.about,
    _ => throw ArgumentError.value(screenId, 'screenId', 'Unknown screen'),
  };
}

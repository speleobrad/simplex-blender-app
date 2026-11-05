import 'bank.dart';
import 'onboarding.dart';
import 'settings.dart';

/// Application data loaded after a factory reset.
class ApplicationData {
  const ApplicationData({
    required this.settings,
    required this.banks,
    required this.theme,
    required this.onboarding,
  });

  final Settings settings;
  final List<Bank> banks;
  final String theme;
  final OnboardingState onboarding;
}

/// Live application state replaced by a factory reset.
class FactoryResetState {
  FactoryResetState({
    required this.settings,
    required this.banks,
    required this.theme,
    required this.onboarding,
  });

  Settings settings;
  List<Bank> banks;
  String theme;
  OnboardingState onboarding;
}

/// Built-in defaults for a reset. [defaultBanks] must be a fresh list so the
/// reset never shares mutable state with the defaults.
ApplicationData builtInApplicationData({
  required List<Bank> defaultBanks,
  required String defaultTheme,
}) {
  return ApplicationData(
    settings: copySettings(DEFAULT_SETTINGS),
    banks: List<Bank>.of(defaultBanks),
    theme: defaultTheme,
    onboarding: DEFAULT_ONBOARDING_STATE,
  );
}

/// Replaces [state] with the data produced by [resetData] after [confirmReset]
/// returns true. [resetData] is the only place storage is cleared; if it
/// throws, [state] is left unchanged and the error propagates.
bool resetApplicationState(
  FactoryResetState state,
  bool Function() confirmReset,
  ApplicationData Function() resetData,
) {
  if (!confirmReset()) {
    return false;
  }
  final defaults = resetData();
  state.settings = defaults.settings;
  state.banks = defaults.banks;
  state.theme = defaults.theme;
  state.onboarding = defaults.onboarding;
  return true;
}

import 'package:simplex_blender/src/data/bank_storage.dart';
import 'package:simplex_blender/src/data/key_value_storage.dart';
import 'package:simplex_blender/src/data/settings_storage.dart';
import 'package:simplex_blender/src/data/theme_storage.dart';
import 'package:simplex_blender/src/domain/factory_reset.dart';
import 'package:simplex_blender/src/domain/onboarding.dart';

/// Port of JS `resetApplicationData`. Clears every stored key first, then
/// loads each value, so the result is the built-in defaults. [onFallback]
/// receives the cause whenever the settings or bank loader falls back.
ApplicationData resetApplicationData(
  KeyValueStorage storage, {
  void Function(Object error)? onFallback,
}) {
  storage.clear();
  return ApplicationData(
    settings: loadSettings(storage, onFallback: onFallback),
    banks: loadSupplyBanks(storage, onFallback: onFallback),
    theme: loadThemePreference(storage),
    onboarding: OnboardingState(
      wizardSeen: DEFAULT_ONBOARDING_STATE.wizardSeen,
    ),
  );
}

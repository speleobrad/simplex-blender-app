import 'dart:convert';

import 'package:simplex_blender/src/data/key_value_storage.dart';
import 'package:simplex_blender/src/domain/onboarding.dart';

const String _invalidRecordMessage =
    'Onboarding state requires a boolean wizardSeen field.';

/// Port of JS `loadOnboardingState`, reduced to the tour-seen flag.
///
/// Only `wizardSeen` is persisted; consent was removed from the app. Any
/// other stored key is ignored, so a legacy record still keeps its seen flag.
/// A read failure, unparsable JSON, or a missing or non-boolean `wizardSeen`
/// falls back to [DEFAULT_ONBOARDING_STATE] and reports the cause through
/// [onFallback].
OnboardingState loadOnboardingState(
  KeyValueStorage storage, {
  void Function(Object error)? onFallback,
}) {
  String? serialized;
  try {
    serialized = storage.getItem(ONBOARDING_STORAGE_KEY);
  } catch (error) {
    onFallback?.call(error);
    return DEFAULT_ONBOARDING_STATE;
  }
  if (serialized == null) return DEFAULT_ONBOARDING_STATE;

  Object? decoded;
  try {
    decoded = jsonDecode(serialized);
  } catch (error) {
    onFallback?.call(error);
    return DEFAULT_ONBOARDING_STATE;
  }

  if (decoded is Map<String, Object?> && decoded['wizardSeen'] is bool) {
    return OnboardingState(wizardSeen: decoded['wizardSeen'] as bool);
  }
  onFallback?.call(RangeError(_invalidRecordMessage));
  return DEFAULT_ONBOARDING_STATE;
}

/// Port of JS `saveOnboardingState`, persisting only the tour-seen flag.
void saveOnboardingState(OnboardingState state, KeyValueStorage storage) {
  storage.setItem(
    ONBOARDING_STORAGE_KEY,
    jsonEncode(<String, Object>{'wizardSeen': state.wizardSeen}),
  );
}

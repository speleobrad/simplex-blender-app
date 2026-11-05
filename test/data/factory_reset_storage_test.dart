import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/data/bank_storage.dart';
import 'package:simplex_blender/src/data/factory_reset_storage.dart';
import 'package:simplex_blender/src/data/key_value_storage.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/factory_reset.dart';
import 'package:simplex_blender/src/domain/onboarding.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/settings_json.dart';
import 'package:simplex_blender/src/domain/theme.dart';

import '../support/memory_storage.dart';

/// Storage whose `clear` fails, standing in for an unavailable store.
class _ClearFailsStorage implements KeyValueStorage {
  @override
  String? getItem(String key) => null;

  @override
  void setItem(String key, String value) {}

  @override
  void clear() {
    throw StateError('storage unavailable');
  }
}

List<Map<String, Object?>> _bankRecords(List<Bank> banks) {
  return <Map<String, Object?>>[for (final bank in banks) bankToRecord(bank)];
}

void main() {
  test(
    'factory reset clears storage and returns independent built-in defaults',
    () {
      final storage = MemoryStorage(<String, String>{
        'simplex-gas-remixer-settings': '{"custom":true}',
        'simplex-gas-remixer-banks': '[{"custom":true}]',
        'simplex-gas-remixer-theme': 'dark',
        'unrelated-app-data': 'also removed',
      });

      final result = resetApplicationData(storage);

      expect(storage.values, isEmpty);
      expect(settingsToJson(result.settings), settingsToJson(DEFAULT_SETTINGS));
      expect(_bankRecords(result.banks), _bankRecords(DEFAULT_BANKS));
      expect(result.theme, DEFAULT_THEME);
      expect(
        identical(result.settings.gasPresets, DEFAULT_SETTINGS.gasPresets),
        isFalse,
      );
      expect(identical(result.banks, DEFAULT_BANKS), isFalse);
      expect(identical(result.onboarding, DEFAULT_ONBOARDING_STATE), isFalse);

      final second = resetApplicationData(storage);
      result.banks.clear();
      expect(second.banks, isNotEmpty);
      expect(_bankRecords(second.banks), _bankRecords(DEFAULT_BANKS));
    },
  );

  test('factory reset honors cancellation and replaces live state after confirmation', () {
    // JS tests/factory-reset.test.js:37-60, storage entry assertions.
    final storage = MemoryStorage(<String, String>{'saved-data': 'present'});
    final state = FactoryResetState(
      settings: copySettings(DEFAULT_SETTINGS)
          .copyWith(interimPressureTolerancePercent: 7),
      banks: <Bank>[
        const Bank(
          id: 'custom',
          name: 'Custom',
          volumeL: 1,
          pressureBar: 1,
          oxygenPercent: 21,
          heliumPercent: 0,
          enabled: true,
        ),
      ],
      theme: 'dark',
      onboarding: const OnboardingState(wizardSeen: true),
    );
    final before = (state.settings, state.banks, state.theme, state.onboarding);

    expect(
      resetApplicationState(
        state,
        () => false,
        () => resetApplicationData(storage),
      ),
      false,
    );
    expect((
      state.settings,
      state.banks,
      state.theme,
      state.onboarding,
    ), before);
    expect(storage.values, <String, String>{'saved-data': 'present'});

    expect(
      resetApplicationState(
        state,
        () => true,
        () => resetApplicationData(storage),
      ),
      true,
    );
    expect(settingsToJson(state.settings), settingsToJson(DEFAULT_SETTINGS));
    expect(_bankRecords(state.banks), _bankRecords(DEFAULT_BANKS));
    expect(state.theme, DEFAULT_THEME);
    expect(state.onboarding, DEFAULT_ONBOARDING_STATE);
    expect(identical(state.onboarding, DEFAULT_ONBOARDING_STATE), isFalse);
    expect(identical(state.settings, DEFAULT_SETTINGS), isFalse);
    expect(identical(state.banks, DEFAULT_BANKS), isFalse);
    expect(storage.values, isEmpty);
  });

  test('factory reset leaves live state unchanged when storage cannot be cleared', () {
    // JS tests/factory-reset.test.js:62-77, with a storage whose clear throws.
    final state = FactoryResetState(
      settings: copySettings(DEFAULT_SETTINGS)
          .copyWith(interimPressureTolerancePercent: 7),
      banks: <Bank>[
        const Bank(
          id: 'custom',
          name: 'Custom',
          volumeL: 1,
          pressureBar: 1,
          oxygenPercent: 21,
          heliumPercent: 0,
          enabled: true,
        ),
      ],
      theme: 'dark',
      onboarding: DEFAULT_ONBOARDING_STATE,
    );
    final before = (state.settings, state.banks, state.theme, state.onboarding);
    final storage = _ClearFailsStorage();

    expect(
      () => resetApplicationState(
        state,
        () => true,
        () => resetApplicationData(storage),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'storage unavailable',
        ),
      ),
    );
    expect((
      state.settings,
      state.banks,
      state.theme,
      state.onboarding,
    ), before);
  });
}

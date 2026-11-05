import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/factory_reset.dart';
import 'package:simplex_blender/src/domain/onboarding.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/theme.dart';

void main() {
  test('factory reset clears storage and returns independent built-in defaults', () {
    // Storage clearing is covered in test/data/factory_reset_storage_test.dart;
    // the built-in defaults are checked here.
    final defaultBanks = <Bank>[
      const Bank(
        id: 'air',
        name: 'Air',
        volumeL: 12,
        pressureBar: 200,
        oxygenPercent: 21,
        heliumPercent: 0,
        enabled: true,
      ),
    ];
    final result = builtInApplicationData(
      defaultBanks: defaultBanks,
      defaultTheme: DEFAULT_THEME,
    );

    expect(result.settings.units, DEFAULT_SETTINGS.units);
    expect(result.settings.physics, DEFAULT_SETTINGS.physics);
    expect(result.settings.gasPresets, DEFAULT_SETTINGS.gasPresets);
    expect(
      result.settings.compressorPresets,
      DEFAULT_SETTINGS.compressorPresets,
    );
    expect(result.settings.boosterPresets, DEFAULT_SETTINGS.boosterPresets);
    expect(result.settings.cylinderPresets, DEFAULT_SETTINGS.cylinderPresets);
    expect(result.settings.booster, DEFAULT_SETTINGS.booster);
    expect(result.banks, defaultBanks);
    expect(result.theme, DEFAULT_THEME);
    expect(result.onboarding, DEFAULT_ONBOARDING_STATE);
    expect(result.onboarding.wizardSeen, DEFAULT_ONBOARDING_STATE.wizardSeen);

    expect(
      identical(result.settings.gasPresets, DEFAULT_SETTINGS.gasPresets),
      isFalse,
    );
    expect(identical(result.banks, defaultBanks), isFalse);
  });

  test('factory reset honors cancellation and replaces live state after confirmation', () {
    final state = FactoryResetState(
      settings: copySettings(DEFAULT_SETTINGS),
      banks: <Bank>[],
      theme: 'dark',
      onboarding: const OnboardingState(wizardSeen: true),
    );
    final before = (state.settings, state.banks, state.theme, state.onboarding);
    var resetCalls = 0;
    ApplicationData reset() {
      resetCalls++;
      return builtInApplicationData(
        defaultBanks: <Bank>[],
        defaultTheme: 'light',
      );
    }

    expect(resetApplicationState(state, () => false, reset), false);
    expect((
      state.settings,
      state.banks,
      state.theme,
      state.onboarding,
    ), before);
    expect(resetCalls, 0);

    expect(resetApplicationState(state, () => true, reset), true);
    expect(resetCalls, 1);
    expect(state.theme, DEFAULT_THEME);
    expect(state.onboarding, DEFAULT_ONBOARDING_STATE);
    expect(state.banks, isEmpty);
  });

  test(
    'factory reset leaves live state unchanged when storage cannot be cleared',
    () {
      final state = FactoryResetState(
        settings: copySettings(DEFAULT_SETTINGS),
        banks: <Bank>[],
        theme: 'dark',
        onboarding: DEFAULT_ONBOARDING_STATE,
      );
      final before = (
        state.settings,
        state.banks,
        state.theme,
        state.onboarding,
      );

      expect(
        () => resetApplicationState(state, () => true, () {
          throw StateError('storage unavailable');
        }),
        throwsA(isA<StateError>()),
      );
      expect((
        state.settings,
        state.banks,
        state.theme,
        state.onboarding,
      ), before);
    },
  );
}

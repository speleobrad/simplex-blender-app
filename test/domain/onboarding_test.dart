import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/onboarding.dart';

void main() {
  test('missing onboarding state starts with the tour unseen', () {
    expect(parseOnboardingState(null), DEFAULT_ONBOARDING_STATE);
  });

  test('valid onboarding state survives save and load', () {
    const state = OnboardingState(wizardSeen: true);
    final saved = serializeOnboardingState(state.toJson());
    expect(parseOnboardingState(saved), state);
  });

  test('malformed and invalid onboarding values use a fresh default', () {
    expect(parseOnboardingState('{not json'), DEFAULT_ONBOARDING_STATE);
    expect(
      parseOnboardingState(jsonEncode(<String, Object?>{'wizardSeen': 'yes'})),
      DEFAULT_ONBOARDING_STATE,
    );
  });

  test('a legacy consent field is ignored and the seen flag is kept', () {
    expect(
      parseOnboardingState('{"consentAccepted":true,"wizardSeen":true}'),
      const OnboardingState(wizardSeen: true),
    );
  });

  test('invalid onboarding state is rejected before replacing saved data', () {
    const valid = OnboardingState(wizardSeen: false);
    final saved = serializeOnboardingState(valid.toJson());
    expect(
      () => serializeOnboardingState(<String, Object?>{'wizardSeen': 'yes'}),
      throwsRangeError,
    );
    expect(parseOnboardingState(saved), valid);
  });

  test(
    'wizard steps walk a new user from the main menu to the result tabs',
    () {
      expect(WIZARD_STEPS.map((step) => step.id).toList(), <String>[
        'main-menu',
        'inventory-gases',
        'inventory-equipment',
        'settings-equipment',
        'working-tank',
        'temperatures',
        'recipe',
        'explore-options',
      ]);
      expect(WIZARD_STEPS[0].targetId, 'primary-navigation');
      final gases = WIZARD_STEPS.firstWhere(
        (step) => step.id == 'inventory-gases',
      );
      expect(gases.targetId, 'supply-banks-section');
      expect(gases.screen, 'inventory');
      final equipment = WIZARD_STEPS.firstWhere(
        (step) => step.id == 'inventory-equipment',
      );
      expect(equipment.targetId, 'equipment-section');
      expect(equipment.screen, 'inventory');
      final settings = WIZARD_STEPS.firstWhere(
        (step) => step.id == 'settings-equipment',
      );
      expect(settings.settingsCategory, 'equipment');
      expect(
        settings.spotlights.map((spotlight) => spotlight.targetId).toList(),
        <String>['settings-pane-equipment', 'settings-category-equipment'],
      );
      expect(
        WIZARD_STEPS.firstWhere((step) => step.id == 'working-tank').targetId,
        'working-tank-section',
      );
      final temperatures = WIZARD_STEPS.firstWhere(
        (step) => step.id == 'temperatures',
      );
      expect(
        temperatures.spotlights.map((spotlight) => spotlight.targetId).toList(),
        <String>['ambient-temperature', 'dive-site-temperature'],
      );
      final recipe = WIZARD_STEPS.firstWhere((step) => step.id == 'recipe');
      expect(recipe.targetId, 'mixing-steps-section');
      expect(recipe.tab, 'recipe');
      expect(
        WIZARD_STEPS
            .firstWhere((step) => step.id == 'explore-options')
            .targetId,
        'results-tablist',
      );
    },
  );
}

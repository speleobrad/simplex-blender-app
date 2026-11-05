// ignore_for_file: constant_identifier_names

/// Port of the pure parts of `js/onboarding.js`: the state shape, the wizard
/// step catalogue, and parse/serialize validation.
///
/// Reading and writing the key through the platform store is in
/// `lib/src/data/onboarding_storage.dart`.
library;

import 'dart:convert';

/// Key used by the web app's localStorage and by the Flutter platform store.
const String ONBOARDING_STORAGE_KEY = 'simplex-gas-remixer-onboarding';

const String _invalidStateMessage =
    'Onboarding state requires a boolean wizardSeen field.';

class OnboardingState {
  const OnboardingState({required this.wizardSeen});

  final bool wizardSeen;

  OnboardingState copyWith({bool? wizardSeen}) {
    return OnboardingState(wizardSeen: wizardSeen ?? this.wizardSeen);
  }

  /// Same key as the JS state object; the consent field is not kept.
  Map<String, Object?> toJson() => <String, Object?>{'wizardSeen': wizardSeen};

  @override
  bool operator ==(Object other) =>
      other is OnboardingState && other.wizardSeen == wizardSeen;

  @override
  int get hashCode => wizardSeen.hashCode;

  @override
  String toString() => 'OnboardingState(wizardSeen: $wizardSeen)';
}

const OnboardingState DEFAULT_ONBOARDING_STATE = OnboardingState(
  wizardSeen: false,
);

class WizardSpotlight {
  const WizardSpotlight({required this.targetId});

  final String targetId;
}

class WizardStep {
  const WizardStep({
    required this.id,
    required this.title,
    required this.body,
    required this.screen,
    this.targetId,
    this.spotlights = const <WizardSpotlight>[],
    this.settingsCategory,
    this.tab,
  });

  final String id;
  final String title;
  final String body;
  final String screen;
  final String? targetId;
  final List<WizardSpotlight> spotlights;
  final String? settingsCategory;
  final String? tab;
}

const List<WizardStep> WIZARD_STEPS = <WizardStep>[
  WizardStep(
    id: 'main-menu',
    title: 'Main menu',
    body: 'Use the main menu to navigate between Blending, Inventory, and few other options. Inventory is where you define your available gases and equipment, and Blending is where you get a recipe for your fill.',
    targetId: 'primary-navigation',
    screen: 'blending',
  ),
  WizardStep(
    id: 'inventory-gases',
    title: 'Define the gases you have',
    body: 'You would start here: define the inventory of gases you have available as ingredients. Add each gas bank with its pressure and mix. Compressor with air is assumed to exist, so don\'t bother adding Air',
    targetId: 'supply-banks-section',
    screen: 'inventory',
  ),
  WizardStep(
    id: 'inventory-equipment',
    title: 'Check your equipment',
    body: 'Select your compressor and booster from the list. Their properties will determine speed of transfering gases.',
    targetId: 'equipment-section',
    screen: 'inventory',
  ),
  WizardStep(
    id: 'settings-equipment',
    title: 'Add missing equipment',
    body: 'If your compressor or booster is not listed, you can add it here with New compressor or New booster.',
    spotlights: <WizardSpotlight>[
      WizardSpotlight(targetId: 'settings-pane-equipment'),
      WizardSpotlight(targetId: 'settings-category-equipment'),
    ],
    screen: 'blending',
    settingsCategory: 'equipment',
  ),
  WizardStep(
    id: 'working-tank',
    title: 'Define your mix',
    body: 'Once your equipment and inventory are set, configure the working tank by defining its current pressure and gas mix. Then set the target pressure and mix you want to reach.',
    targetId: 'working-tank-section',
    screen: 'blending',
  ),
  WizardStep(
    id: 'temperatures',
    title: 'Set the temperatures',
    body: 'Pay close attention to two temperatures: the ambient temperature of environment where you fill, and the dive site\'s water temperature, entered as the dive site temperature.',
    spotlights: <WizardSpotlight>[
      WizardSpotlight(targetId: 'ambient-temperature'),
      WizardSpotlight(targetId: 'dive-site-temperature'),
    ],
    screen: 'blending',
  ),
  WizardStep(
    id: 'recipe',
    title: 'Follow the recipe',
    body: 'The recipe shows how to get there, step by step. It will not allow unsafe fills, and it gives you more gas now so you have exactly what you need at the dive site when tanks cool off.',
    targetId: 'mixing-steps-section',
    screen: 'blending',
    tab: 'recipe',
  ),
  WizardStep(
    id: 'explore-options',
    title: 'Explore other options',
    body: 'Use the result tabs on the right to explore other views: Thermal Graph that will show you how temperature changes as you will, In-water pressures that can show you pressures in other water temperatures, but also if it\'s safe to drive around in a hot summer day, Tanks and costs that will tell you what you are left with after the mix and what the fill costs, and Simplex diagram to show you visual path you will be making as you move from starting to target mix.',
    targetId: 'results-tablist',
    screen: 'blending',
  ),
];

/// Pure half of JS `loadOnboardingState`. [serialized] is the raw stored
/// string (null when absent). Only `wizardSeen` is read; any other key, such
/// as the removed consent field, is ignored. Invalid input returns the
/// default and reports the reason through [onFallback].
OnboardingState parseOnboardingState(
  String? serialized, {
  void Function(Object error)? onFallback,
}) {
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
  onFallback?.call(RangeError(_invalidStateMessage));
  return DEFAULT_ONBOARDING_STATE;
}

/// Pure half of JS `saveOnboardingState`: validates [state] and returns the
/// exact string to persist. Throws [RangeError] when `wizardSeen` is not a
/// boolean.
String serializeOnboardingState(Map<String, Object?> state) {
  if (state['wizardSeen'] is! bool) throw RangeError(_invalidStateMessage);
  return jsonEncode(<String, Object?>{'wizardSeen': state['wizardSeen']});
}

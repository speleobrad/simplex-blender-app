// ignore_for_file: constant_identifier_names

/// Port of the pure part of `js/navigation.js`.
///
/// The DOM selection logic (`setPrimaryScreen`) is replaced by Flutter
/// navigation state in Step 5; only the screen list and validity check live
/// here.
library;

const List<String> PRIMARY_SCREENS = <String>[
  'blending',
  'what-if',
  'inventory',
  'settings',
  'about',
];

/// True when [screenId] names one of the [PRIMARY_SCREENS].
bool isPrimaryScreen(String screenId) => PRIMARY_SCREENS.contains(screenId);

/// Settings categories in display order (JS `setSettingsCategory` in
/// `js/main.js`).
const List<String> SETTINGS_CATEGORIES = <String>[
  'general',
  'gas-presets',
  'cylinder-presets',
  'equipment',
  'costs',
  'preset-management',
];

/// True when [category] names one of the [SETTINGS_CATEGORIES].
bool isSettingsCategory(String category) =>
    SETTINGS_CATEGORIES.contains(category);

/// User-visible storage warning lines for the current failure flags, in JS display order.
/// [bankInputFailureMessage] is the rejected Inventory edit's message; null when there is none.
List<String> getStorageWarningMessages({
  bool settingsLoadFailure = false,
  bool banksLoadFailure = false,
  bool bankSaveFailure = false,
  bool onboardingLoadFailure = false,
  String? bankInputFailureMessage,
}) {
  return [
    if (settingsLoadFailure)
      'Saved presets could not be loaded; built-in defaults are active.',
    if (banksLoadFailure)
      'Saved Inventory could not be loaded; default inventory is active.',
    if (bankSaveFailure)
      'Inventory changes could not be saved to browser storage.',
    if (onboardingLoadFailure) 'Saved guided-tour preference could not be loaded; the guided tour will be shown again.',
    if (bankInputFailureMessage != null)
      'Inventory edit rejected: $bankInputFailureMessage',
  ];
}

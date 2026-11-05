// Port of the pure part of js/result-tabs.js and js/ui/result-panel.js (tab lists and validation).
// The DOM parts (setResultTabState, pane/button attributes, scrollIntoView) are UI-only and are not ported here.

const List<String> optimizeResultTabs = <String>[
  'recipe',
  'thermal',
  'water-pressure',
  'summary',
  'ternary',
];

const List<String> whatIfResultTabs = <String>[
  'recipe',
  'thermal',
  'water-pressure',
  'summary',
  'ternary',
];

/// JS `getResultTabs(mode)`: `what-if` gives the What-if tabs, anything else the optimize tabs.
List<String> getResultTabs([String mode = 'optimize']) =>
    mode == 'what-if' ? whatIfResultTabs : optimizeResultTabs;

/// Whether [tabId] names a tab in [tabs]. JS `setResultTab` / `setResultTabState` reject unknown tabs.
bool canSelectResultTab(String tabId, [List<String>? tabs]) =>
    (tabs ?? optimizeResultTabs).contains(tabId);

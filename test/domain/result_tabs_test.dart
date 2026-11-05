import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/result_tabs.dart';

// Dropped from tests/result-tabs.test.js: "selecting a result tab exposes only its panel and marks
// the button selected". Its assertions are only pane `hidden`/class, `aria-*` and button styling on
// DOM fixtures; that behavior belongs to the Flutter UI, not to this pure module.

void main() {
  test('initial What-if state shows Recipe with active styling', () {
    expect(whatIfResultTabs, [
      'recipe',
      'thermal',
      'water-pressure',
      'summary',
      'ternary',
    ]);
    expect(getResultTabs('what-if'), whatIfResultTabs);
    expect(getResultTabs(), optimizeResultTabs);
    expect(canSelectResultTab('recipe', whatIfResultTabs), isTrue);
  });

  test('unknown result tabs are rejected', () {
    expect(canSelectResultTab('settings'), isFalse);
    expect(canSelectResultTab('settings', whatIfResultTabs), isFalse);
  });
}

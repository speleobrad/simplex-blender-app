import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/navigation.dart';

void main() {
  // The JS DOM pane-visibility and ARIA cases in tests/navigation.test.js are
  // dropped: Flutter navigation state replaces the DOM (Step 5). Only the
  // primary-screen membership check is ported.
  test('selecting Settings is a primary screen', () {
    expect(isPrimaryScreen('settings'), isTrue);
  });

  test('selecting a primary screen is accepted', () {
    expect(isPrimaryScreen('inventory'), isTrue);
  });

  test('unknown primary screens are rejected', () {
    expect(isPrimaryScreen('unknown'), isFalse);
  });
}

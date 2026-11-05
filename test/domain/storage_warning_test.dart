import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/storage_warning.dart';

void main() {
  group('storage warning messages', () {
    test('reports Inventory save failures in the visible storage warning', () {
      final messages = getStorageWarningMessages(bankSaveFailure: true);

      expect(messages, hasLength(1));
      expect(
        messages.single,
        matches(
          RegExp(r'Inventory changes could not be saved', caseSensitive: false),
        ),
      );
    });

    test('reports onboarding-load failures in the visible storage warning', () {
      final messages = getStorageWarningMessages(onboardingLoadFailure: true);

      expect(messages, hasLength(1));
      expect(
        messages.single,
        matches(
          RegExp(
            r'guided-tour preference could not be loaded',
            caseSensitive: false,
          ),
        ),
      );
    });
  });
}

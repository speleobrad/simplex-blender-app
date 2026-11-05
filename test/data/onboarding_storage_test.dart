import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/data/key_value_storage.dart';
import 'package:simplex_blender/src/data/onboarding_storage.dart';
import 'package:simplex_blender/src/domain/onboarding.dart';

import '../support/memory_storage.dart';

/// Storage whose reads always fail; the thrown error is what the caller
/// must receive through `onFallback`.
class _UnreadableStorage implements KeyValueStorage {
  _UnreadableStorage(this.failure);

  final Object failure;

  @override
  String? getItem(String key) => throw failure;

  @override
  void setItem(String key, String value) {}

  @override
  void clear() {}
}

void main() {
  group('onboarding storage', () {
    test('missing onboarding state starts with the tour unseen', () {
      expect(loadOnboardingState(MemoryStorage()), DEFAULT_ONBOARDING_STATE);
    });

    test(
      'unreadable onboarding state falls back and reports the storage failure',
      () {
        final failure = StateError('storage unavailable');
        Object? reportedFailure;
        final storage = _UnreadableStorage(failure);

        expect(
          loadOnboardingState(
            storage,
            onFallback: (error) {
              reportedFailure = error;
            },
          ),
          DEFAULT_ONBOARDING_STATE,
        );
        expect(reportedFailure, same(failure));
      },
    );

    test('tour-seen state survives save and load and is stored alone', () {
      final storage = MemoryStorage();
      saveOnboardingState(const OnboardingState(wizardSeen: true), storage);
      expect(storage.values, <String, String>{
        'simplex-gas-remixer-onboarding': '{"wizardSeen":true}',
      });
      expect(
        loadOnboardingState(storage),
        const OnboardingState(wizardSeen: true),
      );
    });

    test('a legacy consent field is ignored and the seen flag is kept', () {
      final storage = MemoryStorage(<String, String>{
        'simplex-gas-remixer-onboarding':
            '{"consentAccepted":true,"wizardSeen":true}',
      });
      expect(
        loadOnboardingState(storage),
        const OnboardingState(wizardSeen: true),
      );
    });

    test('malformed and invalid onboarding values use a fresh default and report it', () {
      final storage = MemoryStorage(<String, String>{
        'simplex-gas-remixer-onboarding': '{not json',
      });
      final reports = <Object>[];

      expect(
        loadOnboardingState(storage, onFallback: reports.add),
        DEFAULT_ONBOARDING_STATE,
      );
      expect(reports, hasLength(1));

      storage.setItem(
        'simplex-gas-remixer-onboarding',
        '{"consentAccepted":true}',
      );
      expect(
        loadOnboardingState(storage, onFallback: reports.add),
        DEFAULT_ONBOARDING_STATE,
      );
      expect(reports, hasLength(2));
      expect(reports.last, isA<RangeError>());

      storage.setItem('simplex-gas-remixer-onboarding', '{"wizardSeen":"yes"}');
      expect(
        loadOnboardingState(storage, onFallback: reports.add),
        DEFAULT_ONBOARDING_STATE,
      );
      expect(reports, hasLength(3));
    });
  });
}

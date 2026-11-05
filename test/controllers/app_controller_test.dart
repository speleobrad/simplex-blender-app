import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/data/bank_storage.dart';
import 'package:simplex_blender/src/data/key_value_storage.dart';
import 'package:simplex_blender/src/data/settings_storage.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/settings.dart';

import '../support/memory_storage.dart';

typedef _Call = ({String event, Map<String, Object> props});

/// Records every event; stands in for the backend.
class _RecordingAnalytics implements Analytics {
  final List<_Call> calls = <_Call>[];

  @override
  void track(
    String event, [
    Map<String, Object> props = const <String, Object>{},
  ]) {
    calls.add((event: event, props: props));
  }
}

/// Storage whose reads succeed (empty) and whose writes always fail.
class _FailingWriteStorage implements KeyValueStorage {
  @override
  String? getItem(String key) => null;

  @override
  void setItem(String key, String value) {
    throw StateError('quota exceeded');
  }

  @override
  void clear() {}
}

Bank _bankById(List<Bank> banks, String id) =>
    banks.singleWhere((bank) => bank.id == id);

void main() {
  test(
    'an edit that makes a bank Air is rejected, keeps the bank unchanged, and '
    'shows the bank-prefixed message',
    () {
      final storage = MemoryStorage();
      final controller = AppController(
        storage: storage,
        analytics: _RecordingAnalytics(),
      );
      final before = _bankById(controller.banks, 'bank-oxygen');

      controller.updateBank(
        before.copyWith(oxygenPercent: 21, heliumPercent: 0),
      );

      expect(_bankById(controller.banks, 'bank-oxygen'), equals(before));
      expect(
        controller.bankInputFailure,
        'Oxygen: Air is supplied by the compressor and cannot be a finite '
        'supply bank.',
      );
      expect(controller.storageWarning, <String>[
        'Inventory edit rejected: Oxygen: Air is supplied by the compressor '
            'and cannot be a finite supply bank.',
      ]);
      expect(storage.values.containsKey(STORAGE_KEY), isFalse);
    },
  );

  test(
    'an accepted edit clears the rejection for that bank and is persisted',
    () {
      final storage = MemoryStorage();
      final controller = AppController(
        storage: storage,
        analytics: _RecordingAnalytics(),
      );
      final before = _bankById(controller.banks, 'bank-oxygen');
      controller.updateBank(
        before.copyWith(oxygenPercent: 21, heliumPercent: 0),
      );

      controller.updateBank(before.copyWith(oxygenPercent: 32));

      expect(controller.bankInputFailure, isNull);
      expect(controller.storageWarning, isEmpty);
      expect(_bankById(controller.banks, 'bank-oxygen').oxygenPercent, 32);
      final reloaded = loadSupplyBanks(storage);
      expect(_bankById(reloaded, 'bank-oxygen').oxygenPercent, 32);
    },
  );

  test(
    'a failed inventory save keeps the edited banks in memory and warns',
    () {
      final controller = AppController(
        storage: _FailingWriteStorage(),
        analytics: _RecordingAnalytics(),
      );

      controller.addBank();

      expect(controller.banks.last.name, 'New Mix');
      expect(controller.banks.length, DEFAULT_BANKS.length + 1);
      expect(controller.bankSaveFailure, isTrue);
      expect(
        controller.storageWarning,
        contains('Inventory changes could not be saved to browser storage.'),
      );
    },
  );

  test('corrupt saved inventory falls back to the default banks and warns', () {
    final storage = MemoryStorage(<String, String>{STORAGE_KEY: '{not json'});

    final controller = AppController(
      storage: storage,
      analytics: _RecordingAnalytics(),
    );

    expect(controller.banksLoadFailure, isTrue);
    expect(controller.banks, equals(DEFAULT_BANKS));
    expect(
      controller.storageWarning,
      contains(
        'Saved Inventory could not be loaded; default inventory is active.',
      ),
    );
  });

  test('invalid settings are rejected and storage is left untouched', () {
    final storage = MemoryStorage();
    final controller = AppController(
      storage: storage,
      analytics: _RecordingAnalytics(),
    );
    final previous = controller.settings;

    final errors = controller.applySettings(
      DEFAULT_SETTINGS.copyWith(interimPressureTolerancePercent: 20),
    );

    expect(errors, isNotEmpty);
    expect(controller.settings, equals(previous));
    expect(controller.settingsSaveFailure, isFalse);
    expect(storage.values.containsKey(SETTINGS_STORAGE_KEY), isFalse);
  });

  test('a failed settings save keeps the previous settings and reports the '
      'web app message', () {
    final controller = AppController(
      storage: _FailingWriteStorage(),
      analytics: _RecordingAnalytics(),
    );
    final previous = controller.settings;

    final errors = controller.applySettings(
      previous.copyWith(interimPressureTolerancePercent: 5),
    );

    expect(errors, <String>[settingsSaveFailureMessage]);
    expect(controller.settings, equals(previous));
    expect(controller.settingsSaveFailure, isTrue);
  });

  test('factory reset does nothing when cancelled, and clears stored data and '
      'tracks the event once when confirmed', () {
    final analytics = _RecordingAnalytics();
    final storage = MemoryStorage();
    final controller = AppController(storage: storage, analytics: analytics);
    controller.addBank();
    final edited = controller.banks;
    final storedBefore = Map<String, String>.of(storage.values);

    final cancelled = controller.factoryReset(confirm: () => false);

    expect(cancelled, FactoryResetOutcome.cancelled);
    expect(controller.banks, equals(edited));
    expect(storage.values, equals(storedBefore));
    expect(analytics.calls, isEmpty);

    final reset = controller.factoryReset(confirm: () => true);

    expect(reset, FactoryResetOutcome.reset);
    expect(controller.banks, equals(DEFAULT_BANKS));
    expect(controller.bankSaveFailure, isFalse);
    expect(analytics.calls.map((call) => call.event), <String>[
      'factory_reset',
    ]);
    expect(analytics.calls.single.props, equals(<String, Object>{}));
  });

  test(
    'screen_view is sent only when the primary screen changes, and an unknown '
    'screen is rejected',
    () {
      final analytics = _RecordingAnalytics();
      final controller = AppController(
        storage: MemoryStorage(),
        analytics: analytics,
      );

      expect(controller.setPrimaryScreen('inventory'), isTrue);
      expect(controller.setPrimaryScreen('inventory'), isTrue);
      expect(controller.setPrimaryScreen('no-such-screen'), isFalse);

      expect(controller.primaryScreen, 'inventory');
      expect(analytics.calls.map((call) => call.event).toList(), <String>[
        'screen_view',
      ]);
      expect(analytics.calls.single.props, <String, Object>{
        'name': 'Inventory',
      });
    },
  );

  test(
    'updateBank stores a named link applied with changed oxygen and helium',
    () {
      final controller = AppController(
        storage: MemoryStorage(),
        analytics: _RecordingAnalytics(),
      );
      // JS selectBankGasPreset (main.js:2002-2003): apply the preset's gas,
      // then set gasPresetName to the preset name.
      final applied = applyGasPresetToBank(
        _bankById(controller.banks, 'bank-oxygen'),
        const GasPreset(name: 'Trimix', oxygenPercent: 18, heliumPercent: 45),
      ).copyWith(gasPresetLink: const NamedPresetLink('Trimix'));

      controller.updateBank(applied);

      final stored = _bankById(controller.banks, 'bank-oxygen');
      expect(stored.oxygenPercent, 18);
      expect(stored.heliumPercent, 45);
      expect(
        stored.gasPresetLink,
        isA<NamedPresetLink>().having((link) => link.name, 'name', 'Trimix'),
      );
    },
  );

  test('updateBank keeps the link the caller passed on an oxygen edit', () {
    final controller = AppController(
      storage: MemoryStorage(),
      analytics: _RecordingAnalytics(),
    );
    final before = _bankById(controller.banks, 'bank-oxygen');

    controller.updateBank(before.copyWith(oxygenPercent: 90));

    final stored = _bankById(controller.banks, 'bank-oxygen');
    expect(stored.oxygenPercent, 90);
    expect(stored.gasPresetLink, isA<UnnamedPresetLink>());
  });
}

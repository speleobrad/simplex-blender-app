import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/data/bank_storage.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/domain_error.dart';
import 'package:simplex_blender/src/domain/input_validation.dart';

import '../support/memory_storage.dart';

/// Persisted-record view of banks, for structural comparison.
List<Map<String, Object?>> recordsOf(List<Bank> banks) =>
    <Map<String, Object?>>[for (final bank in banks) bankToRecord(bank)];

/// Encodes raw record maps the way they are stored.
String encodeRecords(List<Map<String, Object?>> records) => jsonEncode(records);

/// JS `DEFAULT_BANKS` literal. The third bank is the JS `gasPresetName: null`
/// custom mix; the first two have no `gasPresetName` key (absent).
const List<Map<String, Object?>> expectedDefaultRecords =
    <Map<String, Object?>>[
      <String, Object?>{
        'id': 'bank-helium',
        'name': 'Helium',
        'volumeL': 40,
        'pressureBar': 150,
        'maxPressureBar': 200,
        'oxygenPercent': 0,
        'heliumPercent': 100,
        'enabled': true,
      },
      <String, Object?>{
        'id': 'bank-oxygen',
        'name': 'Oxygen',
        'volumeL': 50,
        'pressureBar': 200,
        'maxPressureBar': 200,
        'oxygenPercent': 100,
        'heliumPercent': 0,
        'enabled': true,
      },
      <String, Object?>{
        'id': 'bank-sample-scrap',
        'name': 'Sample scrap',
        'volumeL': 12,
        'pressureBar': 45,
        'maxPressureBar': 200,
        'oxygenPercent': 19,
        'heliumPercent': 40,
        'enabled': true,
        'gasPresetName': null,
      },
    ];

const String key = STORAGE_KEY;

void main() {
  test(
    'missing saved banks return independent copies of all default fields',
    () {
      final first = loadSupplyBanks(MemoryStorage());
      first.removeAt(0);
      final next = loadSupplyBanks(MemoryStorage());
      expect(recordsOf(next), equals(expectedDefaultRecords));
      expect(next.first.enabled, isTrue);
    },
  );

  test('default banks exclude compressor Air', () {
    expect(
      DEFAULT_BANKS.any(
        (bank) => bank.oxygenPercent == 21 && bank.heliumPercent == 0,
      ),
      isFalse,
    );
  });

  test('built-in supply banks match the requested defaults', () {
    // The third bank's JS `gasPresetName: null` is a CustomMixLink, persisted
    // as the key with a null value (see expectedDefaultRecords).
    expect(recordsOf(DEFAULT_BANKS), equals(expectedDefaultRecords));
  });

  test('previous built-in supply banks migrate to the current defaults', () {
    final storage = MemoryStorage(<String, String>{
      key: encodeRecords(const <Map<String, Object?>>[
        <String, Object?>{
          'id': 'bank-he',
          'name': 'Pure Helium',
          'volumeL': 50,
          'pressureBar': 200,
          'oxygenPercent': 0,
          'heliumPercent': 100,
          'enabled': true,
        },
        <String, Object?>{
          'id': 'bank-1845',
          'name': 'Tx 18/45 Bank',
          'volumeL': 50,
          'pressureBar': 200,
          'oxygenPercent': 18,
          'heliumPercent': 45,
          'enabled': true,
        },
        <String, Object?>{
          'id': 'bank-o2',
          'name': 'Pure Oxygen',
          'volumeL': 40,
          'pressureBar': 180,
          'oxygenPercent': 100,
          'heliumPercent': 0,
          'enabled': true,
        },
      ]),
    });
    expect(
      recordsOf(loadSupplyBanks(storage)),
      equals(recordsOf(DEFAULT_BANKS)),
    );
  });

  test('empty saved bank list is valid', () {
    final storage = MemoryStorage(<String, String>{key: '[]'});
    expect(loadSupplyBanks(storage), isEmpty);
  });

  test('legacy Air records are removed when banks are loaded', () {
    final storage = MemoryStorage(<String, String>{
      key: encodeRecords(<Map<String, Object?>>[
        <String, Object?>{
          ...bankToRecord(DEFAULT_BANKS.first),
          'id': 'bank-heirloom',
        },
        <String, Object?>{
          'id': 'bank-air',
          'name': 'Air Top-off',
          'volumeL': 80,
          'pressureBar': 230,
          'oxygenPercent': 21,
          'heliumPercent': 0,
          'enabled': true,
        },
      ]),
    });
    expect(
      loadSupplyBanks(storage).map((bank) => bank.id).toList(),
      equals(<String>['bank-heirloom']),
    );
  });

  test(
    'saved banks preserve gas, pressure, volume, enable, and preset state',
    () {
      final storage = MemoryStorage();
      const banks = <Bank>[
        Bank(
          id: 'source-a',
          name: 'Custom mix',
          volumeL: 36,
          pressureBar: 217,
          maxPressureBar: 250,
          oxygenPercent: 19,
          heliumPercent: 42,
          enabled: false,
        ),
      ];
      saveSupplyBanks(banks, storage);
      expect(recordsOf(loadSupplyBanks(storage)), equals(recordsOf(banks)));
    },
  );

  test(
    'legacy per-bank minimum pressure is discarded when banks are loaded',
    () {
      final storage = MemoryStorage(<String, String>{
        key: encodeRecords(<Map<String, Object?>>[
          <String, Object?>{
            ...bankToRecord(DEFAULT_BANKS.first),
            'minimumPressureBar': 15,
          },
        ]),
      });
      final banks = loadSupplyBanks(storage);
      expect(banks.single.id, 'bank-helium');
      expect(
        bankToRecord(banks.single).containsKey('minimumPressureBar'),
        isFalse,
      );
    },
  );

  test('unreadable bank data falls back and reports the failure', () {
    final storage = MemoryStorage(<String, String>{key: '{bad json'});
    Object? reportedFailure;
    final banks = loadSupplyBanks(
      storage,
      onFallback: (error) => reportedFailure = error,
    );
    expect(recordsOf(banks), equals(expectedDefaultRecords));
    expect(reportedFailure, isA<FormatException>());
  });

  test('invalid bank records are rejected before replacing saved banks', () {
    // The JS case also lists `enabled: 'true'`; Bank.enabled is a typed bool,
    // so that invalid value cannot be constructed here.
    final storage = MemoryStorage();
    final invalidBanks = <Bank>[
      DEFAULT_BANKS.first.copyWith(id: ''),
      DEFAULT_BANKS.first.copyWith(pressureBar: double.nan),
    ];
    for (final bank in invalidBanks) {
      expect(
        () => saveSupplyBanks(<Bank>[bank], storage),
        throwsA(isA<DomainError>()),
      );
    }
    expect(storage.getItem(key), isNull);
  });

  test('rejects out-of-range banks and falls back when invalid saved records are loaded', () {
    final invalidBanks = <Bank>[
      DEFAULT_BANKS.first.copyWith(volumeL: 0.5),
      DEFAULT_BANKS.first.copyWith(pressureBar: 351),
      DEFAULT_BANKS.first.copyWith(name: '   '),
      DEFAULT_BANKS.first.copyWith(oxygenPercent: -1),
      DEFAULT_BANKS.first.copyWith(oxygenPercent: 30, heliumPercent: 71),
    ];

    for (final bank in invalidBanks) {
      final storage = MemoryStorage();
      expect(
        () => saveSupplyBanks(<Bank>[bank], storage),
        throwsA(isA<DomainError>()),
      );
      expect(storage.getItem(key), isNull);
    }

    final storage = MemoryStorage(<String, String>{
      key: encodeRecords(<Map<String, Object?>>[
        bankToRecord(invalidBanks.last),
      ]),
    });
    Object? reportedFailure;
    final banks = loadSupplyBanks(
      storage,
      onFallback: (error) => reportedFailure = error,
    );
    expect(recordsOf(banks), equals(expectedDefaultRecords));
    expect(reportedFailure, isA<DomainError>());
  });

  test(
    'loadSupplyBanks falls back instead of throwing on null legacy entries',
    () {
      final storage = MemoryStorage(<String, String>{
        key: jsonEncode(<Object?>[null, null, null]),
      });
      var fallbackCalls = 0;
      final banks = loadSupplyBanks(
        storage,
        onFallback: (_) => fallbackCalls += 1,
      );
      expect(fallbackCalls, 1);
      expect(
        banks.map((bank) => bank.id).toList(),
        equals(DEFAULT_BANKS.map((bank) => bank.id).toList()),
      );
    },
  );

  test('bank price per litre persists and legacy banks stay unpriced', () {
    final storage = MemoryStorage();
    final banks = loadSupplyBanks(storage)
        .map(
          (bank) => bank.id == DEFAULT_BANKS.first.id
              ? bank.copyWith(pricePerLitre: () => 0.0123)
              : bank,
        )
        .toList();
    saveSupplyBanks(banks, storage);
    expect(loadSupplyBanks(storage).first.pricePerLitre, 0.0123);
    expect(
      bankToRecord(loadSupplyBanks(MemoryStorage()).first)
          .containsKey('pricePerLitre'),
      isFalse,
    );
  });

  test('every default bank carries a maximum pressure of 200 bar', () {
    for (final bank in DEFAULT_BANKS) {
      expect(bank.maxPressureBar, 200);
    }
  });

  test('stored banks without maxPressureBar migrate to the greater of 200 bar and current pressure', () {
    final storage = MemoryStorage(<String, String>{
      key: encodeRecords(const <Map<String, Object?>>[
        <String, Object?>{
          'id': 'bank-low',
          'name': 'Low',
          'volumeL': 20,
          'pressureBar': 120,
          'oxygenPercent': 0,
          'heliumPercent': 100,
          'enabled': true,
        },
        <String, Object?>{
          'id': 'bank-high',
          'name': 'High',
          'volumeL': 20,
          'pressureBar': 250,
          'oxygenPercent': 0,
          'heliumPercent': 100,
          'enabled': true,
        },
      ]),
    });
    final banks = loadSupplyBanks(storage);
    expect(banks[0].maxPressureBar, 200);
    expect(banks[1].maxPressureBar, 250);
  });

  test('stored valid maxPressureBar is kept when banks are loaded', () {
    final storage = MemoryStorage(<String, String>{
      key: encodeRecords(const <Map<String, Object?>>[
        <String, Object?>{
          'id': 'bank-roomy',
          'name': 'Roomy',
          'volumeL': 20,
          'pressureBar': 120,
          'maxPressureBar': 300,
          'oxygenPercent': 0,
          'heliumPercent': 100,
          'enabled': true,
        },
      ]),
    });
    expect(loadSupplyBanks(storage).first.maxPressureBar, 300);
  });

  test('saving a bank without a finite maximum pressure is rejected', () {
    final storage = MemoryStorage();
    final withoutMax = DEFAULT_BANKS.first.copyWith(maxPressureBar: () => null);
    expect(
      () => saveSupplyBanks(<Bank>[withoutMax], storage),
      throwsA(isA<DomainError>()),
    );
    expect(storage.getItem(key), isNull);
  });

  test('gas preset link round-trips through storage in all three states', () {
    final storage = MemoryStorage();
    saveSupplyBanks(<Bank>[
      DEFAULT_BANKS[0],
      DEFAULT_BANKS[1].copyWith(gasPresetLink: const CustomMixLink()),
      DEFAULT_BANKS[2].copyWith(gasPresetLink: const NamedPresetLink('EAN32')),
    ], storage);
    final loaded = loadSupplyBanks(storage);
    expect(loaded[0].gasPresetLink, isA<UnnamedPresetLink>());
    expect(loaded[1].gasPresetLink, isA<CustomMixLink>());
    expect(
      loaded[2].gasPresetLink,
      isA<NamedPresetLink>().having((link) => link.name, 'name', 'EAN32'),
    );
  });

  test(
    'a non-text gas preset name is rejected as in JS validateSupplyBankInput',
    () {
      final record = Map<String, Object?>.of(bankToRecord(DEFAULT_BANKS[0]));
      record['gasPresetName'] = 5;
      expect(validateSupplyBankInput(record), <String>[
        'Supply bank preset names must be text.',
      ]);
    },
  );
}

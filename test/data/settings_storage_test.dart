import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/data/key_value_storage.dart';
import 'package:simplex_blender/src/data/settings_storage.dart';
import 'package:simplex_blender/src/data/settings_migrations.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/settings_json.dart';

import '../support/memory_storage.dart';

/// Storage whose reads always fail, mirroring `storage.getItem` throwing.
class _UnreadableStorage implements KeyValueStorage {
  @override
  String? getItem(String key) {
    throw StateError('storage unavailable');
  }

  @override
  void setItem(String key, String value) {}

  @override
  void clear() {}
}

/// Raw JSON view of the built-in settings, used to build legacy or invalid
/// stored records.
Map<String, Object?> _rawSettings() => settingsToJson(DEFAULT_SETTINGS);

MemoryStorage _storedRaw(Object? json) =>
    MemoryStorage(<String, String>{SETTINGS_STORAGE_KEY: jsonEncode(json)});

/// Stored record with only a gas list and volume list, as in the JS legacy
/// fixtures. [extra] is merged over those two keys.
MemoryStorage _legacyStorage({
  Map<String, Object?> extra = const <String, Object?>{},
}) => _storedRaw(<String, Object?>{
  'gasPresets': <Object?>[
    <String, Object?>{'name': 'Air', 'oxygenPercent': 21, 'heliumPercent': 0},
  ],
  'volumePresets': <Object?>[12],
  ...extra,
});

void _expectSameSettings(Settings actual, Settings expected) {
  expect(settingsToJson(actual), equals(settingsToJson(expected)));
}

/// Matches a [RangeError] whose message matches [pattern] (case-insensitive).
Matcher _rangeErrorWith(String pattern) => isA<RangeError>().having(
  (error) => error.message,
  'message',
  matches(RegExp(pattern, caseSensitive: false)),
);

void main() {
  test(
    'missing settings return independent copies of the built-in presets',
    () {
      final first = loadSettings(MemoryStorage());
      // The JS test mutates the loaded preset in place. Dart presets are
      // immutable and the loaded lists are unmodifiable, so the equivalent
      // guarantee is that callers cannot change the loaded lists.
      expect(
        () => first.gasPresets.add(first.gasPresets.first),
        throwsUnsupportedError,
      );
      final second = loadSettings(MemoryStorage());
      expect(second.gasPresets[0].name, DEFAULT_SETTINGS.gasPresets[0].name);
      expect(
        second.cylinderPresets[0].name,
        DEFAULT_SETTINGS.cylinderPresets[0].name,
      );
    },
  );

  test('settings default to metric units and the real-gas physics model', () {
    expect(DEFAULT_SETTINGS.units, 'metric');
    expect(DEFAULT_SETTINGS.physics, const PhysicsSettings(model: 'vdw'));
    final loaded = loadSettings(MemoryStorage());
    expect(loaded.units, 'metric');
    expect(loaded.physics, const PhysicsSettings(model: 'vdw'));
  });

  test(
    'settings default to metric display units and persist Imperial selection',
    () {
      expect(DEFAULT_SETTINGS.units, 'metric');
      final storage = MemoryStorage();
      saveSettings(DEFAULT_SETTINGS.copyWith(units: 'imperial'), storage);
      expect(loadSettings(storage).units, 'imperial');
    },
  );

  test(
    'legacy settings migrate active equipment values into preset collections',
    () {
      final loaded = _storedRaw(<String, Object?>{
        'gasPresets': <Object?>[
          <String, Object?>{
            'name': 'Air',
            'oxygenPercent': 21,
            'heliumPercent': 0,
          },
        ],
        'volumePresets': <Object?>[12],
        'booster': <String, Object?>{
          ...settingsBoosterToJson(DEFAULT_SETTINGS.booster),
          'compressorInletFlowLPerMin': 160,
        },
      });

      final settings = loadSettings(loaded);

      expect(settings.compressorPresets[0].inletFlowLPerMin, 160);
      expect(settings.boosterPresets[0].cylinderVolumeCm3, 9);
    },
  );

  test('equipment preset collections survive a settings round trip', () {
    final settings = DEFAULT_SETTINGS.copyWith(
      compressorPresets: <CompressorPreset>[
        ...DEFAULT_SETTINGS.compressorPresets,
        const CompressorPreset(
          name: 'High flow',
          inletFlowLPerMin: 160,
          maxPressureBar: 250,
          temperatureModifierC: 4,
        ),
      ],
    );
    final storage = MemoryStorage();

    saveSettings(settings, storage);

    expect(
      loadSettings(storage).compressorPresets,
      equals(settings.compressorPresets),
    );
  });

  test(
    'invalid equipment preset collections are rejected before storage changes',
    () {
      final storage = MemoryStorage();
      final invalidSettings = <Settings>[
        DEFAULT_SETTINGS.copyWith(
          compressorPresets: <CompressorPreset>[
            DEFAULT_SETTINGS.compressorPresets[0].copyWith(inletFlowLPerMin: 0),
          ],
        ),
        DEFAULT_SETTINGS.copyWith(
          boosterPresets: <BoosterPreset>[
            DEFAULT_SETTINGS.boosterPresets[0].copyWith(
              maxOutputPressureBar: 351,
            ),
          ],
        ),
        DEFAULT_SETTINGS.copyWith(
          compressorPresets: <CompressorPreset>[
            DEFAULT_SETTINGS.compressorPresets[0],
            DEFAULT_SETTINGS.compressorPresets[0].copyWith(
              name: 'bauer junior 2 200bar',
            ),
          ],
        ),
        DEFAULT_SETTINGS.copyWith(
          boosterPresets: <BoosterPreset>[
            DEFAULT_SETTINGS.boosterPresets[0],
            DEFAULT_SETTINGS.boosterPresets[0].copyWith(
              name: 'mps c1 sport light',
            ),
          ],
        ),
      ];

      for (final settings in invalidSettings) {
        expect(() => saveSettings(settings, storage), throwsRangeError);
        expect(storage.getItem(SETTINGS_STORAGE_KEY), isNull);
      }
    },
  );

  test('non-list equipment collections are rejected on load and fall back to defaults', () {
    // JS `saveSettings` rejects `{}` for these collections. The typed Dart
    // `Settings` cannot hold a non-list, so the same case is exercised through
    // the stored JSON on the load path, which is where it can occur.
    for (final collection in <String>['compressorPresets', 'boosterPresets']) {
      final saved = _rawSettings()..[collection] = <String, Object?>{};
      Object? reported;

      final loaded = loadSettings(
        _storedRaw(saved),
        onFallback: (error) {
          reported = error;
        },
      );

      _expectSameSettings(loaded, DEFAULT_SETTINGS);
      expect(reported, isA<RangeError>());
    }
  });

  test(
    'pressure limit mode defaults safely and validates the warning unlock',
    () {
      expect(DEFAULT_SETTINGS.pressureLimitMode, 'hard-stop');
      expect(DEFAULT_SETTINGS.pressureWarningUnlocked, isFalse);

      final legacy = _rawSettings()
        ..remove('pressureLimitMode')
        ..remove('pressureWarningUnlocked');
      final loaded = loadSettings(_storedRaw(legacy));
      expect(loaded.pressureLimitMode, 'hard-stop');
      expect(loaded.pressureWarningUnlocked, isFalse);

      Object? unlockFailure;
      loadSettings(
        _storedRaw(_rawSettings()..['pressureWarningUnlocked'] = 'true'),
        onFallback: (error) {
          unlockFailure = error;
        },
      );
      expect(unlockFailure, _rangeErrorWith(r'unlock.*boolean'));

      Object? modeFailure;
      loadSettings(
        _storedRaw(_rawSettings()..['pressureLimitMode'] = 'ignore'),
        onFallback: (error) {
          modeFailure = error;
        },
      );
      expect(modeFailure, _rangeErrorWith(r'pressure.*mode'));

      final savedStorage = MemoryStorage();
      saveSettings(
        DEFAULT_SETTINGS.copyWith(
          pressureLimitMode: 'warning',
          pressureWarningUnlocked: true,
        ),
        savedStorage,
      );
      final reloaded = loadSettings(savedStorage);
      expect(reloaded.pressureLimitMode, 'warning');
      expect(reloaded.pressureWarningUnlocked, isTrue);

      final invalidRecords = <Settings>[
        DEFAULT_SETTINGS.copyWith(pressureLimitMode: 'ignore'),
        DEFAULT_SETTINGS.copyWith(
          pressureLimitMode: 'warning',
          pressureWarningUnlocked: false,
        ),
      ];
      for (final invalid in invalidRecords) {
        _expectSameSettings(
          loadSettings(_storedRaw(settingsToJson(invalid))),
          DEFAULT_SETTINGS,
        );
      }
    },
  );

  test('old settings gain both pressure ceiling defaults', () {
    expect(
      loadSettings(_legacyStorage()).booster,
      equals(DEFAULT_SETTINGS.booster),
    );
  });

  test('legacy settings gain the default real-gas physics model', () {
    expect(
      loadSettings(_legacyStorage()).physics,
      const PhysicsSettings(model: 'vdw'),
    );
  });

  test('pressure ceilings survive settings round trip', () {
    final settings = DEFAULT_SETTINGS.copyWith(
      booster: DEFAULT_SETTINGS.booster.copyWith(
        maxCompressorPressureBar: 240,
        maxBoosterOutputPressureBar: 190,
      ),
    );
    final storage = MemoryStorage();

    saveSettings(settings, storage);

    expect(loadSettings(storage).booster, equals(settings.booster));
  });

  test('invalid pressure ceilings are rejected before storage changes', () {
    final storage = MemoryStorage();
    final invalidSettings = <Settings>[
      DEFAULT_SETTINGS.copyWith(
        booster: DEFAULT_SETTINGS.booster.copyWith(maxCompressorPressureBar: 9),
      ),
      DEFAULT_SETTINGS.copyWith(
        booster: DEFAULT_SETTINGS.booster.copyWith(
          maxBoosterOutputPressureBar: 9,
        ),
      ),
    ];

    for (final settings in invalidSettings) {
      expect(
        () => saveSettings(settings, storage),
        throwsA(_rangeErrorWith(r'pressure.*10.*350')),
      );
    }
    expect(storage.getItem(SETTINGS_STORAGE_KEY), isNull);
  });

  test('selected gas model survives a settings round trip', () {
    final storage = MemoryStorage();

    saveSettings(
      DEFAULT_SETTINGS.copyWith(physics: const PhysicsSettings(model: 'ideal')),
      storage,
    );

    expect(
      loadSettings(storage).physics,
      const PhysicsSettings(model: 'ideal'),
    );
  });

  test('unsupported gas models are rejected before storage changes', () {
    final storage = MemoryStorage();

    expect(
      () => saveSettings(
        DEFAULT_SETTINGS.copyWith(
          physics: const PhysicsSettings(model: 'peng-robinson'),
        ),
        storage,
      ),
      throwsA(_rangeErrorWith(r'gas model.*ideal.*vdw')),
    );
    expect(storage.getItem(SETTINGS_STORAGE_KEY), isNull);
  });

  test('saved gas and cylinder presets survive a load/save round trip', () {
    final storage = MemoryStorage();
    final settings = Settings(
      units: 'metric',
      physics: const PhysicsSettings(model: 'vdw'),
      costs: DEFAULT_SETTINGS.costs,
      pressureLimitMode: 'hard-stop',
      pressureWarningUnlocked: false,
      interimPressureTolerancePercent: 3,
      gasPresets: const <GasPreset>[
        GasPreset(name: 'Tx 16/50', oxygenPercent: 16, heliumPercent: 50),
      ],
      cylinderPresets: const <CylinderPreset>[
        CylinderPreset(
          name: 'Custom 11 L',
          volumeL: 11,
          material: 'aluminum',
          massKg: 12.4,
          workingPressureBar: 300,
          hotOverfillPercent: 2,
        ),
      ],
      booster: DEFAULT_SETTINGS.booster,
      compressorPresets: DEFAULT_SETTINGS.compressorPresets,
      boosterPresets: DEFAULT_SETTINGS.boosterPresets,
    );

    saveSettings(settings, storage);

    _expectSameSettings(loadSettings(storage), settings);
  });

  test(
    'saved settings preserve the shared booster minimum source pressure',
    () {
      final storage = MemoryStorage();
      final settings = Settings(
        units: 'metric',
        physics: const PhysicsSettings(model: 'vdw'),
        pressureLimitMode: 'hard-stop',
        pressureWarningUnlocked: false,
        interimPressureTolerancePercent: 3,
        costs: DEFAULT_SETTINGS.costs,
        gasPresets: const <GasPreset>[
          GasPreset(name: 'Tx 16/50', oxygenPercent: 16, heliumPercent: 50),
        ],
        cylinderPresets: const <CylinderPreset>[
          CylinderPreset(
            name: '11 L Steel',
            volumeL: 11,
            material: 'steel',
            massKg: 14,
            workingPressureBar: 232,
            hotOverfillPercent: 2,
          ),
        ],
        booster: DEFAULT_SETTINGS.booster.copyWith(
          minimumSourcePressureBar: 27,
        ),
        compressorPresets: DEFAULT_SETTINGS.compressorPresets,
        boosterPresets: DEFAULT_SETTINGS.boosterPresets
            .map((preset) => preset.copyWith(minimumSourcePressureBar: 27))
            .toList(),
      );

      saveSettings(settings, storage);

      _expectSameSettings(loadSettings(storage), settings);
    },
  );

  test('old settings gain the default shared booster minimum', () {
    expect(loadSettings(_legacyStorage()).booster.minimumSourcePressureBar, 5);
  });

  test('old settings gain all thermodynamic booster defaults', () {
    final settings = loadSettings(
      _legacyStorage(
        extra: <String, Object?>{
          'booster': <String, Object?>{'minimumSourcePressureBar': 25},
        },
      ),
    );

    expect(
      settingsBoosterToJson(settings.booster),
      equals(<String, Object?>{
        'minimumSourcePressureBar': 25,
        'cylinderVolumeCm3': 9,
        'oxygenBoostBpm': 35,
        'otherBoostBpm': 50,
        'oxygenDecantRateBarPerMin': 5,
        'otherDecantRateBarPerMin': 10,
        'drainingRateBarPerMin': 15,
        'compressorInletFlowLPerMin': 100,
        'maxCompressorPressureBar': 232,
        'maxBoosterOutputPressureBar': 230,
        'boosterTemperatureModifierC': 10,
        'compressorTemperatureModifierC': 5,
      }),
    );
  });

  test('temperature modifiers survive settings round trip', () {
    final settings = DEFAULT_SETTINGS.copyWith(
      booster: DEFAULT_SETTINGS.booster.copyWith(
        boosterTemperatureModifierC: 12,
        compressorTemperatureModifierC: 28,
      ),
    );
    final storage = MemoryStorage();

    saveSettings(settings, storage);

    expect(loadSettings(storage).booster, equals(settings.booster));
  });

  test('temperature modifiers are bounded', () {
    final storage = MemoryStorage();
    final invalidSettings = <Settings>[
      DEFAULT_SETTINGS.copyWith(
        booster: DEFAULT_SETTINGS.booster.copyWith(
          boosterTemperatureModifierC: 101,
        ),
      ),
      DEFAULT_SETTINGS.copyWith(
        booster: DEFAULT_SETTINGS.booster.copyWith(
          compressorTemperatureModifierC: 101,
        ),
      ),
    ];

    for (final settings in invalidSettings) {
      expect(
        () => saveSettings(settings, storage),
        throwsA(_rangeErrorWith(r'temperature modifier.*-100.*100')),
      );
    }
    expect(storage.getItem(SETTINGS_STORAGE_KEY), isNull);
  });

  test('invalid thermodynamic booster settings are rejected before storage changes', () {
    final storage = MemoryStorage();
    final settings = DEFAULT_SETTINGS.copyWith(
      booster: DEFAULT_SETTINGS.booster.copyWith(
        cylinderVolumeCm3: 0,
        oxygenDecantRateBarPerMin: -1,
        drainingRateBarPerMin: 0,
      ),
    );

    expect(
      () => saveSettings(settings, storage),
      throwsA(_rangeErrorWith(r'cylinder.*cm|decant|draining')),
    );
    expect(storage.getItem(SETTINGS_STORAGE_KEY), isNull);
  });

  test('thermodynamic booster settings survive a save/load round trip', () {
    final storage = MemoryStorage();
    final settings = DEFAULT_SETTINGS.copyWith(
      booster: DEFAULT_SETTINGS.booster.copyWith(
        minimumSourcePressureBar: 18,
        cylinderVolumeCm3: 12,
        oxygenBoostBpm: 40,
        otherBoostBpm: 55,
        oxygenDecantRateBarPerMin: 3,
        otherDecantRateBarPerMin: 7,
        // The JS fixture sets drainingRateBarPerMin twice (2.5, then 9); the
        // later value wins, so 9 is the expected draining rate.
        drainingRateBarPerMin: 9,
        compressorInletFlowLPerMin: 160,
        maxCompressorPressureBar: 245,
        maxBoosterOutputPressureBar: 185,
      ),
    );

    saveSettings(settings, storage);

    expect(loadSettings(storage).booster, equals(settings.booster));
  });

  test('unreadable or invalid saved settings fall back to defaults', () {
    final storage = MemoryStorage(<String, String>{
      SETTINGS_STORAGE_KEY: '{bad json',
    });
    _expectSameSettings(loadSettings(storage), DEFAULT_SETTINGS);

    storage.setItem(
      SETTINGS_STORAGE_KEY,
      jsonEncode(<String, Object?>{
        'gasPresets': <Object?>[],
        'volumePresets': <Object?>[-1],
      }),
    );
    _expectSameSettings(loadSettings(storage), DEFAULT_SETTINGS);
  });

  test('unusable saved settings report the fallback cause', () {
    final storage = MemoryStorage(<String, String>{
      SETTINGS_STORAGE_KEY: '{bad json',
    });
    Object? reportedFailure;

    final loaded = loadSettings(
      storage,
      onFallback: (error) {
        reportedFailure = error;
      },
    );

    _expectSameSettings(loaded, DEFAULT_SETTINGS);
    // Dart's counterpart of the JS SyntaxError from JSON.parse.
    expect(reportedFailure, isA<FormatException>());
  });

  // No JS test covers an unreadable store; this pins the JS `getItem`
  // try/catch branch (defaults returned, cause reported) to the JS behavior.
  test(
    'storage that cannot be read falls back to defaults and reports the cause',
    () {
      Object? reportedFailure;

      final loaded = loadSettings(
        _UnreadableStorage(),
        onFallback: (error) {
          reportedFailure = error;
        },
      );

      _expectSameSettings(loaded, DEFAULT_SETTINGS);
      expect(reportedFailure, isA<StateError>());
    },
  );

  test('invalid preset lists are rejected before storage is changed', () {
    final invalidSettings = <Settings>[
      DEFAULT_SETTINGS.copyWith(
        gasPresets: const <GasPreset>[
          GasPreset(name: 'Air', oxygenPercent: 21, heliumPercent: 0),
          GasPreset(name: 'air', oxygenPercent: 20, heliumPercent: 0),
        ],
        cylinderPresets: <CylinderPreset>[DEFAULT_SETTINGS.cylinderPresets[0]],
      ),
      DEFAULT_SETTINGS.copyWith(
        gasPresets: const <GasPreset>[
          GasPreset(name: 'Invalid', oxygenPercent: 70, heliumPercent: 40),
        ],
        cylinderPresets: <CylinderPreset>[DEFAULT_SETTINGS.cylinderPresets[0]],
      ),
      DEFAULT_SETTINGS.copyWith(
        cylinderPresets: <CylinderPreset>[
          DEFAULT_SETTINGS.cylinderPresets[0].copyWith(material: 'carbon'),
        ],
      ),
      DEFAULT_SETTINGS.copyWith(
        cylinderPresets: <CylinderPreset>[
          DEFAULT_SETTINGS.cylinderPresets[0].copyWith(massKg: 0),
        ],
      ),
      DEFAULT_SETTINGS.copyWith(
        cylinderPresets: <CylinderPreset>[
          DEFAULT_SETTINGS.cylinderPresets[0].copyWith(workingPressureBar: 351),
        ],
      ),
    ];

    for (final settings in invalidSettings) {
      final storage = MemoryStorage();
      expect(() => saveSettings(settings, storage), throwsRangeError);
      expect(storage.getItem(SETTINGS_STORAGE_KEY), isNull);
    }
  });

  test('legacy volume settings migrate to steel cylinder presets', () {
    final storage = _storedRaw(<String, Object?>{
      'gasPresets': <Object?>[
        <String, Object?>{
          'name': 'Air',
          'oxygenPercent': 21,
          'heliumPercent': 0,
        },
      ],
      'volumePresets': <Object?>[12, 24],
    });

    expect(
      loadSettings(storage).cylinderPresets,
      equals(const <CylinderPreset>[
        CylinderPreset(
          name: '12 L Steel 232 bar',
          volumeL: 12,
          material: 'steel',
          massKg: 14,
          workingPressureBar: 232,
          hotOverfillPercent: 2,
        ),
        CylinderPreset(
          name: '24 L Steel 232 bar',
          volumeL: 24,
          material: 'steel',
          massKg: 14,
          workingPressureBar: 232,
          hotOverfillPercent: 2,
        ),
      ]),
    );
  });

  test(
    'settings draft copies own independent equipment preset collections',
    () {
      final source = loadSettings(MemoryStorage());

      final draft = copySettings(source).copyWith(
        compressorPresets: <CompressorPreset>[
          source.compressorPresets[0].copyWith(name: 'Draft compressor'),
          ...source.compressorPresets.skip(1),
        ],
        boosterPresets: <BoosterPreset>[
          source.boosterPresets[0].copyWith(maxOutputPressureBar: 250),
          ...source.boosterPresets.skip(1),
        ],
      );

      expect(draft.compressorPresets[0].name, 'Draft compressor');
      expect(draft.boosterPresets[0].maxOutputPressureBar, 250);
      expect(source.compressorPresets[0].name, 'Bauer Junior 2 200bar');
      expect(source.boosterPresets[0].maxOutputPressureBar, 230);
    },
  );

  test('saved cylinder presets without hot overfill migrate to the two-percent default', () {
    final saved = _rawSettings();
    saved['cylinderPresets'] = <Object?>[
      for (final preset in DEFAULT_SETTINGS.cylinderPresets)
        <String, Object?>{
          'name': preset.name,
          'volumeL': preset.volumeL,
          'material': preset.material,
          'massKg': preset.massKg,
          'workingPressureBar': preset.workingPressureBar,
        },
    ];

    final loaded = loadSettings(_storedRaw(saved));

    expect(
      loaded.cylinderPresets.map((preset) => preset.hotOverfillPercent),
      everyElement(2),
    );
  });

  test('interim pressure tolerance missing from saved settings migrates to three percent', () {
    final legacy = _rawSettings()..remove('interimPressureTolerancePercent');

    expect(loadSettings(_storedRaw(legacy)).interimPressureTolerancePercent, 3);
  });

  test('interim pressure tolerance round-trips through storage and validates its bounds', () {
    final storage = MemoryStorage();
    saveSettings(
      DEFAULT_SETTINGS.copyWith(interimPressureTolerancePercent: 5),
      storage,
    );
    expect(loadSettings(storage).interimPressureTolerancePercent, 5);

    for (final value in <double>[0.5, 10]) {
      saveSettings(
        DEFAULT_SETTINGS.copyWith(interimPressureTolerancePercent: value),
        storage,
      );
      expect(loadSettings(storage).interimPressureTolerancePercent, value);
    }

    for (final value in <double>[0.4, 10.5, double.nan]) {
      expect(
        () => saveSettings(
          DEFAULT_SETTINGS.copyWith(interimPressureTolerancePercent: value),
          storage,
        ),
        throwsA(_rangeErrorWith('interim pressure tolerance')),
      );
    }

    // A stored string is not a number; the load path must reject it.
    Object? reported;
    final loaded = loadSettings(
      _storedRaw(_rawSettings()..['interimPressureTolerancePercent'] = '3'),
      onFallback: (error) {
        reported = error;
      },
    );
    _expectSameSettings(loaded, DEFAULT_SETTINGS);
    expect(reported, _rangeErrorWith('interim pressure tolerance'));
  });

  test('flat fees survive save, load and copy', () {
    final storage = MemoryStorage();
    final costs = Costs(
      currencySymbol: DEFAULT_SETTINGS.costs.currencySymbol,
      leftoverDiscountPercent: DEFAULT_SETTINGS.costs.leftoverDiscountPercent,
      operationPrices: const OperationPrices(
        boost: 1.25,
        decant: 0.5,
        topUp: 4.5,
      ),
    );
    saveSettings(DEFAULT_SETTINGS.copyWith(costs: costs), storage);

    final loaded = loadSettings(storage);

    expect(loaded.costs.operationPrices.boost, 1.25);
    expect(loaded.costs.operationPrices.decant, 0.5);
    expect(loaded.costs.operationPrices.topUp, 4.5);
    expect(costsToJson(loaded.costs).containsKey('pricePerLitre'), isFalse);

    final copy = copySettings(loaded).copyWith(
      costs: Costs(
        currencySymbol: loaded.costs.currencySymbol,
        leftoverDiscountPercent: loaded.costs.leftoverDiscountPercent,
        operationPrices: const OperationPrices(
          boost: 9,
          decant: 0.5,
          topUp: 4.5,
        ),
      ),
    );
    expect(copy.costs.operationPrices.boost, 9);
    expect(loaded.costs.operationPrices.boost, 1.25);
  });

  test('legacy saved settings without costs load with zero-fee defaults', () {
    final legacy = _rawSettings()..remove('costs');

    expect(
      costsToJson(loadSettings(_storedRaw(legacy)).costs),
      equals(costsToJson(DEFAULT_SETTINGS.costs)),
    );
  });

  test('legacy per-litre cost shape loads with zero flat fees and keeps a valid symbol and discount', () {
    final legacy = _rawSettings()
      ..['costs'] = <String, Object?>{
        'currencySymbol': '€',
        'pricePerLitre': <String, Object?>{'oxygen': 0.02, 'helium': 0.05},
        'leftoverDiscountPercent': 12.5,
        'operationPrices': <String, Object?>{
          'boostPerLitre': 0.001,
          'decantPerLitre': 0.002,
          'equalizePerLitre': 0.003,
          'topUpPerOperation': 1.5,
        },
      };
    final failures = <Object>[];

    final loaded = loadSettings(
      _storedRaw(legacy),
      onFallback: (error) => failures.add(error),
    );

    expect(failures, isEmpty);
    expect(loaded.costs.currencySymbol, '€');
    expect(loaded.costs.leftoverDiscountPercent, 12.5);
    expect(loaded.costs.operationPrices.boost, 0);
    expect(loaded.costs.operationPrices.decant, 0);
    expect(loaded.costs.operationPrices.topUp, 0);
  });

  test(
    'invalid flat fees in saved settings fall back to the default settings',
    () {
      final invalidPrices = <Map<String, Object?>>[
        <String, Object?>{'boost': -1, 'decant': 0, 'topUp': 0},
        <String, Object?>{'boost': 0, 'decant': 1000001, 'topUp': 0},
        <String, Object?>{'boost': 0, 'decant': 0, 'topUp': 'x'},
      ];

      for (final operationPrices in invalidPrices) {
        final saved = _rawSettings()
          ..['costs'] = <String, Object?>{
            'currencySymbol': '€',
            'leftoverDiscountPercent': 5,
            'operationPrices': operationPrices,
          };
        final failures = <Object>[];

        final loaded = loadSettings(
          _storedRaw(saved),
          onFallback: (error) => failures.add(error),
        );

        expect(failures, hasLength(1));
        expect(
          costsToJson(loaded.costs),
          equals(costsToJson(DEFAULT_SETTINGS.costs)),
        );
      }
    },
  );

  test('saving settings with invalid costs throws', () {
    final settings = DEFAULT_SETTINGS.copyWith(
      costs: Costs(
        currencySymbol: DEFAULT_SETTINGS.costs.currencySymbol,
        leftoverDiscountPercent: -1,
        operationPrices: DEFAULT_SETTINGS.costs.operationPrices,
      ),
    );

    expect(() => saveSettings(settings, MemoryStorage()), throwsRangeError);
  });

  test('every stored settings shape survives a save then load', () {
    final settings = Settings(
      units: 'imperial',
      physics: const PhysicsSettings(model: 'ideal'),
      pressureLimitMode: 'warning',
      pressureWarningUnlocked: true,
      interimPressureTolerancePercent: 5,
      costs: const Costs(
        currencySymbol: r'$',
        leftoverDiscountPercent: 10,
        operationPrices: OperationPrices(boost: 1, decant: 2, topUp: 3),
      ),
      gasPresets: const <GasPreset>[
        GasPreset(name: 'Tx 16/50', oxygenPercent: 16, heliumPercent: 50),
      ],
      cylinderPresets: const <CylinderPreset>[
        CylinderPreset(
          name: 'Custom 11 L',
          volumeL: 11,
          material: 'aluminum',
          massKg: 12.4,
          workingPressureBar: 300,
          hotOverfillPercent: 2,
        ),
      ],
      compressorPresets: <CompressorPreset>[
        DEFAULT_SETTINGS.compressorPresets[0].copyWith(inletFlowLPerMin: 120),
      ],
      boosterPresets: <BoosterPreset>[
        DEFAULT_SETTINGS.boosterPresets[0].copyWith(maxOutputPressureBar: 200),
      ],
      booster: DEFAULT_SETTINGS.booster.copyWith(
        oxygenBoostBpm: 40,
        drainingRateBarPerMin: 9,
      ),
    );
    final storage = MemoryStorage();

    saveSettings(settings, storage);

    _expectSameSettings(loadSettings(storage), settings);
  });

  group('cylinder dimension migration', () {
    Map<String, Object?> preset(
      String name,
      double volumeL,
      String material, {
      Map<String, Object?> extra = const <String, Object?>{},
    }) => <String, Object?>{
      'name': name,
      'volumeL': volumeL,
      'material': material,
      'massKg': 10,
      'workingPressureBar': 200,
      'hotOverfillPercent': 2,
      ...extra,
    };

    Map<String, Object?> withCylinders(List<Map<String, Object?>> cylinders) =>
        <String, Object?>{..._rawSettings(), 'cylinderPresets': cylinders};

    List<Map<String, Object?>> migrated(List<Map<String, Object?>> input) {
      final result = addNearestCylinderDimensions(withCylinders(input));
      return (result['cylinderPresets']! as List<Object?>)
          .map((p) => p! as Map<String, Object?>)
          .toList();
    }

    test('aluminium customs take the closest-volume default', () {
      final result = migrated(<Map<String, Object?>>[
        preset('Custom 5.5', 5.5, 'aluminum'),
        preset('Custom 20', 20, 'aluminum'),
        preset('Custom 2', 2, 'aluminum'),
      ]);
      expect(result[0]['diameterMm'], 133); // Luxfer S40
      expect(result[0]['lengthMm'], 625);
      expect(result[1]['diameterMm'], 184); // Luxfer S80 (earlier default)
      expect(result[1]['lengthMm'], 662);
      expect(result[2]['diameterMm'], 111.3); // Catalina S13
      expect(result[2]['lengthMm'], 325);
    });

    test('each built-in S80 keeps its own dimensions', () {
      final result = migrated(<Map<String, Object?>>[
        preset('Luxfer S80', 11.1, 'aluminum'),
        preset('Catalina S80', 11.1, 'aluminum'),
      ]);
      expect(result[0]['diameterMm'], 184);
      expect(result[0]['lengthMm'], 662);
      expect(result[1]['diameterMm'], 184.2);
      expect(result[1]['lengthMm'], 658);
    });

    test('steel migrates only at exactly 3 L; others stay without keys', () {
      final result = migrated(<Map<String, Object?>>[
        preset('Steel 3', 3, 'steel'),
        preset('Steel 12', 12, 'steel'),
        preset('Steel 3.1', 3.1, 'steel'),
        preset('Fero 3', 3, 'carbon-wrapped-steel'),
      ]);
      expect(result[0]['diameterMm'], 100.1);
      expect(result[0]['lengthMm'], 495.3);
      for (final i in <int>[1, 2, 3]) {
        expect(result[i].containsKey('diameterMm'), isFalse, reason: '$i');
        expect(result[i].containsKey('lengthMm'), isFalse, reason: '$i');
      }
    });

    test('presets with either key present, including null, are untouched', () {
      final input = <Map<String, Object?>>[
        preset(
          'Has both',
          5.7,
          'aluminum',
          extra: <String, Object?>{'diameterMm': 150, 'lengthMm': 600},
        ),
        preset(
          'Null keys',
          5.7,
          'aluminum',
          extra: <String, Object?>{'diameterMm': null, 'lengthMm': null},
        ),
        preset(
          'One key',
          5.7,
          'aluminum',
          extra: <String, Object?>{'diameterMm': 150},
        ),
      ];
      final result = migrated(input);
      expect(result, input);
    });

    test('non-numeric volume or non-string material is left alone', () {
      final bad = <String, Object?>{
        ...preset('X', 5, 'aluminum'),
        'volumeL': 'a',
      };
      final result = migrated(<Map<String, Object?>>[bad]);
      expect(result.single.containsKey('diameterMm'), isFalse);
    });

    test('running the step twice equals running it once', () {
      final input = withCylinders(<Map<String, Object?>>[
        preset('Custom 5.5', 5.5, 'aluminum'),
        preset('Steel 12', 12, 'steel'),
      ]);
      final once = addNearestCylinderDimensions(input);
      expect(addNearestCylinderDimensions(once), once);
    });

    test('Luxfer S80 volume is corrected only for the untouched built-in', () {
      Map<String, Object?> luxfer({
        String name = 'Luxfer S80',
        double volume = 10.6,
        double mass = 13.7,
      }) => <String, Object?>{
        'name': name,
        'volumeL': volume,
        'material': 'aluminum',
        'massKg': mass,
        'workingPressureBar': 217,
        'hotOverfillPercent': 2,
      };
      double volumeOf(Map<String, Object?> p) {
        final result = correctLuxferS80Volume(
          withCylinders(<Map<String, Object?>>[p]),
        );
        return ((result['cylinderPresets']! as List<Object?>).single!
                as Map<String, Object?>)['volumeL']!
            as double;
      }

      expect(volumeOf(luxfer()), 11.1);
      expect(volumeOf(luxfer(mass: 14)), 10.6); // edited
      expect(volumeOf(luxfer(name: 'My 10.6 alu')), 10.6); // other name
      expect(volumeOf(luxfer(volume: 12)), 12); // edited volume
      // Idempotent: the corrected preset no longer matches.
      final once = correctLuxferS80Volume(
        withCylinders(<Map<String, Object?>>[luxfer()]),
      );
      expect(correctLuxferS80Volume(once), once);
    });

    test('a preset that already has dimension keys is not corrected', () {
      final withKeys = <String, Object?>{
        'name': 'Luxfer S80',
        'volumeL': 10.6,
        'material': 'aluminum',
        'massKg': 13.7,
        'workingPressureBar': 217,
        'hotOverfillPercent': 2,
        'diameterMm': 184,
        'lengthMm': 662,
      };
      final result = correctLuxferS80Volume(
        withCylinders(<Map<String, Object?>>[withKeys]),
      );
      expect(
        ((result['cylinderPresets']! as List<Object?>).single!
            as Map<String, Object?>)['volumeL'],
        10.6,
      );
    });
  });

  group('cylinder migration notice', () {
    Map<String, Object?> legacyPreset(String name, double v, String material) =>
        <String, Object?>{
          'name': name,
          'volumeL': v,
          'material': material,
          'massKg': 10,
          'workingPressureBar': 200,
          'hotOverfillPercent': 2,
        };

    MemoryStorage storedWith(List<Map<String, Object?>> cylinders) =>
        _storedRaw(<String, Object?>{
          ..._rawSettings(),
          'cylinderPresets': cylinders,
        });

    test('reports matched and incomplete names once something changed', () {
      CylinderDimensionMigration? report;
      loadSettings(
        storedWith(<Map<String, Object?>>[
          legacyPreset('Alu 5.5', 5.5, 'aluminum'),
          legacyPreset('Steel 12', 12, 'steel'),
        ]),
        onCylinderDimensionsMigrated: (r) => report = r,
      );
      expect(report, isNotNull);
      expect(report!.matched, <String>['Alu 5.5']);
      expect(report!.incomplete, <String>['Steel 12']);
    });

    test('is not called when only unmatched presets exist', () {
      var called = false;
      loadSettings(
        storedWith(<Map<String, Object?>>[
          legacyPreset('Steel 12', 12, 'steel'),
        ]),
        onCylinderDimensionsMigrated: (_) => called = true,
      );
      expect(called, isFalse);
    });

    test(
      'is not called for defaults, empty storage, or already-migrated data',
      () {
        var calls = 0;
        void count(CylinderDimensionMigration _) => calls++;
        loadSettings(MemoryStorage(), onCylinderDimensionsMigrated: count);
        loadSettings(
          _storedRaw(_rawSettings()),
          onCylinderDimensionsMigrated: count,
        );
        expect(calls, 0);
      },
    );

    test('is not called when load falls back to defaults', () {
      var called = false;
      loadSettings(
        _storedRaw(<String, Object?>{
          ..._rawSettings(),
          'units': 'metric',
          'cylinderPresets': <Object?>[],
        }),
        onFallback: (_) {},
        onCylinderDimensionsMigrated: (_) => called = true,
      );
      expect(called, isFalse);
    });

    test('message lists both groups', () {
      expect(
        cylinderMigrationNoticeMessage(
          const CylinderDimensionMigration(
            matched: <String>['A', 'B'],
            incomplete: <String>['C'],
          ),
        ),
        'Diameter and length were set for 2 saved cylinder presets from the '
        'nearest standard cylinder: A, B. Check them in Settings > Cylinder '
        'presets. 1 preset still needs a diameter and length: C.',
      );
    });
  });
}

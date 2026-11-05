import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/settings.dart';

CylinderPreset _cylinder(String name, double volumeL) {
  return CylinderPreset(
    name: name,
    volumeL: volumeL,
    material: 'steel',
    massKg: 1,
    workingPressureBar: 232,
    hotOverfillPercent: 2,
  );
}

void main() {
  test('settings default to metric units and the real-gas physics model', () {
    expect(DEFAULT_SETTINGS.units, 'metric');
    expect(DEFAULT_SETTINGS.physics, const PhysicsSettings(model: 'vdw'));
  });

  test(
    'settings default to metric display units and persist Imperial selection',
    () {
      expect(DEFAULT_SETTINGS.units, 'metric');
    },
  );

  test('unsupported display units are rejected before storage changes', () {
    expect(
      validateSettings(DEFAULT_SETTINGS.copyWith(units: 'us')).join(' '),
      matches(RegExp('units', caseSensitive: false)),
    );
  });

  test('built-in settings match the requested diving equipment defaults', () {
    expect(DEFAULT_SETTINGS.gasPresets, const <GasPreset>[
      GasPreset(name: 'Air', oxygenPercent: 21, heliumPercent: 0),
      GasPreset(name: 'EAN 32', oxygenPercent: 32, heliumPercent: 0),
      GasPreset(name: 'EAN 50', oxygenPercent: 50, heliumPercent: 0),
      GasPreset(name: 'Oxygen', oxygenPercent: 100, heliumPercent: 0),
      GasPreset(name: 'Helium', oxygenPercent: 0, heliumPercent: 100),
      GasPreset(name: 'Tx 21/35', oxygenPercent: 21, heliumPercent: 35),
      GasPreset(name: 'Tx 18/45', oxygenPercent: 18, heliumPercent: 45),
      GasPreset(name: 'Tx 15/55', oxygenPercent: 15, heliumPercent: 55),
      GasPreset(name: 'Tx 12/65', oxygenPercent: 12, heliumPercent: 65),
      GasPreset(name: 'Tx 50/20', oxygenPercent: 50, heliumPercent: 20),
    ]);
    expect(DEFAULT_SETTINGS.cylinderPresets, const <CylinderPreset>[
      CylinderPreset(
        name: 'Faber 3L',
        volumeL: 3,
        material: 'steel',
        massKg: 4.4,
        workingPressureBar: 232,
        hotOverfillPercent: 2,
      ),
      CylinderPreset(
        name: 'Catalina S13',
        volumeL: 1.9,
        material: 'aluminum',
        massKg: 2.6,
        workingPressureBar: 207,
        hotOverfillPercent: 2,
      ),
      CylinderPreset(
        name: 'Luxfer S40',
        volumeL: 5.7,
        material: 'aluminum',
        massKg: 7.2,
        workingPressureBar: 207,
        hotOverfillPercent: 2,
      ),
      CylinderPreset(
        name: 'Luxfer S80',
        volumeL: 10.6,
        material: 'aluminum',
        massKg: 13.7,
        workingPressureBar: 217,
        hotOverfillPercent: 2,
      ),
      CylinderPreset(
        name: 'Catalina S80',
        volumeL: 11.1,
        material: 'aluminum',
        massKg: 14.3,
        workingPressureBar: 207,
        hotOverfillPercent: 2,
      ),
    ]);
    expect(DEFAULT_SETTINGS.compressorPresets, const <CompressorPreset>[
      CompressorPreset(
        name: 'Bauer Junior 2 200bar',
        inletFlowLPerMin: 100,
        maxPressureBar: 232,
        temperatureModifierC: 5,
      ),
      CompressorPreset(
        name: 'Bauer Oceanus 300bar',
        inletFlowLPerMin: 140,
        maxPressureBar: 300,
        temperatureModifierC: 7,
      ),
      CompressorPreset(
        name: 'Bauer Junior 2 225 bar',
        inletFlowLPerMin: 100,
        maxPressureBar: 225,
        temperatureModifierC: 5,
      ),
      CompressorPreset(
        name: 'Bauer Junior 2 330 bar',
        inletFlowLPerMin: 100,
        maxPressureBar: 330,
        temperatureModifierC: 5,
      ),
      CompressorPreset(
        name: 'Bauer Oceanus 230 bar',
        inletFlowLPerMin: 140,
        maxPressureBar: 230,
        temperatureModifierC: 7,
      ),
      CompressorPreset(
        name: 'Coltri MCH 6 232 bar',
        inletFlowLPerMin: 100,
        maxPressureBar: 232,
        temperatureModifierC: 5,
      ),
      CompressorPreset(
        name: 'Coltri MCH 13 225 bar',
        inletFlowLPerMin: 235,
        maxPressureBar: 225,
        temperatureModifierC: 5,
      ),
      CompressorPreset(
        name: 'Coltri MCH 13 330 bar',
        inletFlowLPerMin: 235,
        maxPressureBar: 330,
        temperatureModifierC: 5,
      ),
    ]);
    expect(DEFAULT_SETTINGS.boosterPresets, const <BoosterPreset>[
      BoosterPreset(
        name: 'MPS C1 Sport light',
        minimumSourcePressureBar: 5,
        cylinderVolumeCm3: 9,
        oxygenBoostBpm: 35,
        otherBoostBpm: 50,
        oxygenDecantRateBarPerMin: 5,
        otherDecantRateBarPerMin: 10,
        maxOutputPressureBar: 230,
        temperatureModifierC: 10,
        drainingRateBarPerMin: 15,
      ),
      BoosterPreset(
        name: 'Maximator ROB22',
        minimumSourcePressureBar: 50,
        cylinderVolumeCm3: 4.6,
        oxygenBoostBpm: 30,
        otherBoostBpm: 50,
        oxygenDecantRateBarPerMin: 5,
        otherDecantRateBarPerMin: 10,
        maxOutputPressureBar: 280,
        temperatureModifierC: 0,
        drainingRateBarPerMin: 15,
      ),
      BoosterPreset(
        name: 'Maximator ROB 32D',
        minimumSourcePressureBar: 50,
        cylinderVolumeCm3: 11.6,
        oxygenBoostBpm: 45,
        otherBoostBpm: 70,
        oxygenDecantRateBarPerMin: 6,
        otherDecantRateBarPerMin: 12,
        maxOutputPressureBar: 300,
        temperatureModifierC: 0,
        drainingRateBarPerMin: 15,
      ),
      BoosterPreset(
        name: 'Haskel AG-15',
        minimumSourcePressureBar: 3.5,
        cylinderVolumeCm3: 101.6,
        oxygenBoostBpm: 30,
        otherBoostBpm: 45,
        oxygenDecantRateBarPerMin: 5,
        otherDecantRateBarPerMin: 10,
        maxOutputPressureBar: 155,
        temperatureModifierC: 0,
        drainingRateBarPerMin: 15,
      ),
    ]);
    expect(
      DEFAULT_SETTINGS.booster,
      const SettingsBooster(
        minimumSourcePressureBar: 5,
        cylinderVolumeCm3: 9,
        oxygenBoostBpm: 35,
        otherBoostBpm: 50,
        oxygenDecantRateBarPerMin: 5,
        otherDecantRateBarPerMin: 10,
        drainingRateBarPerMin: 15,
        compressorInletFlowLPerMin: 100,
        maxCompressorPressureBar: 232,
        maxBoosterOutputPressureBar: 230,
        boosterTemperatureModifierC: 10,
        compressorTemperatureModifierC: 5,
      ),
    );
  });

  test('settings include compressor and booster pressure ceilings, '
      'temperature modifiers, and draining rate', () {
    expect(DEFAULT_SETTINGS.booster.maxCompressorPressureBar, 232);
    expect(DEFAULT_SETTINGS.booster.maxBoosterOutputPressureBar, 230);
    expect(DEFAULT_SETTINGS.booster.drainingRateBarPerMin, 15);
    expect(DEFAULT_SETTINGS.booster.boosterTemperatureModifierC, 10);
    expect(DEFAULT_SETTINGS.booster.compressorTemperatureModifierC, 5);
    expect(DEFAULT_SETTINGS.booster.drainingRateBarPerMin, 15);
  });

  test('default settings expose named compressor and booster presets', () {
    expect(DEFAULT_SETTINGS.compressorPresets.length, 8);
    expect(DEFAULT_SETTINGS.boosterPresets.length, 4);
    expect(DEFAULT_SETTINGS.compressorPresets[0].inletFlowLPerMin, 100);
    expect(DEFAULT_SETTINGS.boosterPresets[0].maxOutputPressureBar, 230);
  });

  test('requires at least one preset in every settings collection', () {
    final emptied = <Settings>[
      DEFAULT_SETTINGS.copyWith(gasPresets: const <GasPreset>[]),
      DEFAULT_SETTINGS.copyWith(cylinderPresets: const <CylinderPreset>[]),
      DEFAULT_SETTINGS.copyWith(compressorPresets: const <CompressorPreset>[]),
      DEFAULT_SETTINGS.copyWith(boosterPresets: const <BoosterPreset>[]),
    ];
    for (final settings in emptied) {
      expect(
        validateSettings(settings).join(' '),
        matches(RegExp(r'At least one .* preset is required\.')),
      );
    }
  });

  test(
    'applying equipment presets copies only their active booster fields',
    () {
      final settings = copySettings(DEFAULT_SETTINGS);
      const compressor = CompressorPreset(
        name: 'High flow',
        inletFlowLPerMin: 160,
        maxPressureBar: 250,
        temperatureModifierC: 4,
      );
      final booster = DEFAULT_SETTINGS.boosterPresets[0].copyWith(
        name: 'Rapid booster',
        cylinderVolumeCm3: 12,
        minimumSourcePressureBar: 25,
        oxygenBoostBpm: 75,
        otherBoostBpm: 80,
        maxOutputPressureBar: 240,
        temperatureModifierC: 3,
        oxygenDecantRateBarPerMin: 7,
        otherDecantRateBarPerMin: 8,
        drainingRateBarPerMin: 9,
      );

      final withCompressor = applyCompressorPresetToSettings(
        settings,
        compressor,
      );
      final withBooster = applyBoosterPresetToSettings(withCompressor, booster);

      expect(identical(withCompressor, settings), isFalse);
      expect(identical(withCompressor.booster, settings.booster), isFalse);
      expect(
        withBooster.booster,
        settings.booster.copyWith(
          compressorInletFlowLPerMin: 160,
          maxCompressorPressureBar: 250,
          compressorTemperatureModifierC: 4,
          cylinderVolumeCm3: 12,
          minimumSourcePressureBar: 25,
          oxygenBoostBpm: 75,
          otherBoostBpm: 80,
          maxBoosterOutputPressureBar: 240,
          boosterTemperatureModifierC: 3,
          oxygenDecantRateBarPerMin: 7,
          otherDecantRateBarPerMin: 8,
          drainingRateBarPerMin: 9,
        ),
      );
      expect(settings.booster, DEFAULT_SETTINGS.booster);
    },
  );

  test(
    'selecting named equipment presets changes only copied draft active fields',
    () {
      final draft = copySettings(DEFAULT_SETTINGS).copyWith(
        compressorPresets: <CompressorPreset>[
          ...DEFAULT_SETTINGS.compressorPresets,
          const CompressorPreset(
            name: 'High flow',
            inletFlowLPerMin: 160,
            maxPressureBar: 250,
            temperatureModifierC: 4,
          ),
        ],
        boosterPresets: <BoosterPreset>[
          ...DEFAULT_SETTINGS.boosterPresets,
          const BoosterPreset(
            name: 'Rapid booster',
            minimumSourcePressureBar: 25,
            cylinderVolumeCm3: 12,
            oxygenBoostBpm: 75,
            otherBoostBpm: 80,
            oxygenDecantRateBarPerMin: 7,
            otherDecantRateBarPerMin: 8,
            maxOutputPressureBar: 240,
            temperatureModifierC: 3,
            drainingRateBarPerMin: 9,
          ),
        ],
      );
      final withCompressor = selectEquipmentPreset(
        draft,
        EquipmentCategory.compressor,
        'High flow',
      )!;
      final withBooster = selectEquipmentPreset(
        withCompressor,
        EquipmentCategory.booster,
        'Rapid booster',
      )!;

      expect(
        withCompressor.booster,
        draft.booster.copyWith(
          compressorInletFlowLPerMin: 160,
          maxCompressorPressureBar: 250,
          compressorTemperatureModifierC: 4,
        ),
      );
      expect(
        withBooster.booster,
        withCompressor.booster.copyWith(
          minimumSourcePressureBar: 25,
          cylinderVolumeCm3: 12,
          oxygenBoostBpm: 75,
          otherBoostBpm: 80,
          oxygenDecantRateBarPerMin: 7,
          otherDecantRateBarPerMin: 8,
          maxBoosterOutputPressureBar: 240,
          boosterTemperatureModifierC: 3,
          drainingRateBarPerMin: 9,
        ),
      );
      expect(withBooster.gasPresets, draft.gasPresets);
      expect(withBooster.cylinderPresets, draft.cylinderPresets);
      expect(withBooster.compressorPresets, draft.compressorPresets);
      expect(withBooster.boosterPresets, draft.boosterPresets);
      expect(draft.booster, DEFAULT_SETTINGS.booster);
    },
  );

  test('normalizes preset names with locale-independent case folding', () {
    expect(normalizePresetName('  I  '), 'i');
    expect(normalizePresetName(' EAN32 '), 'ean32');
  });

  test('creates independent equipment preset clones from active settings', () {
    final settings = copySettings(DEFAULT_SETTINGS).copyWith(
      booster: DEFAULT_SETTINGS.booster.copyWith(
        compressorInletFlowLPerMin: 160,
        maxCompressorPressureBar: 250,
        compressorTemperatureModifierC: 4,
        minimumSourcePressureBar: 25,
        cylinderVolumeCm3: 12,
        oxygenBoostBpm: 75,
        otherBoostBpm: 80,
        oxygenDecantRateBarPerMin: 7,
        otherDecantRateBarPerMin: 8,
        maxBoosterOutputPressureBar: 240,
        boosterTemperatureModifierC: 3,
        drainingRateBarPerMin: 9,
      ),
    );

    final compressor = createCompressorPreset(settings, 'New compressor');
    final booster = createBoosterPreset(settings, 'New booster');

    expect(
      compressor,
      const CompressorPreset(
        name: 'New compressor',
        inletFlowLPerMin: 160,
        maxPressureBar: 250,
        temperatureModifierC: 4,
      ),
    );
    expect(
      booster,
      const BoosterPreset(
        name: 'New booster',
        minimumSourcePressureBar: 25,
        cylinderVolumeCm3: 12,
        oxygenBoostBpm: 75,
        otherBoostBpm: 80,
        oxygenDecantRateBarPerMin: 7,
        otherDecantRateBarPerMin: 8,
        maxOutputPressureBar: 240,
        temperatureModifierC: 3,
        drainingRateBarPerMin: 9,
      ),
    );

    // Clone fields are final, so the JS post-creation mutation of the clones
    // is unrepresentable; the source-independence check is kept.
    expect(settings.booster.compressorInletFlowLPerMin, 160);
    expect(settings.booster.cylinderVolumeCm3, 12);
  });

  test('creates unique equipment names and appends active-setting clones', () {
    final draft = copySettings(DEFAULT_SETTINGS).copyWith(
      compressorPresets: <CompressorPreset>[
        ...DEFAULT_SETTINGS.compressorPresets,
        const CompressorPreset(
          name: 'new compressor',
          inletFlowLPerMin: 150,
          maxPressureBar: 240,
          temperatureModifierC: 2,
        ),
      ],
      boosterPresets: <BoosterPreset>[
        ...DEFAULT_SETTINGS.boosterPresets,
        const BoosterPreset(
          name: 'New booster',
          minimumSourcePressureBar: 30,
          cylinderVolumeCm3: 10,
          oxygenBoostBpm: 60,
          otherBoostBpm: 60,
          oxygenDecantRateBarPerMin: 6,
          otherDecantRateBarPerMin: 6,
          maxOutputPressureBar: 220,
          temperatureModifierC: 1,
          drainingRateBarPerMin: 6,
        ),
      ],
    );
    final active = draft.booster;

    expect(
      createUniquePresetName(
        'New compressor',
        draft.compressorPresets.map((preset) => preset.name),
      ),
      'New compressor 2',
    );
    final compressorResult = addEquipmentPresetToDraft(
      draft,
      EquipmentCategory.compressor,
      'New compressor',
    );
    final boosterResult = addEquipmentPresetToDraft(
      draft,
      EquipmentCategory.booster,
      'New booster',
    );
    expect(compressorResult.name, 'New compressor 2');
    expect(boosterResult.name, 'New booster 2');
    expect(compressorResult.settings.booster, active);
    expect(
      compressorResult.settings.compressorPresets.last,
      CompressorPreset(
        name: 'New compressor 2',
        inletFlowLPerMin: active.compressorInletFlowLPerMin,
        maxPressureBar: active.maxCompressorPressureBar,
        temperatureModifierC: active.compressorTemperatureModifierC,
      ),
    );
    expect(
      boosterResult.settings.boosterPresets.last,
      BoosterPreset(
        name: 'New booster 2',
        minimumSourcePressureBar: active.minimumSourcePressureBar,
        cylinderVolumeCm3: active.cylinderVolumeCm3,
        oxygenBoostBpm: active.oxygenBoostBpm,
        otherBoostBpm: active.otherBoostBpm,
        oxygenDecantRateBarPerMin: active.oxygenDecantRateBarPerMin,
        otherDecantRateBarPerMin: active.otherDecantRateBarPerMin,
        maxOutputPressureBar: active.maxBoosterOutputPressureBar,
        temperatureModifierC: active.boosterTemperatureModifierC,
        drainingRateBarPerMin: active.drainingRateBarPerMin,
      ),
    );
  });

  test(
    'pressure limit mode defaults safely and validates the warning unlock',
    () {
      expect(DEFAULT_SETTINGS.pressureLimitMode, 'hard-stop');
      expect(DEFAULT_SETTINGS.pressureWarningUnlocked, isFalse);

      final lockedWarning = DEFAULT_SETTINGS.copyWith(
        pressureLimitMode: 'warning',
        pressureWarningUnlocked: false,
      );
      expect(
        validateSettings(lockedWarning).join(' '),
        matches(RegExp('unlock', caseSensitive: false)),
      );
      expect(
        validateSettings(DEFAULT_SETTINGS.copyWith(pressureLimitMode: 'ignore'))
            .join(' '),
        matches(RegExp(r'pressure.*mode', caseSensitive: false)),
      );
      // The JS string-typed `pressureWarningUnlocked: 'true'` case is
      // unrepresentable: the field is `bool`.
    },
  );

  test('invalid pressure ceilings are rejected before storage changes', () {
    expect(
      validateSettings(
        DEFAULT_SETTINGS.copyWith(
          booster: DEFAULT_SETTINGS.booster.copyWith(
            maxCompressorPressureBar: 9,
          ),
        ),
      ).join(' '),
      matches(RegExp(r'pressure.*10.*350', caseSensitive: false)),
    );
    expect(
      validateSettings(
        DEFAULT_SETTINGS.copyWith(
          booster: DEFAULT_SETTINGS.booster.copyWith(
            maxBoosterOutputPressureBar: 9,
          ),
        ),
      ).join(' '),
      matches(RegExp(r'pressure.*10.*350', caseSensitive: false)),
    );
  });

  test('unsupported gas models are rejected before storage changes', () {
    expect(
      validateSettings(
        DEFAULT_SETTINGS.copyWith(
          physics: const PhysicsSettings(model: 'peng-robinson'),
        ),
      ).join(' '),
      matches(RegExp(r'gas model.*ideal.*vdw', caseSensitive: false)),
    );
  });

  test('temperature modifiers are bounded', () {
    expect(
      validateSettings(
        DEFAULT_SETTINGS.copyWith(
          booster: DEFAULT_SETTINGS.booster.copyWith(
            boosterTemperatureModifierC: 101,
          ),
        ),
      ).join(' '),
      matches(RegExp(r'temperature modifier.*-100.*100', caseSensitive: false)),
    );
    expect(
      validateSettings(
        DEFAULT_SETTINGS.copyWith(
          booster: DEFAULT_SETTINGS.booster.copyWith(
            compressorTemperatureModifierC: 101,
          ),
        ),
      ).join(' '),
      matches(RegExp(r'temperature modifier.*-100.*100', caseSensitive: false)),
    );
  });

  test('invalid thermodynamic booster settings are rejected before storage changes', () {
    expect(
      validateSettings(
        DEFAULT_SETTINGS.copyWith(
          booster: DEFAULT_SETTINGS.booster.copyWith(
            cylinderVolumeCm3: 0,
            oxygenDecantRateBarPerMin: -1,
            drainingRateBarPerMin: 0,
          ),
        ),
      ).join(' '),
      matches(RegExp(r'cylinder.*cm|decant|draining', caseSensitive: false)),
    );
  });

  test(
    'invalid equipment preset collections are rejected before storage changes',
    () {
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
      // The JS `compressorPresets: {}` / `boosterPresets: {}` cases are
      // unrepresentable: the collections are typed `List`.
      for (final settings in invalidSettings) {
        expect(validateSettings(settings), isNotEmpty);
      }
    },
  );

  test('interim pressure tolerance defaults to three percent and migrates when missing', () {
    expect(DEFAULT_SETTINGS.interimPressureTolerancePercent, 3);
    expect(copySettings(DEFAULT_SETTINGS).interimPressureTolerancePercent, 3);
  });

  test('interim pressure tolerance round-trips through storage and validates its bounds', () {
    for (final value in <double>[0.4, 10.5, double.nan]) {
      expect(
        validateSettings(
          DEFAULT_SETTINGS.copyWith(interimPressureTolerancePercent: value),
        ).join(' '),
        matches(RegExp('interim pressure tolerance', caseSensitive: false)),
      );
    }
    for (final value in <double>[0.5, 10]) {
      expect(
        validateSettings(
          DEFAULT_SETTINGS.copyWith(interimPressureTolerancePercent: value),
        ),
        isEmpty,
      );
    }
  });

  test(
    'settings default costs to empty symbol, no discount and zero flat fees',
    () {
      expect(DEFAULT_SETTINGS.costs.currencySymbol, '');
      expect(DEFAULT_SETTINGS.costs.leftoverDiscountPercent, 0);
      expect(DEFAULT_SETTINGS.costs.operationPrices.boost, 0);
      expect(DEFAULT_SETTINGS.costs.operationPrices.decant, 0);
      expect(DEFAULT_SETTINGS.costs.operationPrices.topUp, 0);
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
        gasPresets: const <GasPreset>[
          GasPreset(name: 'Air', oxygenPercent: 21, heliumPercent: 0),
        ],
        cylinderPresets: <CylinderPreset>[
          DEFAULT_SETTINGS.cylinderPresets[0].copyWith(material: 'carbon'),
        ],
      ),
      DEFAULT_SETTINGS.copyWith(
        gasPresets: const <GasPreset>[
          GasPreset(name: 'Air', oxygenPercent: 21, heliumPercent: 0),
        ],
        cylinderPresets: <CylinderPreset>[
          DEFAULT_SETTINGS.cylinderPresets[0].copyWith(massKg: 0),
        ],
      ),
      DEFAULT_SETTINGS.copyWith(
        gasPresets: const <GasPreset>[
          GasPreset(name: 'Air', oxygenPercent: 21, heliumPercent: 0),
        ],
        cylinderPresets: <CylinderPreset>[
          DEFAULT_SETTINGS.cylinderPresets[0].copyWith(workingPressureBar: 351),
        ],
      ),
    ];
    // Each invalid shape is rejected by validateSettings.
    for (final settings in invalidSettings) {
      expect(validateSettings(settings), isNotEmpty);
    }
  });

  test('applying a gas preset changes only the bank gas and name', () {
    const bank = Bank(
      id: 'source-1',
      name: 'Existing name',
      volumeL: 40,
      pressureBar: 220,
      oxygenPercent: 21,
      heliumPercent: 0,
      enabled: false,
    );
    final result = applyGasPresetToBank(
      bank,
      const GasPreset(name: 'EAN32', oxygenPercent: 32, heliumPercent: 0),
    );
    // Bank has no `minimumPressureBar` field, so that JS assertion is absent.
    expect(result.id, 'source-1');
    expect(result.name, 'EAN32');
    expect(result.volumeL, 40);
    expect(result.pressureBar, 220);
    expect(result.oxygenPercent, 32);
    expect(result.heliumPercent, 0);
    expect(result.enabled, isFalse);
  });

  test('a changed preset is not shown as applied to an unchanged bank', () {
    const bank = Bank(
      id: 'b',
      name: 'EAN32',
      volumeL: 12,
      pressureBar: 200,
      oxygenPercent: 32,
      heliumPercent: 0,
      enabled: true,
      gasPresetLink: NamedPresetLink('EAN32'),
    );
    const preset = GasPreset(
      name: 'EAN32',
      oxygenPercent: 32,
      heliumPercent: 0,
    );
    expect(getSelectedGasPreset(bank, const [preset]), preset);
    expect(
      getSelectedGasPreset(bank, const [
        GasPreset(name: 'EAN32', oxygenPercent: 31, heliumPercent: 0),
      ]),
      isNull,
    );
  });

  test('a named link needs the preset name as well as the composition', () {
    const bank = Bank(
      id: 'b',
      name: 'Mix',
      volumeL: 12,
      pressureBar: 200,
      oxygenPercent: 32,
      heliumPercent: 0,
      enabled: true,
      gasPresetLink: NamedPresetLink('Other'),
    );
    expect(
      getSelectedGasPreset(bank, const [
        GasPreset(name: 'EAN32', oxygenPercent: 32, heliumPercent: 0),
      ]),
      isNull,
    );
  });

  test('a custom mix link selects no preset even when one matches', () {
    const bank = Bank(
      id: 'b',
      name: 'Mix',
      volumeL: 12,
      pressureBar: 200,
      oxygenPercent: 32,
      heliumPercent: 0,
      enabled: true,
      gasPresetLink: CustomMixLink(),
    );
    expect(
      getSelectedGasPreset(bank, const [
        GasPreset(name: 'EAN32', oxygenPercent: 32, heliumPercent: 0),
      ]),
      isNull,
    );
  });

  test(
    'an unnamed link selects the first preset whose composition matches',
    () {
      const bank = Bank(
        id: 'b',
        name: 'Mix',
        volumeL: 12,
        pressureBar: 200,
        oxygenPercent: 32,
        heliumPercent: 0,
        enabled: true,
      );
      const first = GasPreset(
        name: 'First',
        oxygenPercent: 32,
        heliumPercent: 0,
      );
      expect(
        getSelectedGasPreset(bank, const [
          GasPreset(name: 'Other', oxygenPercent: 30, heliumPercent: 0),
          first,
          GasPreset(name: 'Second', oxygenPercent: 32, heliumPercent: 0),
        ]),
        first,
      );
    },
  );

  test(
    'a preset named Custom is distinguishable from the custom-mix choice',
    () {
      const preset = GasPreset(
        name: 'Custom',
        oxygenPercent: 25,
        heliumPercent: 10,
      );
      const bank = Bank(
        id: 'c',
        name: 'Custom',
        volumeL: 12,
        pressureBar: 200,
        oxygenPercent: 25,
        heliumPercent: 10,
        enabled: true,
        gasPresetLink: NamedPresetLink('Custom'),
      );
      expect(getSelectedGasPreset(bank, const [preset]), preset);
    },
  );

  test(
    'gas presets are ordered by increasing helium while retaining tie order',
    () {
      final presets = <GasPreset>[
        const GasPreset(name: 'Pure He', oxygenPercent: 0, heliumPercent: 100),
        const GasPreset(name: 'Air', oxygenPercent: 21, heliumPercent: 0),
        const GasPreset(name: 'Tx 18/30', oxygenPercent: 18, heliumPercent: 30),
        const GasPreset(name: 'Tx 21/30', oxygenPercent: 21, heliumPercent: 30),
      ];
      final ordered = sortGasPresetEntries(presets);
      expect(
        ordered.map((entry) => [entry.preset.name, entry.index]).toList(),
        [
          ['Air', 1],
          ['Tx 18/30', 2],
          ['Tx 21/30', 3],
          ['Pure He', 0],
        ],
      );
      expect(presets.map((preset) => preset.name).toList(), [
        'Pure He',
        'Air',
        'Tx 18/30',
        'Tx 21/30',
      ]);
    },
  );

  test('cylinder presets are ordered numerically without losing duplicate edit indices', () {
    // JS cylinder fixtures carry only name and volumeL; the sort reads only
    // those fields, so the remaining fields are filled with neutral values.
    final presets = <CylinderPreset>[
      _cylinder('24 L', 24),
      _cylinder('7 L A', 7),
      _cylinder('12 L', 12),
      _cylinder('7 L B', 7),
    ];
    final ordered = sortCylinderPresetEntries(presets);
    expect(ordered.map((entry) => [entry.preset.name, entry.index]).toList(), [
      ['7 L A', 1],
      ['7 L B', 3],
      ['12 L', 2],
      ['24 L', 0],
    ]);
    expect(presets.map((preset) => preset.name).toList(), [
      '24 L',
      '7 L A',
      '12 L',
      '7 L B',
    ]);
  });

  test(
    'settings draft copies own independent equipment preset collections',
    () {
      // `source` stands in for the JS `loadSettings(memoryStorage())`. The load
      // round trip is covered in test/data/settings_storage_test.dart.
      const source = DEFAULT_SETTINGS;

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
      expect(source.compressorPresets[0].name, 'Bauer Junior 2 200bar');
      expect(source.boosterPresets[0].maxOutputPressureBar, 230);
    },
  );

  test('cylinder hot overfill accepts only zero to five percent in half-percent steps', () {
    Settings withHotOverfill(double value) {
      return DEFAULT_SETTINGS.copyWith(
        cylinderPresets: <CylinderPreset>[
          DEFAULT_SETTINGS.cylinderPresets[0].copyWith(
            hotOverfillPercent: value,
          ),
          ...DEFAULT_SETTINGS.cylinderPresets.skip(1),
        ],
      );
    }

    for (final value in <double>[0, 0.5, 2, 5]) {
      expect(validateSettings(withHotOverfill(value)), isEmpty);
    }
    for (final value in <double>[-0.5, 2.25, 5.5]) {
      expect(
        validateSettings(withHotOverfill(value)).join(' '),
        matches(RegExp('hot overfill', caseSensitive: false)),
      );
    }
  });

  test('matches the Warning unlock phrase case-insensitively and accepts quote variants', () {
    for (final value in <String>[
      "i know what i'm doing",
      'I kNoW wHaT I`M dOiNg',
      'i know what i"m doing',
    ]) {
      expect(matchesPressureWarningUnlockPhrase(value), isTrue, reason: value);
    }
    for (final value in <String>[
      'I KNOW WHAT I AM DOING',
      'I  KNOW WHAT I\'M DOING',
      'I KNOW WHAT I\u2019M DOING',
      'I KNOW WHAT \u0131\'M DOING',
    ]) {
      expect(matchesPressureWarningUnlockPhrase(value), isFalse, reason: value);
    }
    expect(matchesPressureWarningUnlockPhrase(null), isFalse);
  });

  test('invalid flat fees in saved settings are rejected by validation', () {
    for (final operationPrices in <OperationPrices>[
      const OperationPrices(boost: -1, decant: 0, topUp: 0),
      const OperationPrices(boost: 0, decant: 1000001, topUp: 0),
    ]) {
      final settings = DEFAULT_SETTINGS.copyWith(
        costs: Costs(
          currencySymbol: '€',
          leftoverDiscountPercent: 5,
          operationPrices: operationPrices,
        ),
      );
      expect(validateSettings(settings), isNotEmpty);
    }
  });

  test('saving settings with invalid costs is rejected by validation', () {
    final settings = DEFAULT_SETTINGS.copyWith(
      costs: const Costs(
        currencySymbol: '',
        leftoverDiscountPercent: -1,
        operationPrices: OperationPrices(boost: 0, decant: 0, topUp: 0),
      ),
    );
    expect(validateSettings(settings), isNotEmpty);
  });
}

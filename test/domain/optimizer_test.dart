import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/data/bank_storage.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/optimizer.dart';
import 'package:simplex_blender/src/domain/physics.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

import 'optimizer_fixtures.dart';

import '../support/tank_area.dart';

void main() {
  test(
    'default example keeps the cylinder gas when the safety ceiling is active',
    () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': <String, Object?>{
          'volumeL': 12.0,
          'initialPressureBar': 80.0,
          'initialOxygenPercent': 21.0,
          'initialHeliumPercent': 35.0,
          'targetPressureBar': 210.0,
          'targetOxygenPercent': 18.0,
          'targetHeliumPercent': 45.0,
        },
        'physics': <String, Object?>{
          'model': DEFAULT_SETTINGS.physics.model,
          'temperatureC': 20.0,
        },
        'banks': <Object?>[for (final bank in DEFAULT_BANKS) _bankMap(bank)],
        'settings': _settingsMap(DEFAULT_SETTINGS),
      });

      final blend = _m(result['blend']);
      expect(result['feasible'], isTrue);
      expect(
        _solution(result['solution'])['x_cyl']!,
        greaterThan(_d(_m(result['gas'])['initialMoles']) * 0.99),
      );
      expect(_d(blend['retainedPressureBar']), closeTo(80.0, 0.1));
      expect(_d(blend['ventedPressureBar']), closeTo(0.0, 0.1));
      expect(_d(blend['heliumSalvagedLitres']), greaterThan(300.0));
      expect(_steps(result['protocolSteps']).first.type, 'keep');
    },
  );

  test('maximum-pressure fallback keeps cylinder gas retained by the same-pressure exact recipe', () {
    final input = <String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 10.0,
        'initialPressureBar': 50.0,
        'initialOxygenPercent': 32.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 200.0,
        'targetOxygenPercent': 21.0,
        'targetHeliumPercent': 35.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
      'banks': <Object?>[
        <String, Object?>{
          'id': 'he',
          'name': 'He small',
          'volumeL': 10.0,
          'pressureBar': 60.0,
          'maxPressureBar': 200.0,
          'oxygenPercent': 0.0,
          'heliumPercent': 100.0,
          'enabled': true,
        },
        <String, Object?>{
          'id': 'o2',
          'name': 'O2',
          'volumeL': 50.0,
          'pressureBar': 200.0,
          'maxPressureBar': 200.0,
          'oxygenPercent': 100.0,
          'heliumPercent': 0.0,
          'enabled': true,
        },
      ],
      'settings': _settingsMap(DEFAULT_SETTINGS),
    };
    final fallback = optimizeBlend(input);
    expect(fallback['feasible'], isFalse);
    final maximumPressureBar = _d(
      _m(_m(fallback['maximumPressure'])['blend'])['finalPressureBar'],
    );
    final exact = optimizeBlend(<String, Object?>{
      ...input,
      'cylinder': <String, Object?>{
        ..._m(input['cylinder']),
        'targetPressureBar': (maximumPressureBar * 10).floorToDouble() / 10,
      },
    });

    expect(exact['feasible'], isTrue);
    final exactBlend = _m(exact['blend']);
    final fallbackRetained = _d(
      _m(_m(fallback['maximumPressure'])['blend'])['retainedPercent'],
    );
    expect(_d(exactBlend['retainedPercent']), greaterThan(99.0));
    expect(
      fallbackRetained,
      greaterThanOrEqualTo(_d(exactBlend['retainedPercent']) - 1),
      reason:
          'fallback retained $fallbackRetained% but exact retained ${exactBlend['retainedPercent']}%',
    );
  });

  test('safety fallback preserves working gas and uses available premixes before pure helium', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 12.0,
        'initialPressureBar': 80.0,
        'initialOxygenPercent': 21.0,
        'initialHeliumPercent': 35.0,
        'targetPressureBar': 210.0,
        'targetOxygenPercent': 18.0,
        'targetHeliumPercent': 45.0,
      },
      'physics': <String, Object?>{'model': 'vdw', 'temperatureC': 20.0},
      'banks': <Object?>[
        <String, Object?>{
          'id': 'he',
          'name': 'Pure Helium',
          'volumeL': 50.0,
          'pressureBar': 200.0,
          'maxPressureBar': 350.0,
          'minimumPressureBar': 15.0,
          'oxygenPercent': 0.0,
          'heliumPercent': 100.0,
          'enabled': true,
        },
        <String, Object?>{
          'id': 'o2',
          'name': 'Pure Oxygen',
          'volumeL': 40.0,
          'pressureBar': 180.0,
          'maxPressureBar': 350.0,
          'minimumPressureBar': 10.0,
          'oxygenPercent': 100.0,
          'heliumPercent': 0.0,
          'enabled': true,
        },
        <String, Object?>{
          'id': '1845',
          'name': '18/45',
          'volumeL': 18.0,
          'pressureBar': 200.0,
          'maxPressureBar': 350.0,
          'minimumPressureBar': 20.0,
          'oxygenPercent': 18.0,
          'heliumPercent': 45.0,
          'enabled': true,
        },
        <String, Object?>{
          'id': '770',
          'name': '7/70',
          'volumeL': 50.0,
          'pressureBar': 200.0,
          'maxPressureBar': 350.0,
          'minimumPressureBar': 20.0,
          'oxygenPercent': 7.0,
          'heliumPercent': 70.0,
          'enabled': true,
        },
      ],
      'settings': <String, Object?>{
        'booster': <String, Object?>{
          'maxCompressorPressureBar': 232.0,
          'maxBoosterOutputPressureBar': 200.0,
        },
      },
    });

    expect(result['feasible'], isTrue);
    final solution = _solution(result['solution']);
    expect(solution['x_cyl']!, greaterThan(0.0));
    expect(solution['x_b3_18/45']! > 0 || solution['x_b4_7/70']! > 0, isTrue);
    expect(solution['x_b1_Pure'], 0.0);
  });

  test('uses implicit unlimited Air without an Air bank', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 12.0,
        'initialPressureBar': 0.0,
        'initialOxygenPercent': 0.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 180.0,
        'targetOxygenPercent': 21.0,
        'targetHeliumPercent': 0.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
      'banks': <Object?>[],
      'settings': <String, Object?>{
        'booster': <String, Object?>{
          'maxCompressorPressureBar': 232.0,
          'maxBoosterOutputPressureBar': 200.0,
        },
      },
    });

    expect(result['feasible'], isTrue);
    final last = _steps(result['protocolSteps']).last;
    expect(last.operation, 'Top-up');
    expect(last.minimumSourcePressureBar, isNull);
    expect(last.sourceExhausted, isFalse);
  });

  test(
    'rejects finite Air banks in favor of the implicit compressor source',
    () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': <String, Object?>{
          'volumeL': 12.0,
          'initialPressureBar': 0.0,
          'initialOxygenPercent': 0.0,
          'initialHeliumPercent': 0.0,
          'targetPressureBar': 180.0,
          'targetOxygenPercent': 21.0,
          'targetHeliumPercent': 0.0,
        },
        'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
        'banks': <Object?>[
          <String, Object?>{
            'id': 'air-bank',
            'name': 'Air bank',
            'volumeL': 10.0,
            'pressureBar': 200.0,
            'maxPressureBar': 350.0,
            'oxygenPercent': 21.0,
            'heliumPercent': 0.0,
            'enabled': true,
          },
        ],
      });

      expect(result['feasible'], isFalse);
      expect(
        result['error'],
        matches(
          RegExp(r'Air.*compressor|compressor.*Air', caseSensitive: false),
        ),
      );
    },
  );

  test('compressor Air cannot top up above its configured ceiling', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 12.0,
        'initialPressureBar': 0.0,
        'initialOxygenPercent': 0.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 250.0,
        'targetOxygenPercent': 21.0,
        'targetHeliumPercent': 0.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
      'banks': <Object?>[],
      'settings': <String, Object?>{
        'booster': <String, Object?>{
          'maxCompressorPressureBar': 232.0,
          'maxBoosterOutputPressureBar': 200.0,
        },
      },
    });

    expect(result['feasible'], isFalse);
    expect(
      _d(_m(result['maximumPressure'])['pressureBar']),
      lessThanOrEqualTo(232.0 + 1e-9),
    );
  });

  test('non-Air boost cannot end above the booster output ceiling', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 12.0,
        'initialPressureBar': 0.0,
        'initialOxygenPercent': 0.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 250.0,
        'targetOxygenPercent': 0.0,
        'targetHeliumPercent': 100.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
      'banks': <Object?>[
        <String, Object?>{
          'id': 'he',
          'name': 'Helium',
          'volumeL': 50.0,
          'pressureBar': 150.0,
          'maxPressureBar': 350.0,
          'oxygenPercent': 0.0,
          'heliumPercent': 100.0,
          'enabled': true,
        },
      ],
      'settings': <String, Object?>{
        'booster': <String, Object?>{
          'maxCompressorPressureBar': 232.0,
          'maxBoosterOutputPressureBar': 200.0,
        },
      },
    });

    expect(result['feasible'], isFalse);
    expect(
      _d(_m(result['maximumPressure'])['pressureBar']),
      lessThanOrEqualTo(200.0 + 1e-9),
    );
  });

  test('non-Air decant can exceed the booster output ceiling', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 12.0,
        'initialPressureBar': 0.0,
        'initialOxygenPercent': 0.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 250.0,
        'targetOxygenPercent': 0.0,
        'targetHeliumPercent': 100.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
      'banks': <Object?>[
        <String, Object?>{
          'id': 'he',
          'name': 'Helium',
          'volumeL': 100.0,
          'pressureBar': 300.0,
          'maxPressureBar': 350.0,
          'oxygenPercent': 0.0,
          'heliumPercent': 100.0,
          'enabled': true,
        },
      ],
      'settings': <String, Object?>{
        'booster': <String, Object?>{
          'maxCompressorPressureBar': 232.0,
          'maxBoosterOutputPressureBar': 200.0,
        },
      },
    });

    expect(result['feasible'], isTrue);
    expect(
      _steps(result['protocolSteps']).any(
        (step) =>
            step.operation == 'Decant' &&
            (step.resultingPressureBar ?? 0) > 200,
      ),
      isTrue,
    );
  });

  test('uses one booster minimum source pressure for every supply bank', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 10.0,
        'initialPressureBar': 0.0,
        'initialOxygenPercent': 0.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 100.0,
        'targetOxygenPercent': 0.0,
        'targetHeliumPercent': 100.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
      'settings': <String, Object?>{
        'booster': <String, Object?>{'minimumSourcePressureBar': 50.0},
      },
      'banks': <Object?>[
        <String, Object?>{
          'id': 'helium',
          'name': 'Helium',
          'volumeL': 10.0,
          'pressureBar': 100.0,
          'maxPressureBar': 350.0,
          'oxygenPercent': 0.0,
          'heliumPercent': 100.0,
          'enabled': true,
        },
      ],
    });

    expect(result['feasible'], isFalse);
    expect(
      _d(_m(result['maximumPressure'])['pressureBar']),
      closeTo(50.0, 1e-9),
    );
  });

  test('formats equalising and top-up protocol stages with source leftovers and interim mix', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 10.0,
        'initialPressureBar': 100.0,
        'initialOxygenPercent': 21.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 140.0,
        'targetOxygenPercent': 20.8,
        'targetHeliumPercent': 0.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
      'settings': <String, Object?>{
        'booster': <String, Object?>{'minimumSourcePressureBar': 0.0},
      },
      'banks': <Object?>[
        <String, Object?>{
          'id': 'mix',
          'name': 'Nitrox source',
          'volumeL': 10.0,
          'pressureBar': 120.0,
          'maxPressureBar': 350.0,
          'minimumPressureBar': 0.0,
          'oxygenPercent': 20.0,
          'heliumPercent': 0.0,
          'enabled': true,
        },
      ],
    });

    expect(result['feasible'], isTrue);
    final steps = _steps(result['protocolSteps']);
    final step = steps.firstWhere(
      (item) => item.title?.startsWith('Step 1:') ?? false,
    );
    expect(
      step.title,
      matches(RegExp(r'^Step 1: Equalize Nitrox source to \d+\.\d bar$')),
    );
    expect(
      step.description,
      matches(
        RegExp(
          r'^Equalize \d+\.\d bar from Nitrox source to \d+\.\d bar\. This will leave \d+\.\d bar of Nitrox source\. Interim mix is \d+\.\d/\d+\.\d\.',
        ),
      ),
    );
    final topUp = steps.last;
    expect(
      topUp.title,
      matches(RegExp(r'^Step \d+: Top-up Compressor Air to \d+\.\d bar$')),
    );
  });

  test('counts helium from non-pure supply gas as salvaged helium', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 10.0,
        'initialPressureBar': 0.0,
        'initialOxygenPercent': 0.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 100.0,
        'targetOxygenPercent': 0.0,
        'targetHeliumPercent': 50.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
      'settings': <String, Object?>{
        'booster': <String, Object?>{'minimumSourcePressureBar': 0.0},
      },
      'banks': <Object?>[
        <String, Object?>{
          'id': 'helium-mix',
          'name': 'Helium mix',
          'volumeL': 10.0,
          'pressureBar': 200.0,
          'maxPressureBar': 350.0,
          'oxygenPercent': 0.0,
          'heliumPercent': 50.0,
          'enabled': true,
        },
      ],
    });

    expect(result['feasible'], isTrue);
    expect(
      _d(_m(result['blend'])['heliumSalvagedLitres']),
      closeTo(500.0, 1e-9),
    );
  });

  test(
    'reports vented helium as the helium share of the drained original mix',
    () {
      final base = <String, Object?>{
        'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
        'settings': <String, Object?>{
          'booster': <String, Object?>{'minimumSourcePressureBar': 0.0},
        },
        'banks': <Object?>[],
      };
      final drained = optimizeBlend(<String, Object?>{
        ...base,
        'cylinder': <String, Object?>{
          'volumeL': 10.0,
          'initialPressureBar': 100.0,
          'initialOxygenPercent': 21.0,
          'initialHeliumPercent': 30.0,
          'targetPressureBar': 60.0,
          'targetOxygenPercent': 21.0,
          'targetHeliumPercent': 30.0,
        },
      });
      expect(drained['feasible'], isTrue);
      final drainedBlend = _m(drained['blend']);
      expect(_d(drainedBlend['ventedGasLitres']), closeTo(400.0, 1e-6));
      expect(_d(drainedBlend['heliumVentedLitres']), closeTo(120.0, 1e-6));

      final kept = optimizeBlend(<String, Object?>{
        ...base,
        'cylinder': <String, Object?>{
          'volumeL': 10.0,
          'initialPressureBar': 100.0,
          'initialOxygenPercent': 21.0,
          'initialHeliumPercent': 30.0,
          'targetPressureBar': 100.0,
          'targetOxygenPercent': 21.0,
          'targetHeliumPercent': 30.0,
        },
      });
      expect(kept['feasible'], isTrue);
      expect(_d(_m(kept['blend'])['heliumVentedLitres']), lessThan(1e-6));
    },
  );

  test('splits a transfer into decant and boost stages when source pressure crosses receiver pressure', () {
    final result = optimizeBlend(
      _equalGasTransferInput(
        initialPressureBar: 100.0,
        targetPressureBar: 140.0,
        bankPressureBar: 120.0,
      ),
    );

    expect(result['feasible'], isTrue);
    final transferSteps = _steps(result['protocolSteps']).skip(1).toList();
    expect(transferSteps.map((step) => step.type).toList(), [
      'decant',
      'boost',
    ]);
    expect(transferSteps.map((step) => step.title).toList(), [
      'Step 1: Equalize Nitrogen source to 110.0 bar',
      'Step 2: Boost Nitrogen source to 140.0 bar',
    ]);
    expect(transferSteps[0].resultingPressureBar!, closeTo(110.0, 1e-9));
    expect(transferSteps[1].resultingPressureBar!, closeTo(140.0, 1e-9));
    expect(transferSteps[0].sourceStartPressureBar!, closeTo(120.0, 1e-9));
    expect(transferSteps[0].sourceEndPressureBar!, closeTo(110.0, 1e-9));
    expect(transferSteps[1].sourceStartPressureBar!, closeTo(110.0, 1e-9));
    expect(transferSteps[1].sourceEndPressureBar!, closeTo(80.0, 1e-9));
    expect(
      transferSteps.map((step) => step.description).join(' '),
      isNot(matches(RegExp(r'Decompressively|mol|\(21/0\)'))),
    );
  });

  test(
    'bank transfer stages record the source inventory left at each stage start',
    () {
      final result = optimizeBlend(
        _equalGasTransferInput(
          initialPressureBar: 100.0,
          targetPressureBar: 140.0,
          bankPressureBar: 120.0,
        ),
      );

      expect(result['feasible'], isTrue);
      final transferSteps = _steps(result['protocolSteps'])
          .where((step) => step.type == 'decant' || step.type == 'boost')
          .toList();
      expect(transferSteps, isNotEmpty);
      final bankInventoryMoles =
          calcMolarDensity(120.0, 0.0, 0.0, 20.0, false) * 10.0;
      expect(transferSteps.first.sourceVolumeL, closeTo(10.0, 1e-9));
      expect(
        transferSteps.first.sourceStartMoles,
        closeTo(bankInventoryMoles, 1e-9),
      );
      for (var index = 1; index < transferSteps.length; index += 1) {
        final previous = transferSteps[index - 1];
        final step = transferSteps[index];
        expect(step.sourceVolumeL, closeTo(10.0, 1e-9));
        expect(
          step.sourceStartMoles,
          closeTo(
            previous.sourceStartMoles! - previous.sourceConsumedMoles!,
            1e-9,
          ),
        );
      }
    },
  );

  test('uses one compressor top-up stage without a finite Air bank in thermal mode', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 10.0,
        'initialPressureBar': 100.0,
        'initialOxygenPercent': 21.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 140.0,
        'targetOxygenPercent': 21.0,
        'targetHeliumPercent': 0.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
      'thermal': <String, Object?>{
        'tankMaterial': 'steel',
        'tankSurfaceAreaM2': steelTestAreaM2,
        'coolingMedium': 'air',
        'ambientTemperatureC': 20.0,
        'waitMode': 'minutes',
        'waitMinutes': 10.0,
        'targetTemperatureC': 25.0,
      },
      'settings': <String, Object?>{
        'booster': <String, Object?>{
          'minimumSourcePressureBar': 0.0,
          'cylinderVolumeCm3': 9.0,
          'oxygenBoostBpm': 50.0,
          'otherBoostBpm': 50.0,
          'oxygenDecantRateBarPerMin': 5.0,
          'otherDecantRateBarPerMin': 5.0,
          'compressorInletFlowLPerMin': 100.0,
        },
      },
      'banks': <Object?>[],
    });

    expect(result['feasible'], isTrue);
    final topUps = _steps(result['protocolSteps'])
        .where((step) => step.operation == 'Top-up')
        .toList();
    expect(topUps.length, 1);
    expect(topUps[0].type, 'boost');
    expect(topUps[0].thermal!.rateSource, 'compressor');
    expect(topUps[0].sourceStartMoles, isNull);
  });

  test('uses boost when source pressure is lower than receiver pressure for the whole transfer', () {
    final result = optimizeBlend(
      _equalGasTransferInput(
        initialPressureBar: 100.0,
        targetPressureBar: 130.0,
        bankPressureBar: 80.0,
      ),
    );

    expect(result['feasible'], isTrue);
    final transferSteps = _steps(result['protocolSteps']).skip(1).toList();
    expect(transferSteps.length, 1);
    expect(transferSteps[0].type, 'boost');
    expect(transferSteps[0].operation, 'Boost');
  });

  test('uses decant when source pressure is not lower than receiver pressure for the whole transfer', () {
    final result = optimizeBlend(
      _equalGasTransferInput(
        initialPressureBar: 100.0,
        targetPressureBar: 110.0,
        bankPressureBar: 140.0,
      ),
    );

    expect(result['feasible'], isTrue);
    final transferSteps = _steps(result['protocolSteps']).skip(1).toList();
    expect(transferSteps.length, 1);
    expect(transferSteps[0].type, 'decant');
    expect(transferSteps[0].operation, 'Decant');
  });

  test('cascades interchangeable banks in ascending pressure order', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 50.0,
        'initialPressureBar': 0.0,
        'initialOxygenPercent': 0.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 180.0,
        'targetOxygenPercent': 100.0,
        'targetHeliumPercent': 0.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
      'banks': <Object?>[
        <String, Object?>{
          'id': 'o2-170',
          'name': 'Oxygen 170 bar',
          'volumeL': 50.0,
          'pressureBar': 170.0,
          'maxPressureBar': 200.0,
          'minimumPressureBar': 0.0,
          'oxygenPercent': 100.0,
          'heliumPercent': 0.0,
          'enabled': true,
        },
        <String, Object?>{
          'id': 'o2-100',
          'name': 'Oxygen 100 bar',
          'volumeL': 50.0,
          'pressureBar': 100.0,
          'maxPressureBar': 200.0,
          'minimumPressureBar': 0.0,
          'oxygenPercent': 100.0,
          'heliumPercent': 0.0,
          'enabled': true,
        },
        <String, Object?>{
          'id': 'o2-120',
          'name': 'Oxygen 120 bar',
          'volumeL': 50.0,
          'pressureBar': 120.0,
          'maxPressureBar': 200.0,
          'minimumPressureBar': 0.0,
          'oxygenPercent': 100.0,
          'heliumPercent': 0.0,
          'enabled': true,
        },
      ],
      'settings': <String, Object?>{
        'booster': <String, Object?>{
          'maxCompressorPressureBar': 350.0,
          'maxBoosterOutputPressureBar': 350.0,
        },
      },
    });

    expect(result['feasible'], isTrue);
    final transfers = _steps(result['protocolSteps'])
        .where((step) => step.sourceBankId != null)
        .toList();
    expect(transfers.map((step) => step.recipeGas).toSet().toList(), [
      'Oxygen 100 bar',
      'Oxygen 120 bar',
      'Oxygen 170 bar',
    ]);
    final cascadeTransfers = transfers
        .where((step) => step.operation?.startsWith('Cascade ') ?? false)
        .toList();
    expect(
      cascadeTransfers.any((step) => step.operation == 'Cascade equalize'),
      isTrue,
    );
    expect(
      cascadeTransfers.any((step) => step.operation == 'Cascade boost'),
      isTrue,
    );
    for (final step in cascadeTransfers) {
      expect(step.costOperation, step.type == 'decant' ? 'decant' : 'boost');
      expect(step.costOperationId, matches(RegExp(r'^op-\d+$')));
      expect(step.sourceConsumedMoles!.isFinite, isTrue);
      expect(step.sourceConsumedMoles!, greaterThan(0.0));
    }
    expect(
      cascadeTransfers.map((step) => step.costOperationId).toSet().length,
      cascadeTransfers.length,
    );
  });

  test(
    'orders mixed cascade and non-cascade boost sources deterministically',
    () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': <String, Object?>{
          'volumeL': 10.0,
          'initialPressureBar': 0.0,
          'initialOxygenPercent': 0.0,
          'initialHeliumPercent': 0.0,
          'targetPressureBar': 140.0,
          'targetOxygenPercent': 20.0,
          'targetHeliumPercent': 25.0,
        },
        'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
        'banks': <Object?>[
          <String, Object?>{
            'id': 'cascade-low',
            'name': 'CascadeLow',
            'volumeL': 1.0,
            'pressureBar': 100.0,
            'maxPressureBar': 200.0,
            'minimumPressureBar': 0.0,
            'oxygenPercent': 20.0,
            'heliumPercent': 20.0,
            'enabled': true,
          },
          <String, Object?>{
            'id': 'cascade-high',
            'name': 'CascadeHigh',
            'volumeL': 50.0,
            'pressureBar': 170.0,
            'maxPressureBar': 200.0,
            'minimumPressureBar': 0.0,
            'oxygenPercent': 20.0,
            'heliumPercent': 20.0,
            'enabled': true,
          },
          <String, Object?>{
            'id': 'single-helium-rich',
            'name': 'SingleHeliumRich',
            'volumeL': 50.0,
            'pressureBar': 30.0,
            'maxPressureBar': 200.0,
            'minimumPressureBar': 0.0,
            'oxygenPercent': 20.0,
            'heliumPercent': 30.0,
            'enabled': true,
          },
        ],
        'settings': <String, Object?>{
          'booster': <String, Object?>{
            'maxCompressorPressureBar': 350.0,
            'maxBoosterOutputPressureBar': 350.0,
          },
        },
      });

      expect(result['feasible'], isTrue);
      expect(
        _steps(result['protocolSteps'])
            .where((step) => step.sourceBankId != null)
            .map((step) => step.recipeGas)
            .toList(),
        ['CascadeLow', 'CascadeLow', 'CascadeHigh', 'SingleHeliumRich'],
      );
    },
  );

  test('uses decant when source and receiver start at equal pressure', () {
    final result = optimizeBlend(
      _equalGasTransferInput(
        initialPressureBar: 100.0,
        targetPressureBar: 120.0,
        bankPressureBar: 100.0,
      ),
    );

    expect(result['feasible'], isTrue);
    final transferSteps = _steps(result['protocolSteps']).skip(1).toList();
    expect(transferSteps.length, 1);
    expect(transferSteps[0].type, 'decant');
    expect(transferSteps[0].operation, 'Decant');
  });

  test(
    'rejects a target-mix mismatch below the old absolute phase-I tolerance',
    () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': <String, Object?>{
          'volumeL': 0.1,
          'initialPressureBar': 10.0,
          'initialOxygenPercent': 21.0,
          'initialHeliumPercent': 0.0,
          'targetPressureBar': 10.0,
          'targetOxygenPercent': 23.0,
          'targetHeliumPercent': 0.0,
        },
        'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
        'banks': <Object?>[],
      });

      expect(result['feasible'], isFalse);
      expect(result['blend'], isNull);
      expect(result['maximumPressure'], isNull);
    },
  );

  test('protocol drains any gas required to reach a lower target pressure', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 12.0,
        'initialPressureBar': 10.4,
        'initialOxygenPercent': 21.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 10.0,
        'targetOxygenPercent': 21.0,
        'targetHeliumPercent': 0.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
      'banks': <Object?>[],
    });

    expect(result['feasible'], isTrue);
    final steps = _steps(result['protocolSteps']);
    expect(steps.first.type, 'drain');
    final blend = _m(result['blend']);
    expect(_d(blend['ventedPressureBar']), closeTo(0.4, 1e-9));
    expect(
      steps.last.resultingPressureBar!,
      closeTo(_d(blend['finalPressureBar']), 1e-9),
    );
    expect(
      steps.first.description,
      matches(RegExp(r'from 10\.40 bar down to 10\.00 bar')),
    );
  });

  test('drain steps retain receiver composition for a following transfer in both gas models', () {
    for (final model in ['ideal', 'vdw']) {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': <String, Object?>{
          'volumeL': 12.0,
          'initialPressureBar': 100.0,
          'initialOxygenPercent': 0.0,
          'initialHeliumPercent': 0.0,
          'targetPressureBar': 150.0,
          'targetOxygenPercent': 21.0,
          'targetHeliumPercent': 0.0,
          'workingPressureBar': 250.0,
        },
        'physics': <String, Object?>{'model': model, 'temperatureC': 20.0},
        'thermal': <String, Object?>{
          'tankMaterial': 'steel',
          'tankSurfaceAreaM2': steelTestAreaM2,
          'coolingMedium': 'air',
          'ambientTemperatureC': 20.0,
          'inletTemperatureC': 20.0,
          'targetMediumTemperatureC': 20.0,
          'targetInWaterTemperatureC': 20.0,
          'waitMode': 'minutes',
          'waitMinutes': 0.0,
        },
        'settings': <String, Object?>{
          'booster': <String, Object?>{'compressorInletFlowLPerMin': 100.0},
        },
        'banks': <Object?>[],
      });

      expect(result['feasible'], isTrue, reason: model);
      final steps = _steps(result['protocolSteps']);
      final drain = steps.firstWhere((step) => step.type == 'drain');
      final transfer = steps.firstWhere(
        (step) => step.type != 'drain' && step.type != 'keep',
      );
      expect(drain.resultingMix!.oxygenPercent, 0.0, reason: model);
      expect(drain.resultingMix!.heliumPercent, 0.0, reason: model);
      expect(
        transfer.thermal!.receiverStartMix!.oxygenPercent,
        0.0,
        reason: model,
      );
      expect(
        transfer.thermal!.receiverStartMix!.heliumPercent,
        0.0,
        reason: model,
      );
    }
  });

  test('shows tiny required drains with a nonzero pressure change', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 12.0,
        'initialPressureBar': 10.0,
        'initialOxygenPercent': 21.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 10.0,
        'targetOxygenPercent': 21.01,
        'targetHeliumPercent': 0.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
      'banks': <Object?>[
        <String, Object?>{
          'id': 'oxygen',
          'name': 'Pure Oxygen',
          'volumeL': 10.0,
          'pressureBar': 100.0,
          'maxPressureBar': 350.0,
          'minimumPressureBar': 0.0,
          'oxygenPercent': 100.0,
          'heliumPercent': 0.0,
          'enabled': true,
        },
      ],
    });

    expect(result['feasible'], isTrue);
    final description = _steps(result['protocolSteps']).first.description!;
    final pressureChange = RegExp(
      r'from ([\d.]+) bar down to ([\d.]+) bar \(-([\d.]+) bar vented\)',
    ).firstMatch(description)!;
    expect(pressureChange.group(1), isNot(equals(pressureChange.group(2))));
    expect(double.parse(pressureChange.group(3)!), greaterThan(0.0));
  });

  test('emits a drain for a representable pressure reduction below the old mole cutoff', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 0.1,
        'initialPressureBar': 10.0000002,
        'initialOxygenPercent': 21.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 10.0,
        'targetOxygenPercent': 21.0,
        'targetHeliumPercent': 0.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 40.0},
      'banks': <Object?>[],
    });

    expect(result['feasible'], isTrue);
    final blend = _m(result['blend']);
    expect(_d(blend['ventedMoles']), greaterThan(0.0));
    expect(_d(blend['ventedMoles']), lessThan(1e-9));
    final step = _steps(result['protocolSteps']).first;
    final description = step.description!;
    expect(description, matches(RegExp(r'Retains 100% of the original mix\.')));
    expect(description, isNot(matches(RegExp('mol'))));
    expect(step.type, 'drain');
    final pressureChange = RegExp(
      r'from ([\d.]+) bar down to ([\d.]+) bar \(-([\d.]+) bar vented\)',
    ).firstMatch(description)!;
    expect(pressureChange.group(1), isNot(equals(pressureChange.group(2))));
    expect(double.parse(pressureChange.group(3)!), greaterThan(0.0));
  });

  test('orders recipe transfer stages by descending oxygen content', () {
    final result = optimizeBlend(defaultOptimizerInput());

    expect(result['feasible'], isTrue);
    final gas = _m(result['gas']);
    final blend = _m(result['blend']);
    expect(_d(gas['initialMoles']), closeTo(38.4, 0.1));
    expect(_d(gas['targetMoles']), closeTo(90.8, 0.1));
    expect(_d(blend['retainedPressureBar']), closeTo(80.0, 0.1));
    expect(_d(blend['ventedPressureBar']), closeTo(0.0, 0.1));
    expect(_d(blend['finalPressureBar']), closeTo(210.0, 0.1));
    expect(_steps(result['protocolSteps']).map((step) => step.title).toList(), [
      'Preserve 100% of Cylinder Gas',
      'Step 1: Decant Pure Oxygen to 80.3 bar',
      'Step 2: Equalize Tx 18/45 Bank to 174.6 bar',
      'Step 3: Boost Tx 18/45 Bank to 188.4 bar',
      'Step 4: Equalize Pure Helium to 197.8 bar',
      'Step 5: Boost Pure Helium to 210.0 bar',
    ]);
    expect(_maps(result['trajectory']).length, 6);
  });

  test(
    'protocol steps record the pressure and mix at the end of each stage',
    () {
      final result = optimizeBlend(defaultOptimizerInput());
      const expectedStages =
          <({double pressureBar, double oxygenPercent, double heliumPercent})>[
            (pressureBar: 80.0, oxygenPercent: 21.0, heliumPercent: 35.0),
            (pressureBar: 80.3, oxygenPercent: 21.3, heliumPercent: 34.9),
            (pressureBar: 174.6, oxygenPercent: 19.6, heliumPercent: 40.0),
            (pressureBar: 188.4, oxygenPercent: 19.5, heliumPercent: 40.3),
            (pressureBar: 197.8, oxygenPercent: 18.8, heliumPercent: 42.5),
            (pressureBar: 210.0, oxygenPercent: 18.0, heliumPercent: 45.0),
          ];

      final steps = _steps(result['protocolSteps']);
      expect(steps.length, expectedStages.length);
      for (var index = 0; index < steps.length; index++) {
        final step = steps[index];
        final expected = expectedStages[index];
        expect(step.resultingPressureBar!, closeTo(expected.pressureBar, 0.5));
        final mix = step.resultingMix;
        expect(
          mix,
          isNotNull,
          reason: '${step.title} must include its end-of-stage mix',
        );
        expect(mix!.oxygenPercent, closeTo(expected.oxygenPercent, 0.1));
        expect(mix.heliumPercent, closeTo(expected.heliumPercent, 0.1));
      }
    },
  );

  test(
    'trajectory records source-bank pressure ranges for each transfer stage',
    () {
      final input = defaultOptimizerInput();
      final result = optimizeBlend(input);
      final banks = _maps(input['banks']);
      final banksById = <String, Map<String, Object?>>{
        for (final bank in banks) bank['id']! as String: bank,
      };
      final transferPoints = _maps(result['trajectory'])
          .where((point) => point['bankId'] != null)
          .toList();

      expect(transferPoints.length, 5);
      for (var index = 0; index < transferPoints.length; index++) {
        final point = transferPoints[index];
        final bank = banksById[point['bankId']! as String]!;
        final start = _d(point['sourceStartPressureBar']);
        final end = _d(point['sourceEndPressureBar']);
        expect(start.isFinite, isTrue);
        expect(end.isFinite, isTrue);
        expect(end, lessThan(start));
        if (index == 0 ||
            transferPoints[index - 1]['bankId'] != point['bankId']) {
          expect(start, closeTo(_d(bank['pressureBar']), 1e-9));
        } else {
          expect(
            start,
            closeTo(
              _d(transferPoints[index - 1]['sourceEndPressureBar']),
              1e-9,
            ),
          );
        }
      }
    },
  );

  test(
    'nitrox preset vents the surplus and keeps the cylinder retained gas',
    () {
      final input = _withCylinder(defaultOptimizerInput(), _nitroxCylinder);
      final result = optimizeBlend(input);
      final baseline = optimizeBlend(<String, Object?>{
        ...input,
        '_salvage': false,
      });

      // Salvage into bank-1845 (the recipe's own draw source) would move 34.4 mol but cut the
      // retained cylinder gas (11.60 mol vs 17.77 mol), so the retention gate keeps vent-only.
      expect(result['feasible'], isTrue);
      expect(result['salvageTransfers'], isNull);
      expect(
        _d(_m(result['blend'])['ventedGasLitres']),
        closeTo(838.377979816809, 1e-8),
      );
      expect(
        _solution(result['solution'])['x_cyl']!,
        greaterThanOrEqualTo(
          _solution(baseline['solution'])['x_cyl']! * (1 - 1e-9),
        ),
      );
    },
  );

  test('vent-only mode keeps 838.38 L vented for the nitrox preset', () {
    final input = _withCylinder(defaultOptimizerInput(), _nitroxCylinder);
    final result = optimizeBlend(<String, Object?>{
      ...input,
      '_salvage': false,
    });

    expect(result['feasible'], isTrue);
    expect(result['salvageTransfers'], isNull);
    expect(
      _d(_m(result['blend'])['ventedGasLitres']),
      closeTo(838.377979816809, 1e-8),
    );
  });

  test('reports the maximum achievable pressure at the compressor ceiling', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 10.0,
        'initialPressureBar': 50.0,
        'initialOxygenPercent': 21.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 200.0,
        'targetOxygenPercent': 21.0,
        'targetHeliumPercent': 0.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
      'banks': <Object?>[],
      'settings': <String, Object?>{
        'booster': <String, Object?>{
          'maxCompressorPressureBar': 150.0,
          'maxBoosterOutputPressureBar': 200.0,
        },
      },
    });

    expect(result['feasible'], isFalse);
    final maximumPressure = _m(result['maximumPressure']);
    expect(_d(maximumPressure['pressureBar']), closeTo(150.0, 1e-6));
    final blend = _m(maximumPressure['blend']);
    expect(blend['finalPressureBar'], maximumPressure['pressureBar']);
    expect(blend['finalOxygenPercent'], 21.0);
    expect(blend['finalHeliumPercent'], 0.0);
    expect(
      _steps(maximumPressure['protocolSteps'])
          .map((step) => step.title)
          .toList(),
      [
        'Preserve 100% of Cylinder Gas',
        'Step 1: Top-up Compressor Air to 150.0 bar',
      ],
    );
  });

  test(
    'converts compressor-ceiling fallback with the selected real-gas model',
    () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': <String, Object?>{
          'volumeL': 10.0,
          'initialPressureBar': 50.0,
          'initialOxygenPercent': 21.0,
          'initialHeliumPercent': 0.0,
          'targetPressureBar': 200.0,
          'targetOxygenPercent': 21.0,
          'targetHeliumPercent': 0.0,
        },
        'physics': <String, Object?>{'model': 'vdw', 'temperatureC': 20.0},
        'banks': <Object?>[],
        'settings': <String, Object?>{
          'booster': <String, Object?>{
            'maxCompressorPressureBar': 150.0,
            'maxBoosterOutputPressureBar': 200.0,
          },
        },
      });

      expect(result['feasible'], isFalse);
      final maximumPressure = _m(result['maximumPressure']);
      expect(_d(maximumPressure['pressureBar']), closeTo(150.0, 1e-6));
      expect(
        _steps(maximumPressure['protocolSteps']).last.resultingPressureBar!,
        closeTo(_d(maximumPressure['pressureBar']), 1e-6),
      );
    },
  );

  test('reports helium shortage as required source-bank pressure and names the depleted bank', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 10.0,
        'initialPressureBar': 80.0,
        'initialOxygenPercent': 21.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 200.0,
        'targetOxygenPercent': 15.0,
        'targetHeliumPercent': 55.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
      'banks': <Object?>[
        <String, Object?>{
          'id': 'he',
          'name': 'Pure Helium',
          'volumeL': 1.0,
          'pressureBar': 10.0,
          'maxPressureBar': 350.0,
          'minimumPressureBar': 0.0,
          'oxygenPercent': 0.0,
          'heliumPercent': 100.0,
          'enabled': true,
        },
        <String, Object?>{
          'id': 'o2',
          'name': 'Pure Oxygen',
          'volumeL': 10.0,
          'pressureBar': 100.0,
          'maxPressureBar': 350.0,
          'minimumPressureBar': 0.0,
          'oxygenPercent': 100.0,
          'heliumPercent': 0.0,
          'enabled': true,
        },
      ],
    });

    expect(result['feasible'], isFalse);
    expect(result['reasonCode'], 'insufficient-source-gas');
    expect(result['maximumPressure'], isNotNull);
    final diagnostics = _m(result['diagnostics']);
    final helium = _maps(diagnostics['componentShortfalls'])
        .firstWhere((item) => item['component'] == 'Helium');
    expect(_d(helium['requiredMoles']), greaterThan(40.0));
    expect(_d(helium['availableMoles']), lessThan(1.0));
    expect(_d(helium['deficitMoles']), greaterThan(39.0));
    final exhaustedHelium = _maps(diagnostics['exhaustedBanks'])
        .firstWhere((bank) => bank['name'] == 'Pure Helium');
    expect(exhaustedHelium['currentPressureBar'], 10.0);
    expect(exhaustedHelium['minimumSourcePressureBar'], 0.0);
    final sourceBank = _m(helium['sourceBank']);
    expect(sourceBank['name'], 'Pure Helium');
    expect(sourceBank['volumeL'], 1.0);
    expect(sourceBank['currentPressureBar'], 10.0);
    expect(sourceBank['minimumSourcePressureBar'], 0.0);
    expect(_d(sourceBank['requiredPressureBar']), closeTo(1100.0, 1e-6));
    expect(_d(sourceBank['pressureIncreaseBar']), closeTo(1090.0, 1e-6));
  });

  test(
    'converts required source-bank pressure with the selected real-gas model',
    () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': <String, Object?>{
          'volumeL': 10.0,
          'initialPressureBar': 80.0,
          'initialOxygenPercent': 21.0,
          'initialHeliumPercent': 0.0,
          'targetPressureBar': 200.0,
          'targetOxygenPercent': 15.0,
          'targetHeliumPercent': 55.0,
        },
        'physics': <String, Object?>{'model': 'vdw', 'temperatureC': 20.0},
        'banks': <Object?>[
          <String, Object?>{
            'id': 'he',
            'name': 'Pure Helium',
            'volumeL': 1.0,
            'pressureBar': 10.0,
            'maxPressureBar': 350.0,
            'minimumPressureBar': 0.0,
            'oxygenPercent': 0.0,
            'heliumPercent': 100.0,
            'enabled': true,
          },
          <String, Object?>{
            'id': 'o2',
            'name': 'Pure Oxygen',
            'volumeL': 10.0,
            'pressureBar': 100.0,
            'maxPressureBar': 350.0,
            'minimumPressureBar': 0.0,
            'oxygenPercent': 100.0,
            'heliumPercent': 0.0,
            'enabled': true,
          },
        ],
      });

      final diagnostics = _m(result['diagnostics']);
      final helium = _maps(diagnostics['componentShortfalls'])
          .firstWhere((item) => item['component'] == 'Helium');
      final sourceBank = _m(helium['sourceBank']);
      expect(sourceBank['name'], 'Pure Helium');
      expect(sourceBank['volumeL'], 1.0);
      expect(sourceBank['currentPressureBar'], 10.0);
      expect(_d(sourceBank['requiredPressureBar']), greaterThan(10.0));
      expect(_d(sourceBank['pressureIncreaseBar']), greaterThan(0.0));
    },
  );

  test(
    'does not present an out-of-range real-gas source pressure as exact',
    () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': <String, Object?>{
          'volumeL': 10.0,
          'initialPressureBar': 80.0,
          'initialOxygenPercent': 21.0,
          'initialHeliumPercent': 0.0,
          'targetPressureBar': 350.0,
          'targetOxygenPercent': 15.0,
          'targetHeliumPercent': 55.0,
        },
        'physics': <String, Object?>{'model': 'vdw', 'temperatureC': 20.0},
        'banks': <Object?>[
          <String, Object?>{
            'id': 'he',
            'name': 'Pure Helium',
            'volumeL': 1.0,
            'pressureBar': 10.0,
            'maxPressureBar': 350.0,
            'minimumPressureBar': 0.0,
            'oxygenPercent': 0.0,
            'heliumPercent': 100.0,
            'enabled': true,
          },
          <String, Object?>{
            'id': 'o2',
            'name': 'Pure Oxygen',
            'volumeL': 10.0,
            'pressureBar': 100.0,
            'maxPressureBar': 350.0,
            'minimumPressureBar': 0.0,
            'oxygenPercent': 100.0,
            'heliumPercent': 0.0,
            'enabled': true,
          },
        ],
      });

      final diagnostics = _m(result['diagnostics']);
      final helium = _maps(diagnostics['componentShortfalls'])
          .firstWhere((item) => item['component'] == 'Helium');
      final sourceBank = _m(helium['sourceBank']);
      expect(sourceBank['pressureEstimateOutOfRange'], isTrue);
      expect(sourceBank['requiredPressureBar'], isNull);
      expect(sourceBank['pressureIncreaseBar'], isNull);
    },
  );

  test('does not label an unused trace bank as exhausted', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': <String, Object?>{
        'volumeL': 10.0,
        'initialPressureBar': 0.0,
        'initialOxygenPercent': 0.0,
        'initialHeliumPercent': 0.0,
        'targetPressureBar': 100.0,
        'targetOxygenPercent': 100.0,
        'targetHeliumPercent': 0.0,
      },
      'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
      'banks': <Object?>[
        <String, Object?>{
          'id': 'he',
          'name': 'Trace helium bank',
          'volumeL': 1.0,
          'pressureBar': 1.0,
          'maxPressureBar': 350.0,
          'minimumPressureBar': 0.0,
          'oxygenPercent': 0.0,
          'heliumPercent': 100.0,
          'enabled': true,
        },
      ],
    });

    expect(result['maximumPressure'], isNull);
    final exhausted = _maps(_m(result['diagnostics'])['exhaustedBanks']);
    expect(
      exhausted.any((bank) => bank['name'] == 'Trace helium bank'),
      isFalse,
    );
  });

  test(
    'converts compressor-ceiling fallback with the selected real-gas model',
    () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': <String, Object?>{
          'volumeL': 10.0,
          'initialPressureBar': 50.0,
          'initialOxygenPercent': 21.0,
          'initialHeliumPercent': 0.0,
          'targetPressureBar': 200.0,
          'targetOxygenPercent': 21.0,
          'targetHeliumPercent': 0.0,
        },
        'physics': <String, Object?>{'model': 'vdw', 'temperatureC': 20.0},
        'banks': <Object?>[],
        'settings': <String, Object?>{
          'booster': <String, Object?>{
            'maxCompressorPressureBar': 150.0,
            'maxBoosterOutputPressureBar': 200.0,
          },
        },
      });

      expect(result['feasible'], isFalse);
      final maximumPressure = _m(result['maximumPressure']);
      expect(_d(maximumPressure['pressureBar']), closeTo(150.0, 1e-6));
      expect(
        _steps(maximumPressure['protocolSteps']).last.resultingPressureBar!,
        closeTo(_d(maximumPressure['pressureBar']), 1e-6),
      );
    },
  );
}

const Map<String, Object?> _nitroxCylinder = <String, Object?>{
  'initialPressureBar': 100.0,
  'initialOxygenPercent': 32.0,
  'initialHeliumPercent': 0.0,
  'targetPressureBar': 220.0,
  'targetOxygenPercent': 21.0,
  'targetHeliumPercent': 30.0,
};

Map<String, Object?> _m(Object? value) => value! as Map<String, Object?>;

double _d(Object? value) => (value! as num).toDouble();

List<Map<String, Object?>> _maps(Object? value) =>
    (value! as List<Object?>).cast<Map<String, Object?>>().toList();

List<ProtocolStep> _steps(Object? value) =>
    (value! as List<Object?>).cast<ProtocolStep>().toList();

Map<String, double> _solution(Object? value) => (value! as Map<String, Object?>)
    .map((key, item) => MapEntry(key, (item! as num).toDouble()));

Map<String, Object?> _withCylinder(
  Map<String, Object?> input,
  Map<String, Object?> changes,
) {
  return <String, Object?>{
    ...input,
    'cylinder': <String, Object?>{..._m(input['cylinder']), ...changes},
  };
}

/// JS `equalGasTransferInput`: a 10 L ideal-gas cylinder with one nitrogen bank.
Map<String, Object?> _equalGasTransferInput({
  required double initialPressureBar,
  required double targetPressureBar,
  required double bankPressureBar,
}) {
  return <String, Object?>{
    'cylinder': <String, Object?>{
      'volumeL': 10.0,
      'initialPressureBar': initialPressureBar,
      'initialOxygenPercent': 0.0,
      'initialHeliumPercent': 0.0,
      'targetPressureBar': targetPressureBar,
      'targetOxygenPercent': 0.0,
      'targetHeliumPercent': 0.0,
    },
    'physics': <String, Object?>{'model': 'ideal', 'temperatureC': 20.0},
    'banks': <Object?>[
      <String, Object?>{
        'id': 'nitrogen',
        'name': 'Nitrogen source',
        'volumeL': 10.0,
        'pressureBar': bankPressureBar,
        'minimumPressureBar': 0.0,
        'maxPressureBar': 350.0,
        'oxygenPercent': 0.0,
        'heliumPercent': 0.0,
        'enabled': true,
      },
    ],
  };
}

Map<String, Object?> _bankMap(Bank bank) {
  return <String, Object?>{
    'id': bank.id,
    'name': bank.name,
    'volumeL': bank.volumeL,
    'pressureBar': bank.pressureBar,
    'oxygenPercent': bank.oxygenPercent,
    'heliumPercent': bank.heliumPercent,
    'enabled': bank.enabled,
    if (bank.maxPressureBar != null) 'maxPressureBar': bank.maxPressureBar,
    if (bank.minimumPressureBar != null)
      'minimumPressureBar': bank.minimumPressureBar,
    if (bank.pricePerLitre != null) 'pricePerLitre': bank.pricePerLitre,
  };
}

Map<String, Object?> _settingsMap(Settings settings) {
  final booster = settings.booster;
  return <String, Object?>{
    'pressureLimitMode': settings.pressureLimitMode,
    'booster': <String, Object?>{
      'minimumSourcePressureBar': booster.minimumSourcePressureBar,
      'cylinderVolumeCm3': booster.cylinderVolumeCm3,
      'oxygenBoostBpm': booster.oxygenBoostBpm,
      'otherBoostBpm': booster.otherBoostBpm,
      'oxygenDecantRateBarPerMin': booster.oxygenDecantRateBarPerMin,
      'otherDecantRateBarPerMin': booster.otherDecantRateBarPerMin,
      'drainingRateBarPerMin': booster.drainingRateBarPerMin,
      'compressorInletFlowLPerMin': booster.compressorInletFlowLPerMin,
      'maxCompressorPressureBar': booster.maxCompressorPressureBar,
      'maxBoosterOutputPressureBar': booster.maxBoosterOutputPressureBar,
      'boosterTemperatureModifierC': booster.boosterTemperatureModifierC,
      'compressorTemperatureModifierC': booster.compressorTemperatureModifierC,
    },
  };
}

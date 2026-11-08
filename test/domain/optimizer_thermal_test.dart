import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/domain/optimizer.dart';
import 'package:simplex_blender/src/domain/simplex.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

import 'optimizer_fixtures.dart';

import '../support/tank_area.dart';

void main() {
  test('maximum-pressure fallback uses complementary banks to preserve the exact target fractions', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 10,
        initialPressureBar: 0,
        initialOxygenPercent: 0,
        initialHeliumPercent: 0,
        targetPressureBar: 300,
        targetOxygenPercent: 10,
        targetHeliumPercent: 45,
      ),
      'physics': _idealPhysics(),
      'banks': <Object?>[
        _bank(
          id: 'he',
          name: 'Helium bank',
          volumeL: 10,
          pressureBar: 100,
          minimumPressureBar: 0,
          oxygenPercent: 0,
          heliumPercent: 100,
        ),
        _bank(
          id: 'nitrogen',
          name: 'Nitrogen bank',
          volumeL: 10,
          pressureBar: 100,
          minimumPressureBar: 0,
          oxygenPercent: 0,
          heliumPercent: 0,
        ),
      ],
      'settings': _boosterSettings(
        maxCompressorPressureBar: 350,
        maxBoosterOutputPressureBar: 350,
      ),
    });

    expect(result['feasible'], isFalse);
    expect(
      _num(_obj(result['maximumPressure'])['pressureBar']),
      closeTo(2000 / 9, 1e-6),
    );
    final finalStep = _objs(_obj(result['maximumPressure'])['trajectory']).last;
    expect(_num(finalStep['oxygenPercent']), closeTo(10, 1e-8));
    expect(_num(finalStep['heliumPercent']), closeTo(45, 1e-8));
    expect(_num(finalStep['pressureBar']), closeTo(2000 / 9, 1e-6));
  });

  test('keeps a sub-0.05-mol bank contribution in the fallback recipe', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 10,
        initialPressureBar: 100,
        initialOxygenPercent: 0,
        initialHeliumPercent: 0,
        targetPressureBar: 300,
        targetOxygenPercent: 0.01,
        targetHeliumPercent: 0,
      ),
      'physics': _idealPhysics(),
      'banks': <Object?>[
        _bank(
          id: 'oxygen',
          name: 'Oxygen bank',
          volumeL: 200,
          pressureBar: 100,
          minimumPressureBar: 0,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
      ],
    });

    final maximumPressure = _obj(result['maximumPressure']);
    expect(maximumPressure, isNotEmpty);
    final finalStep = _objs(maximumPressure['trajectory']).last;
    expect(_num(finalStep['addedMoles']), greaterThan(0));
    expect(_num(finalStep['addedMoles']), lessThan(0.05));
    expect(_num(finalStep['oxygenPercent']), closeTo(0.01, 1e-8));
    final stepDescription = _str(
      _objs(maximumPressure['protocolSteps']).last['description'],
    );
    expect(stepDescription, matches(RegExp('bar')));
    expect(
      stepDescription,
      isNot(matches(RegExp(r'Decompressively|mol|\(100/0\)'))),
    );
  });

  test('uses a larger interchangeable oxygen bank when it keeps the maximum recipe safe', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 10,
        initialPressureBar: 150,
        initialOxygenPercent: 0,
        initialHeliumPercent: 0,
        targetPressureBar: 200,
        targetOxygenPercent: 25,
        targetHeliumPercent: 0,
      ),
      'physics': _idealPhysics(),
      'banks': <Object?>[
        _bank(
          id: 'small-oxygen',
          name: 'Small oxygen bank',
          volumeL: 10,
          pressureBar: 80,
          minimumPressureBar: 0,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
        _bank(
          id: 'large-oxygen',
          name: 'Large oxygen bank',
          volumeL: 100,
          pressureBar: 80,
          minimumPressureBar: 0,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
      ],
    });

    expect(result['feasible'], isTrue);
    expect(_num(_obj(result['blend'])['finalPressureBar']), equals(200));
    expect(
      _titleIncludes(result['protocolSteps'], 'Large oxygen bank'),
      isTrue,
    );
  });

  test('searches an alternative high-pressure source instead of overstating an unsafe-bank deficit', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 10,
        initialPressureBar: 150,
        initialOxygenPercent: 0,
        initialHeliumPercent: 0,
        targetPressureBar: 250,
        targetOxygenPercent: 25,
        targetHeliumPercent: 0,
      ),
      'physics': _idealPhysics(),
      'banks': <Object?>[
        _bank(
          id: 'low-pressure',
          name: 'Low-pressure large bank',
          volumeL: 100,
          pressureBar: 20,
          minimumPressureBar: 0,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
        _bank(
          id: 'high-pressure',
          name: 'High-pressure small bank',
          volumeL: 10,
          pressureBar: 100,
          minimumPressureBar: 0,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
      ],
    });

    expect(result['feasible'], isFalse);
    expect(
      _num(_obj(result['maximumPressure'])['pressureBar']),
      closeTo(200, 1e-6),
    );
    expect(
      _titleIncludes(
        _obj(result['maximumPressure'])['protocolSteps'],
        'High-pressure small bank',
      ),
      isTrue,
    );
  });

  test('splits oxygen transfers when neither full-bank allocation is safe', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 10,
        initialPressureBar: 100,
        initialOxygenPercent: 0,
        initialHeliumPercent: 0,
        targetPressureBar: 200,
        targetOxygenPercent: 50,
        targetHeliumPercent: 0,
      ),
      'physics': _idealPhysics(),
      'banks': <Object?>[
        _bank(
          id: 'oxygen-a',
          name: 'Oxygen A',
          volumeL: 10,
          pressureBar: 100,
          minimumPressureBar: 0,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
        _bank(
          id: 'oxygen-b',
          name: 'Oxygen B',
          volumeL: 10,
          pressureBar: 100,
          minimumPressureBar: 0,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
      ],
    });

    expect(result['feasible'], isTrue);
    expect(_num(_obj(result['blend'])['finalPressureBar']), equals(200));
    expect(_titleIncludes(result['protocolSteps'], 'Oxygen A'), isTrue);
    expect(_titleIncludes(result['protocolSteps'], 'Oxygen B'), isTrue);
    expect(
      _num(_objs(result['trajectory']).last['oxygenPercent']),
      closeTo(50, 1e-8),
    );
  });

  test('searches uneven oxygen-bank splits when an equal split fails the 4:1 limit', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 10,
        initialPressureBar: 100,
        initialOxygenPercent: 0,
        initialHeliumPercent: 0,
        targetPressureBar: 200,
        targetOxygenPercent: 50,
        targetHeliumPercent: 0,
      ),
      'physics': _idealPhysics(),
      'banks': <Object?>[
        _bank(
          id: 'oxygen-a',
          name: 'Oxygen A',
          volumeL: 20,
          pressureBar: 90,
          minimumPressureBar: 0,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
        _bank(
          id: 'oxygen-b',
          name: 'Oxygen B',
          volumeL: 10,
          pressureBar: 90,
          minimumPressureBar: 0,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
      ],
    });

    expect(result['feasible'], isTrue);
    expect(_num(_obj(result['blend'])['finalPressureBar']), equals(200));
    expect(_titleIncludes(result['protocolSteps'], 'Oxygen A'), isTrue);
    expect(_titleIncludes(result['protocolSteps'], 'Oxygen B'), isTrue);
  });

  test('finds a narrow safe bank split outside the fixed-share samples', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 10,
        initialPressureBar: 100,
        initialOxygenPercent: 0,
        initialHeliumPercent: 0,
        targetPressureBar: 200,
        targetOxygenPercent: 50,
        targetHeliumPercent: 0,
      ),
      'physics': _idealPhysics(),
      'banks': <Object?>[
        _bank(
          id: 'oxygen-a',
          name: 'Low-pressure oxygen',
          volumeL: 10,
          pressureBar: 55,
          minimumPressureBar: 0,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
        _bank(
          id: 'oxygen-b',
          name: 'High-pressure oxygen',
          volumeL: 10,
          pressureBar: 145,
          minimumPressureBar: 0,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
      ],
    });

    expect(result['feasible'], isTrue);
    expect(_num(_obj(result['blend'])['finalPressureBar']), equals(200));
    expect(
      _titleIncludes(result['protocolSteps'], 'Low-pressure oxygen'),
      isTrue,
    );
    expect(
      _titleIncludes(result['protocolSteps'], 'High-pressure oxygen'),
      isTrue,
    );
  });

  test(
    'allows a later non-Air transfer after compressor Air reaches its ceiling',
    () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': _cylinder(
          volumeL: 10,
          initialPressureBar: 100,
          initialOxygenPercent: 0,
          initialHeliumPercent: 0,
          targetPressureBar: 250,
          targetOxygenPercent: 25,
          targetHeliumPercent: 0,
        ),
        'physics': _idealPhysics(),
        'banks': <Object?>[
          _bank(
            id: 'oxygen-source',
            name: 'Oxygen source',
            volumeL: 100,
            pressureBar: 200,
            maxPressureBar: 350,
            minimumPressureBar: 0,
            oxygenPercent: 100,
            heliumPercent: 0,
          ),
        ],
        'settings': _boosterSettings(
          maxCompressorPressureBar: 232,
          maxBoosterOutputPressureBar: 350,
        ),
      });

      expect(result['feasible'], isTrue);
      final compressorStep = _firstWhereOrNull(
        _objs(result['protocolSteps']),
        (step) => _str(step['title']).contains('Compressor Air'),
      );
      expect(compressorStep, isNotNull);
      expect(
        _num(compressorStep!['resultingPressureBar']),
        lessThanOrEqualTo(232 + 1e-9),
      );
      expect(_num(_obj(result['blend'])['finalPressureBar']), equals(250));
    },
  );

  test('ignores oxygen inventory in air when the exact target contains no nitrogen', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 10,
        initialPressureBar: 100,
        initialOxygenPercent: 0,
        initialHeliumPercent: 0,
        targetPressureBar: 250,
        targetOxygenPercent: 100,
        targetHeliumPercent: 0,
      ),
      'physics': _idealPhysics(),
      'banks': <Object?>[
        _bank(
          id: 'oxygen-a',
          name: 'Oxygen A',
          volumeL: 2,
          pressureBar: 100,
          minimumPressureBar: 45,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
        _bank(
          id: 'oxygen-b',
          name: 'Oxygen B',
          volumeL: 10,
          pressureBar: 240,
          minimumPressureBar: 45,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
      ],
    });

    expect(result['feasible'], isFalse);
    final maximumPressure = _obj(result['maximumPressure']);
    final pressure = _num(maximumPressure['pressureBar']);
    expect(pressure, allOf(greaterThanOrEqualTo(200), lessThan(206)));
    final steps = _objs(maximumPressure['protocolSteps']);
    expect(_titleIncludes(steps, 'Oxygen A'), isTrue);
    expect(_titleIncludes(steps, 'Oxygen B'), isTrue);
    expect(_titleIncludes(steps, 'Air bank'), isFalse);
  });

  test(
    'drains small amounts of cylinder gas when fallback fractions require it',
    () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': _cylinder(
          volumeL: 10,
          initialPressureBar: 100,
          initialOxygenPercent: 0,
          initialHeliumPercent: 0,
          targetPressureBar: 200,
          targetOxygenPercent: 25,
          targetHeliumPercent: 75,
        ),
        'physics': _idealPhysics(),
        'banks': <Object?>[
          _bank(
            id: 'oxygen',
            name: 'Oxygen bank',
            volumeL: 10,
            pressureBar: 100,
            minimumPressureBar: 66.8,
            oxygenPercent: 100,
            heliumPercent: 0,
          ),
          _bank(
            id: 'helium',
            name: 'Helium bank',
            volumeL: 10,
            pressureBar: 100,
            minimumPressureBar: 0,
            oxygenPercent: 0,
            heliumPercent: 100,
          ),
        ],
      });

      final maximumPressure = _obj(result['maximumPressure']);
      final drain = _objs(maximumPressure['protocolSteps'])[0];
      final finalStep = _objs(maximumPressure['trajectory']).last;
      expect(drain['type'], equals('drain'));
      expect(_num(drain['resultingPressureBar']), lessThan(100));
      expect(_num(finalStep['oxygenPercent']), closeTo(25, 1e-8));
      expect(
        _num(finalStep['pressureBar']),
        closeTo(_num(maximumPressure['pressureBar']), 1e-6),
      );
    },
  );

  test('does not display moles for small fallback transfers', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 10,
        initialPressureBar: 100,
        initialOxygenPercent: 0,
        initialHeliumPercent: 0,
        targetPressureBar: 300,
        targetOxygenPercent: 0.365,
        targetHeliumPercent: 99.635,
      ),
      'physics': _idealPhysics(),
      'banks': <Object?>[
        _bank(
          id: 'oxygen',
          name: 'Oxygen bank',
          volumeL: 200,
          pressureBar: 100,
          minimumPressureBar: 0,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
        _bank(
          id: 'helium',
          name: 'Helium bank',
          volumeL: 10,
          pressureBar: 100,
          minimumPressureBar: 0,
          oxygenPercent: 0,
          heliumPercent: 100,
        ),
      ],
    });

    final maximumPressure = _obj(result['maximumPressure']);
    final oxygenStep = _objs(maximumPressure['trajectory'])
        .firstWhere((point) => point['bankName'] == 'Oxygen bank');
    final stepDescription = _str(
      _objs(maximumPressure['protocolSteps']).last['description'],
    );
    expect(_num(oxygenStep['addedMoles']), greaterThan(0.1));
    expect(_num(oxygenStep['addedMoles']), lessThan(0.5));
    expect(stepDescription, matches(RegExp('bar')));
    expect(
      stepDescription,
      isNot(matches(RegExp(r'Decompressively|mol|\(100/0\)'))),
    );
  });

  test('does not report a maximum-pressure recipe when no positive amount matches the target mix', () {
    final result = optimizeBlend(
      _with(defaultOptimizerInput(), <String, Object?>{'banks': <Object?>[]}),
    );

    expect(result['feasible'], isFalse);
    expect(result['maximumPressure'], isNull);
    expect(
      _objs(
        result['tableauSteps'],
      ).any((step) => (step['varNames']! as List<Object?>).contains('n_total')),
      isTrue,
    );
  });

  test(
    'unavailable banks report infeasible without a fabricated blend protocol',
    () {
      final result = optimizeBlend(
        _with(defaultOptimizerInput(), <String, Object?>{'banks': <Object?>[]}),
      );
      expect(result['feasible'], isFalse);
      expect(result['blend'], isNull);
      expect(result['protocolSteps'], isEmpty);
      expect(_str(result['error']), isNotEmpty);
      expect(_objs(result['tableauSteps']), isNotEmpty);
    },
  );

  test('rejects oxygen-rich transfer when receiver exceeds four times source residual pressure', () {
    final result = optimizeBlend(_oxygenTransferInput(80));

    expect(result['feasible'], isFalse);
    expect(_str(result['error']), matches(RegExp('4:1')));
    expect(result['reasonCode'], equals('oxygen-boost-ratio'));
    expect(result['blend'], isNull);
    expect(result['protocolSteps'], isEmpty);
  });

  test('checks oxygen transfer after compressor Air is staged first', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 10,
        initialPressureBar: 150,
        initialOxygenPercent: 0,
        initialHeliumPercent: 0,
        targetPressureBar: 280,
        targetOxygenPercent: 25,
        targetHeliumPercent: 0,
      ),
      'physics': _idealPhysics(),
      'banks': <Object?>[
        <String, Object?>{
          'id': 'oxygen-source',
          'name': 'Oxygen source',
          'volumeL': 10.0,
          'pressureBar': 110.0,
          'maxPressureBar': 350.0,
          'oxygenPercent': 100.0,
          'heliumPercent': 0.0,
          'enabled': true,
        },
      ],
      'settings': _boosterSettings(
        maxCompressorPressureBar: 232,
        maxBoosterOutputPressureBar: 350,
      ),
    });

    expect(result['feasible'], isFalse);
    expect(_str(result['error']), matches(RegExp('4:1')));
    expect(result['reasonCode'], equals('oxygen-boost-ratio'));
  });

  test('finds the maximum lower pressure that keeps the exact mix within the oxygen transfer limit', () {
    final result = optimizeBlend(_oxygenTransferInput(80));

    expect(result['feasible'], isFalse);
    final maximumPressure = _obj(result['maximumPressure']);
    expect(maximumPressure, isNotEmpty);
    expect(_num(maximumPressure['pressureBar']), closeTo(160, 1e-6));
    expect(_str(result['error']), matches(RegExp('4:1')));
    final finalStep = _objs(maximumPressure['trajectory']).last;
    expect(_num(finalStep['oxygenPercent']), closeTo(25, 1e-8));
    expect(_num(finalStep['pressureBar']), closeTo(160, 1e-6));
  });

  test('allows oxygen-rich transfer when receiver pressure is exactly four times source residual pressure', () {
    final result = optimizeBlend(_oxygenTransferInput(100));

    expect(result['feasible'], isTrue);
    expect(_num(_obj(result['blend'])['finalPressureBar']), equals(200));
  });

  test('does not apply the oxygen compression limit to source gas at exactly 25 percent oxygen', () {
    final result = optimizeBlend(_oxygenTransferInput(80, 25));

    expect(result['feasible'], isTrue);
    expect(_num(_obj(result['blend'])['finalPressureBar']), equals(200));
  });

  test(
    'reports the configured minimum when a finite boost source is exhausted',
    () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': _cylinder(
          volumeL: 10,
          initialPressureBar: 0,
          initialOxygenPercent: 0,
          initialHeliumPercent: 0,
          targetPressureBar: 80,
          targetOxygenPercent: 100,
          targetHeliumPercent: 0,
        ),
        'physics': _idealPhysics(),
        'banks': <Object?>[
          _bank(
            id: 'oxygen',
            name: 'Oxygen bank',
            volumeL: 10,
            pressureBar: 100,
            minimumPressureBar: 0,
            oxygenPercent: 100,
            heliumPercent: 0,
          ),
        ],
        'settings': _boosterSettings(
          minimumSourcePressureBar: 20,
          maxCompressorPressureBar: 232,
          maxBoosterOutputPressureBar: 200,
        ),
      });

      expect(result['feasible'], isTrue);
      final step = _firstWhereOrNull(
        _objs(result['protocolSteps']),
        (candidate) => candidate['type'] == 'boost',
      );
      expect(step, isNotNull);
      expect(_num(step!['minimumSourcePressureBar']), equals(20));
      expect(step['sourceExhausted'], isTrue);
      expect(
        _str(step['description']),
        matches(
          RegExp(
            r'This empties Oxygen bank and leaves only 20\.0 bar of gas\.',
          ),
        ),
      );
    },
  );

  test(
    'reports the end-of-boost compression ratio only above 40 percent oxygen',
    () {
      final highOxygenResult = optimizeBlend(_oxygenTransferInput(100, 41));
      final highOxygenBoost = _firstWhereOrNull(
        _objs(highOxygenResult['protocolSteps']),
        (step) => step['type'] == 'boost',
      );
      expect(highOxygenResult['feasible'], isTrue);
      expect(highOxygenBoost, isNotNull);
      expect(
        _num(highOxygenBoost!['oxygenCompressionRatio']),
        closeTo(4, 1e-6),
      );
      expect(
        _str(highOxygenBoost['description']),
        matches(
          RegExp(
            r'O2 compression ratio is 4\.00:1 \(source 50\.0 bar to receiver 200\.0 bar\)\.',
          ),
        ),
      );

      final thresholdResult = optimizeBlend(_oxygenTransferInput(100, 40));
      final thresholdBoost = _firstWhereOrNull(
        _objs(thresholdResult['protocolSteps']),
        (step) => step['type'] == 'boost',
      );
      expect(thresholdResult['feasible'], isTrue);
      expect(thresholdBoost, isNotNull);
      expect(thresholdBoost!['oxygenCompressionRatio'], isNull);
      expect(
        _str(thresholdBoost['description']),
        isNot(matches(RegExp('O2 compression ratio'))),
      );
    },
  );

  test(
    'rejects impossible target gas composition without returning a recipe',
    () {
      final result = optimizeBlend(
        _with(defaultOptimizerInput(), <String, Object?>{
          'cylinder': _with(_defaultCylinder(), <String, Object?>{
            'targetOxygenPercent': 110.0,
            'targetHeliumPercent': 20.0,
          }),
        }),
      );

      expect(result['feasible'], isFalse);
      expect(result['gas'], isNull);
      expect(result['maximumPressure'], isNull);
      expect(result['protocolSteps'], isEmpty);
      expect(
        _str(result['error']),
        matches(RegExp(r'target.*gas composition', caseSensitive: false)),
      );
    },
  );

  test(
    'does not recommend implicit Compressor Air for a pure-oxygen shortfall',
    () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': _cylinder(
          volumeL: 10,
          initialPressureBar: 0,
          initialOxygenPercent: 0,
          initialHeliumPercent: 0,
          targetPressureBar: 100,
          targetOxygenPercent: 100,
          targetHeliumPercent: 0,
        ),
        'physics': _idealPhysics(),
        'banks': <Object?>[],
      });

      expect(result['feasible'], isFalse);
      final shortfalls = _objs(
        _obj(result['diagnostics'])['componentShortfalls'],
      );
      expect(shortfalls[0]['sourceBank'], isNull);
    },
  );

  test('rejects impossible enabled-bank composition before solving', () {
    final result = optimizeBlend(
      _with(defaultOptimizerInput(), <String, Object?>{
        'banks': <Object?>[
          _with(_defaultBanks()[0], <String, Object?>{'oxygenPercent': 10.0}),
          ..._defaultBanks().sublist(1),
        ],
      }),
    );

    expect(result['feasible'], isFalse);
    expect(result['gas'], isNull);
    expect(result['maximumPressure'], isNull);
    expect(result['protocolSteps'], isEmpty);
    expect(
      _str(result['error']),
      matches(RegExp(r'pure helium.*gas composition', caseSensitive: false)),
    );
  });

  test('rejects a supply bank without a usable name', () {
    final result = optimizeBlend(
      _with(defaultOptimizerInput(), <String, Object?>{
        'banks': <Object?>[
          _with(_defaultBanks()[0], <String, Object?>{'name': '   '}),
          ..._defaultBanks().sublist(1),
        ],
      }),
    );

    expect(result['feasible'], isFalse);
    expect(result['gas'], isNull);
    expect(
      _str(result['error']),
      matches(RegExp(r'bank.*name', caseSensitive: false)),
    );
  });

  test(
    'rejects target pressures outside the supported range in direct calls',
    () {
      for (final targetPressureBar in <double>[9, 351]) {
        final result = optimizeBlend(<String, Object?>{
          'cylinder': _cylinder(
            volumeL: 10,
            initialPressureBar: 50,
            initialOxygenPercent: 21,
            initialHeliumPercent: 0,
            targetPressureBar: targetPressureBar,
            targetOxygenPercent: 21,
            targetHeliumPercent: 0,
          ),
          'physics': _idealPhysics(),
          'banks': <Object?>[],
        });

        expect(result['feasible'], isFalse);
        expect(result['gas'], isNull);
        expect(
          _str(result['error']),
          matches(RegExp(r'target pressure.*10.*350', caseSensitive: false)),
        );
      }
    },
  );

  test('rejects bank volumes outside the supported range in direct calls', () {
    for (final volumeL in <double>[0.5, 201]) {
      final result = optimizeBlend(
        _with(defaultOptimizerInput(), <String, Object?>{
          'banks': <Object?>[
            _with(_defaultBanks()[0], <String, Object?>{'volumeL': volumeL}),
            ..._defaultBanks().sublist(1),
          ],
        }),
      );

      expect(result['feasible'], isFalse);
      expect(result['gas'], isNull);
      expect(
        _str(result['error']),
        matches(RegExp(r'bank volume.*1.*200', caseSensitive: false)),
      );
    }
  });

  test(
    'rejects unsupported gas models instead of silently switching to ideal gas',
    () {
      final result = optimizeBlend(
        _with(defaultOptimizerInput(), <String, Object?>{
          'physics': <String, Object?>{'model': 'vdw ', 'temperatureC': 20.0},
        }),
      );

      expect(result['feasible'], isFalse);
      expect(result['gas'], isNull);
      expect(
        _str(result['error']),
        matches(RegExp(r'gas model.*ideal.*vdw', caseSensitive: false)),
      );
    },
  );

  test('thermal recipe overshoots the last hot target so ambient pressure reaches the request', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 12,
        initialPressureBar: 80,
        initialOxygenPercent: 21,
        initialHeliumPercent: 0,
        targetPressureBar: 210,
        targetOxygenPercent: 21,
        targetHeliumPercent: 0,
      ),
      'physics': _idealPhysics(),
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
    final thermal = _obj(result['thermal']);
    expect(_num(thermal['requestedSettledTargetPressureBar']), equals(210));
    expect(_num(_obj(result['gas'])['targetPressureBar']), equals(210));
    expect(_num(thermal['finalTransferEndPressureBar']), greaterThan(210));
    expect(_num(thermal['finalAmbientPressureBar']), closeTo(210, 1e-5));
  });

  test('optimizeBlend exposes the hot transfer endpoint separately from the physics reference pressure', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 12,
        initialPressureBar: 0,
        initialOxygenPercent: 0,
        initialHeliumPercent: 0,
        targetPressureBar: 150,
        targetOxygenPercent: 21,
        targetHeliumPercent: 0,
        workingPressureBar: 250,
      ),
      'physics': _idealPhysics(),
      'thermal': _thermalAirWait(
        inletTemperatureC: 40,
        targetMediumTemperatureC: 20,
        targetInWaterTemperatureC: 20,
        waitMinutes: 0,
      ),
      'settings': <String, Object?>{
        'booster': <String, Object?>{'compressorInletFlowLPerMin': 100.0},
      },
      'banks': <Object?>[],
    });

    expect(result['feasible'], isTrue);
    final transfer = _firstWhereOrNull(
      _objs(result['protocolSteps']),
      (step) => step['type'] == 'boost',
    );
    expect(transfer, isNotNull);
    final thermal = _obj(transfer!['thermal']);
    expect(_num(thermal['pressureReferenceTemperatureC']), equals(20));
    expect(_num(thermal['temperatureAtTransferEndC']), greaterThan(20));
    final expectedHotPressure = calculatePressureAtTemperature(
      pressureBar: _num(thermal['pressureAtTransferEndReferenceBar']),
      oxygenPercent: _num(_obj(transfer['resultingMix'])['oxygenPercent']),
      heliumPercent: _num(_obj(transfer['resultingMix'])['heliumPercent']),
      fromTemperatureC: 20,
      toTemperatureC: _num(thermal['temperatureAtTransferEndC']),
      volumeL: 12,
      useVdw: false,
    );
    expect(
      _num(thermal['pressureAtTransferEndHotBar']),
      closeTo(expectedHotPressure, 1e-9),
    );
    expect(
      (_num(thermal['pressureAtTransferEndReferenceBar']) -
              _num(thermal['pressureAtTransferEndBar']))
          .abs(),
      greaterThan(1e-6),
    );
    expect(
      (_num(thermal['pressureAtTransferEndBar']) -
              _num(thermal['pressureAtTransferEndHotBar']))
          .abs(),
      lessThan(1e-9),
    );
    final finalResultThermal = _obj(result['thermal']);
    expect(
      (_num(finalResultThermal['finalTransferEndPressureBar']) -
              _num(thermal['pressureAtTransferEndHotBar']))
          .abs(),
      lessThan(1e-9),
    );
    expect(
      finalResultThermal['finalTransferEndTemperatureC'],
      equals(thermal['temperatureAtTransferEndC']),
    );
    final trajectoryPoint = _firstWhereOrNull(
      _objs(result['trajectory']),
      (point) => _truthy(point['bankId']),
    );
    expect(trajectoryPoint, isNotNull);
    expect(
      trajectoryPoint!['ambientPressureBar'],
      equals(finalResultThermal['finalAmbientPressureBar']),
    );
    expect(
      trajectoryPoint['hotPressureBar'],
      equals(finalResultThermal['finalTransferEndPressureBar']),
    );
  });

  test('thermal trajectory maps each bank point to its corresponding transfer state', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 12,
        initialPressureBar: 0,
        initialOxygenPercent: 0,
        initialHeliumPercent: 0,
        targetPressureBar: 150,
        targetOxygenPercent: 21,
        targetHeliumPercent: 79,
        workingPressureBar: 250,
      ),
      'physics': _idealPhysics(),
      'thermal': _thermalAirWait(
        inletTemperatureC: 40,
        targetMediumTemperatureC: 20,
        targetInWaterTemperatureC: 20,
        waitMinutes: 0,
      ),
      'settings': <String, Object?>{
        'booster': <String, Object?>{
          'minimumSourcePressureBar': 0.0,
          'cylinderVolumeCm3': 9.0,
          'oxygenBoostBpm': 50.0,
          'otherBoostBpm': 50.0,
          'oxygenDecantRateBarPerMin': 5.0,
          'otherDecantRateBarPerMin': 5.0,
        },
      },
      'banks': <Object?>[
        _bank(
          id: 'o2',
          name: 'Oxygen',
          volumeL: 12,
          pressureBar: 300,
          minimumPressureBar: 0,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
        _bank(
          id: 'he',
          name: 'Helium',
          volumeL: 12,
          pressureBar: 300,
          minimumPressureBar: 0,
          oxygenPercent: 0,
          heliumPercent: 100,
        ),
      ],
    });

    expect(result['feasible'], isTrue);
    final transferSteps = _objs(result['protocolSteps'])
        .where((step) => step['type'] != 'drain' && _rateSourceIsTransfer(step))
        .toList();
    final transferPoints = _objs(result['trajectory'])
        .where((point) => _truthy(point['bankId']))
        .toList();
    expect(transferSteps.length, equals(2));
    expect(transferPoints.length, equals(2));
    for (var index = 0; index < transferPoints.length; index += 1) {
      final point = transferPoints[index];
      final thermal = _obj(transferSteps[index]['thermal']);
      expect(
        point['pressureAtTransferEndReferenceBar'],
        equals(thermal['pressureAtTransferEndReferenceBar']),
      );
      expect(
        point['pressureAtTransferEndAmbientBar'],
        equals(thermal['pressureAtTransferEndAmbientBar']),
      );
      expect(
        point['pressureAtTransferEndHotBar'],
        equals(thermal['pressureAtTransferEndHotBar']),
      );
      expect(
        point['ambientPressureBar'],
        equals(thermal['pressureAtTransferEndAmbientBar']),
      );
      expect(
        point['hotPressureBar'],
        equals(thermal['pressureAtTransferEndHotBar']),
      );
    }
  });

  test('optimizeBlend returns a feasible automatic wait extension with complete safety metadata', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 12,
        initialPressureBar: 0,
        initialOxygenPercent: 21,
        initialHeliumPercent: 0,
        targetPressureBar: 95,
        targetOxygenPercent: 21,
        targetHeliumPercent: 0,
        workingPressureBar: 100,
        hotOverfillPercent: 0,
      ),
      'physics': _idealPhysics(),
      'thermal': <String, Object?>{
        'tankMaterial': 'steel',
        'tankSurfaceAreaM2': steelTestAreaM2,
        'coolingMedium': 'air',
        'ambientTemperatureC': 20.0,
        'inletTemperatureC': 40.0,
        'targetMediumTemperatureC': 20.0,
        'targetInWaterTemperatureC': 20.0,
        'waitMode': 'minutes',
        'waitMinutes': 0.0,
        'interimMeasurements': <Object?>[
          <String, Object?>{'pressureBar': 0.0, 'temperatureC': 40.0},
        ],
      },
      'settings': <String, Object?>{
        'booster': <String, Object?>{
          'compressorInletFlowLPerMin': 100.0,
          'otherBoostBpm': 50.0,
          'oxygenBoostBpm': 50.0,
          'otherDecantRateBarPerMin': 5.0,
          'oxygenDecantRateBarPerMin': 5.0,
          'cylinderVolumeCm3': 9.0,
          'minimumSourcePressureBar': 0.0,
        },
      },
      'banks': <Object?>[],
    });

    expect(result['feasible'], isTrue);
    expect(
      _num(_obj(result['thermal'])['finalAmbientPressureBar']),
      closeTo(95, 1e-5),
    );
    final wait = _firstWhereOrNull(
      _objs(result['protocolSteps']),
      (step) => _truthy(step['automaticWaitMetadata']),
    );
    expect(wait, isNotNull);
    final metadata = _obj(wait!['automaticWaitMetadata']);
    expect(metadata['configuredWaitMinutes'], equals(0));
    expect(_num(metadata['addedWaitMinutes']), greaterThan(0));
    expect(
      metadata['actualWaitMinutes'],
      equals(_obj(wait['thermal'])['waitMinutes']),
    );
    final transfer = _firstWhereOrNull(
      _objs(result['protocolSteps']),
      (step) => step['type'] == 'boost',
    );
    expect(transfer, isNotNull);
    final transferThermal = _obj(transfer!['thermal']);
    expect(
      transferThermal['measuredStartPressureBar'],
      equals(transferThermal['pressureStartBar']),
    );
    expect(transferThermal['measuredStartTemperatureC'], isNot(equals(40)));
    expect(
      transferThermal['measuredStartTemperatureC'],
      equals(transferThermal['temperatureStartC']),
    );
    expect(metadata['warning'], equals('!'));
    for (final step in _objs(result['protocolSteps'])) {
      if (step['thermal'] == null) {
        continue;
      }
      final pressures = _thermalPressuresForCap(_obj(step['thermal']));
      expect(
        pressures.every((pressure) => pressure <= 100 + 1e-7),
        isTrue,
        reason: '${step['title']}',
      );
    }
  });

  test('Warning mode ignores cylinder-only thermal waits but retains equipment caps', () {
    final result = optimizeBlend(_warningInput());
    expect(result['feasible'], isTrue, reason: '${result['error']}');
    expect(
      _num(_obj(result['thermal'])['finalTransferEndPressureBar']),
      greaterThan(100),
    );
    expect(
      _objs(result['protocolSteps'])
          .any((step) => _truthy(step['automaticWaitMetadata'])),
      isFalse,
    );
    expect(
      _objs(result['protocolSteps'])
          .where(
            (step) =>
                step['thermal'] != null &&
                _obj(step['thermal'])['rateSource'] == 'compressor',
          )
          .length,
      equals(1),
    );

    final capped = optimizeBlend(_warningInput(100));
    expect(capped['feasible'], isFalse);
    final cappedMaximum = _obj(capped['maximumPressure']);
    expect(cappedMaximum, isNotEmpty);
    expect(_num(cappedMaximum['pressureBar']), lessThanOrEqualTo(100 + 1e-6));
  });

  test('optimizeBlend returns a feasible split protocol with safe endpoints and target pressure', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 12,
        initialPressureBar: 0,
        initialOxygenPercent: 0,
        initialHeliumPercent: 0,
        targetPressureBar: 96,
        targetOxygenPercent: 0,
        targetHeliumPercent: 0,
        workingPressureBar: 100,
        hotOverfillPercent: 0,
      ),
      'physics': _idealPhysics(),
      'thermal': _thermalAirWait(
        inletTemperatureC: 40,
        targetMediumTemperatureC: 20,
        targetInWaterTemperatureC: 20,
        waitMinutes: 0,
      ),
      'settings': <String, Object?>{
        'booster': <String, Object?>{
          'otherBoostBpm': 50.0,
          'oxygenBoostBpm': 50.0,
          'otherDecantRateBarPerMin': 5.0,
          'oxygenDecantRateBarPerMin': 5.0,
          'cylinderVolumeCm3': 9.0,
          'minimumSourcePressureBar': 0.0,
        },
      },
      'banks': <Object?>[
        _bank(
          id: 'nitrogen',
          name: 'Nitrogen',
          volumeL: 12,
          pressureBar: 300,
          minimumPressureBar: 0,
          oxygenPercent: 0,
          heliumPercent: 0,
        ),
      ],
    });

    expect(result['feasible'], isTrue);
    expect(
      _num(_obj(result['thermal'])['finalAmbientPressureBar']),
      closeTo(96, 1e-5),
    );
    final transferStages = _objs(result['protocolSteps'])
        .where((step) => step['type'] == 'decant')
        .toList();
    expect(transferStages.length, equals(2));
    final transferPoints = _objs(result['trajectory'])
        .where((point) => _truthy(point['bankId']))
        .toList();
    expect(transferPoints.length, equals(2));
    for (var index = 0; index < transferStages.length; index += 1) {
      final stage = transferStages[index];
      final point = transferPoints[index];
      final stageThermal = _obj(stage['thermal']);
      expect(point['pressureBar'], equals(stage['resultingPressureBar']));
      expect(
        point['oxygenPercent'],
        equals(_obj(stage['resultingMix'])['oxygenPercent']),
      );
      expect(
        point['heliumPercent'],
        equals(_obj(stage['resultingMix'])['heliumPercent']),
      );
      expect(
        point['pressureAtTransferEndReferenceBar'],
        equals(stageThermal['pressureAtTransferEndReferenceBar']),
      );
      expect(
        point['pressureAtTransferEndAmbientBar'],
        equals(stageThermal['pressureAtTransferEndAmbientBar']),
      );
      expect(
        point['pressureAtTransferEndHotBar'],
        equals(stageThermal['pressureAtTransferEndHotBar']),
      );
    }
    expect(
      transferPoints.last['hotPressureBar'],
      equals(_obj(result['thermal'])['finalTransferEndPressureBar']),
    );
    final safetyWait = _firstWhereOrNull(
      _objs(result['protocolSteps']),
      (step) => _truthy(step['automaticWaitMetadata']),
    );
    expect(safetyWait, isNotNull);
    expect(_obj(safetyWait!['automaticWaitMetadata'])['warning'], equals('!'));
    for (final step in _objs(result['protocolSteps'])) {
      if (step['thermal'] == null) {
        continue;
      }
      final pressures = _thermalPressuresForCap(_obj(step['thermal']));
      expect(
        pressures.every((pressure) => pressure <= 100 + 1e-7),
        isTrue,
        reason: '${step['title']}',
      );
    }
  });

  test('two scheduler-split transfers preserve stage order, inventories, and thermal safety', () {
    const double workingPressureBar = 99.01;
    const double targetPressureBar = 99;
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 12,
        initialPressureBar: 95,
        initialOxygenPercent: 0,
        initialHeliumPercent: 0,
        targetPressureBar: targetPressureBar,
        targetOxygenPercent: 4,
        targetHeliumPercent: 0.2,
        workingPressureBar: workingPressureBar,
        hotOverfillPercent: 0,
      ),
      'physics': _idealPhysics(),
      'thermal': _thermalAirWait(
        inletTemperatureC: 40,
        targetMediumTemperatureC: 20,
        targetInWaterTemperatureC: 20,
        waitMinutes: 0,
      ),
      'settings': <String, Object?>{
        'booster': <String, Object?>{
          'otherBoostBpm': 50.0,
          'oxygenBoostBpm': 50.0,
          'otherDecantRateBarPerMin': 5.0,
          'oxygenDecantRateBarPerMin': 5.0,
          'cylinderVolumeCm3': 9.0,
          'minimumSourcePressureBar': 0.0,
        },
      },
      'banks': <Object?>[
        _bank(
          id: 'o2',
          name: 'Oxygen',
          volumeL: 12,
          pressureBar: 300,
          minimumPressureBar: 0,
          oxygenPercent: 100,
          heliumPercent: 0,
        ),
        _bank(
          id: 'he',
          name: 'Helium',
          volumeL: 12,
          pressureBar: 300,
          minimumPressureBar: 0,
          oxygenPercent: 0,
          heliumPercent: 100,
        ),
      ],
    });

    expect(result['feasible'], isTrue, reason: '${result['error']}');
    expect(
      _num(_obj(result['thermal'])['finalAmbientPressureBar']),
      closeTo(targetPressureBar, 1e-5),
    );
    final transferStages = _objs(result['protocolSteps'])
        .where((step) => _truthy(step['_thermalSplit']))
        .toList();
    expect(transferStages.length, equals(4));
    expect(
      transferStages.map((step) => step['recipeGas']).toList(),
      equals(<Object?>['Oxygen', 'Oxygen', 'Helium', 'Helium']),
    );
    expect(
      transferStages
          .map(
            (step) =>
                RegExp(r'safe stage [12]')
                    .firstMatch(_str(step['title']))
                    ?.group(0),
          )
          .toList(),
      equals(<String?>[
        'safe stage 1',
        'safe stage 2',
        'safe stage 1',
        'safe stage 2',
      ]),
    );

    final transferPoints = _objs(result['trajectory'])
        .where((point) => _truthy(point['bankId']))
        .toList();
    expect(transferPoints.length, equals(transferStages.length));
    for (var index = 0; index < transferStages.length; index += 1) {
      final stage = transferStages[index];
      final point = transferPoints[index];
      final stageThermal = _obj(stage['thermal']);
      expect(point['pressureBar'], equals(stage['resultingPressureBar']));
      expect(
        point['oxygenPercent'],
        equals(_obj(stage['resultingMix'])['oxygenPercent']),
      );
      expect(
        point['heliumPercent'],
        equals(_obj(stage['resultingMix'])['heliumPercent']),
      );
      expect(
        point['pressureAtTransferEndReferenceBar'],
        equals(stageThermal['pressureAtTransferEndReferenceBar']),
      );
      expect(
        point['pressureAtTransferEndAmbientBar'],
        equals(stageThermal['pressureAtTransferEndAmbientBar']),
      );
      expect(
        point['pressureAtTransferEndHotBar'],
        equals(stageThermal['pressureAtTransferEndHotBar']),
      );
      expect(
        point['ambientPressureBar'],
        equals(stageThermal['pressureAtTransferEndAmbientBar']),
      );
      expect(
        point['hotPressureBar'],
        equals(stageThermal['pressureAtTransferEndHotBar']),
      );
    }

    for (final pair in <List<int>>[
      <int>[0, 1],
      <int>[2, 3],
    ]) {
      final firstStage = transferStages[pair[0]];
      final secondStage = transferStages[pair[1]];
      expect(
        secondStage['sourceStartMoles'],
        equals(firstStage['sourceEndMoles']),
      );
      expect(
        (_num(firstStage['sourceStartMoles']) -
                _num(firstStage['sourceConsumedMoles']) -
                _num(firstStage['sourceEndMoles']))
            .abs(),
        lessThan(1e-9),
      );
      expect(
        (_num(secondStage['sourceStartMoles']) -
                _num(secondStage['sourceConsumedMoles']) -
                _num(secondStage['sourceEndMoles']))
            .abs(),
        lessThan(1e-9),
      );
      expect(
        secondStage['receiverStartMoles'],
        equals(firstStage['receiverEndMoles']),
      );
    }
    expect(
      transferStages[2]['receiverStartMoles'],
      equals(transferStages[1]['receiverEndMoles']),
    );

    final pressures = <double>[];
    for (final step in _objs(result['protocolSteps'])) {
      final thermalValue = step['thermal'];
      if (thermalValue == null) {
        continue;
      }
      final thermal = _obj(thermalValue);
      final values = <Object?>[
        thermal['pressureStartBar'],
        thermal['pressureAtTransferEndReferenceBar'],
        thermal['pressureAtTransferEndAmbientBar'],
        thermal['pressureAtTransferEndHotBar'],
        thermal['pressureAfterWaitBar'],
        for (final sample in _objs(thermal['samples'])) ...<Object?>[
          sample['pressureAtTransferEndReferenceBar'],
          sample['pressureAtTransferEndAmbientBar'],
          sample['pressureAtTransferEndHotBar'],
          sample['ambientPressureBar'],
          sample['projectedPressureBar'] ?? sample['pressureBar'],
        ],
      ];
      for (final value in values) {
        if (value is num && value.isFinite) {
          pressures.add(value.toDouble());
        }
      }
    }
    expect(
      pressures.every((pressure) => pressure <= workingPressureBar + 1e-7),
      isTrue,
    );
  });

  test(
    'thermal final settling defaults to ambient before in-water projection',
    () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': _cylinder(
          volumeL: 12,
          initialPressureBar: 200,
          initialOxygenPercent: 21,
          initialHeliumPercent: 0,
          targetPressureBar: 200,
          targetOxygenPercent: 21,
          targetHeliumPercent: 0,
          workingPressureBar: 250,
        ),
        'physics': _idealPhysics(),
        'thermal': <String, Object?>{
          'tankMaterial': 'steel',
          'tankSurfaceAreaM2': steelTestAreaM2,
          'coolingMedium': 'air',
          'ambientTemperatureC': 20.0,
          'inletTemperatureC': 20.0,
          'targetMediumTemperatureC': 30.0,
          'targetInWaterTemperatureC': 10.0,
          'waitMode': 'minutes',
          'waitMinutes': 0.0,
        },
        'settings': <String, Object?>{},
        'banks': <Object?>[],
      });

      expect(result['feasible'], isTrue);
      final thermal = _obj(result['thermal']);
      expect(thermal['finalAmbientTemperatureC'], equals(20));
      expect(thermal['finalInWaterTemperatureC'], equals(10));
      expect(_num(thermal['finalInWaterPressureBar']), closeTo(200, 1e-5));
    },
  );

  test(
    'final settling remains ambient despite legacy target-temperature aliases',
    () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': _cylinder(
          volumeL: 12,
          initialPressureBar: 80,
          initialOxygenPercent: 21,
          initialHeliumPercent: 0,
          targetPressureBar: 210,
          targetOxygenPercent: 21,
          targetHeliumPercent: 0,
        ),
        'physics': _idealPhysics(),
        'thermal': <String, Object?>{
          'tankMaterial': 'steel',
          'tankSurfaceAreaM2': steelTestAreaM2,
          'coolingMedium': 'air',
          'ambientTemperatureC': 20.0,
          'waitMode': 'minutes',
          'waitMinutes': 10.0,
          'settledTemperatureC': 30.0,
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
      final thermal = _obj(result['thermal']);
      expect(_num(thermal['requestedSettledTargetPressureBar']), equals(210));
      expect(thermal['finalAmbientTemperatureC'], equals(20));
      expect(_num(thermal['finalAmbientPressureBar']), closeTo(210, 1e-5));
    },
  );

  test('projects a below-ambient water target after ambient settling', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 12,
        initialPressureBar: 50,
        initialOxygenPercent: 21,
        initialHeliumPercent: 0,
        targetPressureBar: 200,
        targetOxygenPercent: 18,
        targetHeliumPercent: 45,
      ),
      'physics': <String, Object?>{'model': 'vdw', 'temperatureC': 25.0},
      'thermal': <String, Object?>{
        'tankMaterial': 'steel',
        'tankSurfaceAreaM2': steelTestAreaM2,
        'coolingMedium': 'water',
        'ambientTemperatureC': 25.0,
        'inletTemperatureC': 25.0,
        'targetMediumTemperatureC': 25.0,
        'targetInWaterTemperatureC': 15.0,
        'waitMode': 'minutes',
        'waitMinutes': 10.0,
        'targetTemperatureC': 15.0,
      },
      'banks': <Object?>[
        _bank(
          id: '1845',
          name: '18/45',
          volumeL: 50,
          pressureBar: 200,
          maxPressureBar: 350,
          minimumPressureBar: 20,
          oxygenPercent: 18,
          heliumPercent: 45,
        ),
      ],
      'settings': <String, Object?>{
        'booster': <String, Object?>{
          'minimumSourcePressureBar': 0.0,
          'maxCompressorPressureBar': 350.0,
          'maxBoosterOutputPressureBar': 350.0,
          'cylinderVolumeCm3': 9.0,
          'oxygenBoostBpm': 50.0,
          'otherBoostBpm': 50.0,
          'oxygenDecantRateBarPerMin': 5.0,
          'otherDecantRateBarPerMin': 5.0,
          'compressorInletFlowLPerMin': 100.0,
        },
      },
    });

    expect(result['feasible'], isTrue);
    final thermal = _obj(result['thermal']);
    expect(thermal['finalAmbientTemperatureC'], equals(25));
    expect(thermal['finalInWaterTemperatureC'], equals(15));
    expect(
      (_num(thermal['finalAmbientPressureBar']) -
              _num(thermal['ambientSettledTargetPressureBar']))
          .abs(),
      lessThan(1e-5),
    );
    expect(
      (_num(thermal['finalInWaterPressureBar']) - 200).abs(),
      lessThan(1e-5),
    );
  });

  test(
    'fixed-minute waits allow a hidden target temperature below ambient',
    () {
      final result = optimizeBlend(<String, Object?>{
        'cylinder': _cylinder(
          volumeL: 12,
          initialPressureBar: 80,
          initialOxygenPercent: 21,
          initialHeliumPercent: 0,
          targetPressureBar: 210,
          targetOxygenPercent: 21,
          targetHeliumPercent: 0,
        ),
        'physics': _idealPhysics(),
        'thermal': <String, Object?>{
          'tankMaterial': 'steel',
          'tankSurfaceAreaM2': steelTestAreaM2,
          'coolingMedium': 'air',
          'ambientTemperatureC': 30.0,
          'inletTemperatureC': 29.0,
          'targetMediumTemperatureC': 30.0,
          'targetInWaterTemperatureC': 25.0,
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
    },
  );

  test('excludes helium from an initial mix that is 98% helium or richer', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 12,
        initialPressureBar: 80,
        initialOxygenPercent: 0,
        initialHeliumPercent: 98,
        targetPressureBar: 80,
        targetOxygenPercent: 0,
        targetHeliumPercent: 98,
      ),
      'physics': _idealPhysics(),
      'banks': <Object?>[],
      'settings': _defaultSettingsMap(),
    });

    expect(result['feasible'], isTrue);
    expect(_num(_obj(result['blend'])['heliumSalvagedLitres']), equals(0));
  });

  test('reports retained helium ungated, even for an initial mix 98% helium or richer', () {
    final result = optimizeBlend(<String, Object?>{
      'cylinder': _cylinder(
        volumeL: 12,
        initialPressureBar: 80,
        initialOxygenPercent: 0,
        initialHeliumPercent: 98,
        targetPressureBar: 80,
        targetOxygenPercent: 0,
        targetHeliumPercent: 98,
      ),
      'physics': _idealPhysics(),
      'banks': <Object?>[],
      'settings': _defaultSettingsMap(),
    });

    expect(result['feasible'], isTrue);
    final blend = _obj(result['blend']);
    expect(_num(blend['heliumSalvagedLitres']), equals(0));
    // Ideal gas, nothing vented: retained moles = 80 bar × 12 L / (R × T), so retained He litres = 80 × 12 × 0.98.
    expect(
      (_num(blend['heliumRetainedLitres']) - 80 * 12 * 0.98).abs(),
      lessThan(1e-6),
      reason: '${blend['heliumRetainedLitres']}',
    );
  });
}

// ---------------------------------------------------------------------------
// Helpers. Each mirrors a JS literal or JS idiom used in the ported tests.
// ---------------------------------------------------------------------------

Map<String, Object?> _obj(Object? value) => _jsMap(value);

List<Map<String, Object?>> _objs(Object? value) {
  if (value == null) {
    return <Map<String, Object?>>[];
  }
  return <Map<String, Object?>>[
    for (final item in value as List<Object?>) _jsMap(item),
  ];
}

// The lib returns typed protocol, thermal, sample, mix, and tableau objects.
// These adapters expose them under the JS key names the ported assertions use.
Map<String, Object?> _jsMap(Object? value) => switch (value) {
  final Map<String, Object?> map => map,
  final ProtocolStep step => _protocolStepJs(step),
  final ThermalStep state => _thermalStepJs(state),
  final ThermalSample sample => _thermalSampleJs(sample),
  final SimplexStep step => _simplexStepJs(step),
  _ => throw ArgumentError.value(value, 'value', 'not a JS-shaped object'),
};

Map<String, Object?>? _mixJs(GasMixPercent? mix) => mix == null
    ? null
    : <String, Object?>{
        'oxygenPercent': mix.oxygenPercent,
        'heliumPercent': mix.heliumPercent,
      };

Map<String, Object?> _protocolStepJs(ProtocolStep step) => <String, Object?>{
  'type': step.type,
  'operation': step.operation,
  'title': step.title,
  'method': step.method,
  'stage': step.stage,
  'receiverStartPressureBar': step.receiverStartPressureBar,
  'receiverEndPressureBar': step.receiverEndPressureBar,
  'resultingPressureBar': step.resultingPressureBar,
  'resultingMix': _mixJs(step.resultingMix),
  'receiverStartMix': _mixJs(step.receiverStartMix),
  'receiverVolumeL': step.receiverVolumeL,
  'sourceStartPressureBar': step.sourceStartPressureBar,
  'sourceEndPressureBar': step.sourceEndPressureBar,
  'sourcePressureBar': step.sourcePressureBar,
  'sourceOxygenPercent': step.sourceOxygenPercent,
  'sourceHeliumPercent': step.sourceHeliumPercent,
  'pressureReferenceTemperatureC': step.pressureReferenceTemperatureC,
  'pressureAtTransferEndReferenceBar': step.pressureAtTransferEndReferenceBar,
  'pressureAtTransferEndAmbientBar': step.pressureAtTransferEndAmbientBar,
  'pressureAtTransferEndHotBar': step.pressureAtTransferEndHotBar,
  'automaticWaitMinutes': step.automaticWaitMinutes,
  'waitMode': step.waitMode,
  'waitMinutes': step.waitMinutes,
  'targetTemperatureC': step.targetTemperatureC,
  '_measurementIndex': step.measurementIndex,
  '_applyInterimMeasurement': step.applyInterimMeasurement,
  'scheduledMeasuredStartPressureBar': step.scheduledMeasuredStartPressureBar,
  'scheduledMeasuredStartTemperatureC': step.scheduledMeasuredStartTemperatureC,
  '_safetyWaitOnly': step.safetyWaitOnly,
  'costOperation': step.costOperation,
  'costOperationId': step.costOperationId,
  'sourceConsumedMoles': step.sourceConsumedMoles,
  // JS sets `_thermalSplit: true` only on split transfers; absent otherwise.
  '_thermalSplit': step.thermalSplit ? true : null,
  'sourceInventory': step.sourceInventory,
  'sourceVolumeL': step.sourceVolumeL,
  'sourceStartMoles': step.sourceStartMoles,
  'sourceEndMoles': step.sourceEndMoles,
  'receiverStartMoles': step.receiverStartMoles,
  'receiverEndMoles': step.receiverEndMoles,
  'recipeGas': step.recipeGas,
  'recipeLabel': step.recipeLabel,
  'id': step.id,
  'automaticWaitMetadata': step.automaticWaitMetadata,
  'thermal': step.thermal == null ? null : _thermalStepJs(step.thermal!),
  'recipeAction': step.recipeAction,
  'sourceBankId': step.sourceBankId,
  'description': step.description,
  'pressureDeltaBar': step.pressureDeltaBar,
  'minimumSourcePressureBar': step.minimumSourcePressureBar,
  'sourceExhausted': step.sourceExhausted,
  'oxygenCompressionRatio': step.oxygenCompressionRatio,
  'badgeClass': step.badgeClass,
  'receiverBankId': step.receiverBankId,
  'receiverBankName': step.receiverBankName,
  'movedMoles': step.movedMoles,
  'movedHeliumLitres': step.movedHeliumLitres,
  'receiverEndMix': _mixJs(step.receiverEndMix),
};

Map<String, Object?> _thermalStepJs(ThermalStep state) => <String, Object?>{
  'rateSource': state.rateSource,
  'rateBarPerMin': state.rateBarPerMin,
  'durationMinutes': state.durationMinutes,
  'inletTemperatureC': state.inletTemperatureC,
  'pressureStartBar': state.pressureStartBar,
  'temperatureStartC': state.temperatureStartC,
  'temperatureAtTransferEndC': state.temperatureAtTransferEndC,
  'pressureReferenceTemperatureC': state.pressureReferenceTemperatureC,
  'pressureAtTransferEndReferenceBar': state.pressureAtTransferEndReferenceBar,
  'pressureAtTransferEndAmbientBar': state.pressureAtTransferEndAmbientBar,
  'waitMinutes': state.waitMinutes,
  'temperatureAfterWaitC': state.temperatureAfterWaitC,
  'pressureAtTransferEndBar': state.pressureAtTransferEndBar,
  'pressureAtTransferEndHotBar': state.pressureAtTransferEndHotBar,
  'pressureAfterWaitBar': state.pressureAfterWaitBar,
  'samples': <Map<String, Object?>>[
    for (final sample in state.samples) _thermalSampleJs(sample),
  ],
  'plannedStartPressureBar': state.plannedStartPressureBar,
  'plannedStartTemperatureC': state.plannedStartTemperatureC,
  'measurementIndex': state.measurementIndex,
  'measurementApplied': state.measurementApplied,
  'measuredStartPressureBar': state.measuredStartPressureBar,
  'measuredStartTemperatureC': state.measuredStartTemperatureC,
  'receiverStartMix': _mixJs(state.receiverStartMix),
  'configuredWaitMinutes': state.configuredWaitMinutes,
  'automaticWaitMinutes': state.automaticWaitMinutes,
  'measuredWaitMinutes': state.measuredWaitMinutes,
};

Map<String, Object?> _thermalSampleJs(
  ThermalSample sample,
) => <String, Object?>{
  'elapsedMinutes': sample.elapsedMinutes,
  'temperatureC': sample.temperatureC,
  'pressureBar': sample.pressureBar,
  'projectedPressureBar': sample.projectedPressureBar,
  'ambientPressureBar': sample.ambientPressureBar,
  'oxygenPercent': sample.oxygenPercent,
  'heliumPercent': sample.heliumPercent,
  'pressureReferenceTemperatureC': sample.pressureReferenceTemperatureC,
  'pressureAtTransferEndReferenceBar': sample.pressureAtTransferEndReferenceBar,
  'pressureAtTransferEndAmbientBar': sample.pressureAtTransferEndAmbientBar,
  'pressureAtTransferEndHotBar': sample.pressureAtTransferEndHotBar,
};

Map<String, Object?> _simplexStepJs(SimplexStep step) => <String, Object?>{
  'phase': step.phase,
  'note': step.note,
  'pivotRow': step.pivotRow,
  'pivotCol': step.pivotCol,
  'tableau': step.tableau,
  'varNames': step.varNames,
};

double _num(Object? value) => (value! as num).toDouble();

String _str(Object? value) => value! as String;

// JS truthiness for the values these tests inspect (objects, strings, booleans).
bool _truthy(Object? value) => value is bool ? value : value != null;

Map<String, Object?>? _firstWhereOrNull(
  List<Map<String, Object?>> items,
  bool Function(Map<String, Object?>) test,
) {
  for (final item in items) {
    if (test(item)) {
      return item;
    }
  }
  return null;
}

bool _titleIncludes(Object? steps, String text) =>
    _objs(steps).any((step) => _str(step['title']).contains(text));

// JS `step.thermal?.rateSource && step.thermal.rateSource !== 'none'`.
bool _rateSourceIsTransfer(Map<String, Object?> step) {
  final thermal = step['thermal'];
  if (thermal == null) {
    return false;
  }
  final rateSource = _obj(thermal)['rateSource'];
  return rateSource is String && rateSource.isNotEmpty && rateSource != 'none';
}

// The pressures the JS tests check against a cap: start, transfer-end
// endpoints, after-wait, and every sample's projected (or raw) pressure.
List<double> _thermalPressuresForCap(Map<String, Object?> thermal) {
  final values = <Object?>[
    thermal['pressureStartBar'],
    thermal['pressureAtTransferEndReferenceBar'],
    thermal['pressureAtTransferEndBar'],
    thermal['pressureAtTransferEndHotBar'],
    thermal['pressureAfterWaitBar'],
    for (final sample in _objs(thermal['samples']))
      sample['projectedPressureBar'] ?? sample['pressureBar'],
  ];
  return <double>[for (final value in values) _num(value)];
}

Map<String, Object?> _with(
  Map<String, Object?> base,
  Map<String, Object?> overrides,
) => <String, Object?>{...base, ...overrides};

Map<String, Object?> _defaultCylinder() =>
    _obj(defaultOptimizerInput()['cylinder']);

List<Map<String, Object?>> _defaultBanks() =>
    _objs(defaultOptimizerInput()['banks']);

Map<String, Object?> _idealPhysics() => <String, Object?>{
  'model': 'ideal',
  'temperatureC': 20.0,
};

Map<String, Object?> _cylinder({
  required double volumeL,
  required double initialPressureBar,
  required double initialOxygenPercent,
  required double initialHeliumPercent,
  required double targetPressureBar,
  required double targetOxygenPercent,
  required double targetHeliumPercent,
  double? workingPressureBar,
  double? hotOverfillPercent,
}) => <String, Object?>{
  'volumeL': volumeL,
  'initialPressureBar': initialPressureBar,
  'initialOxygenPercent': initialOxygenPercent,
  'initialHeliumPercent': initialHeliumPercent,
  'targetPressureBar': targetPressureBar,
  'targetOxygenPercent': targetOxygenPercent,
  'targetHeliumPercent': targetHeliumPercent,
  'workingPressureBar': ?workingPressureBar,
  'hotOverfillPercent': ?hotOverfillPercent,
};

Map<String, Object?> _bank({
  required String id,
  required String name,
  required double volumeL,
  required double pressureBar,
  double maxPressureBar = 350,
  double? minimumPressureBar,
  required double oxygenPercent,
  required double heliumPercent,
}) => <String, Object?>{
  'id': id,
  'name': name,
  'volumeL': volumeL,
  'pressureBar': pressureBar,
  'maxPressureBar': maxPressureBar,
  'minimumPressureBar': ?minimumPressureBar,
  'oxygenPercent': oxygenPercent,
  'heliumPercent': heliumPercent,
  'enabled': true,
};

Map<String, Object?> _boosterSettings({
  double? maxCompressorPressureBar,
  double? maxBoosterOutputPressureBar,
  double? minimumSourcePressureBar,
}) => <String, Object?>{
  'booster': <String, Object?>{
    'minimumSourcePressureBar': ?minimumSourcePressureBar,
    'maxCompressorPressureBar': ?maxCompressorPressureBar,
    'maxBoosterOutputPressureBar': ?maxBoosterOutputPressureBar,
  },
};
// JS `DEFAULT_SETTINGS` (js/settings.js) as the optimizer reads it: hard-stop mode and
// the full booster block. Using `{}` would fall back to 200 bar booster output, not 230.
Map<String, Object?> _defaultSettingsMap() => <String, Object?>{
  'pressureLimitMode': 'hard-stop',
  'booster': <String, Object?>{
    'minimumSourcePressureBar': 5.0,
    'cylinderVolumeCm3': 9.0,
    'oxygenBoostBpm': 35.0,
    'otherBoostBpm': 50.0,
    'oxygenDecantRateBarPerMin': 5.0,
    'otherDecantRateBarPerMin': 10.0,
    'drainingRateBarPerMin': 15.0,
    'compressorInletFlowLPerMin': 100.0,
    'maxCompressorPressureBar': 232.0,
    'maxBoosterOutputPressureBar': 230.0,
    'boosterTemperatureModifierC': 10.0,
    'compressorTemperatureModifierC': 5.0,
  },
};

// JS `oxygenTransferInput(sourcePressureBar, sourceOxygenPercent = 100)`.
Map<String, Object?> _oxygenTransferInput(
  double sourcePressureBar, [
  double sourceOxygenPercent = 100,
]) => <String, Object?>{
  'cylinder': _cylinder(
    volumeL: 10,
    initialPressureBar: 150,
    initialOxygenPercent: 0,
    initialHeliumPercent: 0,
    targetPressureBar: 200,
    targetOxygenPercent: sourceOxygenPercent * 0.25,
    targetHeliumPercent: 0,
  ),
  'physics': _idealPhysics(),
  'banks': <Object?>[
    _bank(
      id: 'oxygen-source',
      name: 'Oxygen source',
      volumeL: 10,
      pressureBar: sourcePressureBar,
      minimumPressureBar: 0,
      oxygenPercent: sourceOxygenPercent,
      heliumPercent: 0,
    ),
  ],
};

// JS `warningInput(maxCompressorPressureBar = 232)`.
Map<String, Object?> _warningInput([double maxCompressorPressureBar = 232]) =>
    <String, Object?>{
      'cylinder': _cylinder(
        volumeL: 12,
        initialPressureBar: 0,
        initialOxygenPercent: 21,
        initialHeliumPercent: 0,
        targetPressureBar: 105,
        targetOxygenPercent: 21,
        targetHeliumPercent: 0,
        workingPressureBar: 100,
        hotOverfillPercent: 0,
      ),
      'physics': _idealPhysics(),
      'thermal': <String, Object?>{
        'tankMaterial': 'steel',
        'tankSurfaceAreaM2': steelTestAreaM2,
        'coolingMedium': 'air',
        'ambientTemperatureC': 20.0,
        'inletTemperatureC': 40.0,
        'targetMediumTemperatureC': 20.0,
        'targetInWaterTemperatureC': 20.0,
        'waitMode': 'minutes',
        'waitMinutes': 0.0,
      },
      'settings': <String, Object?>{
        'pressureLimitMode': 'warning',
        'booster': <String, Object?>{
          'compressorInletFlowLPerMin': 100.0,
          'maxCompressorPressureBar': maxCompressorPressureBar,
          'maxBoosterOutputPressureBar': 230.0,
          'otherBoostBpm': 50.0,
          'oxygenBoostBpm': 50.0,
          'otherDecantRateBarPerMin': 5.0,
          'oxygenDecantRateBarPerMin': 5.0,
          'cylinderVolumeCm3': 9.0,
          'minimumSourcePressureBar': 0.0,
        },
      },
      'banks': <Object?>[],
    };

// Thermal block shared by the air-cooled split and trajectory tests.
Map<String, Object?> _thermalAirWait({
  required double inletTemperatureC,
  required double targetMediumTemperatureC,
  required double targetInWaterTemperatureC,
  required double waitMinutes,
}) => <String, Object?>{
  'tankMaterial': 'steel',
  'tankSurfaceAreaM2': steelTestAreaM2,
  'coolingMedium': 'air',
  'ambientTemperatureC': 20.0,
  'inletTemperatureC': inletTemperatureC,
  'targetMediumTemperatureC': targetMediumTemperatureC,
  'targetInWaterTemperatureC': targetInWaterTemperatureC,
  'waitMode': 'minutes',
  'waitMinutes': waitMinutes,
};

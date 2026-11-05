import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/what_if_controller.dart';
import 'package:simplex_blender/src/data/bank_storage.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/compare_recipe.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/what_if_scenario.dart';

class _RecordingAnalytics implements Analytics {
  final List<({String event, Map<String, Object> props})> calls =
      <({String event, Map<String, Object> props})>[];

  @override
  void track(String event, [Map<String, Object> props = const {}]) {
    calls.add((event: event, props: props));
  }
}

class _ThrowingAnalytics implements Analytics {
  @override
  void track(String event, [Map<String, Object> props = const {}]) {
    throw StateError('backend down');
  }
}

WhatIfStart snapshotBlending() {
  return snapshotWhatIfFromBlending(
    initialPressureBar: 50,
    initialOxygenPercent: 21,
    initialHeliumPercent: 0,
    cylinderPresetName: 'Catalina S80',
    ambientTemperatureC: 25,
    coolingMedium: 'water',
    waterSubmersionPercent: 40,
    targetInWaterTemperatureC: 10,
  );
}

WhatIfScenario initializedScenario() {
  return createWhatIfScenario().copyWith(
    initialized: true,
    start: snapshotBlending(),
  );
}

WhatIfController controllerWith(
  Analytics analytics, {
  List<Bank>? banks,
  Settings? settings,
}) {
  return WhatIfController(
    analytics: analytics,
    banks: banks ?? DEFAULT_BANKS,
    settings: settings ?? DEFAULT_SETTINGS,
    scenario: initializedScenario(),
  );
}

void main() {
  group('WhatIfController', () {
    test('a. a failed rerun keeps the last valid result', () {
      final controller = controllerWith(_RecordingAnalytics());
      expect(controller.runWhatIf(), isNull);
      final valid = controller.result;
      expect(valid, isNotNull);

      controller.applyStartPatch(
        const WhatIfStart(cylinderPresetName: 'Missing'),
      );

      expect(controller.result, same(valid));
      expect(controller.errors, isNotEmpty);
      expect(
        controller.errors,
        contains('Select an available cylinder preset.'),
      );
    });

    test('b. a failed rerun keeps the projection stale after shared inputs '
        'changed', () {
      final controller = controllerWith(_RecordingAnalytics());
      expect(controller.runWhatIf(), isNull);
      final valid = controller.result;

      controller.updateSharedInputs(
        banks: DEFAULT_BANKS,
        settings: DEFAULT_SETTINGS.copyWith(pressureLimitMode: 'warning'),
      );
      expect(controller.isStale, isTrue);

      controller.applyStartPatch(
        const WhatIfStart(cylinderPresetName: 'Missing'),
      );

      expect(controller.isStale, isTrue);
      expect(controller.result, same(valid));
      expect(controller.errors, isNotEmpty);
    });

    test('c. a non-price settings change marks a successful run stale', () {
      final controller = controllerWith(_RecordingAnalytics());
      expect(controller.runWhatIf(), isNull);
      expect(controller.isStale, isFalse);

      controller.updateSharedInputs(
        banks: DEFAULT_BANKS,
        settings: DEFAULT_SETTINGS.copyWith(pressureLimitMode: 'warning'),
      );

      expect(controller.isStale, isTrue);
    });

    test('d. a bank price change does not mark a successful run stale', () {
      final controller = controllerWith(_RecordingAnalytics());
      expect(controller.runWhatIf(), isNull);

      final repriced = <Bank>[
        for (final bank in DEFAULT_BANKS)
          bank.copyWith(pricePerLitre: () => 1.0),
      ];
      controller.updateSharedInputs(
        banks: repriced,
        settings: DEFAULT_SETTINGS,
      );

      expect(controller.isStale, isFalse);
    });

    test('e. one successful run sends exactly one what_if blend_calculated '
        'event', () {
      final analytics = _RecordingAnalytics();
      final controller = controllerWith(analytics);

      expect(controller.runWhatIf(), isNull);

      expect(analytics.calls, hasLength(1));
      expect(analytics.calls.single.event, 'blend_calculated');
      expect(analytics.calls.single.props['mode'], 'what_if');
    });

    test('f. a throwing analytics backend does not stop a successful run', () {
      final controller = WhatIfController(
        analytics: _ThrowingAnalytics(),
        banks: DEFAULT_BANKS,
        settings: DEFAULT_SETTINGS,
        scenario: initializedScenario(),
      );

      expect(controller.runWhatIf(), isNull);
      expect(controller.result, isNotNull);
      expect(controller.errors, isEmpty);
    });

    test('g. a successful run clears errors and sets the updated status', () {
      final controller = controllerWith(_RecordingAnalytics());
      controller.applyStartPatch(
        const WhatIfStart(cylinderPresetName: 'Missing'),
      );
      expect(controller.errors, isNotEmpty);

      controller.applyStartPatch(
        const WhatIfStart(cylinderPresetName: 'Catalina S80'),
      );

      expect(controller.errors, isEmpty);
      expect(controller.status, 'Scenario updated.');
      expect(controller.hasRun, isTrue);
    });

    test(
      'h. a first run that fails sets hasRun while the result stays null',
      () {
        final controller = WhatIfController(
          analytics: _RecordingAnalytics(),
          banks: DEFAULT_BANKS,
          settings: DEFAULT_SETTINGS,
          scenario: initializedScenario().copyWith(
            start: snapshotBlending().merge(
              const WhatIfStart(cylinderPresetName: 'Missing'),
            ),
          ),
        );
        expect(controller.hasRun, isFalse);

        expect(controller.runWhatIf(), isNotNull);

        expect(controller.hasRun, isTrue);
        expect(controller.result, isNull);
        expect(
          controller.errors,
          contains('Select an available cylinder preset.'),
        );
      },
    );

    test('i. a row edit after a successful run marks the projection stale', () {
      final controller = controllerWith(_RecordingAnalytics());
      expect(controller.runWhatIf(), isNull);
      final valid = controller.result;
      expect(controller.isStale, isFalse);

      controller.updateRows(<CompareRow>[
        CompareRow(
          id: 'row-1',
          type: 'add',
          bankId: 'missing-bank',
          pressureAddedBar: 10,
          targetPressureBar: 60,
          pressureInputMode: 'added',
        ),
      ]);

      expect(controller.errors, isNotEmpty);
      expect(controller.result, same(valid));
      expect(controller.isStale, isTrue);
    });

    test('j. lastRun is null after a rejected first run', () {
      final controller = WhatIfController(
        analytics: _RecordingAnalytics(),
        banks: DEFAULT_BANKS,
        settings: DEFAULT_SETTINGS,
        scenario: initializedScenario().copyWith(
          start: snapshotBlending().merge(
            const WhatIfStart(cylinderPresetName: 'Missing'),
          ),
        ),
      );

      expect(controller.runWhatIf(), isNotNull);

      expect(controller.lastRun, isNull);
    });

    test(
      'k. a successful run exposes a run whose projection matches result',
      () {
        final controller = controllerWith(_RecordingAnalytics());
        expect(controller.runWhatIf(), isNull);
        final run = controller.lastRun;
        final projection = controller.result;
        expect(run, isNotNull);
        expect(projection, isNotNull);

        final input = run!.input;
        final recomputed = projectWhatIfInWater(
          run.simulation.finalSummary.ambientSettled,
          inWaterTemperatureC: input.inWaterTemperatureC!,
          volumeL: input.cylinderPreset!.volumeL,
          useVdw: input.physicsModel == 'vdw',
        );
        expect(recomputed.pressureBar, closeTo(projection!.pressureBar, 1e-9));
        expect(recomputed.temperatureC, projection.temperatureC);
        expect(run.protocol.protocolSteps, isNotEmpty);
        expect(run.pressureLimitWarnings, same(controller.warnings));
      },
    );

    test('l. a rejected run keeps the last successful lastRun', () {
      final controller = controllerWith(_RecordingAnalytics());
      expect(controller.runWhatIf(), isNull);
      final run = controller.lastRun;
      expect(run, isNotNull);

      controller.applyStartPatch(
        const WhatIfStart(cylinderPresetName: 'Missing'),
      );

      expect(controller.lastRun, same(run));
    });

    test('m. fieldErrors carry the row and field the domain reports', () {
      final controller = controllerWith(_RecordingAnalytics());
      expect(controller.runWhatIf(), isNull);

      controller.updateRows(<CompareRow>[
        CompareRow(
          id: 'row-1',
          type: 'add',
          bankId: 'missing-bank',
          pressureAddedBar: 10,
          targetPressureBar: 60,
          pressureInputMode: 'added',
        ),
      ]);

      expect([
        for (final error in controller.fieldErrors) (error.rowId, error.field),
      ], contains(('row-1', 'bankId')));
    });

    test('n. fieldErrors messages mirror errors in order', () {
      final controller = controllerWith(_RecordingAnalytics());
      controller.applyStartPatch(
        const WhatIfStart(cylinderPresetName: 'Missing'),
      );

      expect(controller.errors, isNotEmpty);
      expect([
        for (final error in controller.fieldErrors) error.message,
      ], controller.errors);
      expect([
        for (final error in controller.fieldErrors) error.field,
      ], contains('cylinderPresetName'));
    });

    test(
      'o. a successful run reports neither shared-input nor draft change',
      () {
        final controller = controllerWith(_RecordingAnalytics());
        expect(controller.runWhatIf(), isNull);

        expect(controller.sharedInputChanged, isFalse);
        expect(controller.draftChanged, isFalse);
        expect(controller.isStale, isFalse);
      },
    );

    test('p. a shared-input change alone sets sharedInputChanged only', () {
      final controller = controllerWith(_RecordingAnalytics());
      expect(controller.runWhatIf(), isNull);

      controller.updateSharedInputs(
        banks: DEFAULT_BANKS,
        settings: DEFAULT_SETTINGS.copyWith(pressureLimitMode: 'warning'),
      );

      expect(controller.sharedInputChanged, isTrue);
      expect(controller.draftChanged, isFalse);
      expect(controller.isStale, isTrue);
    });

    test('q. a failed draft edit alone sets draftChanged only', () {
      final controller = controllerWith(_RecordingAnalytics());
      expect(controller.runWhatIf(), isNull);

      controller.updateRows(<CompareRow>[
        CompareRow(
          id: 'row-1',
          type: 'add',
          bankId: 'missing-bank',
          pressureAddedBar: 10,
          targetPressureBar: 60,
          pressureInputMode: 'added',
        ),
      ]);

      expect(controller.draftChanged, isTrue);
      expect(controller.sharedInputChanged, isFalse);
      expect(controller.isStale, isTrue);
    });

    test('r. a price-only change sets neither flag', () {
      final controller = controllerWith(_RecordingAnalytics());
      expect(controller.runWhatIf(), isNull);

      controller.updateSharedInputs(
        banks: <Bank>[
          for (final bank in DEFAULT_BANKS)
            bank.copyWith(pricePerLitre: () => 1.0),
        ],
        settings: DEFAULT_SETTINGS,
      );

      expect(controller.sharedInputChanged, isFalse);
      expect(controller.draftChanged, isFalse);
      expect(controller.isStale, isFalse);
    });

    test('s. isStale is the OR of sharedInputChanged and draftChanged', () {
      final controller = controllerWith(_RecordingAnalytics());
      expect(controller.runWhatIf(), isNull);

      controller.updateSharedInputs(
        banks: DEFAULT_BANKS,
        settings: DEFAULT_SETTINGS.copyWith(pressureLimitMode: 'warning'),
      );
      controller.updateRows(<CompareRow>[
        CompareRow(
          id: 'row-1',
          type: 'add',
          bankId: 'missing-bank',
          pressureAddedBar: 10,
          targetPressureBar: 60,
          pressureInputMode: 'added',
        ),
      ]);

      expect(controller.sharedInputChanged, isTrue);
      expect(controller.draftChanged, isTrue);
      expect(controller.isStale, isTrue);
    });

    test('t. a successful rerun clears both flags', () {
      final controller = controllerWith(_RecordingAnalytics());
      expect(controller.runWhatIf(), isNull);
      controller.updateSharedInputs(
        banks: DEFAULT_BANKS,
        settings: DEFAULT_SETTINGS.copyWith(pressureLimitMode: 'warning'),
      );
      expect(controller.sharedInputChanged, isTrue);

      controller.applyStartPatch(const WhatIfStart(pressureBar: 45));

      expect(controller.sharedInputChanged, isFalse);
      expect(controller.draftChanged, isFalse);
      expect(controller.isStale, isFalse);
    });

    test(
      'u. the gas composition error is reported under oxygen and helium',
      () {
        final controller = controllerWith(_RecordingAnalytics());
        controller.applyStartPatch(
          const WhatIfStart(oxygenPercent: 60, heliumPercent: 60),
        );

        expect(
          [
            for (final error in controller.fieldErrors)
              if (error.message.startsWith('Initial oxygen and helium'))
                error.field,
          ],
          <String?>['oxygenPercent', 'heliumPercent'],
        );
      },
    );

    test('v. an invalid initial pressure is reported under pressureBar', () {
      final controller = controllerWith(_RecordingAnalytics());
      controller.applyStartPatch(const WhatIfStart(pressureBar: -1));

      expect(
        [
          for (final error in controller.fieldErrors)
            (error.field, error.message),
        ],
        contains((
          'pressureBar',
          'Initial pressure must be between 0 and 350 bar.',
        )),
      );
    });

    test(
      'w. an invalid ambient temperature is reported under ambientTemperatureC',
      () {
        final controller = controllerWith(_RecordingAnalytics());
        controller.applyStartPatch(const WhatIfStart(ambientTemperatureC: 2));

        expect(
          [
            for (final error in controller.fieldErrors)
              (error.field, error.message),
          ],
          contains((
            'ambientTemperatureC',
            'Thermal ambient temperature must be between 5 and 40°C.',
          )),
        );
      },
    );

    test('x. an unmapped calculator error is reported under scenario', () {
      final controller = controllerWith(_RecordingAnalytics());
      controller.setInletTemperatureC(2);

      expect(controller.runWhatIf(), isNotNull);
      expect(
        [
          for (final error in controller.fieldErrors)
            (error.field, error.message),
        ],
        contains((
          'scenario',
          'Thermal inlet gas temperature must be between 5 and 40°C.',
        )),
      );
    });
  });
}

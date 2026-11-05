import 'package:flutter_test/flutter_test.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/data/bank_storage.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/interim_check.dart';
import 'package:simplex_blender/src/domain/pressure_limits.dart';
import 'package:simplex_blender/src/domain/pure_prices.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';

// Source of truth: docs/architecture.md (interim readings, cost derivation,
// bank pricing suggestions) and
// js/main.js (recalculate, applyInterimMeasurement, clearInterimMeasurement,
// bankSuggestionFor).
//
// Adapted inputs:
// - JS reads the DOM; Dart takes a BlendInputs value with the same fields.
// - JS inventory and settings are module state; Dart passes them to the
//   constructor and to updateSharedInputs, as AppController does.

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

CylinderPreset _catalinaS80() => DEFAULT_SETTINGS.cylinderPresets.firstWhere(
  (preset) => preset.name == 'Catalina S80',
);

BlendInputs _defaultInputs() => BlendInputs(
  cylinderPreset: _catalinaS80(),
  initialPressureBar: 50,
  initialOxygenPercent: 21,
  initialHeliumPercent: 0,
  targetPressureBar: 195,
  targetOxygenPercent: 18,
  targetHeliumPercent: 45,
  ambientTemperatureC: 21,
  targetInWaterTemperatureC: 10,
  waitTargetTemperatureC: 25,
  inletTemperatureC: 21,
  coolingMedium: 'water',
  waterSubmersionPercent: 40,
  waitMode: 'minutes',
  waitMinutes: 5,
);

// Reading that the plan accepts: the planned start state of a measured step.
InterimReading _plannedReading(BlendController controller, int index) {
  final steps = controller.lastResult!['protocolSteps']! as List<ProtocolStep>;
  final step = steps.firstWhere((step) => step.measurementIndex == index);
  final thermal = step.thermal!;
  return (
    pressureBar: thermal.pressureStartBar,
    temperatureC: thermal.temperatureStartC,
  );
}

BlendController _controller({
  required List<Bank> bankList,
  required Settings settings,
  BlendInputs? inputs,
  Analytics? analytics,
}) {
  return BlendController(
    inputs: inputs ?? _defaultInputs(),
    banks: bankList,
    settings: settings,
    updateBank: (updated) {
      final index = bankList.indexWhere((bank) => bank.id == updated.id);
      bankList[index] = updated;
    },
    analytics: analytics ?? NoopAnalytics(),
  );
}

void main() {
  test('optimize with the default inventory is feasible', () {
    final controller = _controller(
      bankList: List<Bank>.of(DEFAULT_BANKS),
      settings: DEFAULT_SETTINGS,
    );

    expect(controller.lastResult, isNotNull);
    expect(controller.lastResult!['feasible'], isTrue);
    expect(controller.lastInput, isNotNull);
  });

  test(
    'a successful Optimize sends one blend_calculated event with mode optimize',
    () {
      final analytics = _RecordingAnalytics();
      _controller(
        bankList: List<Bank>.of(DEFAULT_BANKS),
        settings: DEFAULT_SETTINGS,
        analytics: analytics,
      );

      expect(analytics.calls, hasLength(1));
      expect(analytics.calls.single.event, 'blend_calculated');
      expect(analytics.calls.single.props, <String, Object>{
        'mode': 'optimize',
        'outcome': 'feasible',
      });
    },
  );

  test('changing a recipe input clears the interim readings', () {
    final controller = _controller(
      bankList: List<Bank>.of(DEFAULT_BANKS),
      settings: DEFAULT_SETTINGS,
    );
    expect(
      controller.applyInterimMeasurement(0, _plannedReading(controller, 0)),
      isNull,
    );
    expect(
      controller.interimMeasurements.whereType<InterimMeasurement>(),
      isNotEmpty,
    );

    controller.setInputs(_defaultInputs().copyWith(targetPressureBar: 190));

    expect(
      controller.interimMeasurements.whereType<InterimMeasurement>(),
      isEmpty,
    );
    expect(controller.interimMeasurementSignature, isNull);
  });

  test('changing a bank price keeps the interim readings', () {
    final bankList = List<Bank>.of(DEFAULT_BANKS);
    final controller = _controller(
      bankList: bankList,
      settings: DEFAULT_SETTINGS,
    );
    expect(
      controller.applyInterimMeasurement(0, _plannedReading(controller, 0)),
      isNull,
    );

    final index = bankList.indexWhere((bank) => bank.id == 'bank-oxygen');
    bankList[index] = bankList[index].copyWith(pricePerLitre: () => 0.5);
    controller.updateSharedInputs(banks: bankList, settings: DEFAULT_SETTINGS);

    expect(controller.interimMeasurements[0], isNotNull);
  });

  test('only the latest interim reading can be cleared; earlier readings are locked', () {
    final controller = _controller(
      bankList: List<Bank>.of(DEFAULT_BANKS),
      settings: DEFAULT_SETTINGS,
    );
    final measuredSteps =
        (controller.lastResult!['protocolSteps']! as List<ProtocolStep>)
            .where((step) => step.measurementIndex != null)
            .toList();
    expect(measuredSteps.length, greaterThanOrEqualTo(2));

    expect(
      controller.applyInterimMeasurement(0, _plannedReading(controller, 0)),
      isNull,
    );
    expect(
      controller.applyInterimMeasurement(1, _plannedReading(controller, 1)),
      isNull,
    );

    expect(
      controller.clearInterimMeasurement(0),
      'Step 1 is locked. Only the latest reading (step 2) can be changed or cleared.',
    );
    expect(controller.interimMeasurements[0], isNotNull);
    expect(controller.clearInterimMeasurement(1), isNull);
    expect(controller.interimMeasurements[1], isNull);
  });

  test('cost summary follows the current bank prices without re-running the optimizer', () {
    final bankList = List<Bank>.of(DEFAULT_BANKS);
    final controller = _controller(
      bankList: bankList,
      settings: DEFAULT_SETTINGS,
    );
    final resultBefore = controller.lastResult;

    final before = controller.blendingCost();
    expect(before, isNotNull);

    for (var index = 0; index < bankList.length; index++) {
      bankList[index] = bankList[index].copyWith(pricePerLitre: () => 2.0);
    }
    controller.updateSharedInputs(banks: bankList, settings: DEFAULT_SETTINGS);

    expect(identical(controller.lastResult, resultBefore), isFalse);
    final after = controller.blendingCost();
    expect(after, isNotNull);
    expect(after!.total, isNot(before!.total));
    final steps =
        (controller.lastResult!['protocolSteps']! as List<ProtocolStep>);
    final expected = computeFillCost(
      steps: [
        for (final step in steps)
          FillStep(
            costOperation: step.costOperation,
            costOperationId: step.costOperationId,
            sourceBankId: step.sourceBankId,
            sourceBankName: null,
            recipeGas: step.recipeGas,
            sourceConsumedMoles: step.sourceConsumedMoles,
          ),
      ],
      banks: bankList,
      costs: DEFAULT_SETTINGS.costs,
      temperatureC: 21,
    );
    expect(after.total, expected.total);
  });

  test(
    'a bank price suggestion is dropped when the pricing signature changes',
    () {
      final bankList = List<Bank>.of(DEFAULT_BANKS);
      var currentSettings = DEFAULT_SETTINGS;
      final controller = BlendController(
        inputs: _defaultInputs(),
        banks: bankList,
        settings: currentSettings,
        updateBank: (updated) {
          final index = bankList.indexWhere((bank) => bank.id == updated.id);
          bankList[index] = updated;
        },
        analytics: NoopAnalytics(),
      );
      final bank = bankList.firstWhere(
        (bank) => !isPureBank(bank) && bank.oxygenPercent != 21,
      );

      controller.calculateBankPrice(bank.id);
      expect(controller.bankSuggestionFor(bank.id), isNotNull);

      currentSettings = currentSettings.copyWith(pressureLimitMode: 'warning');
      controller.updateSharedInputs(banks: bankList, settings: currentSettings);
      expect(controller.bankSuggestionFor(bank.id), isNull);
    },
  );

  test('toggling a bank drops its price suggestion even when the pricing signature still matches', () {
    final bankList = List<Bank>.of(DEFAULT_BANKS);
    final controller = BlendController(
      inputs: _defaultInputs(),
      banks: bankList,
      settings: DEFAULT_SETTINGS,
      updateBank: (updated) {
        final index = bankList.indexWhere((bank) => bank.id == updated.id);
        bankList[index] = updated;
      },
      analytics: NoopAnalytics(),
    );
    final index = bankList.indexWhere(
      (bank) => !isPureBank(bank) && bank.oxygenPercent != 21,
    );
    final bank = bankList[index];

    controller.calculateBankPrice(bank.id);
    expect(controller.bankSuggestionFor(bank.id), isNotNull);

    // JS `toggle-bank` sets `enabled`, then unconditionally deletes
    // `state.bankSuggestions[bank.id]`. `enabled` is not in the signature,
    // so the signature check alone would keep the suggestion.
    final toggled = bank.copyWith(enabled: !bank.enabled);
    expect(
      controller.bankPricingSignature(toggled),
      controller.bankPricingSignature(bank),
    );
    bankList[index] = toggled;
    controller.updateSharedInputs(banks: bankList, settings: DEFAULT_SETTINGS);

    expect(controller.bankSuggestionFor(bank.id), isNull);
  });

  test('an Optimize run in warning mode carries pressure limit warnings', () {
    final controller = _controller(
      bankList: List<Bank>.of(DEFAULT_BANKS),
      settings: DEFAULT_SETTINGS.copyWith(
        pressureLimitMode: 'warning',
        pressureWarningUnlocked: true,
      ),
      inputs: _defaultInputs().copyWith(
        cylinderPreset: _catalinaS80().copyWith(workingPressureBar: 100),
      ),
    );

    final warnings =
        controller.lastResult!['pressureLimitWarnings']!
            as List<CylinderPressureWarning>;
    expect(warnings, isNotEmpty);
  });

  test(
    'an Optimize run in the default mode carries no pressure limit warnings',
    () {
      final controller = _controller(
        bankList: List<Bank>.of(DEFAULT_BANKS),
        settings: DEFAULT_SETTINGS,
        inputs: _defaultInputs().copyWith(
          cylinderPreset: _catalinaS80().copyWith(workingPressureBar: 100),
        ),
      );

      final warnings =
          controller.lastResult!['pressureLimitWarnings']!
              as List<CylinderPressureWarning>;
      expect(warnings, isEmpty);
    },
  );
}

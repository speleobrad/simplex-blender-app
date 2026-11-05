import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/analytics/analytics_events.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/bank_pricing.dart';
import 'package:simplex_blender/src/domain/calculator_input.dart';
import 'package:simplex_blender/src/domain/cost.dart';
import 'package:simplex_blender/src/domain/input_validation.dart';
import 'package:simplex_blender/src/domain/interim_check.dart';
import 'package:simplex_blender/src/domain/interim_measurements.dart';
import 'package:simplex_blender/src/domain/plan_with_readings.dart';
import 'package:simplex_blender/src/domain/pressure_warnings.dart';
import 'package:simplex_blender/src/domain/pure_prices.dart';
import 'package:simplex_blender/src/domain/savings.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/settings_json.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/domain/blend_defaults.dart';

/// Blending screen form values (JS `readInput`), in internal metric units.
/// [inletTemperatureC] is the effective inlet temperature (JS
/// `effectiveInletTemperatureC()`), already resolved by the caller.
class BlendInputs {
  const BlendInputs({
    required this.cylinderPreset,
    required this.initialPressureBar,
    required this.initialOxygenPercent,
    required this.initialHeliumPercent,
    required this.targetPressureBar,
    required this.targetOxygenPercent,
    required this.targetHeliumPercent,
    required this.ambientTemperatureC,
    required this.targetInWaterTemperatureC,
    required this.waitTargetTemperatureC,
    required this.inletTemperatureC,
    required this.coolingMedium,
    required this.waterSubmersionPercent,
    required this.waitMode,
    required this.waitMinutes,
  });

  final CylinderPreset cylinderPreset;
  final double initialPressureBar;
  final double initialOxygenPercent;
  final double initialHeliumPercent;
  final double targetPressureBar;
  final double targetOxygenPercent;
  final double targetHeliumPercent;
  final double ambientTemperatureC;
  final double targetInWaterTemperatureC;
  final double waitTargetTemperatureC;
  final double inletTemperatureC;
  final String coolingMedium;
  final double waterSubmersionPercent;
  final String waitMode;
  final double waitMinutes;

  BlendInputs copyWith({
    CylinderPreset? cylinderPreset,
    double? initialPressureBar,
    double? initialOxygenPercent,
    double? initialHeliumPercent,
    double? targetPressureBar,
    double? targetOxygenPercent,
    double? targetHeliumPercent,
    double? ambientTemperatureC,
    double? targetInWaterTemperatureC,
    double? waitTargetTemperatureC,
    double? inletTemperatureC,
    String? coolingMedium,
    double? waterSubmersionPercent,
    String? waitMode,
    double? waitMinutes,
  }) {
    return BlendInputs(
      cylinderPreset: cylinderPreset ?? this.cylinderPreset,
      initialPressureBar: initialPressureBar ?? this.initialPressureBar,
      initialOxygenPercent: initialOxygenPercent ?? this.initialOxygenPercent,
      initialHeliumPercent: initialHeliumPercent ?? this.initialHeliumPercent,
      targetPressureBar: targetPressureBar ?? this.targetPressureBar,
      targetOxygenPercent: targetOxygenPercent ?? this.targetOxygenPercent,
      targetHeliumPercent: targetHeliumPercent ?? this.targetHeliumPercent,
      ambientTemperatureC: ambientTemperatureC ?? this.ambientTemperatureC,
      targetInWaterTemperatureC:
          targetInWaterTemperatureC ?? this.targetInWaterTemperatureC,
      waitTargetTemperatureC:
          waitTargetTemperatureC ?? this.waitTargetTemperatureC,
      inletTemperatureC: inletTemperatureC ?? this.inletTemperatureC,
      coolingMedium: coolingMedium ?? this.coolingMedium,
      waterSubmersionPercent:
          waterSubmersionPercent ?? this.waterSubmersionPercent,
      waitMode: waitMode ?? this.waitMode,
      waitMinutes: waitMinutes ?? this.waitMinutes,
    );
  }

  /// Builds the initial Blending form values from [defaultBlendInputs].
  factory BlendInputs.fromDefaults(BlendInputDefaults defaults) {
    return BlendInputs(
      cylinderPreset: defaults.cylinderPreset,
      initialPressureBar: defaults.initialPressureBar,
      initialOxygenPercent: defaults.initialOxygenPercent,
      initialHeliumPercent: defaults.initialHeliumPercent,
      targetPressureBar: defaults.targetPressureBar,
      targetOxygenPercent: defaults.targetOxygenPercent,
      targetHeliumPercent: defaults.targetHeliumPercent,
      ambientTemperatureC: defaults.ambientTemperatureC,
      targetInWaterTemperatureC: defaults.targetInWaterTemperatureC,
      waitTargetTemperatureC: defaults.waitTargetTemperatureC,
      inletTemperatureC: defaults.inletTemperatureC,
      coolingMedium: defaults.coolingMedium,
      waterSubmersionPercent: defaults.waterSubmersionPercent,
      waitMode: defaults.waitMode,
      waitMinutes: defaults.waitMinutes,
    );
  }
}

/// Steps and temperature that the Costs section is derived from (JS
/// `blendingCostSource()`).
typedef BlendCostSource = ({List<ProtocolStep> steps, double temperatureC});

/// Bank price suggestion with the pricing signature it was computed for
/// (JS `state.bankSuggestions[bank.id]`).
class BankPriceEntry {
  const BankPriceEntry({required this.signature, required this.result});

  final String signature;
  final BankPriceResult result;
}

/// Port of the Blending state and recalculation flow in `js/main.js`.
///
/// [AppController] owns banks and settings and pushes changes through
/// [updateSharedInputs]. [updateBank] persists an edited bank (JS
/// `commitBankUpdate`). [analytics] receives one `blend_calculated` event per
/// Optimize run.
class BlendController extends ChangeNotifier {
  BlendController({
    required BlendInputs inputs,
    required List<Bank> banks,
    required Settings settings,
    required void Function(Bank updated) updateBank,
    required Analytics analytics,
  }) : _inputs = inputs,
       _banks = banks,
       _enabledById = <String, bool>{
         for (final bank in banks) bank.id: bank.enabled,
       },
       _settings = settings,
       _updateBank = updateBank,
       _analytics = analytics {
    recalculate();
  }

  List<Bank> _banks;
  Settings _settings;
  final void Function(Bank updated) _updateBank;
  final Analytics _analytics;

  /// Last seen `enabled` flag per bank id. A flip drops that bank's price
  /// suggestion (JS `toggle-bank` always runs `delete state.bankSuggestions`).
  Map<String, bool> _enabledById;

  BlendInputs _inputs;

  /// Optimize state (JS `lastInput`, `lastResult`).
  CalculatorInput? lastInput;
  Map<String, Object?>? lastResult;

  /// Readings by wait step (JS `interimMeasurements`).
  List<InterimMeasurement?> interimMeasurements = <InterimMeasurement?>[];

  /// Recipe signature the readings were recorded against.
  String? interimMeasurementSignature;

  final Map<String, BankPriceEntry> _bankSuggestions =
      <String, BankPriceEntry>{};

  BlendInputs get inputs => _inputs;

  /// Replaces the form values and recalculates.
  void setInputs(BlendInputs next) {
    _inputs = next;
    recalculate();
  }

  /// Receives new banks and settings from [AppController].
  ///
  /// A change to a non-price input (anything except bank and cost prices)
  /// clears the interim readings.
  /// Bank price suggestions are kept only while their pricing signature still
  /// matches (JS `bankSuggestionFor`); nothing is re-priced here.
  void updateSharedInputs({
    required List<Bank> banks,
    required Settings settings,
  }) {
    final previousInput = lastInput;
    for (final bank in banks) {
      if (_enabledById[bank.id] != bank.enabled) {
        _bankSuggestions.remove(bank.id);
      }
    }
    _enabledById = <String, bool>{
      for (final bank in banks) bank.id: bank.enabled,
    };
    _banks = banks;
    _settings = settings;
    final currentInput = _buildInput(interimMeasurements);
    final nonPriceChanged =
        previousInput == null ||
        calculatorInputSignature(previousInput) !=
            calculatorInputSignature(currentInput);
    if (nonPriceChanged) {
      interimMeasurements = <InterimMeasurement?>[];
      interimMeasurementSignature = null;
    }
    _pruneBankSuggestions();
    recalculate();
  }

  /// JS `recalculate()` for the Optimize result. Readings are cleared when a
  /// recipe input changed; cost prices are not part of the signature.
  void recalculate() {
    var input = _buildInput(interimMeasurements);
    if (interimMeasurements.any((measurement) => measurement != null) &&
        interimMeasurementSignature != calculatorInputSignature(input)) {
      interimMeasurements = <InterimMeasurement?>[];
      interimMeasurementSignature = null;
      input = _buildInput(interimMeasurements);
    }
    final errors = _optimizeInputErrors(_inputs, interimMeasurements);
    lastInput = input;
    if (errors.isNotEmpty) {
      lastResult = _withPressureLimitWarnings(
        input,
        _invalidInputResult(errors),
      );
      _trackCalculation(
        AnalyticsBlendMode.optimize,
        AnalyticsOutcome.invalidInput,
      );
    } else {
      final result = planWithReadings(input);
      lastResult = _withPressureLimitWarnings(input, result);
      _trackCalculation(
        AnalyticsBlendMode.optimize,
        result['feasible'] == true
            ? AnalyticsOutcome.feasible
            : AnalyticsOutcome.infeasible,
      );
    }
    notifyListeners();
  }

  /// JS `applyInterimMeasurement`. Returns the error message, or null on success.
  String? applyInterimMeasurement(int index, InterimReading measurement) {
    final lockMessage = interimMeasurementLockMessage(
      interimMeasurements,
      index,
      'apply',
    );
    if (lockMessage != null) {
      return lockMessage;
    }
    final candidateMeasurements = _withMeasurement(
      interimMeasurements,
      index,
      InterimMeasurement(
        pressureBar: measurement.pressureBar,
        temperatureC: measurement.temperatureC,
      ),
    );
    final errors = _optimizeInputErrors(_inputs, candidateMeasurements);
    if (errors.isNotEmpty) {
      return errors.join(' ');
    }
    final candidate = _buildInput(candidateMeasurements);
    final verdict = verifyInterimMeasurement(
      candidate,
      index,
      measurement,
      tolerancePercent: _settings.interimPressureTolerancePercent,
    );
    if (!verdict.ok) {
      return verdict.error;
    }
    interimMeasurements = candidateMeasurements;
    interimMeasurementSignature = calculatorInputSignature(candidate);
    recalculate();
    return null;
  }

  /// JS `clearInterimMeasurement`. Returns the lock message, or null on success.
  String? clearInterimMeasurement(int index) {
    final lockMessage = interimMeasurementLockMessage(
      interimMeasurements,
      index,
      'clear',
    );
    if (lockMessage != null) {
      return lockMessage;
    }
    final cleared = _withMeasurement(interimMeasurements, index, null);
    interimMeasurementSignature = signatureAfterClearingMeasurement(
      _buildInput(interimMeasurements),
      index,
    );
    interimMeasurements = cleared;
    recalculate();
    return null;
  }

  /// JS `resetFactorySettings` (`js/main.js` 715-718): drops every bank price
  /// suggestion and every interim reading, then recalculates.
  void resetForFactoryReset() {
    _bankSuggestions.clear();
    interimMeasurements = <InterimMeasurement?>[];
    interimMeasurementSignature = null;
    recalculate();
  }

  /// JS `blendingCostSource()`: null when there is no feasible source.
  BlendCostSource? blendingCostSource() {
    final result = lastResult;
    final input = lastInput;
    if (result == null || input == null || result['feasible'] == false) {
      return null;
    }
    return (
      steps: _protocolStepsOf(result),
      temperatureC: _temperatureOf(input),
    );
  }

  /// JS `deriveFillCost(source)`: prices come from current banks and settings.
  FillCost? deriveFillCost(BlendCostSource? source) {
    if (source == null) {
      return null;
    }
    return computeFillCost(
      steps: _fillStepsOf(source.steps),
      banks: _banks,
      costs: _settings.costs,
      temperatureC: source.temperatureC,
    );
  }

  /// Costs section for the shown result.
  FillCost? blendingCost() => deriveFillCost(blendingCostSource());

  /// JS `blendingSavings()`: null when there is no feasible Optimize result.
  SavingsResult? blendingSavings() {
    final result = lastResult;
    final input = lastInput;
    if (result == null || input == null) {
      return null;
    }
    final blend = result['blend'] as Map<String, Object?>?;
    return computeSavings(
      heliumRetainedLitres: blend == null
          ? null
          : (blend['heliumRetainedLitres'] as num?)?.toDouble() ?? 0,
      feasible: result['feasible'] as bool?,
      protocolSteps: _fillStepsOf(_protocolStepsOf(result)),
      banks: _banks,
      costs: _settings.costs,
      settings: _settings,
      physics: PhysicsInput(
        model: _settings.physics.model,
        temperatureC: _temperatureOf(input),
      ),
      inventoryTemperatureC: _inputs.inletTemperatureC,
    );
  }

  /// JS `bankPricingSignature(bank)`: every input that changes the recipe price.
  String bankPricingSignature(Bank bank) {
    final physics = PhysicsInput(
      model: _settings.physics.model,
      temperatureC: _inputs.ambientTemperatureC,
    );
    final pure = pureGasPrices(
      banks: _banks,
      physics: physics,
      inventoryTemperatureC: _inputs.inletTemperatureC,
    );
    final json = settingsToJson(_settings);
    return jsonEncode(<String, Object?>{
      'volumeL': bank.volumeL,
      'pressureBar': bank.pressureBar,
      'oxygenPercent': bank.oxygenPercent,
      'heliumPercent': bank.heliumPercent,
      'costs': json['costs'],
      'booster': json['booster'],
      'pressureLimitMode': json['pressureLimitMode'],
      'physics': <String, Object?>{
        'model': physics.model,
        'temperatureC': physics.temperatureC,
      },
      'inventoryGasPrices': <String, Object?>{
        'oxygen': pure.oxygen,
        'helium': pure.helium,
      },
      'inventoryTemperatureC': _inputs.inletTemperatureC,
    });
  }

  /// JS `bankSuggestionFor(bank)`: a suggestion whose signature is stale is dropped.
  BankPriceEntry? bankSuggestionFor(String bankId) {
    final suggestion = _bankSuggestions[bankId];
    if (suggestion == null) {
      return null;
    }
    final bank = _bankById(bankId);
    if (bank == null || suggestion.signature != bankPricingSignature(bank)) {
      _bankSuggestions.remove(bankId);
      return null;
    }
    return suggestion;
  }

  /// JS `calculateBankPrice` + `finishBankPriceCalculation`.
  void calculateBankPrice(String bankId) {
    _priceBank(bankId);
    notifyListeners();
  }

  /// JS `delete state.bankSuggestions[bank.id]` on a committed bank edit
  /// (`commitBankUpdate`), a gas-preset select, and a bank toggle. Callers
  /// recalculate through their own commit path.
  void clearBankSuggestion(String bankId) {
    _bankSuggestions.remove(bankId);
    notifyListeners();
  }

  /// JS `applyBankPrice`: applies only a fresh successful suggestion.
  void applyBankPrice(String bankId) {
    final suggestion = bankSuggestionFor(bankId);
    final result = suggestion?.result;
    final bank = _bankById(bankId);
    if (suggestion == null || bank == null || result is! BankPriceOk) {
      return;
    }
    _updateBank(bank.copyWith(pricePerLitre: () => result.pricePerLitre));
    _bankSuggestions.remove(bankId);
    recalculate();
  }

  /// Drops every bank price suggestion whose bank is gone or whose pricing
  /// signature no longer matches the current inputs. Nothing is re-priced
  /// (JS `bankSuggestionFor`).
  void _pruneBankSuggestions() {
    for (final entry in _bankSuggestions.entries.toList()) {
      final bank = _bankById(entry.key);
      if (bank == null || entry.value.signature != bankPricingSignature(bank)) {
        _bankSuggestions.remove(entry.key);
      }
    }
  }

  /// Prices one bank with the current banks and settings, replacing any
  /// existing suggestion. A bank that no longer exists loses its suggestion.
  void _priceBank(String bankId) {
    final bank = _bankById(bankId);
    if (bank == null) {
      _bankSuggestions.remove(bankId);
      return;
    }
    final result = priceBankByRecipe(
      bank: bank,
      costs: _settings.costs,
      settings: _settings,
      physics: PhysicsInput(
        model: _settings.physics.model,
        temperatureC: _inputs.ambientTemperatureC,
      ),
      inventoryBanks: _banks,
      inventoryTemperatureC: _inputs.inletTemperatureC,
    );
    _bankSuggestions[bankId] = BankPriceEntry(
      signature: bankPricingSignature(bank),
      result: result,
    );
  }

  void _trackCalculation(AnalyticsBlendMode mode, AnalyticsOutcome outcome) {
    trackBlendCalculated(_analytics, mode: mode, outcome: outcome);
  }

  CalculatorInput _buildInput(List<InterimMeasurement?> measurements) {
    final input = _inputs;
    return buildCalculatorInput(
      cylinderPreset: input.cylinderPreset,
      initialPressureBar: input.initialPressureBar,
      initialOxygenPercent: input.initialOxygenPercent,
      initialHeliumPercent: input.initialHeliumPercent,
      targetPressureBar: input.targetPressureBar,
      targetOxygenPercent: input.targetOxygenPercent,
      targetHeliumPercent: input.targetHeliumPercent,
      ambientTemperatureC: input.ambientTemperatureC,
      targetInWaterTemperatureC: input.targetInWaterTemperatureC,
      waitTargetTemperatureC: input.waitTargetTemperatureC,
      inletTemperatureC: input.inletTemperatureC,
      coolingMedium: input.coolingMedium,
      waterSubmersionPercent: input.waterSubmersionPercent,
      waitMode: input.waitMode,
      waitMinutes: input.waitMinutes,
      banks: _banks,
      settings: _settings,
      interimMeasurements: measurements,
    );
  }

  List<String> _optimizeInputErrors(
    BlendInputs input,
    List<InterimMeasurement?> measurements,
  ) {
    return validateCalculatorInputs(
      _calculatorCylinder(input, input.targetPressureBar),
      CalculatorPhysics(temperatureC: input.ambientTemperatureC),
      _calculatorThermal(input, measurements),
      pressureLimitMode: _settings.pressureLimitMode,
    );
  }

  CalculatorCylinder _calculatorCylinder(
    BlendInputs input,
    double targetPressureBar,
  ) {
    return CalculatorCylinder(
      volumeL: input.cylinderPreset.volumeL,
      initialPressureBar: input.initialPressureBar,
      targetPressureBar: targetPressureBar,
      workingPressureBar: input.cylinderPreset.workingPressureBar,
      hotOverfillPercent: input.cylinderPreset.hotOverfillPercent,
    );
  }

  CalculatorThermal _calculatorThermal(
    BlendInputs input,
    List<InterimMeasurement?> measurements,
  ) {
    return CalculatorThermal(
      ambientTemperatureC: input.ambientTemperatureC,
      tankMaterial: input.cylinderPreset.material,
      coolingMedium: input.coolingMedium,
      waterSubmersionPercent: input.waterSubmersionPercent,
      inletTemperatureC: input.inletTemperatureC,
      targetMediumTemperatureC: input.waitTargetTemperatureC,
      targetTemperatureC: input.waitTargetTemperatureC,
      targetInWaterTemperatureC: input.targetInWaterTemperatureC,
      waitMode: input.waitMode,
      waitMinutes: input.waitMinutes,
      interimMeasurements: measurements,
    );
  }

  /// JS `recalculate()`: the Optimize result carries `pressureLimitWarnings`
  /// on both the valid and invalid-input branches.
  Map<String, Object?> _withPressureLimitWarnings(
    CalculatorInput input,
    Map<String, Object?> result,
  ) {
    return <String, Object?>{
      ...result,
      'pressureLimitWarnings': collectPressureWarnings(
        pressureLimitMode: _settings.pressureLimitMode,
        cylinder: cylinderPressureSpecOfInput(input),
        observations: pressureWarningObservationsForOptimize(input, result),
      ),
    };
  }

  Map<String, Object?> _invalidInputResult(List<String> errors) {
    return <String, Object?>{
      'feasible': false,
      'error': 'Invalid input: ${errors.join(' ')}',
      'blend': null,
      'protocolSteps': <Object?>[],
    };
  }

  Bank? _bankById(String bankId) {
    for (final bank in _banks) {
      if (bank.id == bankId) {
        return bank;
      }
    }
    return null;
  }

  List<InterimMeasurement?> _withMeasurement(
    List<InterimMeasurement?> measurements,
    int index,
    InterimMeasurement? value,
  ) {
    final copy = <InterimMeasurement?>[...measurements];
    while (copy.length <= index) {
      copy.add(null);
    }
    copy[index] = value;
    return copy;
  }

  List<ProtocolStep> _protocolStepsOf(Map<String, Object?> result) {
    final steps = result['protocolSteps'];
    if (steps is! List<Object?>) {
      return <ProtocolStep>[];
    }
    return steps.whereType<ProtocolStep>().toList();
  }

  List<FillStep> _fillStepsOf(List<ProtocolStep> steps) {
    return <FillStep>[
      for (final step in steps)
        FillStep(
          costOperation: step.costOperation,
          costOperationId: step.costOperationId,
          sourceBankId: step.sourceBankId,
          recipeGas: step.recipeGas,
          sourceConsumedMoles: step.sourceConsumedMoles,
        ),
    ];
  }
}

double _temperatureOf(CalculatorInput input) {
  final physics = input['physics']! as Map<String, Object?>;
  return physics['temperatureC']! as double;
}

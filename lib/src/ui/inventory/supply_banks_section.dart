import 'dart:async';

import 'package:flutter/material.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/controllers/blend_controller.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/bank_price_format.dart';
import 'package:simplex_blender/src/domain/bank_pricing.dart';
import 'package:simplex_blender/src/domain/finite_number.dart';
import 'package:simplex_blender/src/domain/js_number.dart';
import 'package:simplex_blender/src/domain/pure_prices.dart';
import 'package:simplex_blender/src/domain/settings.dart';
import 'package:simplex_blender/src/domain/thermodynamics.dart';
import 'package:simplex_blender/src/domain/units.dart';
import 'package:simplex_blender/src/ui/shared/focus_loss_node.dart';
import 'package:simplex_blender/src/ui/shared/number_input.dart';

/// JS `PRICE_BASIS_PER_VOLUME`.
const String priceBasisPerVolume = 'per-volume';

/// JS `PRICE_BASIS_FULL_TANK`.
const String priceBasisFullTank = 'full-tank';

const double _checkWidth = 40;
const double _nameWidth = 180;
const double _volumeWidth = 110;
const double _pressureWidth = 110;
const double _gasWidth = 70;
const double _priceWidth = 160;
const double _removeWidth = 48;

const String _customGas = 'custom';
const String _gasPrefix = 'gas:';

/// Inventory supply-bank table (port of `js/ui/supply-banks.js`).
///
/// Rebuilds from [app] and [blend]. The per-bank price basis lives in this
/// widget's state, as the JS keeps it in its render options.
class SupplyBanksSection extends StatefulWidget {
  const SupplyBanksSection({super.key, required this.app, required this.blend});

  final AppController app;
  final BlendController blend;

  @override
  State<SupplyBanksSection> createState() => _SupplyBanksSectionState();
}

class _SupplyBanksSectionState extends State<SupplyBanksSection> {
  final Map<String, String> _priceBasis = <String, String>{};

  /// JS `state.bankSuggestions[id]` with `status: 'calculating'`: bank id to pricing signature.
  final Map<String, String> _pendingPricing = <String, String>{};
  final Map<String, Timer> _pendingTimers = <String, Timer>{};

  /// JS `pendingBankFocus`: bank whose Calculate control regains focus after the table rebuilds.
  String? _pendingBankFocus;
  final Map<String, FocusNode> _calculateFocus = <String, FocusNode>{};
  final FocusNode _statusFocus = FocusNode(debugLabel: 'bank-price-status');

  /// JS `#bank-price-status` text.
  String _status = '';

  AppController get _app => widget.app;
  BlendController get _blend => widget.blend;

  @override
  void dispose() {
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    for (final node in _calculateFocus.values) {
      node.dispose();
    }
    _statusFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[widget.app, widget.blend]),
      builder: (context, _) => _buildTable(),
    );
  }

  Widget _buildTable() {
    final units = _app.settings.units;
    final gasPresets = _app.settings.gasPresets;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            liveRegion: true,
            child: Focus(focusNode: _statusFocus, child: Text(_status)),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _headerRow(units),
                for (final bank in _app.banks)
                  _bankRow(bank, units, gasPresets),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerRow(String units) {
    return Row(
      children: <Widget>[
        _cell(_checkWidth, const Text('Use')),
        _cell(_nameWidth, const Text('Bank / gas')),
        _cell(_volumeWidth, Text('Volume (${unitLabel('volumeL', units)})')),
        _cell(
          _pressureWidth,
          Text('Pressure (${unitLabel('pressureBar', units)})'),
        ),
        _cell(
          _pressureWidth,
          Text('Max pressure (${unitLabel('pressureBar', units)})'),
        ),
        _cell(_gasWidth, const Text('O₂%')),
        _cell(_gasWidth, const Text('He%')),
        _cell(
          _priceWidth,
          Text('Price (${unitLabel('pricePerVolumeL', units)})'),
        ),
        _cell(_removeWidth, const Text('Del')),
      ],
    );
  }

  Widget _bankRow(Bank bank, String units, List<GasPreset> gasPresets) {
    final basis = _priceBasis[bank.id] ?? priceBasisPerVolume;
    return Opacity(
      opacity: bank.enabled ? 1 : 0.4,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _cell(
            _checkWidth,
            Semantics(
              label: 'Use ${bank.name}',
              child: Checkbox(
                value: bank.enabled,
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  _setEnabled(bank, value);
                },
              ),
            ),
          ),
          _cell(
            _nameWidth,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _EditableText(
                  value: bank.name,
                  semanticsLabel: '${bank.name} bank name',
                  width: _nameWidth,
                  onCommit: (text) => _commitName(bank, text),
                ),
                _gasPresetSelect(bank, gasPresets),
              ],
            ),
          ),
          _cell(
            _volumeWidth,
            _EditableText(
              value: jsNumberString(
                convertToDisplay(bank.volumeL, 'volumeL', units),
              ),
              semanticsLabel:
                  '${bank.name} volume in ${unitLabel('volumeL', units)}',
              width: _volumeWidth,
              numeric: true,
              onCommit: (text) => _commitVolume(bank, text, units),
            ),
          ),
          _cell(
            _pressureWidth,
            _EditableText(
              value: jsNumberString(
                convertToDisplay(bank.pressureBar, 'pressureBar', units),
              ),
              semanticsLabel:
                  '${bank.name} pressure in ${unitLabel('pressureBar', units)}',
              width: _pressureWidth,
              numeric: true,
              onCommit: (text) => _commitPressure(bank, text, units),
            ),
          ),
          _cell(
            _pressureWidth,
            _EditableText(
              value: bank.maxPressureBar == null
                  ? ''
                  : jsNumberString(
                      convertToDisplay(
                        bank.maxPressureBar!,
                        'pressureBar',
                        units,
                      ),
                    ),
              semanticsLabel:
                  '${bank.name} max pressure in ${unitLabel('pressureBar', units)}',
              width: _pressureWidth,
              numeric: true,
              onCommit: (text) => _commitMaxPressure(bank, text, units),
            ),
          ),
          _cell(
            _gasWidth,
            _EditableText(
              value: jsNumberString(bank.oxygenPercent),
              semanticsLabel: '${bank.name} oxygen percentage',
              width: _gasWidth,
              numeric: true,
              onCommit: (text) => _commitOxygen(bank, text),
            ),
          ),
          _cell(
            _gasWidth,
            _EditableText(
              value: jsNumberString(bank.heliumPercent),
              semanticsLabel: '${bank.name} helium percentage',
              width: _gasWidth,
              numeric: true,
              onCommit: (text) => _commitHelium(bank, text),
            ),
          ),
          _cell(_priceWidth, _priceControl(bank, basis, units)),
          _cell(
            _removeWidth,
            Semantics(
              label: 'Remove ${bank.name}',
              button: true,
              onTap: () => _remove(bank),
              child: ExcludeSemantics(
                child: TextButton(
                  onPressed: () => _remove(bank),
                  child: const Text('✕'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(double width, Widget child) {
    return SizedBox(
      width: width,
      child: Padding(padding: const EdgeInsets.all(4), child: child),
    );
  }

  Widget _gasPresetSelect(Bank bank, List<GasPreset> gasPresets) {
    final selected = getSelectedGasPreset(bank, gasPresets);
    return Semantics(
      label: 'Gas preset for ${bank.name}',
      child: DropdownButton<String>(
        isDense: true,
        isExpanded: true,
        value: selected == null ? _customGas : '$_gasPrefix${selected.name}',
        items: <DropdownMenuItem<String>>[
          const DropdownMenuItem<String>(
            value: _customGas,
            child: Text('Custom'),
          ),
          for (final entry in sortGasPresetEntries(gasPresets))
            DropdownMenuItem<String>(
              value: '$_gasPrefix${entry.preset.name}',
              child: Text(entry.preset.name),
            ),
        ],
        onChanged: (value) {
          if (value == null) {
            return;
          }
          _selectGas(bank, value, gasPresets);
        },
      ),
    );
  }

  Widget _priceControl(Bank bank, String basis, String units) {
    final fullTank = basis == priceBasisFullTank;
    final suggestion = _suggestionOf(bank);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _EditableText(
          value: fullTank ? '' : formatBankPrice(bank.pricePerLitre, units),
          placeholder: fullTank ? 'Full tank price' : 'Not set',
          semanticsLabel: fullTank
              ? '${bank.name} full tank price'
              : '${bank.name} price per ${unitLabel('pricePerVolumeL', units)}',
          width: _priceWidth,
          numeric: true,
          onCommit: (text) => fullTank
              ? _commitFullTank(bank, text)
              : _commitPricePerVolume(bank, text, units),
        ),
        _basisSelect(bank, basis, units),
        // Pure oxygen and helium banks take their price by hand.
        if (!isPureComposition(bank))
          ..._calculationControls(bank, suggestion, units),
      ],
    );
  }

  Widget _basisSelect(Bank bank, String basis, String units) {
    return Semantics(
      label: 'Price basis for ${bank.name}',
      child: DropdownButton<String>(
        isDense: true,
        isExpanded: true,
        value: basis,
        items: <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(
            value: priceBasisPerVolume,
            child: Text('Per ${unitLabel('volumeL', units)}'),
          ),
          const DropdownMenuItem<String>(
            value: priceBasisFullTank,
            child: Text('Full tank'),
          ),
        ],
        onChanged: (value) {
          if (value == null) {
            return;
          }
          setState(() {
            _priceBasis[bank.id] = value;
          });
        },
      ),
    );
  }

  List<Widget> _calculationControls(
    Bank bank,
    BankPriceSuggestion? suggestion,
    String units,
  ) {
    final priced = bank.pricePerLitre != null;
    final apply = suggestion is BankPriceSuggestionOk
        ? (priced ? 'Replace' : 'Apply')
        : null;
    final pending = _pendingPricing.containsKey(bank.id);
    final calculate = pending ? null : () => _calculatePrice(bank);
    return <Widget>[
      Semantics(
        label: 'Calculate price for ${bank.name}',
        button: true,
        onTap: calculate,
        child: ExcludeSemantics(
          child: TextButton(
            focusNode: _calculateFocusFor(bank.id),
            onPressed: calculate,
            child: const Text('Calculate price'),
          ),
        ),
      ),
      if (suggestion != null)
        Semantics(
          liveRegion: true,
          child: Text(
            formatSuggestionNote(
              bank,
              suggestion,
              units,
              _app.settings.costs.currencySymbol,
              _app.settings.costs.leftoverDiscountPercent,
            ),
          ),
        ),
      if (apply != null)
        Semantics(
          label: '$apply suggested price for ${bank.name}',
          button: true,
          onTap: () => _applyPrice(bank),
          child: ExcludeSemantics(
            child: TextButton(
              onPressed: () => _applyPrice(bank),
              child: Text(apply),
            ),
          ),
        ),
    ];
  }

  /// JS `bankSuggestionFor`, including the in-flight `calculating` state.
  BankPriceSuggestion? _suggestionOf(Bank bank) {
    final pending = _pendingPricing[bank.id];
    if (pending != null) {
      return pending == _blend.bankPricingSignature(bank)
          ? const BankPriceSuggestionCalculating()
          : null;
    }
    final entry = _blend.bankSuggestionFor(bank.id);
    if (entry == null) {
      return null;
    }
    return switch (entry.result) {
      BankPriceOk(:final pricePerLitre, :final recipeCost, :final litres) =>
        BankPriceSuggestionOk(
          pricePerLitre: pricePerLitre,
          recipeCost: recipeCost,
          litres: litres,
        ),
      BankPriceFailure(:final reason) => BankPriceSuggestionFailed(
        reason: reason,
      ),
    };
  }

  Bank? _bankById(String bankId) {
    for (final bank in _app.banks) {
      if (bank.id == bankId) {
        return bank;
      }
    }
    return null;
  }

  FocusNode _calculateFocusFor(String bankId) {
    return _calculateFocus.putIfAbsent(
      bankId,
      () => FocusNode(debugLabel: 'calculate-$bankId'),
    );
  }

  void _announce(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _status = message;
    });
  }

  void _scheduleBankPriceFocusRestore() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _restoreBankPriceFocus(),
    );
  }

  /// JS `restoreBankPriceFocus`.
  void _restoreBankPriceFocus() {
    if (!mounted) {
      return;
    }
    final bankId = _pendingBankFocus;
    if (bankId == null) {
      return;
    }
    _pendingBankFocus = null;
    final bank = _bankById(bankId);
    final calculate = _calculateFocus[bankId];
    if (bank == null || isPureComposition(bank) || calculate == null) {
      return;
    }
    final active = FocusManager.instance.primaryFocus;
    if (active != null && active != _statusFocus && active != calculate) {
      return;
    }
    if (_pendingPricing.containsKey(bankId)) {
      _statusFocus.requestFocus();
      return;
    }
    calculate.requestFocus();
  }

  /// JS `calculateBankPrice`: marks the bank as calculating and defers the
  /// pricing run to a zero-delay timer (JS `setTimeout(0)`).
  void _calculatePrice(Bank bank) {
    final signature = _blend.bankPricingSignature(bank);
    _pendingBankFocus = bank.id;
    setState(() {
      _pendingPricing[bank.id] = signature;
    });
    _announce('Calculating price for ${bank.name}…');
    _scheduleBankPriceFocusRestore();
    _pendingTimers[bank.id]?.cancel();
    _pendingTimers[bank.id] = Timer(
      Duration.zero,
      () => _finishPriceCalculation(bank.id),
    );
  }

  /// JS `finishBankPriceCalculation`.
  void _finishPriceCalculation(String bankId) {
    _pendingTimers.remove(bankId);
    if (!mounted) {
      return;
    }
    final signature = _pendingPricing[bankId];
    final bank = _bankById(bankId);
    if (bank == null || signature == null) {
      _pendingPricing.remove(bankId);
      _pendingBankFocus = null;
      return;
    }
    if (signature != _blend.bankPricingSignature(bank)) {
      setState(() {
        _pendingPricing.remove(bankId);
      });
      _pendingBankFocus = null;
      _announce('Price calculation for ${bank.name} was discarded.');
      return;
    }
    setState(() {
      _pendingPricing.remove(bankId);
    });
    try {
      _blend.calculateBankPrice(bankId);
    } catch (error, stack) {
      _pendingBankFocus = null;
      _announce('Price calculation for ${bank.name} failed.');
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'simplex_blender',
        ),
      );
      return;
    }
    final suggestion = _suggestionOf(bank);
    if (suggestion == null) {
      _pendingBankFocus = null;
      _announce('Price calculation for ${bank.name} failed.');
      return;
    }
    _announce(
      '${bank.name}: ${formatSuggestionNote(bank, suggestion, _app.settings.units, _app.settings.costs.currencySymbol, _app.settings.costs.leftoverDiscountPercent)}',
    );
    _scheduleBankPriceFocusRestore();
  }

  /// JS `applyBankPrice` with focus restore.
  void _applyPrice(Bank bank) {
    _pendingBankFocus = bank.id;
    _blend.applyBankPrice(bank.id);
    _scheduleBankPriceFocusRestore();
  }

  /// Applies [updated] and clears the bank's suggestion only when it was
  /// accepted (JS `commitBankUpdate`). Returns whether it was accepted.
  bool _commit(Bank bank, Bank updated) {
    _app.updateBank(updated);
    final index = _app.banks.indexWhere((candidate) => candidate.id == bank.id);
    final accepted = index >= 0 && identical(_app.banks[index], updated);
    if (accepted) {
      _blend.clearBankSuggestion(bank.id);
    }
    return accepted;
  }

  void _setEnabled(Bank bank, bool enabled) {
    _app.setBankEnabled(bank.id, enabled: enabled);
    _blend.clearBankSuggestion(bank.id);
  }

  void _remove(Bank bank) {
    _app.removeBank(bank.id);
    _blend.clearBankSuggestion(bank.id);
  }

  void _commitName(Bank bank, String text) {
    _app.clearBankInputFailure(bank.id);
    _commit(bank, bank.copyWith(name: text));
  }

  /// Parses a numeric field edit. Text that is not a finite number is
  /// rejected with a bank-prefixed message instead of being dropped silently.
  double? _parseEdit(Bank bank, String text, String label) {
    final value = parseFiniteNumber(text);
    if (value == null) {
      _app.rejectBankEdit(bank, 'Enter a number for the $label.');
    }
    return value;
  }

  void _commitVolume(Bank bank, String text, String units) {
    _app.clearBankInputFailure(bank.id);
    final value = _parseEdit(bank, text, 'volume');
    if (value == null) {
      return;
    }
    _commit(
      bank,
      bank.copyWith(volumeL: convertFromDisplay(value, 'volumeL', units)),
    );
  }

  void _commitPressure(Bank bank, String text, String units) {
    _app.clearBankInputFailure(bank.id);
    final value = _parseEdit(bank, text, 'pressure');
    if (value == null) {
      return;
    }
    _commit(
      bank,
      bank.copyWith(
        pressureBar: convertFromDisplay(value, 'pressureBar', units),
      ),
    );
  }

  void _commitMaxPressure(Bank bank, String text, String units) {
    _app.clearBankInputFailure(bank.id);
    final value = _parseEdit(bank, text, 'maximum pressure');
    if (value == null) {
      return;
    }
    final stored = convertFromDisplay(value, 'pressureBar', units);
    _commit(bank, bank.copyWith(maxPressureBar: () => stored));
  }

  void _commitOxygen(Bank bank, String text) {
    _app.clearBankInputFailure(bank.id);
    final value = _parseEdit(bank, text, 'oxygen percent');
    // A focus change without an edit must not unlink a named preset (JS only
    // unlinks on a changed input value).
    if (value == null || value == bank.oxygenPercent) {
      return;
    }
    _commit(
      bank,
      bank.copyWith(oxygenPercent: value, gasPresetLink: const CustomMixLink()),
    );
  }

  void _commitHelium(Bank bank, String text) {
    _app.clearBankInputFailure(bank.id);
    final value = _parseEdit(bank, text, 'helium percent');
    if (value == null || value == bank.heliumPercent) {
      return;
    }
    _commit(
      bank,
      bank.copyWith(heliumPercent: value, gasPresetLink: const CustomMixLink()),
    );
  }

  void _commitPricePerVolume(Bank bank, String text, String units) {
    _app.clearBankInputFailure(bank.id);
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _commit(bank, bank.copyWith(pricePerLitre: () => null));
      return;
    }
    final value = _parseEdit(bank, trimmed, 'price per volume');
    if (value == null) {
      return;
    }
    final stored = convertFromDisplay(value, 'pricePerVolumeL', units);
    _commit(bank, bank.copyWith(pricePerLitre: () => stored));
  }

  /// JS full-tank commit: the tank price becomes a per-litre price for the
  /// bank's free gas, then the basis returns to per-volume when accepted.
  void _commitFullTank(Bank bank, String text) {
    _app.clearBankInputFailure(bank.id);
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final tankPrice = _parseEdit(bank, trimmed, 'full tank price');
    if (tankPrice == null) {
      return;
    }
    final inputs = _blend.inputs;
    final freeGasLitres = bankFreeGasLitres(
      bank,
      PhysicsInput(
        model: _app.settings.physics.model,
        temperatureC: inputs.ambientTemperatureC,
      ),
      inputs.inletTemperatureC,
    );
    final perLitre = pricePerLitreFromFullTank(tankPrice, freeGasLitres);
    if (perLitre == null) {
      _app.rejectBankEdit(
        bank,
        'Enter a non-negative full tank price for a bank that holds gas.',
      );
      return;
    }
    if (_commit(bank, bank.copyWith(pricePerLitre: () => perLitre))) {
      setState(() {
        _priceBasis[bank.id] = priceBasisPerVolume;
      });
    }
  }

  void _selectGas(Bank bank, String value, List<GasPreset> gasPresets) {
    _app.clearBankInputFailure(bank.id);
    if (value == _customGas) {
      _commit(bank, bank.copyWith(gasPresetLink: const CustomMixLink()));
      return;
    }
    final name = value.substring(_gasPrefix.length);
    GasPreset? preset;
    for (final candidate in gasPresets) {
      if (candidate.name == name) {
        preset = candidate;
        break;
      }
    }
    if (preset == null) {
      return;
    }
    // Air is rejected by AppController.updateBank with the JS message.
    _commit(
      bank,
      bank.copyWith(
        oxygenPercent: preset.oxygenPercent,
        heliumPercent: preset.heliumPercent,
        gasPresetLink: NamedPresetLink(preset.name),
      ),
    );
  }
}

/// A text field that commits on focus loss or submit (JS `change`), and
/// restores its stored display value after a commit that did not change it.
class _EditableText extends StatefulWidget {
  const _EditableText({
    required this.value,
    required this.semanticsLabel,
    required this.onCommit,
    this.placeholder,
    this.width,
    this.numeric = false,
  });

  final String value;
  final String semanticsLabel;
  final String? placeholder;
  final double? width;
  final bool numeric;
  final void Function(String text) onCommit;

  @override
  State<_EditableText> createState() => _EditableTextState();
}

class _EditableTextState extends State<_EditableText> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final FocusLossNode _focus = FocusLossNode(onFocusLost: _commit);

  @override
  void didUpdateWidget(_EditableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focus.focusNode.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    widget.onCommit(_controller.text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focus.focusNode.hasFocus) {
        return;
      }
      if (_controller.text != widget.value) {
        _controller.text = widget.value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticsLabel,
      textField: true,
      child: SizedBox(
        width: widget.width,
        child: TextField(
          controller: _controller,
          focusNode: _focus.focusNode,
          keyboardType: widget.numeric
              ? signedDecimalKeyboard
              : TextInputType.text,
          onSubmitted: (_) => _focus.focusNode.unfocus(),
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: widget.placeholder,
          ),
        ),
      ),
    );
  }
}

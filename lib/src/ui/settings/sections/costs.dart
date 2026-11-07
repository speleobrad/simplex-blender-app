part of '../settings_screen.dart';

extension _CostsSection on _SettingsScreenState {
  // Costs ------------------------------------------------------------------

  Widget _costsSection() {
    final costs = _draft.costs;
    final prices = costs.operationPrices;
    return _section('Costs', <Widget>[
      TextFormField(
        key: _key('cost-currency'),
        initialValue: costs.currencySymbol,
        maxLength: 8,
        decoration: const InputDecoration(
          labelText: 'Currency symbol',
          isDense: true,
        ),
        onChanged: (text) => _update(_withCosts(currencySymbol: text)),
      ),
      _NumberField(
        key: _key('cost-discount'),
        label: 'Leftover gas discount (%)',
        value: costs.leftoverDiscountPercent,
        onChanged: (value) => _update(_withCosts(discountPercent: value)),
      ),
      _NumberField(
        key: _key('cost-boost'),
        label: 'Boost (per operation)',
        value: prices.boost,
        display: _formatFee,
        onChanged: (value) => _update(_withCosts(boost: _roundFee(value))),
      ),
      _NumberField(
        key: _key('cost-decant'),
        label: 'Decant incl. equalize (per operation)',
        value: prices.decant,
        display: _formatFee,
        onChanged: (value) => _update(_withCosts(decant: _roundFee(value))),
      ),
      _NumberField(
        key: _key('cost-topup'),
        label: 'Top-up (per operation, includes compressor air)',
        value: prices.topUp,
        display: _formatFee,
        onChanged: (value) => _update(_withCosts(topUp: _roundFee(value))),
      ),
    ]);
  }

  Settings _withCosts({
    String? currencySymbol,
    double? discountPercent,
    double? boost,
    double? decant,
    double? topUp,
  }) {
    final costs = _draft.costs;
    final prices = costs.operationPrices;
    return _draft.copyWith(
      costs: Costs(
        currencySymbol: currencySymbol ?? costs.currencySymbol,
        leftoverDiscountPercent:
            discountPercent ?? costs.leftoverDiscountPercent,
        operationPrices: OperationPrices(
          boost: boost ?? prices.boost,
          decant: decant ?? prices.decant,
          topUp: topUp ?? prices.topUp,
        ),
      ),
    );
  }
}

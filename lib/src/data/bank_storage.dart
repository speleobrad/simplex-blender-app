/// Port of `js/bank-storage.js`.
///
/// Storage I/O (`loadSupplyBanks` / `saveSupplyBanks`) runs on
/// [KeyValueStorage]. The library also holds the built-in defaults, the record
/// shape persisted for a [Bank], and the normalization and validation applied
/// to decoded saved banks.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:simplex_blender/src/data/key_value_storage.dart';
import 'package:simplex_blender/src/domain/bank.dart';
import 'package:simplex_blender/src/domain/domain_error.dart';
import 'package:simplex_blender/src/domain/input_validation.dart';

// ignore: constant_identifier_names
const String STORAGE_KEY = 'simplex-gas-remixer-banks';

/// Built-in supply banks. The third bank is the JS `gasPresetName: null`
/// custom mix; the other two have no link (absent). An absent `pricePerLitre`
/// is `null` here.
// ignore: constant_identifier_names
const List<Bank> DEFAULT_BANKS = <Bank>[
  Bank(
    id: 'bank-helium',
    name: 'Helium',
    volumeL: 40,
    pressureBar: 150,
    maxPressureBar: 200,
    oxygenPercent: 0,
    heliumPercent: 100,
    enabled: true,
  ),
  Bank(
    id: 'bank-oxygen',
    name: 'Oxygen',
    volumeL: 50,
    pressureBar: 200,
    maxPressureBar: 200,
    oxygenPercent: 100,
    heliumPercent: 0,
    enabled: true,
  ),
  Bank(
    id: 'bank-sample-scrap',
    name: 'Sample scrap',
    volumeL: 12,
    pressureBar: 45,
    maxPressureBar: 200,
    oxygenPercent: 19,
    heliumPercent: 40,
    enabled: true,
    gasPresetLink: CustomMixLink(),
  ),
];

// ignore: constant_identifier_names
const List<Map<String, Object>> LEGACY_DEFAULT_BANKS = <Map<String, Object>>[
  <String, Object>{
    'id': 'bank-he',
    'name': 'Pure Helium',
    'volumeL': 50,
    'pressureBar': 200,
    'oxygenPercent': 0,
    'heliumPercent': 100,
    'enabled': true,
  },
  <String, Object>{
    'id': 'bank-1845',
    'name': 'Tx 18/45 Bank',
    'volumeL': 50,
    'pressureBar': 200,
    'oxygenPercent': 18,
    'heliumPercent': 45,
    'enabled': true,
  },
  <String, Object>{
    'id': 'bank-o2',
    'name': 'Pure Oxygen',
    'volumeL': 40,
    'pressureBar': 180,
    'oxygenPercent': 100,
    'heliumPercent': 0,
    'enabled': true,
  },
];

// ignore: constant_identifier_names
const List<String> LEGACY_BANK_FIELDS = <String>[
  'id',
  'name',
  'volumeL',
  'pressureBar',
  'oxygenPercent',
  'heliumPercent',
  'enabled',
];

/// Outcome of normalizing decoded saved banks.
///
/// [banks] is always usable: the normalized saved list when valid, otherwise
/// a fresh copy of [DEFAULT_BANKS]. [failure] is set only when saved data was
/// rejected (the JS `onFallback` error).
class SavedBanksResult {
  const SavedBanksResult({required this.banks, this.failure});

  final List<Bank> banks;
  final DomainError? failure;
}

/// Persisted record shape for [bank]; the JS `copyBanks` copy.
Map<String, Object?> bankToRecord(Bank bank) {
  final record = <String, Object?>{
    'id': bank.id,
    'name': bank.name,
    'volumeL': bank.volumeL,
    'pressureBar': bank.pressureBar,
    'maxPressureBar': bank.maxPressureBar,
    'oxygenPercent': bank.oxygenPercent,
    'heliumPercent': bank.heliumPercent,
    'enabled': bank.enabled,
  };
  switch (bank.gasPresetLink) {
    case CustomMixLink():
      record['gasPresetName'] = null;
    case NamedPresetLink(:final name):
      record['gasPresetName'] = name;
    case UnnamedPresetLink():
      break;
  }
  if (bank.pricePerLitre != null) {
    record['pricePerLitre'] = bank.pricePerLitre;
  }
  return record;
}

/// Validation errors for [banks] as they would be persisted; empty when valid.
List<String> validateSupplyBanks(List<Bank> banks) => _validateRecords(
  <Map<String, Object?>>[for (final bank in banks) bankToRecord(bank)],
);

/// Normalizes a decoded saved-banks value (the JSON after `jsonDecode`).
///
/// Order matches the JS `loadSupplyBanks`: drop legacy Air records, replace
/// the exact legacy default set with [DEFAULT_BANKS], migrate missing
/// `maxPressureBar`, then validate. Any rejection yields [DEFAULT_BANKS] and
/// a [DomainError] whose message is the validation errors joined by spaces.
SavedBanksResult normalizeSavedBanks(Object? decoded) {
  Object? normalized = decoded is List<Object?>
      ? decoded.where((bank) => !_isLegacyAirBank(bank)).toList()
      : decoded;
  if (_isLegacyDefaultBanks(normalized)) {
    return SavedBanksResult(banks: List<Bank>.of(DEFAULT_BANKS));
  }
  if (normalized is List<Object?>) {
    normalized = normalized.map(_migrateMaxPressureBar).toList();
  }
  final errors = _validateRecords(normalized);
  if (errors.isNotEmpty) {
    return SavedBanksResult(
      banks: List<Bank>.of(DEFAULT_BANKS),
      failure: DomainError(errors.join(' ')),
    );
  }
  final records = normalized as List<Object?>;
  return SavedBanksResult(
    banks: <Bank>[
      for (final record in records)
        _bankFromRecord(record as Map<String, Object?>),
    ],
  );
}

/// JS `isLegacyDefaultBanks`. The `pricePerLitre` comparison in the JS is
/// implied by the key count plus the seven legacy field matches (a legacy
/// record with all seven fields has no `pricePerLitre` key), so only the
/// legacy fields are compared here.
bool _isLegacyDefaultBanks(Object? banks) {
  if (banks is! List<Object?> || banks.length != LEGACY_DEFAULT_BANKS.length) {
    return false;
  }
  for (var index = 0; index < banks.length; index++) {
    final bank = banks[index];
    if (bank is! Map<String, Object?> ||
        bank.length != LEGACY_BANK_FIELDS.length) {
      return false;
    }
    for (final field in LEGACY_BANK_FIELDS) {
      if (bank[field] != LEGACY_DEFAULT_BANKS[index][field]) {
        return false;
      }
    }
  }
  return true;
}

/// JS `isLegacyAirBank`: compressor Air is never a finite supply bank.
bool _isLegacyAirBank(Object? bank) {
  if (bank is! Map<String, Object?>) {
    return false;
  }
  return bank['oxygenPercent'] == 21 && bank['heliumPercent'] == 0;
}

/// JS `migrateMaxPressureBar`: a record without `maxPressureBar` (key absent;
/// `null` counts as present) gets `max(200, pressureBar)` when pressure is a
/// finite number.
Object? _migrateMaxPressureBar(Object? bank) {
  if (bank is! Map<String, Object?>) {
    return bank;
  }
  if (bank.containsKey('maxPressureBar')) {
    return bank;
  }
  final pressure = bank['pressureBar'];
  if (pressure is! num || !pressure.isFinite) {
    return bank;
  }
  return <String, Object?>{
    ...bank,
    'maxPressureBar': math.max<num>(200, pressure),
  };
}

/// JS `validateBanks` over decoded records.
List<String> _validateRecords(Object? banks) {
  if (banks is! List<Object?>) {
    return <String>['Supply banks must be a list.'];
  }
  final ids = <String>{};
  for (final bank in banks) {
    final errors = validateSupplyBankInput(bank);
    if (errors.isNotEmpty) {
      return errors;
    }
    final id = (bank as Map<String, Object?>)['id']! as String;
    if (!ids.add(id)) {
      return <String>['Supply banks must have unique IDs.'];
    }
  }
  return <String>[];
}

/// Builds a [Bank] from a record that already passed [_validateRecords].
Bank _bankFromRecord(Map<String, Object?> record) {
  final price = record['pricePerLitre'];
  return Bank(
    id: record['id']! as String,
    name: record['name']! as String,
    volumeL: (record['volumeL']! as num).toDouble(),
    pressureBar: (record['pressureBar']! as num).toDouble(),
    maxPressureBar: (record['maxPressureBar']! as num).toDouble(),
    oxygenPercent: (record['oxygenPercent']! as num).toDouble(),
    heliumPercent: (record['heliumPercent']! as num).toDouble(),
    enabled: record['enabled']! as bool,
    pricePerLitre: price == null ? null : (price as num).toDouble(),
    gasPresetLink: _gasPresetLinkOf(record),
  );
}

/// JS `copyBanks`: an absent `gasPresetName` key is [UnnamedPresetLink], a
/// `null` value is [CustomMixLink], and a string is [NamedPresetLink]. Runs
/// only on records that already passed [_validateRecords].
BankGasPresetLink _gasPresetLinkOf(Map<String, Object?> record) {
  if (!record.containsKey('gasPresetName')) {
    return const UnnamedPresetLink();
  }
  final name = record['gasPresetName'];
  if (name == null) {
    return const CustomMixLink();
  }
  return NamedPresetLink(name as String);
}

/// JS `loadSupplyBanks`. Returns [DEFAULT_BANKS] (fresh copy) when nothing is
/// saved, when storage or JSON decoding throws, or when the saved list is
/// rejected. [onFallback] receives the error in each fallback case, as the
/// JS `onFallback` callback does.
List<Bank> loadSupplyBanks(
  KeyValueStorage storage, {
  void Function(Object error)? onFallback,
}) {
  String? serialized;
  try {
    serialized = storage.getItem(STORAGE_KEY);
  } on Object catch (error) {
    onFallback?.call(error);
    return List<Bank>.of(DEFAULT_BANKS);
  }
  if (serialized == null) {
    return List<Bank>.of(DEFAULT_BANKS);
  }
  Object? decoded;
  try {
    decoded = jsonDecode(serialized);
  } on FormatException catch (error) {
    onFallback?.call(error);
    return List<Bank>.of(DEFAULT_BANKS);
  }
  final result = normalizeSavedBanks(decoded);
  final failure = result.failure;
  if (failure != null) {
    onFallback?.call(failure);
  }
  return result.banks;
}

/// JS `saveSupplyBanks`. Throws [DomainError] with the joined validation
/// errors before anything is written, so saved banks are never replaced by
/// invalid ones.
void saveSupplyBanks(List<Bank> banks, KeyValueStorage storage) {
  final errors = validateSupplyBanks(banks);
  if (errors.isNotEmpty) {
    throw DomainError(errors.join(' '));
  }
  storage.setItem(
    STORAGE_KEY,
    jsonEncode(<Map<String, Object?>>[
      for (final bank in banks) bankToRecord(bank),
    ]),
  );
}

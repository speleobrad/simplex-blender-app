import 'package:shared_preferences/shared_preferences.dart';
import 'package:simplex_blender/src/data/key_value_storage.dart';

/// [KeyValueStorage] backed by `shared_preferences`.
///
/// The interface is synchronous, so [open] preloads every string entry into
/// memory. Writes update memory immediately and are sent to the platform
/// store in call order, one at a time. A failed write is reported through
/// `onWriteError` and is not rethrown, so the in-memory value keeps serving
/// the session. `onWriteError` must not throw.
class PreferencesKeyValueStorage implements KeyValueStorage {
  PreferencesKeyValueStorage._(
    this._preferences,
    this._values,
    this._onWriteError,
  );

  final SharedPreferences _preferences;
  final Map<String, String> _values;
  final void Function(Object error)? _onWriteError;
  Future<void> _pendingWrites = Future<void>.value();

  /// Loads every string entry from the platform store. Non-string entries are
  /// not visible through [getItem].
  static Future<PreferencesKeyValueStorage> open({
    void Function(Object error)? onWriteError,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final values = <String, String>{};
    for (final key in preferences.getKeys()) {
      final value = preferences.get(key);
      if (value is String) {
        values[key] = value;
      }
    }
    return PreferencesKeyValueStorage._(preferences, values, onWriteError);
  }

  /// Completes once every write issued so far has finished.
  Future<void> get pendingWrites => _pendingWrites;

  @override
  String? getItem(String key) => _values[key];

  @override
  void setItem(String key, String value) {
    _values[key] = value;
    _enqueue('setString', () => _preferences.setString(key, value));
  }

  @override
  void clear() {
    _values.clear();
    _enqueue('clear', _preferences.clear);
  }

  void _enqueue(String operation, Future<bool> Function() write) {
    _pendingWrites = _pendingWrites.then<void>((_) async {
      try {
        final succeeded = await write();
        if (!succeeded) {
          _report(StateError('shared_preferences $operation reported failure'));
        }
      } catch (error) {
        _report(error);
      }
    });
  }

  void _report(Object error) => _onWriteError?.call(error);
}

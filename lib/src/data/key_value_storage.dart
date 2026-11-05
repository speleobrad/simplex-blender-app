/// Synchronous key/value store, the shape the JS `storage` argument needs
/// (`getItem` returns `null` when absent; `clear` removes every key, as
/// `localStorage.clear()` does). The platform adapter is
/// `PreferencesKeyValueStorage`.
abstract interface class KeyValueStorage {
  String? getItem(String key);
  void setItem(String key, String value);
  void clear();
}

import 'package:simplex_blender/src/data/key_value_storage.dart';

/// In-memory [KeyValueStorage]; mirrors the JS `memoryStorage` test helper.
class MemoryStorage implements KeyValueStorage {
  MemoryStorage([Map<String, String> initial = const <String, String>{}])
    : _values = Map<String, String>.of(initial);

  final Map<String, String> _values;

  /// Snapshot of the stored keys, for assertions.
  Map<String, String> get values => Map<String, String>.unmodifiable(_values);

  @override
  String? getItem(String key) => _values[key];

  @override
  void setItem(String key, String value) {
    _values[key] = value;
  }

  @override
  void clear() => _values.clear();
}

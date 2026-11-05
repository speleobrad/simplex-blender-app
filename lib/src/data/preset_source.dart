import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

/// Timeout for fetching a preset JSON document from a URL (plan: 15 s).
const Duration presetUrlTimeout = Duration(seconds: 15);

/// Largest preset JSON body accepted from a URL (plan: 2 MB).
const int presetUrlMaxBytes = 2 * 1024 * 1024;

/// Text of a preset file chosen by the user.
class PresetSourceText {
  const PresetSourceText({required this.name, required this.text});

  final String name;
  final String text;
}

/// Shows the native file picker for a preset JSON file.
///
/// Returns null when the user cancels. Parsing and validation are left to the
/// domain layer.
Future<PresetSourceText?> pickPresetFile() async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: <String>['json'],
  );
  if (picked == null) {
    return null;
  }
  final bytes = await picked.readAsBytes();
  return PresetSourceText(name: picked.name, text: utf8.decode(bytes));
}

/// Downloads a preset JSON document and returns its text.
///
/// Only 2xx responses are accepted, matching JS `response.ok`. Bodies larger
/// than [maxBytes] are rejected before decoding.
Future<String> fetchPresetUrl(
  Uri uri, {
  http.Client? client,
  Duration timeout = presetUrlTimeout,
  int maxBytes = presetUrlMaxBytes,
}) async {
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient.get(uri).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw StateError('The server returned HTTP ${response.statusCode}.');
    }
    if (response.bodyBytes.length > maxBytes) {
      throw StateError(
        'The preset file is larger than the $maxBytes byte limit.',
      );
    }
    return utf8.decode(response.bodyBytes);
  } finally {
    if (client == null) {
      httpClient.close();
    }
  }
}

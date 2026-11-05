import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simplex_blender/src/analytics/analytics.dart';
import 'package:simplex_blender/src/controllers/app_controller.dart';
import 'package:simplex_blender/src/data/preset_source.dart';
import 'package:simplex_blender/src/data/settings_storage.dart';
import 'package:simplex_blender/src/ui/settings/settings_screen.dart';
import 'package:simplex_blender/src/ui/shell/tour_targets.dart';

import '../support/memory_storage.dart';

// Fixtures come from the JS repo (tests/browser/fixtures/import-fixtures).
// Expected strings come from tests/browser/persistence.spec.js.
const String _validFixturePath = 'test/fixtures/valid-gases.json';
const String _invalidFixturePath = 'test/fixtures/invalid.json';
const String _validSummary =
    'Loaded 3 entries. 1 new 2 already present 0 rejected';
const String _onlineUrl = 'https://example.test/presets/gases.json';

Finder _key(String id) => find.byKey(ValueKey<String>(id));

String _statusText(WidgetTester tester) =>
    tester.widget<Text>(_key('settings-preset-import-status')).data ?? '';

bool _confirmEnabled(WidgetTester tester) {
  final button = tester.widget<FilledButton>(
    _key('settings-preset-import-button'),
  );
  return button.onPressed != null;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<MemoryStorage> _pumpSettings(
  WidgetTester tester, {
  Future<PresetSourceText?> Function()? filePicker,
  http.Client? httpClient,
}) async {
  // Tall enough that the Confirm button is on screen without scrolling.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  final storage = MemoryStorage();
  final app = AppController(storage: storage, analytics: const NoopAnalytics());
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TourTargetsScope(
          targets: TourTargets(),
          child: SettingsScreen(
            app: app,
            filePicker: filePicker,
            httpClient: httpClient,
          ),
        ),
      ),
    ),
  );
  await _tap(tester, _key('settings-category-preset-management'));
  return storage;
}

Future<PresetSourceText?> Function() _filePicker(String name, String path) {
  return () async =>
      PresetSourceText(name: name, text: File(path).readAsStringSync());
}

void main() {
  testWidgets('file import shows the preview with duplicates marked', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      filePicker: _filePicker('valid-gases.json', _validFixturePath),
    );

    await _tap(tester, _key('settings-preset-import-file'));

    expect(_statusText(tester), _validSummary);
    expect(find.textContaining('Browser fixture gas'), findsOneWidget);
    expect(find.textContaining('Ready to import.'), findsOneWidget);
    // EAN 32 and Tx 18/45 already exist, so the JS preview marks them as such.
    expect(find.textContaining('Already exists'), findsNWidgets(2));
    expect(_confirmEnabled(tester), isTrue);
  });

  testWidgets('Confirm persists the selected new gas preset', (tester) async {
    final storage = await _pumpSettings(
      tester,
      filePicker: _filePicker('valid-gases.json', _validFixturePath),
    );
    await _tap(tester, _key('settings-preset-import-file'));

    await _tap(tester, _key('settings-preset-import-button'));

    expect(_statusText(tester), 'Imported 1 preset.');
    final raw = storage.values[SETTINGS_STORAGE_KEY];
    expect(raw, isNotNull);
    final saved = jsonDecode(raw!) as Map<String, Object?>;
    final gases = (saved['gasPresets']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final imported = gases.where((g) => g['name'] == 'Browser fixture gas');
    expect(imported, hasLength(1));
    expect(imported.single['oxygenPercent'], 37);
    expect(imported.single['heliumPercent'], 12);
  });

  testWidgets('online import fetches the URL and shows the same preview', (
    tester,
  ) async {
    final client = MockClient((request) async {
      expect(request.url.toString(), _onlineUrl);
      return http.Response(File(_validFixturePath).readAsStringSync(), 200);
    });
    await _pumpSettings(tester, httpClient: client);

    await tester.enterText(_key('settings-preset-import-url'), _onlineUrl);
    await _tap(tester, _key('settings-preset-import-load-url'));

    expect(_statusText(tester), _validSummary);
    expect(_confirmEnabled(tester), isTrue);
  });

  testWidgets('online import reports an HTTP error from the server', (
    tester,
  ) async {
    final client = MockClient((request) async => http.Response('', 503));
    await _pumpSettings(tester, httpClient: client);

    await tester.enterText(_key('settings-preset-import-url'), _onlineUrl);
    await _tap(tester, _key('settings-preset-import-load-url'));

    expect(
      _statusText(tester),
      'Could not load $_onlineUrl: The server returned HTTP 503.',
    );
    expect(_confirmEnabled(tester), isFalse);
  });

  testWidgets('an invalid file reports the JS error and blocks Confirm', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      filePicker: _filePicker('invalid.json', _invalidFixturePath),
    );

    await _tap(tester, _key('settings-preset-import-file'));

    expect(_statusText(tester), contains('Gas presets must be an array.'));
    expect(_confirmEnabled(tester), isFalse);
  });
}

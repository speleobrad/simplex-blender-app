import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simplex_blender/src/data/preset_source.dart';

void main() {
  group('fetchPresetUrl', () {
    final uri = Uri.parse(
      'https://raw.githubusercontent.com/speleobrad/simplex-blender/master/presets/gas.json',
    );

    test('returns the body text of a 200 response', () async {
      final client = MockClient((request) async {
        expect(request.url, uri);
        return http.Response('[{"name":"Imported gas"}]', 200);
      });

      final text = await fetchPresetUrl(uri, client: client);

      expect(text, '[{"name":"Imported gas"}]');
    });

    test('throws with the HTTP status for a 404 response', () async {
      final client = MockClient((request) async {
        return http.Response('missing', 404);
      });

      expect(
        fetchPresetUrl(uri, client: client),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'The server returned HTTP 404.',
          ),
        ),
      );
    });

    test('throws when the body exceeds maxBytes', () async {
      final client = MockClient((request) async {
        return http.Response('12345678901', 200);
      });

      expect(
        fetchPresetUrl(uri, client: client, maxBytes: 10),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'The preset file is larger than the 10 byte limit.',
          ),
        ),
      );
    });

    test(
      'throws TimeoutException when the response is slower than timeout',
      () async {
        final client = MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response('[]', 200);
        });

        expect(
          fetchPresetUrl(
            uri,
            client: client,
            timeout: const Duration(milliseconds: 10),
          ),
          throwsA(isA<TimeoutException>()),
        );
      },
    );
  });
}

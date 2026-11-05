import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:local_services_finder/auth_service.dart';

class MemoryTokenStorage implements AuthTokenStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  test('restore validates access token and rotates expired session using refresh token', () async {
    final storage = MemoryTokenStorage()
      ..values['access_token'] = 'expired-access'
      ..values['refresh_token'] = 'valid-refresh';
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/api/auth/me')) {
        return http.Response('{"error":"expired"}', 401);
      }
      if (request.url.path.endsWith('/api/auth/refresh')) {
        expect(jsonDecode(request.body), {'refresh_token': 'valid-refresh'});
        return http.Response(
          jsonEncode({
            'access_token': 'renewed-access',
            'refresh_token': 'renewed-refresh',
            'user': {'id': 8, 'full_name': 'Salman', 'email': 'salman@example.com'},
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });
    final service = AuthService(client: client, storage: storage, baseUrl: 'https://api.example.test');

    final user = await service.restoreSession();

    expect(user?.fullName, 'Salman');
    expect(requests.map((request) => request.url.path), [
      '/api/auth/me',
      '/api/auth/refresh',
    ]);
    expect(storage.values['access_token'], 'renewed-access');
    expect(storage.values['refresh_token'], 'renewed-refresh');
  });

  test('invalid refresh session clears stored credentials', () async {
    final storage = MemoryTokenStorage()
      ..values['access_token'] = 'expired-access'
      ..values['refresh_token'] = 'revoked-refresh';
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/auth/me')) {
        return http.Response('{"error":"expired"}', 401);
      }
      return http.Response('{"error":"revoked"}', 401);
    });
    final service = AuthService(client: client, storage: storage, baseUrl: 'https://api.example.test');

    expect(await service.restoreSession(), isNull);
    expect(storage.values, isEmpty);
  });
}

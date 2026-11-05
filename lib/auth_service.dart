import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const authApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:5000',
);

const _secureStorage = FlutterSecureStorage();

abstract interface class AuthTokenStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterAuthTokenStorage implements AuthTokenStorage {
  final FlutterSecureStorage storage;
  const FlutterAuthTokenStorage([this.storage = _secureStorage]);

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

class AuthApiException implements Exception {
  final String message;
  final int? statusCode;
  const AuthApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class AuthUser {
  final int id;
  final String fullName;
  final String email;

  const AuthUser({required this.id, required this.fullName, required this.email});

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as int,
    fullName: json['full_name'] as String,
    email: json['email'] as String,
  );
}

class AuthSession {
  final AuthUser user;
  final String accessToken;
  final String refreshToken;

  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    user: AuthUser.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
  );
}

class AuthService {
  final http.Client _client;
  final AuthTokenStorage _storage;
  final String baseUrl;

  AuthService({
    http.Client? client,
    AuthTokenStorage? storage,
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _storage = storage ?? const FlutterAuthTokenStorage(),
       baseUrl = (baseUrl ?? authApiBaseUrl).replaceFirst(RegExp(r'/+$'), '');

  Future<AuthSession> login({required String email, required String password}) async {
    final body = await _post('/api/auth/login', {
      'email': email.trim(),
      'password': password,
    });
    final session = AuthSession.fromJson(body);
    await _save(session);
    return session;
  }

  Future<AuthSession> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final body = await _post('/api/auth/register', {
      'full_name': fullName.trim(),
      'email': email.trim(),
      'password': password,
    });
    final session = AuthSession.fromJson(body);
    await _save(session);
    return session;
  }

  Future<AuthUser?> restoreSession() async {
    final access = await _storage.read('access_token');
    final refresh = await _storage.read('refresh_token');
    if (access == null || access.isEmpty) {
      if (refresh == null || refresh.isEmpty) return null;
      return (await _refresh(refresh)).user;
    }
    try {
      final body = await _get('/api/auth/me', access);
      return AuthUser.fromJson(Map<String, dynamic>.from(body['user'] as Map));
    } on AuthApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      if (refresh == null || refresh.isEmpty) {
        await clearSession();
        return null;
      }
      try {
        return (await _refresh(refresh)).user;
      } on AuthApiException catch (refreshError) {
        if (refreshError.statusCode == 401) {
          await clearSession();
          return null;
        }
        rethrow;
      }
    }
  }

  Future<void> logout() async {
    final access = await _storage.read('access_token');
    final refresh = await _storage.read('refresh_token');
    try {
      if (access != null && access.isNotEmpty) {
        await _post('/api/auth/logout', {'refresh_token': refresh ?? ''}, token: access);
      } else if (refresh != null && refresh.isNotEmpty) {
        await _post('/api/auth/logout', {'refresh_token': refresh});
      }
    } finally {
      await clearSession();
    }
  }

  Future<void> clearSession() async {
    await _storage.delete('access_token');
    await _storage.delete('refresh_token');
  }

  Future<Map<String, dynamic>> getAuthenticated(String path) =>
      _authenticatedRequest('GET', path);

  Future<Map<String, dynamic>> postAuthenticated(
    String path,
    Map<String, dynamic> payload,
  ) =>
      _authenticatedRequest('POST', path, payload);

  Future<Map<String, dynamic>> putAuthenticated(
    String path,
    Map<String, dynamic> payload,
  ) =>
      _authenticatedRequest('PUT', path, payload);

  Future<Map<String, dynamic>> deleteAuthenticated(String path) =>
      _authenticatedRequest('DELETE', path);

  Future<Map<String, dynamic>> _authenticatedRequest(
    String method,
    String path, [
    Map<String, dynamic>? payload,
  ]) async {
    final access = await _storage.read('access_token');
    if (access == null || access.isEmpty) {
      throw const AuthApiException('Please sign in to continue.', statusCode: 401);
    }
    try {
      return await _send(method, path, payload, access);
    } on AuthApiException catch (error) {
      if (error.statusCode != 401) rethrow;
      final refresh = await _storage.read('refresh_token');
      if (refresh == null || refresh.isEmpty) {
        await clearSession();
        rethrow;
      }
      try {
        final session = await _refresh(refresh);
        return await _send(method, path, payload, session.accessToken);
      } on AuthApiException catch (refreshError) {
        if (refreshError.statusCode == 401) await clearSession();
        rethrow;
      }
    }
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? payload,
    String token,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final headers = <String, String>{
        'Authorization': 'Bearer $token',
        if (payload != null) 'Content-Type': 'application/json',
      };
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (payload != null) request.body = jsonEncode(payload);
      final streamed = await _client.send(request).timeout(const Duration(seconds: 12));
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } on AuthApiException {
      rethrow;
    } catch (_) {
      throw const AuthApiException('Network error. Check that the authentication server is running and try again.');
    }
  }

  Future<AuthSession> _refresh(String refreshToken) async {
    final body = await _post('/api/auth/refresh', {'refresh_token': refreshToken});
    final session = AuthSession.fromJson(body);
    await _save(session);
    return session;
  }

  Future<void> _save(AuthSession session) async {
    await _storage.write('access_token', session.accessToken);
    await _storage.write('refresh_token', session.refreshToken);
  }

  Future<Map<String, dynamic>> _get(String path, String token) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl$path'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 12));
      return _decode(response);
    } on AuthApiException {
      rethrow;
    } catch (_) {
      throw const AuthApiException('Network error. Check that the authentication server is running and try again.');
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload, {
    String? token,
  }) async {
    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final response = await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));
      return _decode(response);
    } on AuthApiException {
      rethrow;
    } catch (_) {
      throw const AuthApiException('Network error. Check that the authentication server is running and try again.');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> body;
    try {
      body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw AuthApiException('The authentication server returned an invalid response.', statusCode: response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthApiException(
        body['error'] as String? ?? 'Authentication request failed.',
        statusCode: response.statusCode,
      );
    }
    return body;
  }
}

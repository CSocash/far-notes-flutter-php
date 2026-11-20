// The PHP server's API. The app signs in with "X-Far-Notes-Client: app", gets a session token back,
// keeps it on the device and sends it as "Authorization: Bearer <token>". It never uses the cookie.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'core.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => message;
}

class FarNotesApi {
  FarNotesApi({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? defaultBaseUrl(),
        _client = client ?? http.Client();

  static const _tokenKey = 'far-notes-session-token';
  static const _timeout = Duration(seconds: 15);

  /// Set at build time with --dart-define=FAR_NOTES_API_URL=http://... (the device tests do this).
  /// Otherwise the dev server on this Mac: the iOS Simulator reaches it as 127.0.0.1, the Android
  /// emulator as 10.0.2.2.
  static String defaultBaseUrl() {
    const configured = String.fromEnvironment('FAR_NOTES_API_URL');
    if (configured.isNotEmpty) return configured;
    return Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://127.0.0.1:3000';
  }

  final String baseUrl;
  final http.Client _client;
  String? _token;

  Future<void> loadToken() async {
    _token = (await SharedPreferences.getInstance()).getString(_tokenKey);
  }

  Future<void> _saveToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, token);
    }
  }

  Future<dynamic> _request(String method, String path, {Object? body}) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll({
        'Content-Type': 'application/json',
        'X-Far-Notes-Client': 'app',
        if (_token != null) 'Authorization': 'Bearer $_token',
      });
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request).timeout(_timeout));
    } on TimeoutException {
      throw ApiException(0, 'The server did not answer. Is it running?');
    } on http.ClientException {
      throw ApiException(0, 'Could not reach the server at $baseUrl.');
    }
    dynamic result;
    try {
      result = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      result = null;
    }
    if (response.statusCode == 401) await _saveToken(null);
    if (response.statusCode >= 400) {
      final error = result is Map && result['error'] is String
          ? result['error'] as String
          : 'Request failed (${response.statusCode}).';
      throw ApiException(response.statusCode, error);
    }
    return result;
  }

  String _partQuery(String part) => '?part=$part';

  /// The signed-in username, or null when there is no saved session or it has expired.
  Future<String?> currentUsername() async {
    if (_token == null) return null;
    final result = await _request('GET', '/api/auth/me') as Map<String, dynamic>;
    if (result['authenticated'] == true) return result['username'] as String;
    await _saveToken(null);
    return null;
  }

  Future<String> signIn(String usernameOrEmail, String password) async {
    final result =
        await _request('POST', '/api/auth/login', body: {'username': usernameOrEmail.trim(), 'password': password});
    await _saveToken(result['token'] as String);
    return result['username'] as String;
  }

  Future<void> register(String username, String email, String password) => _request('POST', '/api/auth/register',
      body: {'username': username.trim(), 'email': email.trim(), 'password': password});

  Future<String> forgotPassword(String email) async {
    final result = await _request('POST', '/api/auth/forgot-password', body: {'email': email.trim()});
    return result['message'] as String;
  }

  Future<void> signOut() async {
    try {
      await _request('POST', '/api/auth/logout');
    } finally {
      await _saveToken(null);
    }
  }

  Future<List<Regulation>> regulations(String part) async {
    final result = await _request('GET', '/api/regulations${_partQuery(part)}') as List;
    return [for (final item in result) Regulation.fromJson(item as Map<String, dynamic>)];
  }

  Future<Regulation> addRegulation(String part) async {
    final result = await _request('POST', '/api/regulations${_partQuery(part)}', body: {'regulation': ''});
    return Regulation.fromJson(result as Map<String, dynamic>);
  }

  Future<void> saveHeading(String part, Regulation regulation) =>
      _request('PATCH', '/api/regulations/${regulation.id}${_partQuery(part)}',
          body: {'regulation': regulation.heading});

  Future<void> saveSubsection(String part, Subsection subsection) =>
      _request('PATCH', '/api/subsections/${subsection.id}${_partQuery(part)}', body: subsection.toPatch());
}

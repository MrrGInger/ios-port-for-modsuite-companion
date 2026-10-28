import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// VRChat credentials are exclusively handled here. Never import this class
/// into CompanionApi or attach these cookies to a ModSuite request.
class VrchatApi {
  static const _host = 'api.vrchat.cloud';
  static const _storage = FlutterSecureStorage();
  static const _authKey = 'vrchat_auth_cookie';
  static const _twoFactorKey = 'vrchat_twofactor_cookie';
  static String? _auth;
  static String? _twoFactor;

  static bool get connected => _auth != null && _auth!.isNotEmpty;

  static String _clean(String value, String name) {
    var s = value.trim();
    if (s.contains(';')) {
      final parts = s.split(';').map((x) => x.trim());
      final matching = parts.where((x) => x.startsWith('$name='));
      if (matching.isNotEmpty) s = matching.first;
    }
    if (s.startsWith('$name=')) s = s.substring(name.length + 1);
    if (s.isEmpty || s.contains(RegExp(r'[\r\n;]'))) {
      throw const FormatException('Invalid cookie value');
    }
    return s;
  }

  static Future<void> restore() async {
    _auth = await _storage.read(key: _authKey);
    _twoFactor = await _storage.read(key: _twoFactorKey);
  }

  static Future<void> connect(String auth, String twoFactor) async {
    final cleanAuth = _clean(auth, 'auth');
    final clean2fa = twoFactor.trim().isEmpty ? null : _clean(twoFactor, 'twoFactorAuth');
    // Validate with VRChat before saving; nothing is sent to ModSuite.
    final previousAuth = _auth;
    final previous2fa = _twoFactor;
    _auth = cleanAuth;
    _twoFactor = clean2fa;
    try {
      await currentUser();
      await _storage.write(key: _authKey, value: cleanAuth);
      if (clean2fa != null) {
        await _storage.write(key: _twoFactorKey, value: clean2fa);
      } else {
        await _storage.delete(key: _twoFactorKey);
      }
    } catch (_) {
      _auth = previousAuth;
      _twoFactor = previous2fa;
      rethrow;
    }
  }

  static Future<void> disconnect() async {
    _auth = null;
    _twoFactor = null;
    await _storage.delete(key: _authKey);
    await _storage.delete(key: _twoFactorKey);
  }

  static Future<dynamic> _request(String method, String path, [Map<String, dynamic>? payload]) async {
    if (!connected) throw StateError('Connect VRChat first');
    final uri = Uri.https(_host, '/api/1$path');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.openUrl(method, uri).timeout(const Duration(seconds: 15));
      request.cookies.add(Cookie('auth', _auth!));
      if (_twoFactor != null && _twoFactor!.isNotEmpty) {
        request.cookies.add(Cookie('twoFactorAuth', _twoFactor!));
      }
      request.headers.set(HttpHeaders.userAgentHeader, 'ModSuiteCompanionAndroid/1.0 (VRChat API)');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (payload != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(payload)));
      }
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('VRChat HTTP ${response.statusCode}: ${body.length > 250 ? body.substring(0, 250) : body}');
      }
      return body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> currentUser() async =>
      Map<String, dynamic>.from(await _request('GET', '/auth/user') as Map);

  /// Location is read from VRChat only; never forwarded to ModSuite.
  static Future<Map<String, dynamic>> ownLocation() async {
    final me = await currentUser();
    final id = me['id']?.toString();
    if (id == null || id.isEmpty) throw StateError('VRChat user ID missing');
    return getUser(id);
  }

  static Future<Map<String, dynamic>> getUser(String id) async =>
      Map<String, dynamic>.from(await _request('GET', '/users/${Uri.encodeComponent(id)}') as Map);

  static Future<List<Map<String, dynamic>>> search(String query) async {
    final q = query.trim();
    final id = extractUserId(q);
    if (id != null) return [await getUser(id)];
    if (q.length < 2) throw const FormatException('Enter at least 2 characters');
    final data = await _request('GET', '/users?search=${Uri.encodeQueryComponent(q)}&n=20');
    if (data is! List) throw const FormatException('Unexpected VRChat search response');
    return data.map((x) => Map<String, dynamic>.from(x as Map)).toList();
  }

  static String? extractUserId(String text) {
    final match = RegExp(r'usr_[0-9a-fA-F-]{36}').firstMatch(text);
    return match?.group(0);
  }

  static Future<void> inviteToGroup(String groupId, String userId) async {
    await _request('POST', '/groups/${Uri.encodeComponent(groupId)}/invites', {'userId': userId});
  }

  static Future<void> ban(String groupId, String userId) async {
    await _request('POST', '/groups/${Uri.encodeComponent(groupId)}/bans', {'userId': userId});
  }

  static Future<void> unban(String groupId, String userId) async {
    await _request('DELETE', '/groups/${Uri.encodeComponent(groupId)}/bans/${Uri.encodeComponent(userId)}');
  }
}

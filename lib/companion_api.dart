import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CompanionApi {
  static const base = 'https://tcostaffmodtool.tcostaffmodtools.com';
  static const storage = FlutterSecureStorage();
  static const tokenKey = 'modsuite_companion_token';

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(Uri.parse('$base$path'));
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(const Duration(seconds: 15));
      final raw = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: ${raw.length > 200 ? raw.substring(0, 200) : raw}');
      }
      return jsonDecode(raw) as Map<String, dynamic>;
    } finally { client.close(force: true); }
  }

  static Future<Map<String, dynamic>> submitSession(String token, Map<String, dynamic> session) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(Uri.parse('$base/api/companion/time/session'));
      request.headers.contentType = ContentType.json;
      request.headers.set('X-Companion-Token', token);
      request.add(utf8.encode(jsonEncode(session)));
      final response = await request.close().timeout(const Duration(seconds: 15));
      final raw = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) throw HttpException('Time report HTTP ${response.statusCode}: $raw');
      return jsonDecode(raw) as Map<String, dynamic>;
    } finally { client.close(force: true); }
  }

  static Future<Map<String, dynamic>> inviteRequest(String token, String method, String path, [Map<String, dynamic>? data]) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse('$base/api/companion/invites/$path');
      final request = await client.openUrl(method, uri);
      request.headers.set('X-Companion-Token', token);
      if (data != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(data)));
      }
      final response = await request.close().timeout(const Duration(seconds: 20));
      final raw = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) throw HttpException('Invite request HTTP ${response.statusCode}');
      return jsonDecode(raw) as Map<String, dynamic>;
    } finally { client.close(force: true); }
  }

  static Future<Map<String, dynamic>> profile(String token) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse('$base/api/companion/profile'));
      request.headers.set('X-Companion-Token', token);
      final response = await request.close().timeout(const Duration(seconds: 15));
      final raw = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) throw HttpException('Profile rejected (HTTP ${response.statusCode})');
      return jsonDecode(raw) as Map<String, dynamic>;
    } finally { client.close(force: true); }
  }
}

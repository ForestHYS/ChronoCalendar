import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'auth_token_storage.dart';

/// 统一请求 `/api/v1/...`，解析 `{ "data": ... }` / `{ "error": ... }`，处理 401 刷新。
class ApiClient {
  ApiClient(this._prefs);

  final SharedPreferences _prefs;

  Uri _uri(String path) {
    final p = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('${ApiConfig.baseUrl}/api/v1/$p');
  }

  Map<String, String> _headers({bool withAuth = true}) {
    final h = <String, String>{'Content-Type': 'application/json; charset=utf-8'};
    if (withAuth) {
      final t = _prefs.getString(AuthTokenStorage.accessTokenKey);
      if (t != null && t.isNotEmpty) {
        h['Authorization'] = 'Bearer $t';
      }
    }
    return h;
  }

  Object? _unwrapData(http.Response r) {
    if (r.statusCode == 204 || r.body.isEmpty) return null;
    final decoded = jsonDecode(r.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('响应格式错误');
    }
    if (decoded.containsKey('data')) return decoded['data'];
    if (decoded.containsKey('error')) {
      final err = decoded['error'];
      if (err is Map<String, dynamic>) {
        throw ApiException(
          err['message'] as String? ?? '请求失败',
          code: err['code'] as String?,
        );
      }
    }
    throw ApiException('响应格式错误');
  }

  Future<bool> _tryRefresh() async {
    final refresh = _prefs.getString(AuthTokenStorage.refreshTokenKey);
    if (refresh == null || refresh.isEmpty) return false;
    final uri = _uri('auth/refresh/');
    final resp = await http.post(
      uri,
      headers: _headers(withAuth: false),
      body: jsonEncode({'refresh_token': refresh}),
    );
    if (resp.statusCode != 200) return false;
    try {
      final data = _unwrapData(resp);
      if (data is Map<String, dynamic>) {
        final access = data['access_token'] as String?;
        if (access != null && access.isNotEmpty) {
          await _prefs.setString(AuthTokenStorage.accessTokenKey, access);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<Object?> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    Future<http.Response> send() async {
      final uri = _uri(path);
      final encoded = body != null ? jsonEncode(body) : null;
      final headers = _headers(withAuth: auth);
      try {
        switch (method.toUpperCase()) {
          case 'GET':
            return await http.get(uri, headers: headers);
          case 'POST':
            return await http.post(uri, headers: headers, body: encoded);
          case 'PATCH':
            return await http.patch(uri, headers: headers, body: encoded);
          case 'DELETE':
            return await http.delete(uri, headers: headers);
          default:
            throw ApiException('不支持的 HTTP 方法: $method');
        }
      } on SocketException {
        throw ApiException('无法连接服务器，请检查网络与 API 地址');
      } on http.ClientException {
        throw ApiException('网络请求失败，请稍后重试');
      }
    }

    http.Response resp;
    try {
      resp = await send();
    } on ApiException {
      rethrow;
    }
    if (auth && resp.statusCode == 401) {
      final ok = await _tryRefresh();
      if (ok) resp = await send();
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return _unwrapData(resp);
    }

    if (resp.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic> && decoded['error'] is Map<String, dynamic>) {
          final err = decoded['error'] as Map<String, dynamic>;
          throw ApiException(
            err['message'] as String? ?? '请求失败',
            code: err['code'] as String?,
          );
        }
      } catch (e) {
        if (e is ApiException) rethrow;
      }
    }
    throw ApiException('HTTP ${resp.statusCode}');
  }
}

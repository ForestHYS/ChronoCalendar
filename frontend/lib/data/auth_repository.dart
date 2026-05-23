import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../core/api/auth_token_storage.dart';

const _kEmail = 'user_email';
const _kNickname = 'user_nickname';
const _kUserName = 'auth_user_name';

class AuthRepository {
  AuthRepository(this._prefs, this._api);

  final SharedPreferences _prefs;
  final ApiClient _api;

  bool get isLoggedIn {
    final t = _prefs.getString(AuthTokenStorage.accessTokenKey);
    return t != null && t.isNotEmpty;
  }

  String? get savedEmail => _prefs.getString(_kEmail);

  String get nickname =>
      _prefs.getString(_kNickname)?.trim().isNotEmpty == true
          ? _prefs.getString(_kNickname)!
          : (_prefs.getString(_kUserName) ?? '用户');

  Future<void> _persistSessionFromAuthData(Map<String, dynamic> data, String email) async {
    final access = data['access_token'] as String?;
    final refresh = data['refresh_token'] as String?;
    if (access == null || access.isEmpty) {
      throw ArgumentError('响应缺少 access_token');
    }
    await _prefs.setString(AuthTokenStorage.accessTokenKey, access);
    if (refresh != null && refresh.isNotEmpty) {
      await _prefs.setString(AuthTokenStorage.refreshTokenKey, refresh);
    }
    await _prefs.setString(_kEmail, email);
    final user = data['user'];
    if (user is Map<String, dynamic>) {
      final name = user['name'] as String?;
      if (name != null && name.isNotEmpty) {
        await _prefs.setString(_kUserName, name);
        await _prefs.setString(_kNickname, name);
      }
    }
  }

  Future<void> login(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      throw ArgumentError('邮箱与密码不能为空');
    }
    final data = await _api.request(
      'POST',
      'auth/login/',
      body: {'email': email, 'password': password},
      auth: false,
    );
    if (data is! Map<String, dynamic>) {
      throw ArgumentError('登录响应无效');
    }
    await _persistSessionFromAuthData(data, email);
  }

  Future<void> register({
    required String email,
    required String password,
    String? name,
  }) async {
    if (email.isEmpty || password.isEmpty) {
      throw ArgumentError('邮箱与密码不能为空');
    }
    if (password.length < 6) {
      throw ArgumentError('密码至少 6 位');
    }
    final body = <String, dynamic>{
      'email': email,
      'password': password,
    };
    final n = name?.trim();
    if (n != null && n.isNotEmpty) {
      body['name'] = n;
    }
    final data = await _api.request(
      'POST',
      'auth/register/',
      body: body,
      auth: false,
    );
    if (data is! Map<String, dynamic>) {
      throw ArgumentError('注册响应无效');
    }
    await _persistSessionFromAuthData(data, email);
  }

  /// PATCH /auth/me/，同步本地昵称缓存。
  Future<void> updateNickname(String nickname) async {
    final n = nickname.trim();
    if (n.isEmpty) throw ArgumentError('昵称不能为空');
    if (n.length > 150) throw ArgumentError('昵称不能超过 150 个字符');
    final data = await _api.request(
      'PATCH',
      'auth/me/',
      body: {'name': n},
      auth: true,
    );
    if (data is Map<String, dynamic>) {
      final name = data['name'] as String? ?? n;
      await _prefs.setString(_kNickname, name);
      await _prefs.setString(_kUserName, name);
    } else {
      await _prefs.setString(_kNickname, n);
      await _prefs.setString(_kUserName, n);
    }
  }

  /// POST /auth/change-password/，修改服务端密码。
  Future<void> changePassword({required String current, required String next}) async {
    if (current.trim().isEmpty || next.trim().isEmpty) {
      throw ArgumentError('密码不能为空');
    }
    if (next.length < 6) {
      throw ArgumentError('新密码至少 6 位');
    }
    await _api.request(
      'POST',
      'auth/change-password/',
      body: {
        'current_password': current,
        'new_password': next,
      },
      auth: true,
    );
  }

  Future<void> logout() async {
    try {
      final refresh = _prefs.getString(AuthTokenStorage.refreshTokenKey);
      await _api.request(
        'POST',
        'auth/logout/',
        body: refresh != null && refresh.isNotEmpty ? {'refresh_token': refresh} : <String, dynamic>{},
        auth: true,
      );
    } catch (_) {}
    await _prefs.remove(AuthTokenStorage.accessTokenKey);
    await _prefs.remove(AuthTokenStorage.refreshTokenKey);
    await _prefs.remove(_kEmail);
    await _prefs.remove(_kNickname);
    await _prefs.remove(_kUserName);
  }
}

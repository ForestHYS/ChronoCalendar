import 'package:shared_preferences/shared_preferences.dart';

const _kToken = 'access_token';
const _kEmail = 'user_email';

/// 演示用本地登录。// TODO: 替换为 Dio + POST /api/v1/auth/login
class AuthRepository {
  AuthRepository(this._prefs);

  final SharedPreferences _prefs;

  bool get isLoggedIn => _prefs.getString(_kToken) != null;

  String? get savedEmail => _prefs.getString(_kEmail);

  Future<void> login(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      throw ArgumentError('邮箱与密码不能为空');
    }
    await _prefs.setString(_kToken, 'mock_token');
    await _prefs.setString(_kEmail, email);
  }

  Future<void> logout() async {
    await _prefs.remove(_kToken);
    await _prefs.remove(_kEmail);
  }
}

import 'package:shared_preferences/shared_preferences.dart';

const _kToken = 'access_token';
const _kEmail = 'user_email';
const _kNickname = 'user_nickname';
const _kPassword = 'user_password'; // demo only

/// 演示用本地登录。// TODO: 替换为 Dio + POST /api/v1/auth/login
class AuthRepository {
  AuthRepository(this._prefs);

  final SharedPreferences _prefs;

  bool get isLoggedIn => _prefs.getString(_kToken) != null;

  String? get savedEmail => _prefs.getString(_kEmail);

  String get nickname => _prefs.getString(_kNickname) ?? 'Forest';

  Future<void> login(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      throw ArgumentError('邮箱与密码不能为空');
    }
    await _prefs.setString(_kToken, 'mock_token');
    await _prefs.setString(_kEmail, email);
    await _prefs.setString(_kPassword, password);
    await _prefs.setString(_kNickname, _prefs.getString(_kNickname) ?? email.split('@').first);
  }

  Future<void> updateNickname(String nickname) async {
    final n = nickname.trim();
    if (n.isEmpty) throw ArgumentError('昵称不能为空');
    await _prefs.setString(_kNickname, n);
  }

  Future<void> changePassword({required String current, required String next}) async {
    if (current.trim().isEmpty || next.trim().isEmpty) {
      throw ArgumentError('密码不能为空');
    }
    final saved = _prefs.getString(_kPassword);
    if (saved != null && saved != current) {
      throw ArgumentError('当前密码不正确');
    }
    if (next.length < 6) {
      throw ArgumentError('新密码至少 6 位');
    }
    await _prefs.setString(_kPassword, next);
  }

  Future<void> logout() async {
    await _prefs.remove(_kToken);
    await _prefs.remove(_kEmail);
  }
}

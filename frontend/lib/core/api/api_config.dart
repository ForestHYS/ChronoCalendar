/// 后端根地址（不含 `/api/v1`）。
/// 构建时可传：`--dart-define=API_BASE_URL=http://10.0.2.2:8000`
abstract final class ApiConfig {
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    final raw = fromEnv.isNotEmpty ? fromEnv : 'http://127.0.0.1:8000';
    return raw.replaceAll(RegExp(r'/$'), '');
  }
}

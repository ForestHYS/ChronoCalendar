/// 后端根地址（不含 `/api/v1`）。
///
/// Release APKs must provide this value at build time, for example:
/// `--dart-define=API_BASE_URL=https://api.example.com或者http://10.0.2.2:8000`
abstract final class ApiConfig {
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    final raw = fromEnv.isNotEmpty ? fromEnv : 'http://127.0.0.1:8000';
    return raw.replaceAll(RegExp(r'/$'), '');
  }
}

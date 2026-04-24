/// 与 [AuthRepository] 共用键名，供 [ApiClient] 读写 Token。
abstract final class AuthTokenStorage {
  static const accessTokenKey = 'access_token';
  static const refreshTokenKey = 'refresh_token';
}

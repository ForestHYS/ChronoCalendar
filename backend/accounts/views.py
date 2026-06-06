"""
accounts/views.py

认证相关视图：注册、登录、刷新 Token、登出。
使用 SimpleJWT 生成/校验 token，无需额外存储 session。
"""

from django.contrib.auth import get_user_model
from rest_framework import serializers, status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken

User = get_user_model()


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

def _token_pair(user) -> dict:
    """为指定用户生成 access + refresh token 对。"""
    refresh = RefreshToken.for_user(user)
    return {
        "access_token": str(refresh.access_token),
        "refresh_token": str(refresh),
        "user": {"id": str(user.id), "name": user.get_full_name() or user.username},
    }


# ---------------------------------------------------------------------------
# 序列化器
# ---------------------------------------------------------------------------

class RegisterSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(min_length=6, write_only=True)
    name = serializers.CharField(max_length=150, required=False, default="")

    def validate_email(self, value):
        if User.objects.filter(email=value).exists():
            raise serializers.ValidationError("该邮箱已被注册")
        return value

    def create(self, validated_data):
        name = validated_data.pop("name", "")
        user = User(
            email=validated_data["email"],
            username=validated_data["email"],  # username 设为 email
        )
        if name:
            parts = name.split(" ", 1)
            user.first_name = parts[0]
            user.last_name = parts[1] if len(parts) > 1 else ""
        user.set_password(validated_data["password"])
        user.save()
        return user


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)


class RefreshSerializer(serializers.Serializer):
    refresh_token = serializers.CharField()


# ---------------------------------------------------------------------------
# 视图
# ---------------------------------------------------------------------------

class RegisterView(APIView):
    """
    POST /auth/register/
    Body: { "email": "...", "password": "...", "name": "..." }
    Resp: { "data": { "access_token": "...", "refresh_token": "...", "user": {...} } }
    """
    permission_classes = [AllowAny]

    def post(self, request):
        s = RegisterSerializer(data=request.data)
        if not s.is_valid():
            return Response(
                {"error": {"code": "VALIDATION_ERROR", "message": "输入数据无效", "details": s.errors}},
                status=status.HTTP_400_BAD_REQUEST,
            )
        user = s.save()
        return Response({"data": _token_pair(user)}, status=status.HTTP_201_CREATED)


class LoginView(APIView):
    """
    POST /auth/login/
    Body: { "email": "...", "password": "..." }
    Resp: { "data": { "access_token": "...", "refresh_token": "...", "user": {...} } }
    """
    permission_classes = [AllowAny]

    def post(self, request):
        s = LoginSerializer(data=request.data)
        if not s.is_valid():
            return Response(
                {"error": {"code": "VALIDATION_ERROR", "message": "输入数据无效", "details": s.errors}},
                status=status.HTTP_400_BAD_REQUEST,
            )

        email = s.validated_data["email"]
        password = s.validated_data["password"]

        try:
            user = User.objects.get(email=email)
        except User.DoesNotExist:
            return Response(
                {"error": {"code": "INVALID_CREDENTIALS", "message": "邮箱或密码错误"}},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        if not user.check_password(password):
            return Response(
                {"error": {"code": "INVALID_CREDENTIALS", "message": "邮箱或密码错误"}},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        if not user.is_active:
            return Response(
                {"error": {"code": "ACCOUNT_DISABLED", "message": "账号已被禁用"}},
                status=status.HTTP_403_FORBIDDEN,
            )

        return Response({"data": _token_pair(user)})


class RefreshView(APIView):
    """
    POST /auth/refresh/
    Body: { "refresh_token": "..." }
    Resp: { "data": { "access_token": "..." } }
    """
    permission_classes = [AllowAny]

    def post(self, request):
        s = RefreshSerializer(data=request.data)
        if not s.is_valid():
            return Response(
                {"error": {"code": "VALIDATION_ERROR", "message": "输入数据无效", "details": s.errors}},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            refresh = RefreshToken(s.validated_data["refresh_token"])
            return Response({"data": {"access_token": str(refresh.access_token)}})
        except TokenError as e:
            return Response(
                {"error": {"code": "INVALID_TOKEN", "message": str(e)}},
                status=status.HTTP_401_UNAUTHORIZED,
            )


class ProfileView(APIView):
    """
    PATCH /auth/me/
    Body: { "name": "昵称" }
    """

    permission_classes = [IsAuthenticated]

    def patch(self, request):
        name = (request.data.get("name") or "").strip()
        if not name:
            return Response(
                {"error": {"code": "VALIDATION_ERROR", "message": "昵称不能为空"}},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if len(name) > 150:
            return Response(
                {"error": {"code": "VALIDATION_ERROR", "message": "昵称过长（最多 150 字）"}},
                status=status.HTTP_400_BAD_REQUEST,
            )
        user = request.user
        parts = name.split(" ", 1)
        user.first_name = parts[0]
        user.last_name = parts[1] if len(parts) > 1 else ""
        user.save(update_fields=["first_name", "last_name"])
        return Response(
            {"data": {"id": str(user.id), "name": user.get_full_name() or user.username}}
        )

    def delete(self, request):
        current = request.data.get("current_password") or ""
        if not current:
            return Response(
                {"error": {"code": "VALIDATION_ERROR", "message": "请填写当前密码"}},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user = request.user
        if not user.check_password(current):
            return Response(
                {"error": {"code": "INVALID_CREDENTIALS", "message": "当前密码不正确"}},
                status=status.HTTP_400_BAD_REQUEST,
            )

        refresh_token = request.data.get("refresh_token")
        if refresh_token:
            try:
                RefreshToken(refresh_token).blacklist()
            except Exception:
                pass

        user.delete()
        return Response({"data": {"ok": True}})


class ChangePasswordView(APIView):
    """
    POST /auth/change-password/
    Body: { "current_password": "...", "new_password": "..." }
    """

    permission_classes = [IsAuthenticated]

    def post(self, request):
        current = request.data.get("current_password") or ""
        new_pw = request.data.get("new_password") or ""
        if not current or not new_pw:
            return Response(
                {"error": {"code": "VALIDATION_ERROR", "message": "请填写当前密码与新密码"}},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if len(new_pw) < 6:
            return Response(
                {"error": {"code": "VALIDATION_ERROR", "message": "新密码至少 6 位"}},
                status=status.HTTP_400_BAD_REQUEST,
            )
        user = request.user
        if not user.check_password(current):
            return Response(
                {"error": {"code": "INVALID_CREDENTIALS", "message": "当前密码不正确"}},
                status=status.HTTP_400_BAD_REQUEST,
            )
        user.set_password(new_pw)
        user.save(update_fields=["password"])
        return Response({"data": {"ok": True}})


class LogoutView(APIView):
    """
    POST /auth/logout/
    Header: Authorization: Bearer <access_token>
    Body:   { "refresh_token": "..." }

    将 refresh_token 加入黑名单（需在 settings 启用 token_blacklist）。
    若未启用黑名单，服务端无状态，客户端删除本地 token 即视为登出。
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        refresh_token = request.data.get("refresh_token")
        if not refresh_token:
            return Response(status=status.HTTP_204_NO_CONTENT)

        try:
            token = RefreshToken(refresh_token)
            token.blacklist()  # 需在 INSTALLED_APPS 中添加 rest_framework_simplejwt.token_blacklist
        except Exception:
            pass  # 黑名单未启用或 token 已失效，均视为登出成功

        return Response(status=status.HTTP_204_NO_CONTENT)

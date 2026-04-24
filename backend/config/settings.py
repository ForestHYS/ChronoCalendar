"""
config/settings.py

开发环境配置。生产部署时请：
  1. 将 SECRET_KEY 替换为真实随机值（可用 python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"）
  2. 将 DEBUG 设为 False
  3. 配置 ALLOWED_HOSTS
  4. 将 DATABASES 切换为 PostgreSQL
"""

from datetime import timedelta
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

# ------------------------------------------------------------------ #
# 安全
# ------------------------------------------------------------------ #
SECRET_KEY = "django-insecure-change-me-before-production"
DEBUG = True
ALLOWED_HOSTS = ["*"]

# ------------------------------------------------------------------ #
# 应用
# ------------------------------------------------------------------ #
INSTALLED_APPS = [
    # Django 最小核心（本项目无管理后台）
    "django.contrib.auth",
    "django.contrib.contenttypes",
    # 第三方
    "corsheaders",
    "rest_framework",
    "rest_framework_simplejwt",
    # 本项目
    "accounts",
    "tasks",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.common.CommonMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"

# ------------------------------------------------------------------ #
# 数据库（开发默认 SQLite；生产切换为 PostgreSQL）
# ------------------------------------------------------------------ #
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "db.sqlite3",
    }
    # PostgreSQL 示例：
    # "default": {
    #     "ENGINE": "django.db.backends.postgresql",
    #     "NAME": "chronocalendar",
    #     "USER": "postgres",
    #     "PASSWORD": "yourpassword",
    #     "HOST": "localhost",
    #     "PORT": "5432",
    # }
}

# ------------------------------------------------------------------ #
# 用户模型
# ------------------------------------------------------------------ #
AUTH_USER_MODEL = "tasks.User"

# ------------------------------------------------------------------ #
# Django REST Framework
# ------------------------------------------------------------------ #
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
    ],
    "DEFAULT_RENDERER_CLASSES": [
        "rest_framework.renderers.JSONRenderer",
    ],
    # 统一异常响应格式
    "EXCEPTION_HANDLER": "tasks.exceptions.custom_exception_handler",
}

# ------------------------------------------------------------------ #
# SimpleJWT
# ------------------------------------------------------------------ #
SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(hours=2),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=30),
    "AUTH_HEADER_TYPES": ("Bearer",),
    "UPDATE_LAST_LOGIN": False,
}

# ------------------------------------------------------------------ #
# 时区与时间
# ------------------------------------------------------------------ #
USE_TZ = True
TIME_ZONE = "UTC"
LANGUAGE_CODE = "zh-hans"

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# ------------------------------------------------------------------ #
# CORS（Flutter Web / 浏览器跨域；需安装 django-cors-headers）
# ------------------------------------------------------------------ #
CORS_ALLOW_ALL_ORIGINS = True  # 开发用；生产请改为 CORS_ALLOWED_ORIGINS 白名单

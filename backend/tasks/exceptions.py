"""
tasks/exceptions.py

将 DRF 的默认异常响应包装为统一的 { "error": {...} } 格式。
"""

from rest_framework.views import exception_handler


def custom_exception_handler(exc, context):
    response = exception_handler(exc, context)
    if response is not None:
        original = response.data
        # 尝试提取第一条错误信息作为 message
        if isinstance(original, dict):
            message = "; ".join(
                f"{k}: {v[0] if isinstance(v, list) else v}"
                for k, v in original.items()
            )
        elif isinstance(original, list):
            message = str(original[0]) if original else "Unknown error"
        else:
            message = str(original)

        response.data = {
            "error": {
                "code": "ERROR",
                "message": message,
                "details": original,
            }
        }
    return response

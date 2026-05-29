"""从 client_context 解析用户时区，并提供本地时间格式化。"""
from __future__ import annotations

from datetime import datetime, time, timedelta, timezone as dt_timezone
from typing import Any, Dict, Optional
from zoneinfo import ZoneInfo

from django.utils import timezone as dj_timezone


def resolve_user_tz(client_context: Optional[Dict[str, Any]]):
    """返回用户时区（zoneinfo 或 fixed offset），无法解析时退回 UTC。"""
    ctx = client_context or {}

    for key in ("timezone", "iana_timezone", "time_zone"):
        name = (ctx.get(key) or "").strip()
        if name:
            try:
                return ZoneInfo(name)
            except Exception:
                pass

    off = ctx.get("timezone_offset_minutes")
    if off is not None:
        try:
            minutes = int(off)
            if -14 * 60 <= minutes <= 14 * 60:
                return dt_timezone(timedelta(minutes=minutes))
        except (TypeError, ValueError):
            pass

    return ZoneInfo("UTC")


def format_dt_local(
    dt: Optional[datetime],
    client_context: Optional[Dict[str, Any]],
) -> str:
    """将 aware datetime 格式化为用户本地可读字符串。"""
    if dt is None:
        return ""
    tz = resolve_user_tz(client_context)
    local = dt.astimezone(tz)
    return local.strftime("%Y-%m-%d %H:%M")


def user_now(client_context: Optional[Dict[str, Any]]) -> datetime:
    """当前时刻，转换为用户本地 aware datetime。"""
    tz = resolve_user_tz(client_context)
    return dj_timezone.now().astimezone(tz)


def user_now_payload(client_context: Optional[Dict[str, Any]]) -> Dict[str, str]:
    """供 LLM 使用的本地时间与元数据。"""
    tz = resolve_user_tz(client_context)
    now = user_now(client_context)
    label = getattr(tz, "key", None) or str(tz)
    return {
        "now_local": now.isoformat(),
        "timezone": label,
        "utc_offset_minutes": int(now.utcoffset().total_seconds() // 60) if now.utcoffset() else 0,
        "weekday": now.strftime("%A"),
        "date_local": now.strftime("%Y-%m-%d"),
        "time_local": now.strftime("%H:%M"),
    }


def local_day_range_iso(
    client_context: Optional[Dict[str, Any]],
    *,
    day_offset: int = 0,
) -> Dict[str, str]:
    """按用户本地日历日生成查询区间 [当日 0:00, 次日 0:00)。day_offset：0=今天，1=明天。"""
    tz = resolve_user_tz(client_context)
    now = user_now(client_context)
    d = now.date() + timedelta(days=day_offset)
    start = dj_timezone.make_aware(datetime.combine(d, time.min), tz)
    end = dj_timezone.make_aware(datetime.combine(d + timedelta(days=1), time.min), tz)
    label = "今天" if day_offset == 0 else ("明天" if day_offset == 1 else f"+{day_offset}天")
    return {
        "label": label,
        "range_from": start.isoformat(),
        "range_to": end.isoformat(),
    }


def calendar_range_hints(client_context: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    return {
        "today": local_day_range_iso(client_context, day_offset=0),
        "tomorrow": local_day_range_iso(client_context, day_offset=1),
    }


def timezone_prompt_lines(client_context: Optional[Dict[str, Any]]) -> str:
    p = user_now_payload(client_context)
    return (
        f"- 用户时区：{p['timezone']}（UTC{p['utc_offset_minutes']:+d} 分钟）\n"
        f"- 用户本地现在：{p['date_local']} {p['time_local']}（{p['now_local']}）\n"
        "- 用户说的「今天/明天/现在几点」均指上述本地时间，勿用服务器 UTC 替代。\n"
        "- 任务时间写入 API 须为 ISO 8601 UTC（带 Z 或 +00:00）；"
        "从用户口语生成时间时，先按用户本地理解再换算为 UTC。\n"
    )

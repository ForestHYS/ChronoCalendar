import json
import uuid
from datetime import datetime, timedelta
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone

from tasks.models import FocusSession, Task, User
from tasks.views import _apply_import


DEFAULT_EMAIL = "test@thu.cn"
DEFAULT_PASSWORD = "test996"


FOCUS_ROWS = [
    ("20000000-0000-4000-8000-000000000015", 0, 9, 0, 1500, 1500, "timeout"),
    ("20000000-0000-4000-8000-000000000009", 0, 10, 0, 3000, 2700, "manual"),
    ("20000000-0000-4000-8000-000000000020", 0, 15, 0, 1500, 1320, "manual"),
    ("20000000-0000-4000-8000-000000000016", 1, 8, 30, 1500, 1500, "timeout"),
    ("20000000-0000-4000-8000-000000000017", 1, 13, 30, 3000, 3000, "timeout"),
    ("20000000-0000-4000-8000-000000000023", 1, 20, 0, 1500, 1200, "manual"),
    ("20000000-0000-4000-8000-000000000001", 2, 9, 0, 1500, 1500, "timeout"),
    ("20000000-0000-4000-8000-000000000004", 2, 14, 0, 3000, 2400, "manual"),
    ("20000000-0000-4000-8000-000000000019", 2, 18, 30, 1500, 900, "manual"),
    ("20000000-0000-4000-8000-000000000005", 3, 10, 0, 1500, 1500, "timeout"),
    ("20000000-0000-4000-8000-000000000016", 3, 15, 0, 1500, 1380, "manual"),
    ("20000000-0000-4000-8000-000000000020", 3, 20, 0, 3000, 3000, "timeout"),
    ("20000000-0000-4000-8000-000000000017", 4, 8, 0, 1500, 1500, "timeout"),
    ("20000000-0000-4000-8000-000000000009", 4, 11, 0, 1500, 1200, "manual"),
    ("20000000-0000-4000-8000-000000000015", 4, 19, 30, 3000, 2700, "manual"),
    ("20000000-0000-4000-8000-000000000004", 5, 9, 30, 1500, 1500, "timeout"),
    ("20000000-0000-4000-8000-000000000023", 5, 14, 30, 3000, 2520, "manual"),
    ("20000000-0000-4000-8000-000000000020", 5, 21, 0, 1500, 1500, "timeout"),
    ("20000000-0000-4000-8000-000000000008", 6, 10, 0, 3000, 2700, "manual"),
    ("20000000-0000-4000-8000-000000000011", 6, 16, 0, 1500, 900, "manual"),
    ("20000000-0000-4000-8000-000000000003", 6, 18, 0, 1500, 1200, "manual"),
    ("20000000-0000-4000-8000-000000000018", 7, 11, 0, 1500, 900, "manual"),
    ("20000000-0000-4000-8000-000000000021", 7, 15, 0, 1500, 1200, "manual"),
    ("20000000-0000-4000-8000-000000000022", 7, 20, 0, 1500, 900, "manual"),
]


class Command(BaseCommand):
    help = "Create the demo account, import sample tasks, and seed focus sessions."

    def add_arguments(self, parser):
        default_json = (
            Path(__file__).resolve().parents[3]
            / "demo_data"
            / "test_tasks_import.json"
        )
        parser.add_argument("--email", default=DEFAULT_EMAIL)
        parser.add_argument("--password", default=DEFAULT_PASSWORD)
        parser.add_argument("--json", default=str(default_json))
        parser.add_argument(
            "--force-reset",
            action="store_true",
            help="Delete the existing user (if any) before seeding.",
        )
        parser.add_argument(
            "--skip-import",
            action="store_true",
            help="Only rebuild focus sessions for already imported tasks.",
        )

    def handle(self, *args, **options):
        json_path = Path(options["json"]).resolve()
        if not json_path.exists():
            raise CommandError(f"Import JSON not found: {json_path}")

        with json_path.open("r", encoding="utf-8") as f:
            payload = json.load(f)

        email = options["email"]
        password = options["password"]
        force_reset = options["force_reset"]

        with transaction.atomic():
            if force_reset:
                User.objects.filter(email=email).delete()
            user, created = User.objects.get_or_create(
                email=email,
                defaults={"username": email},
            )
            user.username = user.username or email
            user.set_password(password)
            user.save()

            if not options["skip_import"]:
                summary = _apply_import(user, payload, "merge")
            else:
                summary = {"tags": {"created": 0, "reused": 0}, "tasks": {"created": 0, "updated": 0}}

            task_ids = [uuid.UUID(row[0]) for row in FOCUS_ROWS]
            tasks = Task.objects.filter(user=user, id__in=task_ids).in_bulk()
            missing = sorted(str(tid) for tid in set(task_ids) if tid not in tasks)
            if missing:
                raise CommandError(
                    "Focus seed references tasks that do not exist: "
                    + ", ".join(missing)
                )

            FocusSession.objects.filter(user=user, task_id__in=set(task_ids)).delete()
            sessions = []
            for index, row in enumerate(FOCUS_ROWS, start=1):
                task_id, days_ago, hour, minute, planned, actual, reason = row
                started_at = self._window_time(days_ago, hour, minute)
                sessions.append(
                    FocusSession(
                        id=uuid.UUID(f"40000000-0000-4000-8000-{index:012d}"),
                        user=user,
                        task=tasks[uuid.UUID(task_id)],
                        status=FocusSession.Status.STOPPED,
                        started_at=started_at,
                        ended_at=started_at + timedelta(seconds=actual),
                        planned_seconds=planned,
                        actual_seconds=actual,
                        stop_reason=reason,
                        noise_id="demo",
                    )
                )
            FocusSession.objects.bulk_create(sessions)

        self.stdout.write(
            self.style.SUCCESS(
                f"Seeded {email}: user_created={created}, "
                f"tags={summary['tags']}, tasks={summary['tasks']}, "
                f"focus_sessions={len(FOCUS_ROWS)}"
            )
        )

    def _window_time(self, days_ago, hour, minute):
        today = timezone.localdate()
        dt = datetime.combine(
            today - timedelta(days=days_ago),
            datetime.min.time(),
        ).replace(hour=hour, minute=minute)
        if timezone.is_naive(dt):
            return timezone.make_aware(dt, timezone.get_current_timezone())
        return dt

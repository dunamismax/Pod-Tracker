import os
from datetime import datetime, timedelta
from pathlib import Path
from tempfile import TemporaryDirectory
from zoneinfo import ZoneInfo

from django.test import SimpleTestCase, TestCase
from django.urls import reverse
from django.utils import timezone

from podwatch.env import load_dotenv
from podwatch.middleware import TIMEZONE_COOKIE_NAME

from .models import Event, Pod


class EnvLoaderTests(SimpleTestCase):
    def test_load_dotenv_reads_env_file_without_overwriting_existing_values(self) -> None:
        keys = ["PODWATCH_DOTENV_NEW", "PODWATCH_DOTENV_OLD", "PODWATCH_DOTENV_EXPORT"]
        original_values = {key: os.environ.get(key) for key in keys}

        try:
            with TemporaryDirectory() as temp_dir:
                env_path = Path(temp_dir) / ".env"
                env_path.write_text(
                    "\n".join(
                        [
                            "# sample",
                            "PODWATCH_DOTENV_NEW=from-file",
                            "PODWATCH_DOTENV_OLD=from-file",
                            "export PODWATCH_DOTENV_EXPORT=from-export",
                        ]
                    ),
                    encoding="utf-8",
                )

                os.environ.pop("PODWATCH_DOTENV_NEW", None)
                os.environ["PODWATCH_DOTENV_OLD"] = "from-env"
                os.environ.pop("PODWATCH_DOTENV_EXPORT", None)

                load_dotenv(Path(temp_dir))

                self.assertEqual(os.environ["PODWATCH_DOTENV_NEW"], "from-file")
                self.assertEqual(os.environ["PODWATCH_DOTENV_OLD"], "from-env")
                self.assertEqual(os.environ["PODWATCH_DOTENV_EXPORT"], "from-export")
        finally:
            for key, value in original_values.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value


class DashboardTests(TestCase):
    def test_dashboard_renders(self) -> None:
        response = self.client.get(reverse("pods:dashboard"))

        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "PodWatch")
        self.assertContains(response, "Create a pod")
        self.assertContains(response, 'name="timezone"', html=False)

    def test_create_pod(self) -> None:
        response = self.client.post(
            reverse("pods:create_pod"),
            {
                "name": "Friday Pod",
                "description": "Casual recurring group.",
            },
        )

        self.assertRedirects(response, reverse("pods:dashboard"))
        self.assertTrue(Pod.objects.filter(name="Friday Pod").exists())

    def test_create_pod_rejects_duplicate_name_case_insensitively(self) -> None:
        Pod.objects.create(name="Friday Pod", description="First pod.")

        response = self.client.post(
            reverse("pods:create_pod"),
            {
                "name": "friday pod",
                "description": "Duplicate pod.",
            },
        )

        self.assertEqual(response.status_code, 400)
        self.assertContains(response, "A pod with this name already exists.", status_code=400)
        self.assertEqual(Pod.objects.count(), 1)

    def test_create_event(self) -> None:
        pod = Pod.objects.create(name="Archive Pod", description="Keeps the dates straight.")
        scheduled_for = timezone.localtime(timezone.now() + timedelta(days=2)).replace(
            second=0,
            microsecond=0,
        )

        response = self.client.post(
            reverse("pods:create_event"),
            {
                "pod": pod.pk,
                "title": "Monthly Planning",
                "location": "Back room",
                "scheduled_for": scheduled_for.strftime("%Y-%m-%dT%H:%M"),
                "description": "Bring the draft agenda.",
            },
        )

        self.assertRedirects(response, reverse("pods:dashboard"))
        self.assertTrue(
            Event.objects.filter(
                pod=pod,
                title="Monthly Planning",
                location="Back room",
            ).exists()
        )

    def test_create_event_uses_submitted_browser_timezone(self) -> None:
        pod = Pod.objects.create(name="Phoenix Pod", description="Keeps the dates straight.")

        response = self.client.post(
            reverse("pods:create_event"),
            {
                "pod": pod.pk,
                "title": "Summer Meetup",
                "location": "Community center",
                "scheduled_for": "2026-07-10T19:00",
                "timezone": "America/Phoenix",
                "description": "Bring water.",
            },
        )

        self.assertRedirects(response, reverse("pods:dashboard"))
        event = Event.objects.get(title="Summer Meetup")
        self.assertEqual(
            event.scheduled_for,
            datetime(2026, 7, 11, 2, 0, tzinfo=ZoneInfo("UTC")),
        )
        self.assertEqual(response.cookies[TIMEZONE_COOKIE_NAME].value, "America/Phoenix")

    def test_dashboard_renders_events_in_cookie_timezone(self) -> None:
        pod = Pod.objects.create(name="Archive Pod", description="Keeps the dates straight.")
        Event.objects.create(
            pod=pod,
            title="Summer Meetup",
            location="Community center",
            scheduled_for=datetime(2026, 7, 11, 2, 0, tzinfo=ZoneInfo("UTC")),
            description="Bring water.",
        )

        self.client.cookies[TIMEZONE_COOKIE_NAME] = "America/Phoenix"
        response = self.client.get(reverse("pods:dashboard"))

        self.assertContains(response, "Jul 10, 2026 7:00 PM MST")

    def test_invalid_event_returns_dashboard_with_errors(self) -> None:
        response = self.client.post(
            reverse("pods:create_event"),
            {
                "title": "Missing Pod",
                "scheduled_for": "",
            },
        )

        self.assertEqual(response.status_code, 400)
        self.assertContains(response, "This field is required.", status_code=400)

    def test_event_scheduled_for_field_is_indexed(self) -> None:
        self.assertTrue(Event._meta.get_field("scheduled_for").db_index)

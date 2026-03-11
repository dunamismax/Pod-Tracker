from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from django.http import HttpRequest, HttpResponse
from django.utils import timezone


TIMEZONE_COOKIE_NAME = "podwatch_timezone"


def get_timezone(timezone_name: str | None) -> ZoneInfo | None:
    if not timezone_name:
        return None

    try:
        return ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError:
        return None


class BrowserTimezoneMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        timezone_name = self.get_timezone_name(request)
        tzinfo = get_timezone(timezone_name)

        if tzinfo is None:
            timezone.deactivate()
        else:
            timezone.activate(tzinfo)

        response = self.get_response(request)

        if timezone_name and request.COOKIES.get(TIMEZONE_COOKIE_NAME) != timezone_name:
            response.set_cookie(
                TIMEZONE_COOKIE_NAME,
                timezone_name,
                max_age=60 * 60 * 24 * 365,
                samesite="Lax",
                secure=request.is_secure(),
            )

        return response

    def get_timezone_name(self, request: HttpRequest) -> str | None:
        submitted_timezone = request.POST.get("timezone", "").strip() if request.method == "POST" else ""
        timezone_name = (
            submitted_timezone
            or request.COOKIES.get(TIMEZONE_COOKIE_NAME, "").strip()
            or request.session.get(TIMEZONE_COOKIE_NAME, "").strip()
        )

        if get_timezone(timezone_name) is None:
            request.session.pop(TIMEZONE_COOKIE_NAME, None)
            return None

        request.session[TIMEZONE_COOKIE_NAME] = timezone_name
        return timezone_name

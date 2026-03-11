import os

from django.core.exceptions import ImproperlyConfigured

from .settings import *  # noqa: F403


DEBUG = False

if os.environ.get("DJANGO_SECRET_KEY") in {None, "", "podwatch-dev-secret-key-change-me"}:
    raise ImproperlyConfigured(
        "Set DJANGO_SECRET_KEY before using podwatch.settings_production."
    )

if "DJANGO_ALLOWED_HOSTS" not in os.environ:
    raise ImproperlyConfigured(
        "Set DJANGO_ALLOWED_HOSTS before using podwatch.settings_production."
    )

SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_SSL_REDIRECT = env_flag("DJANGO_SECURE_SSL_REDIRECT", default=True)  # noqa: F405
SESSION_COOKIE_SECURE = env_flag("DJANGO_SESSION_COOKIE_SECURE", default=True)  # noqa: F405
CSRF_COOKIE_SECURE = env_flag("DJANGO_CSRF_COOKIE_SECURE", default=True)  # noqa: F405
SECURE_HSTS_SECONDS = env_int("DJANGO_SECURE_HSTS_SECONDS", default=31536000)  # noqa: F405
SECURE_HSTS_INCLUDE_SUBDOMAINS = env_flag(  # noqa: F405
    "DJANGO_SECURE_HSTS_INCLUDE_SUBDOMAINS",
    default=True,
)
SECURE_HSTS_PRELOAD = env_flag("DJANGO_SECURE_HSTS_PRELOAD", default=True)  # noqa: F405
SECURE_CONTENT_TYPE_NOSNIFF = env_flag(  # noqa: F405
    "DJANGO_SECURE_CONTENT_TYPE_NOSNIFF",
    default=True,
)
SECURE_REFERRER_POLICY = os.environ.get("DJANGO_SECURE_REFERRER_POLICY", "same-origin")

# PodWatch

PodWatch is a small Django app for keeping track of pods and their scheduled events.

In this repo, a pod means a named group that meets repeatedly: a game night table, a study group, a volunteer crew, or any other small recurring unit. The app does two things only:

- record pods
- record upcoming events for those pods

## Product Shape

- single Django project
- server-rendered HTML templates
- standard Django forms with CSRF protection
- plain CSS
- SQLite by default for local development

No authentication, RBAC, API surface, or client-side app shell is part of the current foundation.

## Quick Start

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt
cp .env.example .env
python3 manage.py migrate
python3 manage.py runserver
```

Open `http://127.0.0.1:8000/`.

`manage.py`, `wsgi.py`, and `asgi.py` load `.env` automatically, so copying `.env.example` to `.env` is enough for local development.

## Commands

```bash
python3 manage.py migrate
python3 manage.py runserver
python3 manage.py check
python3 manage.py test
python3 -m compileall manage.py podwatch pods
```

For a production deploy check, use the hardened settings module:

```bash
DJANGO_SETTINGS_MODULE=podwatch.settings_production \
DJANGO_SECRET_KEY=replace-this-before-production \
DJANGO_ALLOWED_HOSTS=podwatch.example.com \
python3 manage.py check --deploy
```

## Environment

- `DJANGO_SETTINGS_MODULE`: defaults to `podwatch.settings`; switch to `podwatch.settings_production` for deployment
- `DJANGO_SECRET_KEY`: Django secret key
- `DJANGO_DEBUG`: `1`/`0` toggle for debug mode
- `DJANGO_ALLOWED_HOSTS`: comma-separated hostnames
- `DJANGO_CSRF_TRUSTED_ORIGINS`: comma-separated trusted origins for production HTTPS
- `DJANGO_DATABASE_PATH`: SQLite path relative to the repo root
- `DJANGO_TIME_ZONE`: default server timezone when a browser timezone is not yet known

## Timezones

Event scheduling uses the browser's IANA timezone and stores the correct UTC instant. The dashboard also renders event times in the browser timezone once the timezone cookie is established.

## Project Structure

```text
podwatch/               Django project settings and URL config
pods/                   Core app: models, forms, views, tests
pods/templates/         Server-rendered templates
pods/static/            Plain CSS
manage.py               Django entrypoint
requirements.txt        Python dependencies
```

## Scope Notes

- Pods and events are the only product concepts in scope.
- Authentication, permissions, APIs, and background jobs are intentionally absent from the current implementation.
- If richer workflows return later, they should be added from this server-rendered Django base.

## License

[MIT](LICENSE)

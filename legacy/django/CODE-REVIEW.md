# Code Review — PodWatch

**Date:** 2026-03-08
**Scope:** Current Django codebase in this repo

## Current Architecture

**Stack:** Python 3, Django, SQLite, server-rendered HTML templates, plain CSS

The current repository is a compact Django app centered on one dashboard workflow:

- create pods
- schedule events for pods
- review recent and upcoming events

## Strengths

- The codebase is small and coherent, with the main behavior concentrated in `pods/models.py`, `pods/forms.py`, `pods/views.py`, and `pods/templates/pods/dashboard.html`.
- Django forms and CSRF middleware are used for all write actions.
- The data model is simple and readable: one `Pod` model and one `Event` model with a direct foreign key.
- The test suite covers the main dashboard render path plus successful and invalid form submissions.
- GitHub Actions already run Python-only checks that match the repository.

## Current Limitations

- There is no authentication or authorization layer. That is consistent with the current product scope, but it means all write actions are open if the app is exposed as-is.
- The dashboard is the only interface. There is no API surface, admin workflow, or import/export path.
- Tests are focused on the core happy paths and one invalid submission path. Broader validation and edge-case coverage could be added later if the product grows.

## Review Notes For Future Work

- Keep this document focused on the code that actually exists in the repo.
- If the product remains intentionally small, prefer deleting stale review notes over keeping reviews for removed stacks.
- If the repo grows beyond the current dashboard workflow, refresh this review against the live Django implementation instead of carrying forward historical notes.

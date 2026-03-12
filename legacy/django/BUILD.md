# podwatch — Build Tracker

**Status:** Doc Cleanup Complete (Verification Limited By Environment)
**Last Updated:** 2026-03-08
**Branch:** `codex/stack-realign-20260308-105446`

## Current Repo Reality

PodWatch is already a small Django application for tracking pods and their scheduled events.

The implementation present in this worktree is:

- Python 3
- Django
- SQLite for local development
- server-rendered HTML templates
- plain CSS

The app currently supports:

- creating pods
- listing pods with event counts
- scheduling events for pods
- viewing recent and upcoming events on one dashboard

## Migration Objective For This Pass

This pass is not a framework rewrite. The Django app already exists and is the retained implementation.

The objective is to remove stale documentation and helper guidance that still describes the deleted Bun/React/TypeScript/PostgreSQL-era codebase as if it were current.

## Scope Of Work

### Keep

- the current Django project layout
- existing models, forms, views, templates, CSS, and tests
- Python-only CI that matches the actual repo

### Clean Up

- top-level docs that still frame the repo around the removed stack
- helper instructions that still require Bun or TypeScript workflows
- review notes that only describe the deleted implementation
- stray wording that treats removed stack components as active project guidance

### Avoid

- rewriting the working Django app unless a doc fix depends on it
- adding a new frontend or API stack
- touching files outside this repo worktree

## Concrete Targets

- `README.md`
  - describe only the current Django app
  - remove old-stack migration narration unless a short historical note is needed
- `CLAUDE.md`
  - replace Bun/TypeScript commit instructions with Python/Django repo rules
- `CODE-REVIEW.md`
  - remove the stale review of the deleted React/Bun/Postgres system
  - replace it with a short note or a current-scope review document
- repo-local CI docs and helper text
  - keep only truthful Python/Django checks

## Architecture Snapshot

```text
podwatch/
├── manage.py
├── podwatch/
│   ├── settings.py
│   ├── urls.py
│   ├── asgi.py
│   └── wsgi.py
├── pods/
│   ├── forms.py
│   ├── models.py
│   ├── tests.py
│   ├── urls.py
│   ├── views.py
│   ├── migrations/
│   ├── static/pods/site.css
│   └── templates/
└── requirements.txt
```

## Verification Target

Run the smallest truthful checks that match the current repository:

```bash
python3 manage.py check
python3 manage.py test
python3 -m compileall manage.py podwatch pods
```

## Exit Criteria

- top-level repo documentation describes only the Django implementation
- no repo-local instructions require Bun, TypeScript, or the removed app/server/database stack
- verification commands above pass in this worktree environment
- a local commit is created if the repo reaches a coherent verified checkpoint

## Verification Notes

- `python3 -m compileall manage.py podwatch pods` passed on 2026-03-08.
- `python3 manage.py check` and `python3 manage.py test` could not run because Django is not installed in the current shell.
- A temporary venv install attempt was also blocked on 2026-03-08 because outbound package download was unavailable in this environment.

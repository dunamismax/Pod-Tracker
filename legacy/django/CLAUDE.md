# CLAUDE.md

> Code agent instructions for this repository.

## Repo Rules

- Read `README.md` and `BUILD.md` before changing the repo.
- Treat the Django app in `podwatch/` and `pods/` as the source of truth for current behavior.
- Prefer Python and Django tooling only.
- Run the smallest truthful verification available before committing:
  - `python3 manage.py check`
  - `python3 manage.py test`
  - `python3 -m compileall manage.py podwatch pods`
- No AI attribution in commits.
- Do not push or rewrite history as part of routine repo work.

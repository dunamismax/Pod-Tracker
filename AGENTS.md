# AGENTS.md

## Purpose

This file contains repo-local operating rules for Ideal Magic. It supplements `/Users/sawyer/github/SOUL.md` and `/Users/sawyer/github/AGENTS.md`; those workspace files still define Scry identity and general workflow.

## Read Order

1. `/Users/sawyer/github/SOUL.md`
2. `/Users/sawyer/github/AGENTS.md`
3. `README.md`
4. `BUILD.md`
5. Task-relevant files under `docs/` or the Rails app once scaffolded

## Current Build Manual

`BUILD.md` is the active implementation manual until the Rails app is built and stable docs describe shipped behavior. Keep it honest:

- Check boxes only for completed and verified repo truth.
- Update `README.md` when current product or setup truth changes.
- Keep future execution detail in `BUILD.md`, not `README.md`.
- Do not mark planned behavior as shipped.

## Product Boundaries

- Ideal Magic is Commander-first for v1.
- Public deck URLs, pasted decklists, and user-provided exports are allowed.
- Private Archidekt or Moxfield account sync requires documented provider support or explicit approval.
- OpenAI work must use server-side API credentials or encrypted bring-your-own API keys.
- Do not implement or describe ChatGPT subscription passthrough unless OpenAI publishes an official supported flow.
- Card facts and Commander legality must come from deterministic source data, primarily Scryfall bulk data and source-backed rules.
- AI analysis can interpret deterministic facts, but it must not be the rules authority.

## Verification

For docs-only work, run the smallest relevant checks plus `git diff --check`.

For code work after scaffolding, run narrow checks first, then the repo verify entrypoint if present. The planned verify command is `bin/verify`.


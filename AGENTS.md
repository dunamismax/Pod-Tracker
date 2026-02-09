# AGENTS.md

This file gives fast context for AI agents working in this repo.

## Project summary

Pod Tracker is a privacy-first web app for Magic: The Gathering pods and other tabletop groups.
It focuses on event planning, attendance, and real-time session updates.

## Tech stack

- React + TypeScript
- Vite
- React Router
- TanStack Query
- Zod
- Supabase (Postgres, Auth, Realtime, Edge Functions, Storage)

## Repo layout

- `src/`
  - `src/App.tsx` : route table + providers
  - `src/web/` : website pages/components/styles
  - `src/lib/` : env, Supabase client, query client, auth parsing
  - `src/hooks/` : session hook(s)
  - `src/features/` : domain query/mutation modules
- `scripts/`
  - `scripts/supabase-setup.sql` : schema/RLS source of truth
- `supabase/functions/`
  - `notify-event` edge function

## Environment

- Use `.env` for local secrets.
- Required keys:
  - `VITE_SUPABASE_URL`
  - `VITE_SUPABASE_ANON_KEY`
- `.env.example` exists; never commit real secrets.

## Commands

- Install: `npm install`
- Run dev server: `npm run dev` (or `npm start`)
- Build: `npm run build`
- Preview build: `npm run preview`
- Lint: `npm run lint`

## Conventions

- Keep web UI under `src/web/`.
- Keep shared domain logic under `src/features/`.
- Use Zod for env/input validation.
- Use TanStack Query for data fetching/caching.
- Keep schema and policy updates in `scripts/supabase-setup.sql`.

## License

AGPL-3.0. See `LICENSE`.

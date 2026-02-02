# AGENTS.md

This file gives fast context for AI agents working in this repo.

## Project summary

Gatherer is a privacy-first coordination app for small, trusted groups who gather regularly.
It focuses on event-scoped planning, arrival, and real-time coordination.

## Tech stack

- Expo (React Native) + TypeScript
- Expo Router
- React Native Paper (dark theme)
- TanStack Query
- Zod
- Supabase (Postgres, Auth, Realtime, Edge Functions, Storage)

## Repo layout

- app/ : Expo Router routes
- src/ : shared code and assets
  - src/lib/ : client helpers (env, Supabase, Query)
  - src/theme/ : theme tokens and Paper theme
  - src/components/ : shared UI
  - src/features/ : domain modules (pods, events, profiles)
  - src/types/ : shared types (planned; not yet populated)
  - src/assets/ : images and app icons

## Environment

- Use `.env` for local secrets.
- Required keys:
  - EXPO_PUBLIC_SUPABASE_URL
  - EXPO_PUBLIC_SUPABASE_ANON_KEY
- `.env.example` exists; never commit real secrets.

## Current setup

- Providers are wired in `app/_layout.tsx` (Query + Paper).
- Dark theme is enforced via `src/theme/paperTheme.ts`.
- Supabase client: `src/lib/supabase.ts`
- Query client: `src/lib/queryClient.ts`
- Env validation: `src/lib/env.ts`
- Supabase session hook: `src/hooks/use-supabase-session.ts`
- Supabase query hooks:
  - Pods: `src/features/pods/pods-queries.ts`
  - Events/attendance/checklist: `src/features/events/events-queries.ts`
  - Profiles: `src/features/profiles/profiles-queries.ts`
- Auth screens: `app/auth.tsx`, `app/auth/callback.tsx`
- Create flows: `app/create-pod.tsx`, `app/create-event.tsx`
- Home and Pods tabs pull live data in `app/(tabs)/index.tsx` and `app/(tabs)/explore.tsx`.
- Template components still exist in `src/components/` and can be pruned once replaced.

## Commands

- Install: `npm install`
- Run: `npm start`
- Android: `npm run android`
- iOS (Mac only): `npm run ios`
- Web: `npm run web`

## Conventions

- Keep components and logic under `src/`; routes under `app/`.
- Prefer feature modules under `src/features/` for domain logic.
- Use Zod for input/env validation.
- Use TanStack Query for data fetching and caching.

## License

AGPL-3.0. See `LICENSE`.

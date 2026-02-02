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
  - scripts/ : setup scripts (includes Supabase bootstrap SQL)
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
- MCP servers: use the Supabase MCP server when you need to view or change project state, and use the Context7 MCP server to pull latest library documentation when up-to-date info is needed.

## Current setup

- Providers are wired in `app/_layout.tsx` (Query + Paper).
- Dark theme is enforced via `src/theme/paperTheme.ts`.
- Supabase client: `src/lib/supabase.ts`
- Query client: `src/lib/queryClient.ts`
- Env validation: `src/lib/env.ts`
- Supabase session hook: `src/hooks/use-supabase-session.ts`
- Push token registration: `src/hooks/use-register-push-token.ts` (uses `expo-notifications`)
- Supabase SQL bootstrap: `scripts/supabase-setup.sql` (run in Supabase SQL editor; idempotent)
  - Includes transactional RPCs: `create_pod_with_owner` and `accept_pod_invite`
  - Invite acceptance is restricted to the RPC path
  - Includes `notifications` + `user_push_tokens` tables and Realtime publication for notifications
- Edge Function: `supabase/functions/notify-event/index.ts` (delivers arrival/schedule notifications)
- Supabase query hooks:
  - Pods: `src/features/pods/pods-queries.ts`
  - Events/attendance/checklist: `src/features/events/events-queries.ts`
  - Profiles: `src/features/profiles/profiles-queries.ts`
  - Invites (RPC accept): `src/features/invites/invites-queries.ts`
  - Notifications: `src/features/notifications/notifications-queries.ts`
- Auth screens: `app/auth.tsx`, `app/auth/callback.tsx`
- Create flows: `app/create-pod.tsx`, `app/create-event.tsx`
- Event detail/edit: `app/event/[id].tsx`, `app/event/edit/[id].tsx`
- Notifications screen: `app/notifications.tsx`
- Home and Pods tabs pull live data in `app/(tabs)/index.tsx` and `app/(tabs)/explore.tsx`.
- Template components still exist in `src/components/` and can be pruned once replaced.
  - Invite tokens are generated server-side (see `scripts/supabase-setup.sql`).

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
- `scripts/supabase-setup.sql` is the source of truth for schema/RLS changes.
  - If you change invite or membership flows, consider adding/adjusting RPCs to keep multi-step writes transactional.

## License

AGPL-3.0. See `LICENSE`.

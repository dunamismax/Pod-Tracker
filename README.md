# Pod Tracker (Web)

Pod Tracker is a privacy-first web app for Magic: The Gathering pods and other tabletop groups.
It focuses on event planning, attendance, and real-time session updates.

## Tech stack

- React + TypeScript
- Vite
- React Router
- TanStack Query
- Zod
- Supabase (Postgres, Auth, Realtime, Edge Functions, Storage)

## Environment

Create a local `.env` file:

```bash
# Preferred keys for web (Vite)
VITE_SUPABASE_URL=...
VITE_SUPABASE_ANON_KEY=...

# Optional compatibility keys from Expo projects
EXPO_PUBLIC_SUPABASE_URL=...
EXPO_PUBLIC_SUPABASE_ANON_KEY=...
```

`.env.example` includes the required keys. The app prefers `VITE_*` and can also read `EXPO_PUBLIC_*`.
After changing `.env`, restart the dev server.

## Commands

- Install: `npm install`
- Run local dev server: `npm run dev` (or `npm start`)
- Build: `npm run build`
- Preview production build: `npm run preview`
- Lint: `npm run lint`

## Repo layout

- `src/App.tsx` : app routes and shell
- `src/web/` : website pages, layout, and styles
- `src/features/` : Supabase domain query/mutation modules
- `src/lib/` : env parsing, Supabase client, query client
- `src/hooks/use-supabase-session.ts` : shared session hook
- `scripts/supabase-setup.sql` : schema/RLS source of truth
- `supabase/functions/notify-event` : notification edge function

## Supabase setup

Run `scripts/supabase-setup.sql` in the Supabase SQL editor to bootstrap or update schema/RLS policies.

The app uses email one-time-code auth on `/auth`.

## License

AGPL-3.0. See [LICENSE](LICENSE).

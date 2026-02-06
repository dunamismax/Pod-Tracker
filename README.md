# Gatherer

Gatherer is a lightweight, privacy-first coordination app for small groups who gather regularly, built to make planning, arriving, and playing together smoother, faster, and less chaotic.

## Project next step

- Add recurring pod schedules and role management UI.
- Add notification preferences and quiet hours.
- Add event history and richer attendance analytics.

## What it is

Gatherer is built for trusted groups that meet regularly in the real world: Magic pods, D&D sessions, board game nights, climbing crews, and more. It focuses on the full coordination loop: who is coming, who is late, when to start, and what is needed to make the session happen.

This is not a social network. It is social infrastructure for recurring, real-life meetups.

## Core principles

- Pods over generic friend lists
- Consent-first, event-scoped location sharing
- Event-centered planning and coordination
- Lightweight, purpose-driven communication
- Clear status and useful ETAs

## Features (current)

- Home screen backed by Supabase (next event, arrival board, checklist, quick actions)
- Pods overview backed by Supabase (pods list + upcoming events)
- Auth screens (magic link only) with callback handling and pasted-link fallback
- Create pod + create event flows (Supabase inserts)
- RSVP + checklist updates (mutations + query invalidation)
- Pod invites + pending invites flow (invite tokens are generated server-side)
- Profile creation on sign-in + profile editing
- Pod + event detail screens with RSVP/arrival/checklist editing
- Event edit screen with host controls (including cancel flow)
- In-app notifications + push notifications for arrivals, schedule changes, and cancellations
- Dark theme via React Native Paper
- Expo Router tab navigation
- Supabase Query hooks for pods, events, attendance, checklist

## Roadmap (near-term)

- Recurring pod schedules and roles management
- Event history and richer attendance analytics
- Notification preferences and quiet hours
- Presence/arrival timeline refinements

## Tech stack (current)

### Client

- Expo (React Native)
- TypeScript
- Expo Router
- React Native Paper
- TanStack Query
- Zod (input + env validation)

### Backend

- Supabase
  - Postgres (pods, events, membership, invites, permissions)
  - Auth (magic links only)
  - Realtime (presence, event updates, status changes)
  - Edge Functions (`notify-event` for event/arrival notifications)
  - Storage (avatars, optional pod images)

### Infra (planned/integration-ready)

- No production infra integrations are wired in this repo yet.

## Status

Core MVP flows are wired: auth, pods, events, invites, profiles, and notifications.

## Getting started

1. Install dependencies

```bash
npm install
```

1. Configure env vars
   Create a local `.env` file with:

```
EXPO_PUBLIC_SUPABASE_URL=...
EXPO_PUBLIC_SUPABASE_ANON_KEY=...
```

1. Run the app

```bash
npm start
```

For Expo Go on a physical iPhone, tunnel mode is usually the most reliable:

```bash
npm start -- --tunnel
```

### Android setup note

If you run `npm run android`, ensure the Android SDK is installed and `ANDROID_HOME` is set, and that `platform-tools` is on your PATH so `adb` is available.

## Supabase setup

Use `scripts/supabase-setup.sql` in the Supabase SQL editor to bootstrap or update the schema, RLS, and policies in one run (idempotent, non-destructive). This script also ensures `pod_invites.token` is server-generated and non-null.
It also defines transactional RPCs for create pod + owner membership and accept invite + membership, and restricts invite acceptance to the RPC path.
`scripts/supabase-setup.sql` is the source of truth for schema and policy changes.

### Magic link auth URL config (important)

Magic links in this app use `Linking.createURL('auth/callback')` at runtime. In Expo Go this resolves to an `exp://.../--/auth/callback` URL, and in app builds it resolves to your app scheme callback.

In Supabase Auth URL configuration, allow the callback URLs you use:

1. `gatherer://auth/callback` (app scheme from `app.json`)
2. Your current Expo Go callback URL shown by `Linking.createURL('auth/callback')` (typically `exp://.../--/auth/callback`)

If a magic link opens in Safari and does not return to the app, the auth screen includes a pasted-link fallback: copy the full URL from Safari and use "Sign in from pasted URL".

### Notifications

Notifications are delivered via the Edge Function `notify-event` and stored in `notifications`. Push tokens are stored in `user_push_tokens`. To enable push + in-app notifications:

1. Deploy the Edge Function and set the `SUPABASE_SERVICE_ROLE_KEY` secret in Supabase Edge Functions.
2. Install `expo-notifications` in the client app.
3. Ensure Realtime is enabled for the `notifications` table (the setup SQL includes the publication add).

## Contributing

We welcome focused contributions that move the MVP forward.

- Open an issue for product ideas or bug reports
- Keep UI components under `src/` and routes under `app/`
- Favor feature-first modules under `src/features/` as they are introduced
- Avoid committing secrets; use `.env` (already ignored)

If you want to pick up work, start with the Roadmap items and coordinate in an issue.

## License

This project is licensed under the AGPL-3.0. See [LICENSE](LICENSE).

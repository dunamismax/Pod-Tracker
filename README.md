# Gatherer

Gatherer is a lightweight, privacy-first coordination app for small groups who gather regularly, built to make planning, arriving, and playing together smoother, faster, and less chaotic.

## Project next step

We are ready to wire the Home and Pods tabs to real Supabase data. Next: create the Supabase schema (see `docs/supabase-setup.md`), then implement TanStack Query hooks and replace mock data in the screens.

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

- Home screen scaffold for the next gather (arrival board, checklist, quick actions)
- Pods overview scaffold (pods list + upcoming events)
- Dark theme via React Native Paper
- Expo Router tab navigation

## Roadmap (near-term)

- Pod detail screens (members, roles, recurring schedule)
- Event detail flow (RSVP, arrival status, checklist editing)
- Supabase-backed data (pods, events, membership, invites)
- Auth (magic link + OAuth)
- Realtime updates for arrivals and status changes
- Notifications and reminders

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
  - Auth (magic links, OAuth)
  - Realtime (presence, event updates, status changes)
  - Edge Functions (ETAs, scheduled reminders, server-side validation)
  - Storage (avatars, optional pod images)

### Infra

- Cloudflare (DNS + edge caching)
- Sentry (crash reporting)
- PostHog (analytics, privacy-friendly)

## Status

UI scaffolding in place. Backend wiring is the current focus.

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

### Android setup note

If you run `npm run android`, ensure the Android SDK is installed and `ANDROID_HOME` is set, and that `platform-tools` is on your PATH so `adb` is available.

## Supabase setup

See `docs/supabase-setup.md` for the recommended database schema and RLS policies for a fresh project.

## Contributing

We welcome focused contributions that move the MVP forward.

- Open an issue for product ideas or bug reports
- Keep UI components under `src/` and routes under `app/`
- Favor feature-first modules under `src/features/` as they are introduced
- Avoid committing secrets; use `.env` (already ignored)

If you want to pick up work, start with the Roadmap items and coordinate in an issue.

## License

This project is licensed under the AGPL-3.0. See [LICENSE](LICENSE).

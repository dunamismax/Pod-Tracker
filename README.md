# Gatherer

Gatherer is a lightweight, privacy-first coordination app for small groups who gather regularly, built to make planning, arriving, and playing together smoother, faster, and less chaotic.

## Project next step

Auth UI, create pod/event flows, and RSVP/checklist mutations are now wired. Next: add invite flow, profile creation on sign-in, and richer event/pod detail screens (RSVP/arrival/checklist editing).

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
- Auth screens (magic link + OAuth) with callback handling
- Create pod + create event flows (Supabase inserts)
- RSVP + checklist updates (mutations + query invalidation)
- Dark theme via React Native Paper
- Expo Router tab navigation
- Supabase Query hooks for pods, events, attendance, checklist

## Roadmap (near-term)

- Pod detail screens (members, roles, recurring schedule)
- Event detail flow (arrival status, checklist editing, attendance history)
- Invite flow (email and/or code), including admin-only policies
- Profile creation on sign-in (display names, avatars)
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

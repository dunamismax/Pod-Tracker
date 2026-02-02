# Gatherer
Gatherer is a lightweight, privacy-first coordination app for small groups who gather regularly, built to make planning, arriving, and playing together smoother, faster, and less chaotic.

## What it is
Gatherer is built for trusted groups that meet regularly in the real world: Magic pods, D&D sessions, board game nights, climbing crews, and more. It focuses on the full coordination loop: who is coming, who is late, when to start, and what is needed to make the session happen.

This is not a social network. It is social infrastructure for recurring, real-life meetups.

## Core principles
- Pods over generic friend lists
- Consent-first, event-scoped location sharing
- Event-centered planning and coordination
- Lightweight, purpose-driven communication
- Clear status and useful ETAs

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
Early build. Scaffolding in progress.

## Getting started (soon)
This repository is being scaffolded. Once the initial Expo app and local Supabase setup are in place, this section will include the exact steps to run the app locally.

## Contributing
If you want to help shape the MVP, open an issue with ideas or feedback.

## License
This project is licensed under the AGPL-3.0. See [LICENSE](LICENSE).

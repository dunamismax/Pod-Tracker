# Gatherer

## New here? Pod tester quick start

If you are testing with the friend group, start here first: **[POD_TESTERS_QUICK_START.md](POD_TESTERS_QUICK_START.md)**.

Gatherer is a lightweight, privacy-first coordination app for small groups who gather regularly, built to make planning, arriving, and playing together smoother, faster, and less chaotic.

## Project next step

1. Pod admin permissions (backend first)
   - Add transactional RPCs for:
     - promoting/demoting members (`member` <-> `admin`)
     - transferring ownership
     - removing members from a pod
     - deleting a pod (owner-only)
   - Enforce role constraints in SQL/RLS:
     - only owners can transfer ownership or delete pods
     - owners/admins can manage members
     - owners cannot be removed unless ownership is transferred first
   - Keep `scripts/supabase-setup.sql` as the source of truth for all policy/RPC updates.

2. Pod admin controls in app UI
   - Add a pod "Manage members" screen for owners/admins.
   - Show role badges and admin-only actions (promote, demote, remove).
   - Add owner-only controls: transfer ownership and delete pod (with explicit confirmation).
   - Hide or disable admin actions for non-admin members.

3. Safety, auditing, and notification wiring
   - Add in-app notifications for role changes, removals, ownership transfer, and pod deletion.
   - Add soft-guard UX for destructive actions (typed confirm + irreversible warning).
   - Add event logging metadata (who changed what, when) to support debugging and trust.

4. Stabilize with tests and edge-case handling
   - Add integration coverage for permission boundaries and failure modes.
   - Verify no self-lockout scenarios (for example, last owner losing owner role).
   - Validate query invalidation/refetch for member list and pod list after admin actions.

5. After permissions are solid, continue product roadmap
   - Recurring pod schedules
   - Notification preferences and quiet hours
   - Event history and richer attendance analytics

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

## Build and share with friends (no Expo Go)

Use EAS internal builds for real device testing with your pod. This is required for full `expo-notifications` support and avoids Expo Go limitations.

### Recommended profile

Use the `preview` profile in `eas.json` for friend-group testing and internal installs.

```bash
npx eas build --platform all --profile preview
```

### One-time setup

1. Log in to Expo:

```bash
npx eas login
```

2. Confirm `eas.json` exists at the repo root.
3. iOS only: enroll in Apple Developer Program (required for installing iOS builds on other devices).

### Android sharing flow (easiest)

1. Build Android preview:

```bash
npx eas build --platform android --profile preview
```

2. Open the build on expo.dev and share the install link (or APK) with your friends.
3. Friends install directly on Android (they may need to allow installs from unknown sources once).

### iOS sharing flow (internal Ad Hoc)

1. Register each tester iPhone once:

```bash
npx eas device:create
```

2. After devices are registered, build iOS preview:

```bash
npx eas build --platform ios --profile preview
```

3. Share the iOS install link from the build page on expo.dev.
4. If you add a new iPhone tester later, register that device and rebuild iOS.

### Build from GitHub (expo.dev website)

1. Go to expo.dev -> your project -> Build from GitHub.
2. Pick the branch and choose profile `preview`.
3. Build Android and/or iOS.
4. Share resulting install links from the build details page.

### Notes

- Use real devices for push notification testing.
- For day-to-day friend testing, prefer `preview` builds over Expo Go.
- Use `development` profile only when you specifically need a developer client workflow.

### Android setup note

If you run `npm run android`, ensure the Android SDK is installed and `ANDROID_HOME` is set, and that `platform-tools` is on your PATH so `adb` is available.

## Supabase setup

Use `scripts/supabase-setup.sql` in the Supabase SQL editor to bootstrap or update the schema, RLS, and policies in one run (idempotent, non-destructive). This script also ensures `pod_invites.token` is server-generated and non-null.
It also defines transactional RPCs for create pod + owner membership and accept invite + membership, and restricts invite acceptance to the RPC path.
`scripts/supabase-setup.sql` is the source of truth for schema and policy changes.

### Magic link auth URL config (important)

Magic links in this app use `Linking.createURL('auth/callback')` at runtime.

For dev/preview builds (no Expo Go), allow:

1. `gatherer://auth/callback` (app scheme from `app.json`)

If you still test in Expo Go, also allow your current Expo Go callback URL (typically `exp://.../--/auth/callback`).

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

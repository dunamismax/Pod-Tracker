# Pod Dashboard

Web app for coordinating tabletop game pods with shared events, RSVPs, arrival tracking, checklists, invites, and in-app notifications.

![React](https://img.shields.io/badge/React-19-blue)
![TypeScript](https://img.shields.io/badge/TypeScript-5.x-3178c6)
![Backend](https://img.shields.io/badge/Backend-Supabase-3ecf8e)
![License](https://img.shields.io/badge/License-MIT-green)

Live URL: `https://poddashboard.com`

## Quick Start

### Prerequisites

- Node.js 20+ (recommended)
- npm
- Supabase project (URL + anon key)

### Local Setup

```bash
git clone https://github.com/dunamismax/poddashboard.git
cd poddashboard
npm install
cp .env.example .env
```

Set required values in `.env`:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

Apply database setup in Supabase SQL editor:

- Run `scripts/supabase-setup.sql`

Configure Supabase Auth email templates for code-based login:

- Use `{{ .Token }}` (OTP)
- Remove `{{ .ConfirmationURL }}` for email sign-in templates

Start the app:

```bash
npm run dev
```

Expected result: Vite serves the app locally and login is available at `/auth`.

## Features

- OTP email authentication with Supabase Auth.
- Pod creation, membership management, and invite acceptance flows.
- Event creation/editing with schedule, location, and cancellation support.
- RSVP and live arrival status tracking with optional ETA minutes.
- Shared checklist items per event with `open`, `done`, and `blocked` states.
- In-app notifications and realtime cache refresh for event/pod activity.

## Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| Frontend | [React 19](https://react.dev/) + [TypeScript](https://www.typescriptlang.org/) | Web UI and route-driven pages |
| Build Tool | [Vite](https://vitejs.dev/) | Local dev server and production build |
| Routing | [React Router](https://reactrouter.com/) | Client-side page routing |
| Data Fetching | [TanStack Query](https://tanstack.com/query) | Query/mutation state and cache management |
| Validation | [Zod](https://zod.dev/) | Environment and input validation |
| Backend | [Supabase](https://supabase.com/) | Postgres, Auth, Realtime, Edge Functions |

## Project Structure

```text
poddashboard/
├── src/
│   ├── App.tsx                         # Route graph and app providers
│   ├── web/                            # Pages, layout, styles, and UI utils
│   ├── features/                       # Domain query/mutation modules
│   ├── hooks/use-supabase-session.ts   # Session bootstrap/auth state
│   └── lib/                            # Env parsing, Supabase client, query client
├── scripts/supabase-setup.sql          # DB schema, enums, RLS, RPC, indexes
├── supabase/functions/notify-event/    # Notification edge function
├── POD_TESTERS_QUICK_START.md          # End-user testing guide
├── package.json
└── .env.example
```

## Development Workflow and Common Commands

```bash
# Start dev server
npm run dev

# Lint source files
npm run lint

# Type-check + production build
npm run build

# Preview production build locally
npm run preview
```

## Deployment and Operations

- Production build artifacts are generated with `npm run build`.
- Supabase schema and policies are defined in `scripts/supabase-setup.sql`.
- Edge function `notify-event` expects Supabase runtime env vars (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`).
- Health/behavior checks are primarily done through app routes and Supabase dashboard logs.

## Security and Reliability Notes

- RLS policies are enabled across core tables (`pods`, `events`, `attendance`, `invites`, `notifications`, and others).
- Helper SQL functions (`can_access_pod`, `is_pod_admin`, `shares_pod_with`) centralize authorization logic.
- RPC functions (`create_pod_with_owner`, `accept_pod_invite`) enforce transactional membership/invite behavior.
- `src/lib/env.ts` validates env inputs at startup and fails fast on invalid config.
- Keep real credentials out of source control; use `.env.example` as the template only.

## Documentation

| Path | Purpose |
|---|---|
| [POD_TESTERS_QUICK_START.md](POD_TESTERS_QUICK_START.md) | Lightweight guide for pod testers |
| [scripts/supabase-setup.sql](scripts/supabase-setup.sql) | Authoritative schema, RLS policies, RPC functions |
| [supabase/functions/notify-event/index.ts](supabase/functions/notify-event/index.ts) | Notification fan-out function |
| [src/App.tsx](src/App.tsx) | Route definitions and auth gating |
| [src/lib/env.ts](src/lib/env.ts) | Runtime environment validation |

## Contributing

Open an issue or pull request with clear repro steps and expected behavior. Keep data-access logic in `src/features`, UI code in `src/web`, and schema changes in `scripts/supabase-setup.sql`.

## License

Licensed under the [MIT License](LICENSE).

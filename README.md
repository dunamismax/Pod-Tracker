# PodDashboard

PodDashboard is a Bun-first TypeScript app for pod management and upcoming event visibility.

## Stack

- Bun runtime/package manager
- Nuxt 4 + Vue 3 + TypeScript
- Tailwind CSS + Nuxt UI
- Postgres + Drizzle ORM + drizzle-kit
- Credentials auth with Auth.js session tables, custom credentials endpoints, and Zod validation
- Biome for lint/format

## Setup

```bash
cp .env.example .env
bun install
bun run db:migrate
bun run db:seed
```

If you are pointing at an existing local Postgres container on a non-default port, override `DATABASE_URL` accordingly before running the DB commands.

## Run

```bash
bun run dev
```

- Frontend: `http://localhost:3000`
- API/Auth: `http://localhost:3001`

Nuxt proxies `/api/*` to the Bun backend, so the browser stays same-origin for app requests.

## Quality Gates

```bash
bun run lint
bun run typecheck
bun run smoke
bun run scry:doctor
```

## API

Authenticated routes require a valid session cookie and permission grants.

- `GET /api/pods`
- `POST /api/pods`
- `GET /api/events`
- `POST /api/register`
- `GET /api/session`
- `POST /api/login`
- `POST /api/logout`

## Seeded User

`bun run db:seed` creates:

- email: `test@example.com`
- password: `password`
- role: `admin`

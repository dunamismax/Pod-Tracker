# AGENTS.md

This file gives fast context for AI agents working in this repo.

## Project summary

Magic Pod Dashboard is a web app for Magic: The Gathering pods and other tabletop groups.
It focuses on pod management, event planning, attendance and arrival tracking, invites, and real-time notifications.

## Tech stack

---

### Frontend

- **Framework + routing:** React Router (Framework mode)
- **UI:** React
- **Language:** TypeScript
- **Build tool / dev server:** Vite

### Backend and API (TypeScript)

- **Server runtime:** Bun
- **API approach:** React Router route modules written in TypeScript
  - **Loaders / actions** for app data mutations and reads
  - **JSON “resource routes”** under `/api/*` for API-style endpoints (still TypeScript, still in the same server)

### Database

- **Database:** PostgreSQL
- **DB driver:** `pg` (node-postgres)

### Auth and email

- **Auth model:** Email OTP + server-side sessions (cookie-based)
- **SMTP sending:** Nodemailer

### Validation and quality

- **Validation:** Zod
- **Linting:** ESLint

### Deployment and hosting

- **Containerization:** Docker + Docker Compose
- **Reverse proxy / TLS:** Caddy
- **Hosting target:** Self-hosted Ubuntu server

## Repo layout

- `app/`
  - `app/root.tsx` : root layout + auth-aware header
  - `app/routes.ts` : route table (framework mode)
  - `app/routes/` : route modules (pages + `/api/*` resources)
  - `app/lib/` : env, db, auth, sessions, validation
- `scripts/`
  - `scripts/postgres-setup.sql` : schema source of truth
  - `scripts/migrate.ts` : migration runner
- `Dockerfile`, `docker-compose.yml`, `Caddyfile`
  - container build, orchestration, TLS reverse proxy

## Environment

- Use `.env` for local secrets.
- Required keys:
  - `DATABASE_URL`
  - `SESSION_SECRET`
  - `SMTP_HOST`
  - `SMTP_PORT`
  - `SMTP_SECURE`
  - `SMTP_FROM`
- `.env.example` exists; never commit real secrets.

## Commands

- Install: `bun install`
- Run dev server: `bun run dev`
- Build: `bun run build`
- Start built server: `bun run start`
- Lint: `bun run lint`
- Run migrations: `bun run db:migrate`

## Conventions

- Keep route modules under `app/routes/`.
- Keep server/domain logic under `app/lib/`.
- Use Zod for env/input validation.
- Use route loaders/actions and resource routes for data access.
- Keep schema updates in `scripts/postgres-setup.sql`.

## License

MIT. See `LICENSE`.

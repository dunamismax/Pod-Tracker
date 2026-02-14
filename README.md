# Magic Pod Dashboard

Magic Pod Dashboard is a React Router framework-mode web app for tabletop pod management, using Bun on the server with PostgreSQL, email OTP authentication, and cookie sessions.

## Stack (exclusive)

- Frontend: React + TypeScript
- Routing/framework: React Router (framework mode)
- Build/dev: Vite
- Server runtime: Bun
- Backend/API: React Router route modules (loaders/actions + `/api/*` resource routes)
- Database: PostgreSQL with `pg`
- Auth: Email OTP + server-side cookie sessions
- Email: Nodemailer (SMTP)
- Validation: Zod
- Linting: ESLint
- Deployment: Docker + Docker Compose + Caddy

## Project layout

- `app/`
- `app/root.tsx`: root route + layout
- `app/routes.ts`: route table
- `app/routes/*`: page routes + `/api/*` resource routes
- `app/lib/*`: env, db, auth, sessions, validation
- `scripts/postgres-setup.sql`: schema source of truth
- `scripts/migrate.ts`: migration runner using `pg`
- `Dockerfile`, `docker-compose.yml`, `Caddyfile`: deployment assets

## Environment

Copy `.env.example` to `.env` and set:

- `DATABASE_URL`
- `SESSION_SECRET`
- `SMTP_HOST`
- `SMTP_PORT`
- `SMTP_SECURE`
- `SMTP_USER` (optional for unauthenticated SMTP)
- `SMTP_PASS` (optional)
- `SMTP_FROM`
- `APP_ORIGIN`

## Development

```bash
bun install
bun run db:migrate
bun run dev
```

## API routes

- `GET /api/pods`: list pods for current session user
- `POST /api/pods`: create pod from JSON body
- `GET /api/events`: list upcoming events for current session user

Session auth is cookie-based; unauthenticated API calls return `401`.

## Production (self-hosted Ubuntu)

```bash
docker compose up --build -d
```

Set at minimum in your deployment environment:

- `APP_DOMAIN`
- `ACME_EMAIL`
- `SESSION_SECRET`
- `POSTGRES_PASSWORD`
- SMTP variables

Caddy reverse-proxies to the app and manages TLS certificates for `APP_DOMAIN`.

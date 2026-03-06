# PodWatch

Pod management and event dashboard with authentication, role-based permissions, and a clean admin UI. Built on React Router 7 and a Bun-powered API backend.

## Features

- **Pod management** — create, view, and manage pods with event tracking
- **Event visibility** — upcoming events dashboard with filtering
- **Authentication** — credentials-based auth with registration, login, and sessions
- **Role-based access** — admin and user roles with permission-gated routes
- **Drizzle ORM** — type-safe Postgres queries with migrations and seeding
- **Dark UI** — Tailwind CSS with responsive layout

## Prerequisites

- [Bun](https://bun.sh)
- PostgreSQL

## Quick Start

```bash
git clone https://github.com/dunamismax/podwatch.git
cd podwatch
bun install
cp .env.example .env
# configure DATABASE_URL in .env
bun run db:migrate
bun run db:seed
bun run dev
```

Open [http://localhost:3000](http://localhost:3000). The API runs on port 3001 (proxied automatically in dev).

For production with the default split deployment, keep `APP_URL=http://localhost:3000`,
`API_URL=http://localhost:3001`, and set `VITE_API_URL=http://localhost:3001` before `bun run build`.

### Seeded User

`bun run db:seed` creates a test account:

- **Email**: `test@example.com`
- **Password**: `password`
- **Role**: `admin`

## Commands

| Command | Description |
|---|---|
| `bun run dev` | Start frontend + API dev servers |
| `bun run dev:api` | Start only the API server (with watch) |
| `bun run dev:web` | Start only the Vite dev server |
| `bun run build` | Production build |
| `bun run start` | Start the production API plus the SPA static server |
| `bun run lint` | Biome lint check |
| `bun run format` | Biome auto-format |
| `bun run typecheck` | TypeScript type check |
| `bun run smoke` | Smoke test API endpoints |
| `bun run db:generate` | Generate Drizzle migrations |
| `bun run db:migrate` | Run database migrations |
| `bun run db:seed` | Seed database with test data |
| `bun run scry:doctor` | Verify project prerequisites |

## Stack

- **Runtime**: Bun
- **Frontend**: React 19 · React Router 7 (framework mode) · Tailwind CSS v4
- **Backend**: Bun HTTP server with Zod-validated routes
- **Database**: PostgreSQL · Drizzle ORM
- **Auth**: Session cookies · bcrypt · Better Auth
- **Validation**: Zod
- **Tooling**: Biome · TypeScript 5.9

## API

Authenticated routes require a valid session cookie.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/auth/sign-up/email` | Create a new account |
| `POST` | `/api/auth/sign-in/email` | Sign in |
| `POST` | `/api/auth/sign-out` | Sign out |
| `GET` | `/api/auth/get-session` | Get current session |
| `GET` | `/api/pods` | List pods (paginated: `?limit=50&offset=0`) |
| `POST` | `/api/pods` | Create a pod |
| `GET` | `/api/events` | List events |
| `GET` | `/health` | Health check |

## Project Structure

```
app/                    # React frontend
  components/           # UI components
  hooks/                # Custom React hooks
  lib/                  # Utilities, API client, types
  routes/               # Route modules
  root.tsx              # App shell
backend/                # API server
  index.ts              # Server entry + routing
  auth.ts               # Authentication logic
  db.ts                 # Database client
  env.ts                # Environment config (Zod)
  session.ts            # Session management
  permissions.ts        # RBAC logic
db/                     # Database layer
  migrate.ts            # Migration runner
  seed.ts               # Database seeder
scripts/                # CLI tools
```

## License

[MIT](LICENSE)

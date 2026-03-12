# PodWatch

PodWatch is a Bun-powered scheduling workspace for small recurring groups.

A pod is a named group that meets repeatedly: a study circle, volunteer crew, commander table, or any other recurring unit. The rewritten app keeps the product narrow:

- create pods
- schedule events against pods
- review a recent and upcoming event timeline
- use an in-app AI coach grounded in the current board state

## Stack

- Runtime: Bun
- Package manager / monorepo: pnpm workspaces
- Frontend / app framework: TanStack Start, Router, and Query
- Language: TypeScript
- Domain / validation: Effect + Effect Schema
- Database: PostgreSQL + Drizzle ORM
- Auth: Better Auth
- AI UX: TanStack AI
- AI workflow orchestration: Mastra
- Observability: OpenTelemetry
- Lint / format: Biome
- Tests: Vitest

## Quick Start

1. Install dependencies.

```bash
pnpm install
```

2. Copy the environment file and fill in secrets.

```bash
cp .env.example .env
```

3. Start PostgreSQL.

```bash
docker compose up -d postgres
```

4. Push the Drizzle schema.

```bash
pnpm db:push
```

5. Start the app.

```bash
pnpm dev
```

Open `http://127.0.0.1:3000`.

## Environment

- `DATABASE_URL`: PostgreSQL connection string
- `BETTER_AUTH_SECRET`: secret used to sign auth cookies
- `BETTER_AUTH_URL`: public origin for Better Auth callbacks and cookies
- `OPENAI_API_KEY`: optional, enables the TanStack AI coach
- `AI_MODEL`: optional, required when AI is enabled
- `OTEL_SERVICE_NAME`: service name for traces
- `OTEL_EXPORTER_OTLP_ENDPOINT`: optional OTLP HTTP exporter endpoint

If `OPENAI_API_KEY` or `AI_MODEL` are missing, the core app still runs and the AI coach returns a configuration error when used.

## Commands

```bash
pnpm dev
pnpm build
pnpm typecheck
pnpm test
pnpm db:generate
pnpm db:push
pnpm db:studio
```

## Workspace Layout

```text
apps/web/              TanStack Start app, routes, auth UI, AI route
packages/db/           Drizzle schema, PostgreSQL client, repository layer
packages/domain/       Effect workflows and contracts
packages/observability/OpenTelemetry bootstrap helpers
legacy/django/         Archived Django implementation from before the rewrite
```

## Notes

- The active application is the TypeScript workspace in `apps/web`.
- The archived Django app remains in `legacy/django` for reference only.
- The dashboard stores event times as UTC and renders them in the browser timezone.

## License

[MIT](LICENSE)

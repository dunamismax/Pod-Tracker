# Deployment

`ideal-magic.com` is live and self-hosted on Stephen's Ubuntu VM. This document is the operational runbook for the running deployment, not a future plan.

## Architecture

```
internet → Caddy (host) → 127.0.0.1:8083 (Puma in ideal-magic-web.service) → Rails 8.1 → PostgreSQL 17
```

- One Ubuntu VM. The same VM also runs `dunamismax-web.service` (port 8082) and `sentrypact-web.service` (port 8081); Ideal Magic uses the same systemd+Puma+Caddy pattern with `8083`.
- Caddy is the public TLS edge for `ideal-magic.com` and `www.ideal-magic.com` (a redirect to apex). TLS certs are ACME via Let's Encrypt.
- Puma is started directly by systemd; no Docker, no Compose, no Kamal in v1. Solid Queue runs in-Puma (`SOLID_QUEUE_IN_PUMA=true`). Add a sibling unit later if jobs outgrow that.
- PostgreSQL is the host package (`apt install postgresql`), accepting TCP on `localhost`. The `ideal_magic` role owns four databases: `ideal_magic_production` (primary), and `_cache`, `_queue`, `_cable`.
- Ruby 4.0.3 and Node 24.13.1 come from `mise` installs under `/home/sawyer/.local/share/mise/installs/`. The systemd unit pins those paths explicitly so it does not depend on shell setup.

## Runtime processes

| Process | Where | Notes |
| --- | --- | --- |
| `web` | `ideal-magic-web.service` (Puma cluster, 2 workers, 5 threads) | Listens on `127.0.0.1:8083`. |
| `jobs` | Solid Queue inside Puma | Runs the `card_corpus` queue and any other registered queues. |
| `db` | `postgresql.service` | Host package, default cluster on `localhost:5432`. |
| `tls/edge` | `caddy.service` | Reverse-proxies the apex hostname; redirects `www`. |

Rails can talk to Codex App Server over the feature-flagged stdio JSON-RPC transport, but production keeps that flag off until AI evaluation ships. If Codex needs a long-lived runtime for production login/evaluation flows, add it as another systemd unit on the same VM, not folded into the web unit.

## Paths

| Thing | Path |
| --- | --- |
| App tree | `/home/sawyer/github/ideal-magic` |
| Env file | `/etc/ideal-magic-web/env` (root:sawyer 0640) |
| systemd unit | `/etc/systemd/system/ideal-magic-web.service` |
| Caddy config | `/etc/caddy/Caddyfile` (block: `ideal-magic.com`) |
| Sudoers drop-in | `/etc/sudoers.d/ideal-magic-web` |
| Master key | `/home/sawyer/github/ideal-magic/config/master.key` (gitignored) |
| Logs | `sudo journalctl -u ideal-magic-web` |

## Environment contract

Production env vars live in `/etc/ideal-magic-web/env` and are loaded by the systemd unit. The required and recommended variables today:

| Variable | Required | Notes |
| --- | --- | --- |
| `RAILS_ENV` | yes | Always `production` in this file. |
| `SECRET_KEY_BASE` | yes | 64-byte hex generated with `bin/rails secret`. |
| `IDEAL_MAGIC_DATABASE_PASSWORD` | yes | Password for the `ideal_magic` PostgreSQL role. |
| `IDEAL_MAGIC_DATABASE_HOST` | yes | Defaults to `localhost`. PG on the VM uses peer auth on the default socket, so TCP is required for the role. |
| `PORT` | yes | `8083`. Must match the Caddy upstream and the `ExecStart` flag. |
| `RAILS_SERVE_STATIC_FILES` | yes | `1`. Rails serves precompiled assets directly; Caddy is just the proxy. |
| `RAILS_FORCE_SSL` | yes | `true`. The Rails app is fronted by Caddy TLS. |
| `RAILS_LOG_LEVEL` | recommended | `info` in production. |
| `WEB_CONCURRENCY` | recommended | Puma worker count. Currently `2`. |
| `RAILS_MAX_THREADS` | recommended | Puma threads per worker. Currently `5`. Keep `database.yml` `max_connections` ≥ this. |
| `SOLID_QUEUE_IN_PUMA` | recommended | `true` until jobs need a separate process. |
| `APP_HOST` | yes | `ideal-magic.com`. Used for mailer URLs and similar. |
| `CODEX_APP_SERVER_ENABLED` | optional | `false` by default. Set to `true` only when the Codex App Server runtime is intentionally enabled. |
| `CODEX_HOME` | optional | Codex credential/cache home. Do not point this at a git-tracked path. |
| `CODEX_APP_SERVER_COMMAND` | optional | Command used by the stdio transport when enabled. Defaults to `codex app-server`. |
| `CODEX_APP_SERVER_REQUEST_TIMEOUT_SECONDS` | optional | JSON-RPC request timeout. Defaults to `20`. |

Never commit `/etc/ideal-magic-web/env`, `config/master.key`, or rotated database passwords. Update `.env.example` with placeholder names when a new variable is added so local development stays in sync.

## Deploy flow

The single command on the VM is:

```sh
bin/redeploy
```

Which performs, in order:

1. `git pull --ff-only`.
2. `bundle install` (production groups only; the script sets `BUNDLE_WITHOUT='development:test'`).
3. `bin/rails db:prepare` (creates/migrates primary, cache, queue, cable databases).
4. `bin/rails assets:precompile`.
5. `sudo systemctl restart ideal-magic-web.service` (passwordless via the sudoers drop-in).
6. Polls `https://ideal-magic.com/up` until it returns `200`, otherwise prints the last 40 lines of journal and exits non-zero.

Restart-only iteration (no pull, no asset rebuild):

```sh
sudo systemctl restart ideal-magic-web
```

Tail the live process:

```sh
sudo journalctl -u ideal-magic-web -f
```

## First-deploy bootstrap

The current production environment was bootstrapped roughly as follows; capture this as a runbook for spinning up a fresh VM:

1. Install system packages: `apt install postgresql postgresql-contrib libpq-dev caddy`. Install Ruby and Node via `mise` matching `.ruby-version` and `.mise.toml`.
2. Create the PostgreSQL role and four databases (`ideal_magic_production{,_cache,_queue,_cable}`) owned by `ideal_magic`. Generate a strong password and store it only in `/etc/ideal-magic-web/env`.
3. Clone the repo to `/home/sawyer/github/ideal-magic`.
4. Generate `config/master.key` and `config/credentials.yml.enc` with `EDITOR=true RAILS_ENV=production bundle exec rails credentials:edit`. Keep an out-of-band backup of `master.key`.
5. Write `/etc/ideal-magic-web/env` with the variables listed above.
6. Install `/etc/systemd/system/ideal-magic-web.service` (model on `dunamismax-web.service`), `daemon-reload`, then `systemctl enable --now ideal-magic-web`.
7. Append the `ideal-magic.com` and `www.ideal-magic.com` blocks to `/etc/caddy/Caddyfile`, validate with `caddy validate`, then `systemctl reload caddy`. Caddy will obtain TLS certificates on the first request.
8. Install `/etc/sudoers.d/ideal-magic-web` with `visudo -c -f` validation so `bin/redeploy` is non-interactive.
9. Verify: `curl -fsS https://ideal-magic.com/up`.

## Backups and restore

Not yet implemented. Tracked in `BUILD.md` Slice 8. What is needed before public traffic:

- `pg_dump` of all four production databases on a systemd timer.
- Active Storage blob backup once user uploads exist as durable product data.
- A restore script exercised against a fresh database cluster.
- Off-host copy of `config/master.key` and `/etc/ideal-magic-web/env`.

Backups are not complete until restore has been tested.

## Health checks

- `/up` — process up. Used by `bin/redeploy`.
- `/ready` — database connectivity (planned; see `BUILD.md` Slice 8).

`/up` is silenced in the Rails log via `config.silence_healthcheck_path = "/up"`, so frequent probes do not pollute production logs.

## Adding a new production process

When the worker eventually needs to leave Puma (or the Codex App Server runtime ships):

1. Copy `/etc/systemd/system/ideal-magic-web.service` to a sibling unit (`ideal-magic-worker.service`, `ideal-magic-codex.service`).
2. Replace `ExecStart` with the appropriate command (e.g. `bundle exec bin/jobs`).
3. Reuse `/etc/ideal-magic-web/env` via `EnvironmentFile=` so secrets stay in one place.
4. Add a matching `NOPASSWD` entry to `/etc/sudoers.d/ideal-magic-web` and extend `bin/redeploy` to restart the new unit alongside the web one.

Resist the urge to bring in Docker Compose just to add one process.

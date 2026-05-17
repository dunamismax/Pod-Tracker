# Operations

Pod Tracker production target:

```text
Cloudflare DNS
  -> Ubuntu VM
  -> Caddy
  -> pod-tracker-web
  -> pod-tracker-worker
  -> PostgreSQL service
```

This runbook documents the Rust/PostgreSQL deployment shape. It does not
claim the current public site has been migrated until these steps have
been run and verified on the VM.

## Paths

```text
/opt/pod-tracker/releases/       immutable release directories
/opt/pod-tracker/current         symlink to active release
/etc/pod-tracker/env             production environment file
/var/lib/pod-tracker             app-owned durable files if needed
/var/log/pod-tracker             app logs if file logging is added later
/var/backups/pod-tracker         PostgreSQL dump files
```

## First-Time Host Setup

Create the service account and directories:

```sh
sudo useradd --system --home /var/lib/pod-tracker --shell /usr/sbin/nologin pod-tracker
sudo install -d -o pod-tracker -g pod-tracker /var/lib/pod-tracker /var/log/pod-tracker
sudo install -d -o root -g root /etc/pod-tracker /opt/pod-tracker/releases
sudo install -d -m 0750 /var/backups/pod-tracker
```

Create `/etc/pod-tracker/env` from
`deploy/env/production.env.example`, replacing placeholders with real
local PostgreSQL credentials and SMTP2GO settings. Do not commit that
file.

```sh
sudo install -m 0640 -o root -g pod-tracker deploy/env/production.env.example /etc/pod-tracker/env
sudo editor /etc/pod-tracker/env
```

Install units and Caddy config:

```sh
sudo cp deploy/systemd/pod-tracker-*.service /etc/systemd/system/
sudo cp deploy/caddy/Caddyfile /etc/caddy/sites-enabled/pod-tracker.Caddyfile
sudo systemctl daemon-reload
sudo systemctl enable pod-tracker-web.service pod-tracker-worker.service
```

The exact Caddy include path depends on the VM's Caddy packaging. If the
main `/etc/caddy/Caddyfile` does not import `sites-enabled`, add an
import line or place the `pod-tracker.app` site block in the main file.
The checked-in site config proxies `pod-tracker.app` to
`127.0.0.1:8083`, which is the Rust web service address in the
production environment template. Rollback keeps the same proxy port and
points `/opt/pod-tracker/current` back to the previous verified release.

Install a Rust toolchain compatible with `rust-toolchain.toml` on the VM
before the first Rust deploy. The deploy script uses Cargo directly and
builds with `--locked`.

## Deploy

Run from a clean checkout on the VM:

```sh
sudo deploy/scripts/deploy.sh
```

The deploy script creates an immutable release directory, copies the Rust
workspace and deploy assets, builds `pod-tracker-web`,
`pod-tracker-worker`, and `pod-tracker-migrate` with Cargo, applies SQLx
migrations with `POD_TRACKER_MIGRATION_DATABASE_URL`, advances
`/opt/pod-tracker/current`, restarts the web and worker services, and
reloads Caddy. Keep `POD_TRACKER_DATABASE_URL` on the runtime role and
`POD_TRACKER_MIGRATION_DATABASE_URL` on the more privileged migration
role.

Check health:

```sh
systemctl status pod-tracker-web.service
systemctl status pod-tracker-worker.service
curl -fsS https://pod-tracker.app/healthz
curl -fsS https://pod-tracker.app/readyz
```

For local release smoke before touching production:

```sh
just release
POD_TRACKER_ADDR=127.0.0.1:18083 \
  POD_TRACKER_DATABASE_URL=postgres://pod_tracker:pod_tracker@localhost:5432/pod_tracker?sslmode=disable \
  target/release/pod-tracker-web
curl -fsS http://127.0.0.1:18083/healthz
curl -fsS http://127.0.0.1:18083/readyz
```

## Backup

Run:

```sh
sudo deploy/scripts/backup.sh
```

The script loads `/etc/pod-tracker/env`, runs `pg_dump` in custom format,
stores the dump under `/var/backups/pod-tracker`, and prints the backup
path. Copy backups off the VM through the normal server backup channel.

## Restore Drill

Use a non-production database for drills:

```sh
createdb pod_tracker_restore_drill
POD_TRACKER_RESTORE_DATABASE_URL=postgres://pod_tracker:CHANGE_ME@127.0.0.1:5432/pod_tracker_restore_drill?sslmode=disable \
  deploy/scripts/restore.sh /var/backups/pod-tracker/pod_tracker_TIMESTAMP.dump
```

After restore, run migrations and readiness checks against the restored
database. A production restore requires an explicit maintenance window,
a fresh backup, stopped services, and confirmation that the target URL is
the intended database.

Rust migration and readiness commands for the restored database:

```sh
POD_TRACKER_MIGRATION_DATABASE_URL="$POD_TRACKER_RESTORE_DATABASE_URL" \
  /opt/pod-tracker/current/bin/pod-tracker-migrate up
POD_TRACKER_DATABASE_URL="$POD_TRACKER_RESTORE_DATABASE_URL" \
  POD_TRACKER_ADDR=127.0.0.1:18084 \
  /opt/pod-tracker/current/bin/pod-tracker-web
curl -fsS http://127.0.0.1:18084/readyz
```

## Rollback

List releases:

```sh
ls -1 /opt/pod-tracker/releases
```

Point `current` back to the previous release and restart:

```sh
sudo ln -sfn /opt/pod-tracker/releases/PREVIOUS_RELEASE /opt/pod-tracker/current
sudo systemctl restart pod-tracker-web.service pod-tracker-worker.service
```

Database migrations are forward-only during normal deploys. If a schema
change requires a data rollback, write a specific recovery plan before
deploying it.

## Current Readiness

`/readyz` checks the database when `POD_TRACKER_DATABASE_URL` is set and
requires the SQLx migration table plus `core.users`,
`ops.background_jobs`, and `ops.email_deliveries`.

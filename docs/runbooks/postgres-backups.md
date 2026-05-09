# PostgreSQL Backups and Restore Drill

Operator runbook for the Pod Tracker production PostgreSQL backups. The host (`pod-tracker.app`) runs PostgreSQL 17 from Ubuntu's package; this runbook covers `pg_dump`-based logical backups for the four production databases plus the documented restore-verification drill.

## What gets backed up

`bin/backup_db` dumps every production database via `pg_dump --format=custom`:

| Database | Why it's dumped |
| --- | --- |
| `pod_tracker_production` | Primary application data (users, decks, analyses, sessions, matchup notes, audit events). Loss-bearing — must be restorable. |
| `pod_tracker_production_cache` | Solid Cache. Disposable in principle, but a cold cache on restore is worth avoiding when the dump is cheap. |
| `pod_tracker_production_queue` | Solid Queue. Carries scheduled and in-flight jobs. Restoring it preserves recurring schedules and pending Codex evaluations. |
| `pod_tracker_production_cable` | Solid Cable. State is short-lived; included for parity. |

The dumps are written under `$BACKUP_ROOT` (default `/var/backups/pod-tracker`), keyed by UTC date and timestamp. Each run directory carries:

- one `<database>.dump` per database (custom-format, compressed),
- a `MANIFEST` listing `<database> <bytes> <sha256>` for every dump,
- an `OK` marker written last; its absence means the run failed mid-flight.

The script logs progress to stdout and errors to stderr, and exits non-zero if any individual `pg_dump` failed. Failed runs are kept on disk (without `OK`) so the operator can inspect what went wrong before the next attempt.

## What is *not* backed up

- `config/master.key` — gitignored locally, must be backed up out-of-band (1Password, paper, etc.). Without it, `config/credentials.yml.enc` is unreadable on a fresh host.
- `/etc/pod-tracker-web/env` — contains `SECRET_KEY_BASE` and the database password. Same out-of-band rule.
- Active Storage blobs — there are no user uploads in v1. Revisit when uploads land.

## Install

The systemd unit and timer files are committed at `config/systemd/pod-tracker-backup.{service,timer}`. To install on the production VM (one-time):

```sh
sudo install -m 0644 config/systemd/pod-tracker-backup.service /etc/systemd/system/pod-tracker-backup.service
sudo install -m 0644 config/systemd/pod-tracker-backup.timer   /etc/systemd/system/pod-tracker-backup.timer
sudo install -d -o sawyer -g sawyer -m 0750 /var/backups/pod-tracker
sudo systemctl daemon-reload
sudo systemctl enable --now pod-tracker-backup.timer
```

To allow the operator to run the unit by hand without a sudo password, append the matching `NOPASSWD` lines to `/etc/sudoers.d/pod-tracker-web` (validate with `visudo -c -f`):

```
sawyer ALL=(root) NOPASSWD: /bin/systemctl start pod-tracker-backup.service, /bin/systemctl status pod-tracker-backup.service, /bin/systemctl status pod-tracker-backup.timer, /bin/journalctl -u pod-tracker-backup*
```

Verify the timer is armed:

```sh
systemctl list-timers pod-tracker-backup.timer
```

## Schedule

`pod-tracker-backup.timer` fires `OnCalendar=*-*-* 03:30:00 UTC` with a 5-minute randomized delay and `Persistent=true` so a missed run executes at boot. 03:30 UTC is intentionally off the 10:30 UTC Scryfall corpus refresh window (see `docs/runbooks/scryfall-corpus-refresh.md`).

`bin/backup_db` honors:

- `BACKUP_ROOT` (default `/var/backups/pod-tracker`)
- `BACKUP_RETENTION_DAYS` (default `14`) — date-keyed directories with mtime older than this are pruned after a successful run. Set to `0` to disable retention.
- `POD_TRACKER_ENV_FILE` (default `/etc/pod-tracker-web/env`) — must define `POD_TRACKER_DATABASE_PASSWORD` and (optionally) `POD_TRACKER_DATABASE_HOST`.

Fourteen days of retention at the current scale is well under 1 GiB; revisit when the corpus or per-deck analysis history grows materially.

## Manual run

```sh
sudo systemctl start pod-tracker-backup.service
sudo systemctl status pod-tracker-backup.service
sudo journalctl -u pod-tracker-backup -n 50
```

Or, without systemd (e.g. before a risky migration on a non-prod host):

```sh
bin/backup_db
```

A successful run prints the new run directory on stdout:

```
==> backup complete: /var/backups/pod-tracker/2026-05-07/20260507T033012Z
```

## Restore drill

Backups are not real until a restore has succeeded. `bin/restore_db_drill` performs a non-destructive verification:

```sh
bin/restore_db_drill /var/backups/pod-tracker/2026-05-07/20260507T033012Z
```

The drill:

1. Reads the run's `MANIFEST` and re-checks every dump's `sha256`.
2. Creates a throwaway database `pod_tracker_restore_drill_<pid>_<epoch>` owned by `pod_tracker`.
3. Runs `pg_restore --exit-on-error` against the primary dump (`pod_tracker_production.dump`).
4. Counts rows on `users`, `decks`, and `oracle_cards` to confirm the schema and core data made it through.
5. Drops the throwaway database.

Run the drill at minimum:

- After installing the timer for the first time.
- After every PostgreSQL major version upgrade.
- After any change to `bin/backup_db` or the dump options.
- Quarterly, even if nothing changed — a backup that nobody has restored in three months is no longer a backup.

If the drill fails, capture the run directory path, the `journalctl` line, and the `pg_restore` output before re-running the backup. Do not delete the failing run; it is the evidence.

## Restoring for real

If primary data is lost (corruption, accidental destructive migration, host loss), restore the most recent `OK`-marked run:

1. Identify the run: `ls -1 /var/backups/pod-tracker/*/  | tail -n5` and pick the latest with an `OK` marker.
2. Stop the web service so nothing writes to a partial database:
   ```sh
   sudo systemctl stop pod-tracker-web
   ```
3. Take a safety dump of the current (broken) database in case you need forensics:
   ```sh
   pg_dump --format=custom pod_tracker_production -f /tmp/pod_tracker_production.pre-restore.dump
   ```
4. Drop and recreate the target database (this is destructive — be sure):
   ```sh
   psql -d postgres -c 'DROP DATABASE pod_tracker_production;'
   psql -d postgres -c 'CREATE DATABASE pod_tracker_production OWNER pod_tracker;'
   ```
5. Restore:
   ```sh
   pg_restore \
     --dbname=pod_tracker_production \
     --no-owner \
     --no-privileges \
     --exit-on-error \
     /var/backups/pod-tracker/<DATE>/<STAMP>/pod_tracker_production.dump
   ```
6. Repeat steps 4–5 for the cache, queue, and cable databases if they need to be restored. Cache and Cable can also be rebuilt by `bin/rails db:prepare`; only restore them if the lost in-flight state matters.
7. Run `bin/rails db:migrate` to apply any migrations newer than the dump.
8. Bring the web service back up:
   ```sh
   sudo systemctl start pod-tracker-web
   curl -fsS https://pod-tracker.app/up
   ```

The connection details (`PGHOST`, `PGUSER`, `PGPASSWORD`) come from `/etc/pod-tracker-web/env`. Source that file or export the variables before running `pg_dump` / `pg_restore` against production.

## Off-host copies

The on-VM backups protect against application-level data loss but not against host loss. For v1, copy successful run directories off-host on an out-of-band cadence — `rsync` to a workstation, `restic`/`borg` to S3-compatible storage, or scp into the same off-host vault that holds `config/master.key` and `/etc/pod-tracker-web/env`. The off-host destination is intentionally not in scope for the systemd timer; choosing it commits a long-lived secret to live on the production host.

## Failure modes

- **`backup_db: POD_TRACKER_DATABASE_PASSWORD not set`** — the env file is missing or the variable was renamed. Backups are skipped; restore the env file before re-running the timer.
- **`pg_dump: error: connection to server on socket "/var/run/postgresql/.s.PGSQL.5432" failed`** — the script is connecting via socket because the host fell back to peer auth. Confirm `POD_TRACKER_DATABASE_HOST=localhost` is set in the env file so `pg_dump` uses TCP under the `pod_tracker` role.
- **Run directory exists with no `OK`** — the previous run failed; check `sudo journalctl -u pod-tracker-backup` for the underlying error and re-run by hand. The timer will not retry until the next scheduled fire.
- **`No space left on device`** — `BACKUP_ROOT` filled up. Lower `BACKUP_RETENTION_DAYS`, copy old runs off-host, or move `BACKUP_ROOT` onto a larger volume.

## Verifying the timer

```sh
systemctl list-timers pod-tracker-backup.timer
sudo journalctl -u pod-tracker-backup --since "yesterday"
ls -1 /var/backups/pod-tracker/$(date -u +%Y-%m-%d)/
```

A healthy state has a recent run directory with an `OK` marker, four `*.dump` files, and a `MANIFEST` whose sha256 entries match the on-disk files.

#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
source_db="${POD_TRACKER_DRILL_SOURCE_DB:-pod_tracker_drill_source_${timestamp}}"
restore_db="${POD_TRACKER_DRILL_RESTORE_DB:-pod_tracker_drill_restore_${timestamp}}"
db_host="${POD_TRACKER_DRILL_DB_HOST:-localhost}"
db_port="${POD_TRACKER_DRILL_DB_PORT:-5432}"
db_user="${POD_TRACKER_DRILL_DB_USER:-$(whoami)}"
sslmode="${POD_TRACKER_DRILL_SSLMODE:-disable}"
keep_artifacts="${POD_TRACKER_DRILL_KEEP_ARTIFACTS:-0}"

backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/pod-tracker-restore-drill.XXXXXX")"
env_file="${backup_dir}/drill.env"
source_url="postgres://${db_user}@${db_host}:${db_port}/${source_db}?sslmode=${sslmode}"
restore_url="postgres://${db_user}@${db_host}:${db_port}/${restore_db}?sslmode=${sslmode}"

validate_drill_db_name() {
  local name="$1"
  if [[ ! "$name" =~ ^pod_tracker_drill_[A-Za-z0-9_]+$ ]]; then
    printf 'refusing non-drill database name: %s\n' "$name" >&2
    printf 'database names must start with pod_tracker_drill_\n' >&2
    exit 1
  fi
}

cleanup() {
  local status=$?
  if [[ "$keep_artifacts" != "1" ]]; then
    dropdb --if-exists --host "$db_host" --port "$db_port" --username "$db_user" "$source_db" >/dev/null 2>&1 || true
    dropdb --if-exists --host "$db_host" --port "$db_port" --username "$db_user" "$restore_db" >/dev/null 2>&1 || true
    rm -rf "$backup_dir"
  else
    printf 'kept drill artifacts in %s\n' "$backup_dir"
  fi
  exit "$status"
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    printf 'required command is missing: %s\n' "$name" >&2
    exit 1
  fi
}

apply_migrations() {
  local database_url="$1"

  psql -v ON_ERROR_STOP=1 "$database_url" <<'SQL' >/dev/null
create table if not exists public._sqlx_migrations (
  version bigint primary key,
  description text not null,
  installed_on timestamptz not null default now(),
  success boolean not null,
  checksum bytea not null,
  execution_time bigint not null
);
SQL

  local migration migration_name version version_number description already_applied
  for migration in "$repo_root"/crates/pod-db/migrations/*.sql; do
    migration_name="$(basename "$migration")"
    version="${migration_name%%_*}"
    version_number="$((10#$version))"
    description="${migration_name#*_}"
    description="${description%.sql}"
    already_applied="$(
      psql \
        -v ON_ERROR_STOP=1 \
        -v version="$version_number" \
        -At \
        "$database_url" <<'SQL'
select exists(
  select 1
  from public._sqlx_migrations
  where version = :version
    and success
);
SQL
    )"
    if [[ "$already_applied" == "t" ]]; then
      continue
    fi
    psql -v ON_ERROR_STOP=1 "$database_url" -f "$migration" >/dev/null
    psql \
      -v ON_ERROR_STOP=1 \
      -v version="$version_number" \
      -v description="$description" \
      "$database_url" <<'SQL' >/dev/null
insert into public._sqlx_migrations (
  version, description, installed_on, success, checksum, execution_time
)
values (:version, :'description', now(), true, '\x'::bytea, 0)
on conflict (version) do update
set description = excluded.description,
    success = excluded.success,
    checksum = excluded.checksum,
    execution_time = excluded.execution_time;
SQL
  done
}

validate_drill_db_name "$source_db"
validate_drill_db_name "$restore_db"
if [[ "$source_db" == "$restore_db" ]]; then
  printf 'source and restore drill databases must be different\n' >&2
  exit 1
fi

for command in createdb dropdb pg_dump pg_restore psql; do
  require_command "$command"
done

trap cleanup EXIT

createdb --host "$db_host" --port "$db_port" --username "$db_user" "$source_db"
createdb --host "$db_host" --port "$db_port" --username "$db_user" "$restore_db"

apply_migrations "$source_url"

psql -v ON_ERROR_STOP=1 "$source_url" <<'SQL' >/dev/null
insert into ops.background_jobs (queue, job_type, payload)
values (
  'maintenance',
  'backup_restore_drill_marker',
  '{"kind":"backup_restore_drill","sensitive":false}'::jsonb
);
SQL

printf 'POD_TRACKER_DATABASE_URL=%q\n' "$source_url" >"$env_file"
printf 'POD_TRACKER_RESTORE_DATABASE_URL=%q\n' "$restore_url" >>"$env_file"

backup_file="$(
  POD_TRACKER_ENV_FILE="$env_file" \
  POD_TRACKER_BACKUP_DIR="$backup_dir" \
  "$repo_root/deploy/scripts/backup.sh"
)"

pg_restore --list "$backup_file" >/dev/null

POD_TRACKER_ENV_FILE="$env_file" \
POD_TRACKER_RESTORE_CONFIRM=RESTORE \
  "$repo_root/deploy/scripts/restore.sh" "$backup_file"

apply_migrations "$restore_url"

psql -v ON_ERROR_STOP=1 "$restore_url" <<'SQL' >/dev/null
do $$
begin
  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = '_sqlx_migrations'
  ) then
    raise exception 'missing _sqlx_migrations table after restore';
  end if;

  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'core'
      and table_name = 'users'
  ) then
    raise exception 'missing core.users after restore';
  end if;

  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'ops'
      and table_name = 'background_jobs'
  ) then
    raise exception 'missing ops.background_jobs after restore';
  end if;

  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'ops'
      and table_name = 'email_deliveries'
  ) then
    raise exception 'missing ops.email_deliveries after restore';
  end if;

  if not exists (
    select 1
    from ops.background_jobs
    where job_type = 'backup_restore_drill_marker'
      and payload = '{"kind":"backup_restore_drill","sensitive":false}'::jsonb
  ) then
    raise exception 'missing restored drill marker row';
  end if;
end
$$;
SQL

printf 'backup_restore_drill=ok\n'
printf 'source_db=%s\n' "$source_db"
printf 'restore_db=%s\n' "$restore_db"
printf 'backup_file=%s\n' "$backup_file"

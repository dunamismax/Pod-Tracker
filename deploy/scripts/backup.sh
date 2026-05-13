#!/usr/bin/env bash
set -euo pipefail

env_file="${POD_TRACKER_ENV_FILE:-/etc/pod-tracker/env}"
backup_dir="${POD_TRACKER_BACKUP_DIR:-/var/backups/pod-tracker}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_file="${backup_dir}/pod_tracker_${timestamp}.dump"

if [[ ! -f "$env_file" ]]; then
  printf 'missing environment file: %s\n' "$env_file" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

install -d -m 0750 "$backup_dir"
pg_dump --format=custom --no-owner --no-acl --file "$backup_file" "$POD_TRACKER_DATABASE_URL"
chmod 0640 "$backup_file"
printf '%s\n' "$backup_file"

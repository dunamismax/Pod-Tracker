#!/usr/bin/env bash
set -euo pipefail

env_file="${POD_TRACKER_ENV_FILE:-/etc/pod-tracker/env}"

if [[ $# -ne 1 ]]; then
  printf 'usage: %s /path/to/pod_tracker.dump\n' "$0" >&2
  exit 1
fi

backup_file="$1"
if [[ ! -f "$backup_file" ]]; then
  printf 'backup file does not exist: %s\n' "$backup_file" >&2
  exit 1
fi
if [[ ! -f "$env_file" ]]; then
  printf 'missing environment file: %s\n' "$env_file" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

restore_url="${POD_TRACKER_RESTORE_DATABASE_URL:-${POD_TRACKER_DATABASE_URL:-}}"
if [[ -z "$restore_url" ]]; then
  printf 'POD_TRACKER_RESTORE_DATABASE_URL or POD_TRACKER_DATABASE_URL is required\n' >&2
  exit 1
fi

confirmation="${POD_TRACKER_RESTORE_CONFIRM:-}"
if [[ -z "$confirmation" ]]; then
  read -r -p "Restore ${backup_file} into configured database? Type RESTORE to continue: " confirmation
fi
if [[ "$confirmation" != "RESTORE" ]]; then
  printf 'restore cancelled\n' >&2
  exit 1
fi

pg_restore --clean --if-exists --no-owner --no-acl --dbname "$restore_url" "$backup_file"

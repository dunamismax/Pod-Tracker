#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
release_root="${POD_TRACKER_RELEASE_ROOT:-/opt/pod-tracker/releases}"
current_link="${POD_TRACKER_CURRENT_LINK:-/opt/pod-tracker/current}"
release_id="$(date -u +%Y%m%dT%H%M%SZ)"
release_dir="${release_root}/${release_id}"
env_file="${POD_TRACKER_ENV_FILE:-/etc/pod-tracker/env}"

if [[ ! -f "$env_file" ]]; then
  printf 'missing environment file: %s\n' "$env_file" >&2
  exit 1
fi

install -d "$release_dir/bin"
cp -a "$repo_root"/cmd "$release_dir"/
cp -a "$repo_root"/deploy "$release_dir"/
cp -a "$repo_root"/internal "$release_dir"/
cp -a "$repo_root"/migrations "$release_dir"/
cp -a "$repo_root"/web "$release_dir"/
cp -a "$repo_root"/go.mod "$repo_root"/go.sum "$repo_root"/sqlc.yaml "$repo_root"/justfile "$release_dir"/

(
  cd "$release_dir"
  go build -o bin/pod-tracker-web ./cmd/pod-tracker-web
  go build -o bin/pod-tracker-worker ./cmd/pod-tracker-worker
  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
  go run github.com/pressly/goose/v3/cmd/goose@v3.27.1 -dir migrations postgres "$POD_TRACKER_MIGRATION_DATABASE_URL" up
)

ln -sfn "$release_dir" "$current_link"
systemctl daemon-reload
systemctl restart pod-tracker-web.service
systemctl restart pod-tracker-worker.service
systemctl reload caddy.service

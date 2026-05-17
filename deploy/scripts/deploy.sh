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
cp -a "$repo_root"/Cargo.lock "$repo_root"/Cargo.toml "$repo_root"/rust-toolchain.toml "$release_dir"/
cp -a "$repo_root"/AGENTS.md "$repo_root"/BUILD.md "$repo_root"/README.md "$repo_root"/LICENSE "$release_dir"/
cp -a "$repo_root"/crates "$release_dir"/
cp -a "$repo_root"/deploy "$release_dir"/
cp -a "$repo_root"/docs "$release_dir"/
cp -a "$repo_root"/justfile "$release_dir"/

(
  cd "$release_dir"
  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
  export DATABASE_URL="${DATABASE_URL:-$POD_TRACKER_DATABASE_URL}"
  cargo build --locked --release \
    -p pod-web --bin pod-tracker-web \
    -p pod-worker --bin pod-tracker-worker \
    -p pod-db --bin pod-tracker-migrate
  cp target/release/pod-tracker-web bin/
  cp target/release/pod-tracker-worker bin/
  cp target/release/pod-tracker-migrate bin/
  bin/pod-tracker-migrate up
)

ln -sfn "$release_dir" "$current_link"
systemctl daemon-reload
systemctl restart pod-tracker-web.service
systemctl restart pod-tracker-worker.service
systemctl reload caddy.service

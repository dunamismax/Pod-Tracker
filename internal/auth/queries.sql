-- name: CreateUser :one
insert into core.users (email, display_name, password_hash)
values ($1, $2, $3)
returning id, email, display_name, password_hash, created_at, updated_at;

-- name: GetUserByEmail :one
select id, email, display_name, password_hash, created_at, updated_at
from core.users
where email = $1;

-- name: GetUserByID :one
select id, email, display_name, password_hash, created_at, updated_at
from core.users
where id = $1;

-- name: CreateSession :one
insert into core.sessions (user_id, token_hash, user_agent, ip_address, expires_at)
values ($1, $2, $3, $4, $5)
returning id, user_id, token_hash, user_agent, ip_address, created_at, last_seen_at, expires_at, revoked_at;

-- name: GetSessionByTokenHash :one
select id, user_id, token_hash, user_agent, ip_address, created_at, last_seen_at, expires_at, revoked_at
from core.sessions
where token_hash = $1
  and revoked_at is null
  and expires_at > now();

-- name: RevokeSession :exec
update core.sessions
set revoked_at = now()
where token_hash = $1
  and revoked_at is null;

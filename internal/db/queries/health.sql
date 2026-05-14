-- name: CheckDatabase :one
select 1::int as ok;

-- name: CheckMigrationsReady :one
select (
  to_regclass('core.users') is not null and
  to_regclass('core.playgroups') is not null and
  to_regclass('core.events') is not null
)::boolean as ready;

-- name: CheckBackgroundJobsReady :one
select (to_regclass('ops.background_jobs') is not null)::boolean as ready;

-- name: CheckEmailDeliveriesReady :one
select (to_regclass('ops.email_deliveries') is not null)::boolean as ready;

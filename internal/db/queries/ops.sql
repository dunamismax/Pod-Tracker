-- name: InsertEmailDelivery :one
insert into ops.email_deliveries (
  to_address, subject, body_text, body_html
) values (
  $1, $2, $3, $4
) returning *;

-- name: UpdateEmailDeliveryStatus :one
update ops.email_deliveries
set
  status = $2,
  error_message = $3,
  sent_at = case when $2 = 'sent' then now() else sent_at end,
  updated_at = now()
where id = $1
returning *;

-- name: GetEmailDelivery :one
select * from ops.email_deliveries where id = $1;

-- name: InsertBackgroundJob :one
insert into ops.background_jobs (
  queue, job_type, payload, run_at
) values (
  $1, $2, $3, $4
) returning *;

-- name: AcquireNextBackgroundJob :one
update ops.background_jobs
set 
  locked_at = now(),
  locked_by = $1,
  attempts = attempts + 1,
  updated_at = now()
where id = (
  select id from ops.background_jobs
  where run_at <= now() and locked_at is null
  order by run_at asc
  limit 1
  for update skip locked
)
returning *;

-- name: CompleteBackgroundJob :exec
delete from ops.background_jobs where id = $1;

-- name: FailBackgroundJob :exec
update ops.background_jobs
set
  locked_at = null,
  locked_by = null,
  last_error = $2,
  run_at = now() + (pow(2, attempts) * interval '1 minute'),
  updated_at = now()
where id = $1;

-- name: CreateEventLocation :one
insert into core.event_locations (
  playgroup_id, name, address_line1, address_line2, city, state_province, postal_code, country, notes, created_by
) values (
  $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
) returning *;

-- name: GetEventLocation :one
select * from core.event_locations where id = $1;

-- name: CreateEvent :one
insert into core.events (
  playgroup_id, title, description, start_time, end_time, location_id, visibility, invite_token, created_by
) values (
  $1, $2, $3, $4, $5, $6, $7, $8, $9
) returning *;

-- name: GetEvent :one
select * from core.events where id = $1;

-- name: UpdateEvent :one
update core.events
set 
  title = $2,
  description = $3,
  start_time = $4,
  end_time = $5,
  visibility = $6,
  updated_at = now()
where id = $1
returning *;

-- name: ListEventsForPlaygroup :many
select * from core.events
where playgroup_id = $1
order by start_time asc;

-- name: CreateEventHost :one
insert into core.event_hosts (
  event_id, user_id, address_visibility
) values (
  $1, $2, $3
) returning *;

-- name: GetEventHost :one
select * from core.event_hosts
where event_id = $1 and user_id = $2;

-- name: ListEventHosts :many
select * from core.event_hosts
where event_id = $1;

-- name: CreateEventRSVP :one
insert into core.event_rsvps (
  event_id, user_id, guest_name, status, arrival_time, leaving_time, guest_count, travel_buffer_minutes, notes
) values (
  $1, $2, $3, $4, $5, $6, $7, $8, $9
) returning *;

-- name: GetEventRSVP :one
select * from core.event_rsvps
where event_id = $1 and user_id = $2;

-- name: GetEventRSVPByID :one
select * from core.event_rsvps
where id = $1;

-- name: ListEventRSVPs :many
select * from core.event_rsvps
where event_id = $1;

-- name: UpdateEventRSVP :one
update core.event_rsvps
set 
  status = $2,
  arrival_time = $3,
  leaving_time = $4,
  guest_count = $5,
  travel_buffer_minutes = $6,
  notes = $7,
  updated_at = now()
where id = $1
returning *;

-- name: CreateEventGuest :one
insert into core.event_guests (
  event_id, rsvp_id, name
) values (
  $1, $2, $3
) returning *;

-- name: ListEventGuests :many
select * from core.event_guests
where event_id = $1;

-- name: CreateEventReminder :one
insert into core.event_reminders (
  event_id, scheduled_for, reminder_type, status, created_by
) values (
  $1, $2, $3, $4, $5
) returning *;

create schema if not exists ops;

create table core.event_locations (
  id uuid primary key default gen_random_uuid(),
  playgroup_id uuid not null references core.playgroups (id) on delete cascade,
  name text not null,
  address_line1 text,
  address_line2 text,
  city text,
  state_province text,
  postal_code text,
  country text,
  notes text not null default '',
  created_by uuid references core.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_locations_name_not_blank check (length(btrim(name)) > 0)
);

create index event_locations_playgroup_id_idx on core.event_locations (playgroup_id);

create table core.events (
  id uuid primary key default gen_random_uuid(),
  playgroup_id uuid not null references core.playgroups (id) on delete cascade,
  title text not null,
  description text not null default '',
  start_time timestamptz not null,
  end_time timestamptz,
  location_id uuid references core.event_locations (id) on delete set null,
  visibility text not null default 'members',
  invite_token text unique,
  created_by uuid references core.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint events_title_not_blank check (length(btrim(title)) > 0),
  constraint events_visibility_check check (visibility in ('members', 'invite_only', 'public_safe'))
);

create index events_playgroup_id_idx on core.events (playgroup_id);
create index events_start_time_idx on core.events (start_time);

create table core.event_hosts (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references core.events (id) on delete cascade,
  user_id uuid not null references core.users (id) on delete cascade,
  address_visibility text not null default 'rsvps',
  created_at timestamptz not null default now(),
  constraint event_hosts_address_visibility_check check (address_visibility in ('rsvps', 'members', 'public', 'hidden'))
);

create unique index event_hosts_event_user_key on core.event_hosts (event_id, user_id);

create table core.event_rsvps (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references core.events (id) on delete cascade,
  user_id uuid references core.users (id) on delete cascade,
  guest_name text,
  status text not null,
  arrival_time timestamptz,
  leaving_time timestamptz,
  guest_count integer not null default 0,
  travel_buffer_minutes integer,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_rsvps_status_check check (status in ('yes', 'maybe', 'no', 'waitlist')),
  constraint event_rsvps_guest_count_nonnegative check (guest_count >= 0),
  constraint event_rsvps_user_or_guest_name check (
    (user_id is not null and guest_name is null) or
    (user_id is null and guest_name is not null and length(btrim(guest_name)) > 0)
  )
);

create unique index event_rsvps_event_user_key on core.event_rsvps (event_id, user_id) where user_id is not null;
create index event_rsvps_event_id_idx on core.event_rsvps (event_id);

create table core.event_guests (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references core.events (id) on delete cascade,
  rsvp_id uuid not null references core.event_rsvps (id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_guests_name_not_blank check (length(btrim(name)) > 0)
);

create table core.event_reminders (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references core.events (id) on delete cascade,
  scheduled_for timestamptz not null,
  reminder_type text not null,
  status text not null default 'pending',
  created_by uuid references core.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_reminders_status_check check (status in ('pending', 'sent', 'failed', 'cancelled')),
  constraint event_reminders_reminder_type_not_blank check (length(btrim(reminder_type)) > 0)
);

create index event_reminders_scheduled_for_idx on core.event_reminders (scheduled_for) where status = 'pending';

create table ops.background_jobs (
  id uuid primary key default gen_random_uuid(),
  queue text not null default 'default',
  job_type text not null,
  payload jsonb not null default '{}'::jsonb,
  run_at timestamptz not null default now(),
  locked_at timestamptz,
  locked_by text,
  attempts integer not null default 0,
  max_attempts integer not null default 3,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint background_jobs_job_type_not_blank check (length(btrim(job_type)) > 0)
);

create index background_jobs_run_at_idx on ops.background_jobs (queue, run_at) where locked_at is null;

create table ops.email_deliveries (
  id uuid primary key default gen_random_uuid(),
  to_address text not null,
  subject text not null,
  body_text text,
  body_html text,
  status text not null default 'pending',
  error_message text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint email_deliveries_status_check check (status in ('pending', 'sent', 'failed'))
);

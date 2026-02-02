# Supabase Setup Guide (Gatherer)

This guide describes a clean, minimal Supabase schema for Gatherer and the recommended policies for a privacy-first, pod-scoped coordination app.

## Prerequisites

- A Supabase project created in the dashboard
- A local `.env` with:
  - `EXPO_PUBLIC_SUPABASE_URL`
  - `EXPO_PUBLIC_SUPABASE_ANON_KEY`

## Create the schema

Open the Supabase SQL editor and run the following in order.

### 1) Extensions

```sql
create extension if not exists "pgcrypto";
```

### 2) Enums

```sql
do $$ begin
  create type membership_role as enum ('owner', 'admin', 'member');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type invite_status as enum ('pending', 'accepted', 'revoked', 'expired');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type rsvp_status as enum ('yes', 'no', 'maybe');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type arrival_status as enum ('not_sure', 'on_the_way', 'arrived', 'late');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type checklist_state as enum ('open', 'done', 'blocked');
exception
  when duplicate_object then null;
end $$;
```

### 3) Tables

```sql
-- Pods: the core trusted group
create table if not exists pods (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  location_text text,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Pod memberships: who is in each pod
create table if not exists pod_memberships (
  id uuid primary key default gen_random_uuid(),
  pod_id uuid not null references pods(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role membership_role not null default 'member',
  is_active boolean not null default true,
  joined_at timestamptz not null default now(),
  unique (pod_id, user_id)
);

-- Events: a single gathering within a pod
create table if not exists events (
  id uuid primary key default gen_random_uuid(),
  pod_id uuid not null references pods(id) on delete cascade,
  title text not null,
  description text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  location_text text,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Event attendance and arrival status
create table if not exists event_attendance (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rsvp rsvp_status not null default 'maybe',
  arrival arrival_status not null default 'not_sure',
  eta_minutes integer,
  updated_at timestamptz not null default now(),
  unique (event_id, user_id)
);

-- Checklist items scoped to an event
create table if not exists event_checklist_items (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  label text not null,
  state checklist_state not null default 'open',
  note text,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Invites for new pod members
create table if not exists pod_invites (
  id uuid primary key default gen_random_uuid(),
  pod_id uuid not null references pods(id) on delete cascade,
  invited_email text,
  invited_user_id uuid references auth.users(id) on delete set null,
  invited_by uuid not null references auth.users(id) on delete restrict,
  status invite_status not null default 'pending',
  token text not null unique,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
```

### 4) Indexes

```sql
create index if not exists idx_pod_memberships_pod on pod_memberships(pod_id);
create index if not exists idx_pod_memberships_user on pod_memberships(user_id);
create index if not exists idx_events_pod on events(pod_id);
create index if not exists idx_events_starts_at on events(starts_at);
create index if not exists idx_event_attendance_event on event_attendance(event_id);
create index if not exists idx_event_attendance_user on event_attendance(user_id);
create index if not exists idx_checklist_event on event_checklist_items(event_id);
create index if not exists idx_invites_pod on pod_invites(pod_id);
```

### 5) Updated-at trigger

```sql
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

do $$ begin
  create trigger pods_set_updated_at before update on pods
  for each row execute procedure set_updated_at();
exception when duplicate_object then null; end $$;

do $$ begin
  create trigger events_set_updated_at before update on events
  for each row execute procedure set_updated_at();
exception when duplicate_object then null; end $$;

do $$ begin
  create trigger checklist_set_updated_at before update on event_checklist_items
  for each row execute procedure set_updated_at();
exception when duplicate_object then null; end $$;
```

## Row Level Security (RLS)

Enable RLS and add policies so only pod members can read/write their pod data.

### 1) Enable RLS

```sql
alter table pods enable row level security;
alter table pod_memberships enable row level security;
alter table events enable row level security;
alter table event_attendance enable row level security;
alter table event_checklist_items enable row level security;
alter table pod_invites enable row level security;
```

### 2) Policies

```sql
-- Pods: members can read pods they belong to
create policy "pods_read" on pods
for select using (
  exists (
    select 1 from pod_memberships
    where pod_memberships.pod_id = pods.id
      and pod_memberships.user_id = auth.uid()
      and pod_memberships.is_active = true
  )
);

-- Pods: creators can insert
create policy "pods_insert" on pods
for insert with check (auth.uid() = created_by);

-- Pods: admins/owners can update
create policy "pods_update" on pods
for update using (
  exists (
    select 1 from pod_memberships
    where pod_memberships.pod_id = pods.id
      and pod_memberships.user_id = auth.uid()
      and pod_memberships.role in ('owner','admin')
  )
);

-- Memberships: members can read their pod memberships
create policy "memberships_read" on pod_memberships
for select using (
  exists (
    select 1 from pod_memberships m
    where m.pod_id = pod_memberships.pod_id
      and m.user_id = auth.uid()
      and m.is_active = true
  )
);

-- Memberships: pod owners/admins can insert members
create policy "memberships_insert" on pod_memberships
for insert with check (
  exists (
    select 1 from pod_memberships m
    where m.pod_id = pod_memberships.pod_id
      and m.user_id = auth.uid()
      and m.role in ('owner','admin')
  )
);

-- Events: pod members can read
create policy "events_read" on events
for select using (
  exists (
    select 1 from pod_memberships
    where pod_memberships.pod_id = events.pod_id
      and pod_memberships.user_id = auth.uid()
      and pod_memberships.is_active = true
  )
);

-- Events: pod members can insert
create policy "events_insert" on events
for insert with check (
  exists (
    select 1 from pod_memberships
    where pod_memberships.pod_id = events.pod_id
      and pod_memberships.user_id = auth.uid()
      and pod_memberships.is_active = true
  )
);

-- Events: creator or admin can update
create policy "events_update" on events
for update using (
  events.created_by = auth.uid()
  or exists (
    select 1 from pod_memberships
    where pod_memberships.pod_id = events.pod_id
      and pod_memberships.user_id = auth.uid()
      and pod_memberships.role in ('owner','admin')
  )
);

-- Attendance: members can read/write their attendance
create policy "attendance_read" on event_attendance
for select using (
  exists (
    select 1 from events
    join pod_memberships on pod_memberships.pod_id = events.pod_id
    where events.id = event_attendance.event_id
      and pod_memberships.user_id = auth.uid()
      and pod_memberships.is_active = true
  )
);

create policy "attendance_upsert" on event_attendance
for insert with check (auth.uid() = user_id);

create policy "attendance_update" on event_attendance
for update using (auth.uid() = user_id);

-- Checklist: pod members can read; creator or admins can edit
create policy "checklist_read" on event_checklist_items
for select using (
  exists (
    select 1 from events
    join pod_memberships on pod_memberships.pod_id = events.pod_id
    where events.id = event_checklist_items.event_id
      and pod_memberships.user_id = auth.uid()
      and pod_memberships.is_active = true
  )
);

create policy "checklist_insert" on event_checklist_items
for insert with check (
  exists (
    select 1 from events
    join pod_memberships on pod_memberships.pod_id = events.pod_id
    where events.id = event_checklist_items.event_id
      and pod_memberships.user_id = auth.uid()
      and pod_memberships.is_active = true
  )
);

create policy "checklist_update" on event_checklist_items
for update using (
  event_checklist_items.created_by = auth.uid()
  or exists (
    select 1 from events
    join pod_memberships on pod_memberships.pod_id = events.pod_id
    where events.id = event_checklist_items.event_id
      and pod_memberships.user_id = auth.uid()
      and pod_memberships.role in ('owner','admin')
  )
);

-- Invites: only admins/owners can read/create
create policy "invites_read" on pod_invites
for select using (
  exists (
    select 1 from pod_memberships
    where pod_memberships.pod_id = pod_invites.pod_id
      and pod_memberships.user_id = auth.uid()
      and pod_memberships.role in ('owner','admin')
  )
);

create policy "invites_insert" on pod_invites
for insert with check (
  exists (
    select 1 from pod_memberships
    where pod_memberships.pod_id = pod_invites.pod_id
      and pod_memberships.user_id = auth.uid()
      and pod_memberships.role in ('owner','admin')
  )
);
```

## Notes

- This schema is intentionally minimal; you can extend with profiles, pod images, recurring templates, and richer permissions later.
- For a new pod, insert into `pods`, then insert the creator into `pod_memberships` with role `owner`.
- For events, insert into `events` and optionally pre-create `event_attendance` rows for members.

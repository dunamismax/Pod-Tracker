-- Gatherer Supabase Setup (idempotent)
-- Safe to run multiple times; creates or updates schema, policies, and indexes without destroying data.

-- 1) Extensions
create extension if not exists "pgcrypto";

-- 2) Enums (create + ensure values)
DO $$ BEGIN
  create type membership_role as enum ('owner', 'admin', 'member');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  create type invite_status as enum ('pending', 'accepted', 'revoked', 'expired');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  create type rsvp_status as enum ('yes', 'no', 'maybe');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  create type arrival_status as enum ('not_sure', 'on_the_way', 'arrived', 'late');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  create type checklist_state as enum ('open', 'done', 'blocked');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Ensure enum values exist (safe for older deployments)
DO $$ BEGIN
  ALTER TYPE membership_role ADD VALUE IF NOT EXISTS 'owner';
  ALTER TYPE membership_role ADD VALUE IF NOT EXISTS 'admin';
  ALTER TYPE membership_role ADD VALUE IF NOT EXISTS 'member';
END $$;

DO $$ BEGIN
  ALTER TYPE invite_status ADD VALUE IF NOT EXISTS 'pending';
  ALTER TYPE invite_status ADD VALUE IF NOT EXISTS 'accepted';
  ALTER TYPE invite_status ADD VALUE IF NOT EXISTS 'revoked';
  ALTER TYPE invite_status ADD VALUE IF NOT EXISTS 'expired';
END $$;

DO $$ BEGIN
  ALTER TYPE rsvp_status ADD VALUE IF NOT EXISTS 'yes';
  ALTER TYPE rsvp_status ADD VALUE IF NOT EXISTS 'no';
  ALTER TYPE rsvp_status ADD VALUE IF NOT EXISTS 'maybe';
END $$;

DO $$ BEGIN
  ALTER TYPE arrival_status ADD VALUE IF NOT EXISTS 'not_sure';
  ALTER TYPE arrival_status ADD VALUE IF NOT EXISTS 'on_the_way';
  ALTER TYPE arrival_status ADD VALUE IF NOT EXISTS 'arrived';
  ALTER TYPE arrival_status ADD VALUE IF NOT EXISTS 'late';
END $$;

DO $$ BEGIN
  ALTER TYPE checklist_state ADD VALUE IF NOT EXISTS 'open';
  ALTER TYPE checklist_state ADD VALUE IF NOT EXISTS 'done';
  ALTER TYPE checklist_state ADD VALUE IF NOT EXISTS 'blocked';
END $$;

-- 3) Tables
create table if not exists pods (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  location_text text,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  email text,
  first_name text,
  last_name text,
  phone text,
  contact_email text,
  contact_handle text,
  contact_notes text,
  avatar_url text,
  updated_at timestamptz not null default now()
);

create table if not exists pod_memberships (
  id uuid primary key default gen_random_uuid(),
  pod_id uuid not null references pods(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role membership_role not null default 'member',
  is_active boolean not null default true,
  joined_at timestamptz not null default now(),
  unique (pod_id, user_id)
);

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

create table if not exists pod_invites (
  id uuid primary key default gen_random_uuid(),
  pod_id uuid not null references pods(id) on delete cascade,
  invited_email text,
  invited_user_id uuid references auth.users(id) on delete set null,
  invited_by uuid not null references auth.users(id) on delete restrict,
  status invite_status not null default 'pending',
  token text not null unique default encode(gen_random_uuid()::bytea, 'hex'),
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

-- 3b) Non-destructive column adds (for older schemas)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS display_name text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS email text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS first_name text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS last_name text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS contact_email text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS contact_handle text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS contact_notes text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS avatar_url text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS updated_at timestamptz not null default now();

ALTER TABLE pods ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE pods ADD COLUMN IF NOT EXISTS location_text text;
ALTER TABLE pods ADD COLUMN IF NOT EXISTS updated_at timestamptz not null default now();

ALTER TABLE events ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE events ADD COLUMN IF NOT EXISTS ends_at timestamptz;
ALTER TABLE events ADD COLUMN IF NOT EXISTS location_text text;
ALTER TABLE events ADD COLUMN IF NOT EXISTS updated_at timestamptz not null default now();

ALTER TABLE event_attendance ADD COLUMN IF NOT EXISTS eta_minutes integer;
ALTER TABLE event_attendance ADD COLUMN IF NOT EXISTS updated_at timestamptz not null default now();

ALTER TABLE event_checklist_items ADD COLUMN IF NOT EXISTS note text;
ALTER TABLE event_checklist_items ADD COLUMN IF NOT EXISTS updated_at timestamptz not null default now();

ALTER TABLE pod_invites ADD COLUMN IF NOT EXISTS invited_email text;
ALTER TABLE pod_invites ADD COLUMN IF NOT EXISTS invited_user_id uuid;
ALTER TABLE pod_invites ADD COLUMN IF NOT EXISTS status invite_status not null default 'pending';
ALTER TABLE pod_invites ADD COLUMN IF NOT EXISTS token text;
ALTER TABLE pod_invites ADD COLUMN IF NOT EXISTS expires_at timestamptz;
ALTER TABLE pod_invites ADD COLUMN IF NOT EXISTS created_at timestamptz not null default now();

-- 4) Indexes
create index if not exists idx_pod_memberships_pod on pod_memberships(pod_id);
create index if not exists idx_pod_memberships_user on pod_memberships(user_id);
create index if not exists idx_profiles_display_name on profiles(display_name);
create index if not exists idx_events_pod on events(pod_id);
create index if not exists idx_events_starts_at on events(starts_at);
create index if not exists idx_event_attendance_event on event_attendance(event_id);
create index if not exists idx_event_attendance_user on event_attendance(user_id);
create index if not exists idx_checklist_event on event_checklist_items(event_id);
create index if not exists idx_invites_pod on pod_invites(pod_id);

-- 5) Updated-at trigger
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

DO $$ BEGIN
  create trigger pods_set_updated_at before update on pods
  for each row execute procedure set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  create trigger profiles_set_updated_at before update on profiles
  for each row execute procedure set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  create trigger events_set_updated_at before update on events
  for each row execute procedure set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  create trigger checklist_set_updated_at before update on event_checklist_items
  for each row execute procedure set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 6) Row Level Security (RLS)
ALTER TABLE pods ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE pod_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_checklist_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE pod_invites ENABLE ROW LEVEL SECURITY;

-- 7) Policies (drop and recreate to keep updated)
DROP POLICY IF EXISTS pods_read ON pods;
CREATE POLICY pods_read ON pods
FOR SELECT USING (
  created_by = auth.uid()
  OR EXISTS (
    SELECT 1 FROM pod_memberships
    WHERE pod_memberships.pod_id = pods.id
      AND pod_memberships.user_id = auth.uid()
      AND pod_memberships.is_active = true
  )
);

DROP POLICY IF EXISTS pods_insert ON pods;
CREATE POLICY pods_insert ON pods
FOR INSERT WITH CHECK (auth.uid() = created_by);

-- Profiles: pod members can read each other (and themselves)
DROP POLICY IF EXISTS profiles_read ON profiles;
CREATE POLICY profiles_read ON profiles
FOR SELECT USING (
  id = auth.uid()
  OR EXISTS (
    SELECT 1
    FROM pod_memberships self
    JOIN pod_memberships other ON other.pod_id = self.pod_id
    WHERE self.user_id = auth.uid()
      AND self.is_active = true
      AND other.user_id = profiles.id
      AND other.is_active = true
  )
);

DROP POLICY IF EXISTS profiles_insert ON profiles;
CREATE POLICY profiles_insert ON profiles
FOR INSERT WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS profiles_update ON profiles;
CREATE POLICY profiles_update ON profiles
FOR UPDATE USING (auth.uid() = id);

DROP POLICY IF EXISTS pods_update ON pods;
CREATE POLICY pods_update ON pods
FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM pod_memberships
    WHERE pod_memberships.pod_id = pods.id
      AND pod_memberships.user_id = auth.uid()
      AND pod_memberships.role in ('owner','admin')
  )
);

DROP POLICY IF EXISTS memberships_read ON pod_memberships;
CREATE POLICY memberships_read ON pod_memberships
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM pod_memberships m
    WHERE m.pod_id = pod_memberships.pod_id
      AND m.user_id = auth.uid()
      AND m.is_active = true
  )
);

DROP POLICY IF EXISTS memberships_insert ON pod_memberships;
CREATE POLICY memberships_insert ON pod_memberships
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM pod_memberships m
    WHERE m.pod_id = pod_memberships.pod_id
      AND m.user_id = auth.uid()
      AND m.role in ('owner','admin')
  )
);

-- Memberships: invited users can accept into a pod
DROP POLICY IF EXISTS memberships_insert_invited ON pod_memberships;
CREATE POLICY memberships_insert_invited ON pod_memberships
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM pod_invites
    WHERE pod_invites.pod_id = pod_memberships.pod_id
      AND pod_invites.status = 'pending'
      AND (
        pod_invites.invited_user_id = auth.uid()
        OR pod_invites.invited_email = (auth.jwt() ->> 'email')
      )
  )
  AND pod_memberships.user_id = auth.uid()
);

DROP POLICY IF EXISTS events_read ON events;
CREATE POLICY events_read ON events
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM pod_memberships
    WHERE pod_memberships.pod_id = events.pod_id
      AND pod_memberships.user_id = auth.uid()
      AND pod_memberships.is_active = true
  )
);

DROP POLICY IF EXISTS events_insert ON events;
CREATE POLICY events_insert ON events
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM pod_memberships
    WHERE pod_memberships.pod_id = events.pod_id
      AND pod_memberships.user_id = auth.uid()
      AND pod_memberships.is_active = true
  )
);

DROP POLICY IF EXISTS events_update ON events;
CREATE POLICY events_update ON events
FOR UPDATE USING (
  events.created_by = auth.uid()
  OR EXISTS (
    SELECT 1 FROM pod_memberships
    WHERE pod_memberships.pod_id = events.pod_id
      AND pod_memberships.user_id = auth.uid()
      AND pod_memberships.role in ('owner','admin')
  )
);

DROP POLICY IF EXISTS attendance_read ON event_attendance;
CREATE POLICY attendance_read ON event_attendance
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM events
    JOIN pod_memberships ON pod_memberships.pod_id = events.pod_id
    WHERE events.id = event_attendance.event_id
      AND pod_memberships.user_id = auth.uid()
      AND pod_memberships.is_active = true
  )
);

DROP POLICY IF EXISTS attendance_upsert ON event_attendance;
CREATE POLICY attendance_upsert ON event_attendance
FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS attendance_update ON event_attendance;
CREATE POLICY attendance_update ON event_attendance
FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS checklist_read ON event_checklist_items;
CREATE POLICY checklist_read ON event_checklist_items
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM events
    JOIN pod_memberships ON pod_memberships.pod_id = events.pod_id
    WHERE events.id = event_checklist_items.event_id
      AND pod_memberships.user_id = auth.uid()
      AND pod_memberships.is_active = true
  )
);

DROP POLICY IF EXISTS checklist_insert ON event_checklist_items;
CREATE POLICY checklist_insert ON event_checklist_items
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM events
    JOIN pod_memberships ON pod_memberships.pod_id = events.pod_id
    WHERE events.id = event_checklist_items.event_id
      AND pod_memberships.user_id = auth.uid()
      AND pod_memberships.is_active = true
  )
);

DROP POLICY IF EXISTS checklist_update ON event_checklist_items;
CREATE POLICY checklist_update ON event_checklist_items
FOR UPDATE USING (
  event_checklist_items.created_by = auth.uid()
  OR EXISTS (
    SELECT 1 FROM events
    JOIN pod_memberships ON pod_memberships.pod_id = events.pod_id
    WHERE events.id = event_checklist_items.event_id
      AND pod_memberships.user_id = auth.uid()
      AND pod_memberships.role in ('owner','admin')
  )
);

-- Invites: admins/owners can read all; invitees can read their own
DROP POLICY IF EXISTS invites_read ON pod_invites;
CREATE POLICY invites_read ON pod_invites
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM pod_memberships
    WHERE pod_memberships.pod_id = pod_invites.pod_id
      AND pod_memberships.user_id = auth.uid()
      AND pod_memberships.role in ('owner','admin')
  )
  OR pod_invites.invited_user_id = auth.uid()
  OR pod_invites.invited_email = (auth.jwt() ->> 'email')
);

DROP POLICY IF EXISTS invites_insert ON pod_invites;
CREATE POLICY invites_insert ON pod_invites
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM pod_memberships
    WHERE pod_memberships.pod_id = pod_invites.pod_id
      AND pod_memberships.user_id = auth.uid()
      AND pod_memberships.role in ('owner','admin')
  )
);

-- Invites: invitees can mark their invite accepted
DROP POLICY IF EXISTS invites_update ON pod_invites;
CREATE POLICY invites_update ON pod_invites
FOR UPDATE USING (
  pod_invites.invited_user_id = auth.uid()
  OR pod_invites.invited_email = (auth.jwt() ->> 'email')
);

-- Notes:
-- If your JWT claims do not include email, update invite policies to match your auth configuration.

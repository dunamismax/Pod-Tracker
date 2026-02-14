create extension if not exists citext;

create table if not exists users (
  id bigserial primary key,
  email citext not null unique,
  created_at timestamptz not null default now()
);

create table if not exists otp_codes (
  id bigserial primary key,
  email citext not null,
  code_hash text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz
);

create index if not exists otp_codes_email_created_idx on otp_codes (email, created_at desc);
create index if not exists otp_codes_expires_idx on otp_codes (expires_at);

create table if not exists sessions (
  token_hash text primary key,
  user_id bigint not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create index if not exists sessions_user_idx on sessions (user_id);
create index if not exists sessions_expires_idx on sessions (expires_at);

create table if not exists pods (
  id bigserial primary key,
  name text not null,
  description text,
  owner_id bigint not null references users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists pod_members (
  pod_id bigint not null references pods(id) on delete cascade,
  user_id bigint not null references users(id) on delete cascade,
  role text not null check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (pod_id, user_id)
);

create index if not exists pod_members_user_idx on pod_members (user_id);

create table if not exists events (
  id bigserial primary key,
  pod_id bigint not null references pods(id) on delete cascade,
  title text not null,
  description text,
  location text,
  scheduled_for timestamptz not null,
  created_by bigint not null references users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists events_pod_idx on events (pod_id);
create index if not exists events_scheduled_idx on events (scheduled_for);

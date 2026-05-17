create schema if not exists core;

create table core.users (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  display_name text not null,
  password_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint users_email_lowercase check (email = lower(email)),
  constraint users_email_shape check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  constraint users_display_name_not_blank check (length(btrim(display_name)) > 0),
  constraint users_password_hash_not_blank check (length(password_hash) > 0)
);

create unique index users_email_key on core.users (email);

create table core.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references core.users (id) on delete cascade,
  account_type text not null default 'password',
  label text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint accounts_account_type_check check (
    account_type in ('password', 'oauth', 'passkey', 'external')
  ),
  constraint accounts_label_not_blank check (
    label is null or length(btrim(label)) > 0
  )
);

create index accounts_user_id_idx on core.accounts (user_id);

create table core.auth_identities (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references core.accounts (id) on delete cascade,
  provider text not null,
  provider_subject text not null,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_used_at timestamptz,
  constraint auth_identities_provider_not_blank check (length(btrim(provider)) > 0),
  constraint auth_identities_provider_subject_not_blank check (length(btrim(provider_subject)) > 0),
  constraint auth_identities_email_lowercase check (email is null or email = lower(email))
);

create unique index auth_identities_provider_subject_key
on core.auth_identities (provider, provider_subject);

create unique index auth_identities_account_provider_key
on core.auth_identities (account_id, provider);

create table core.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references core.users (id) on delete cascade,
  token_hash bytea not null,
  user_agent text,
  ip_address inet,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  constraint sessions_token_hash_length check (length(token_hash) = 32),
  constraint sessions_expire_after_create check (expires_at > created_at)
);

create unique index sessions_token_hash_key on core.sessions (token_hash);
create index sessions_user_id_idx on core.sessions (user_id);
create index sessions_active_idx on core.sessions (user_id, expires_at)
where revoked_at is null;

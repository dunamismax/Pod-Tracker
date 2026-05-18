-- +goose Up
create table if not exists core.accounts (
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

create index if not exists accounts_user_id_idx on core.accounts (user_id);

create table if not exists core.auth_identities (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references core.accounts (id) on delete cascade,
  provider text not null,
  provider_subject text not null,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_used_at timestamptz,
  constraint auth_identities_provider_not_blank check (length(btrim(provider)) > 0),
  constraint auth_identities_subject_not_blank check (length(btrim(provider_subject)) > 0),
  constraint auth_identities_email_lowercase check (email is null or email = lower(email))
);

create unique index if not exists auth_identities_provider_subject_key
on core.auth_identities (provider, provider_subject);

create index if not exists auth_identities_account_id_idx
on core.auth_identities (account_id);

-- +goose Down
drop table if exists core.auth_identities;
drop table if exists core.accounts;

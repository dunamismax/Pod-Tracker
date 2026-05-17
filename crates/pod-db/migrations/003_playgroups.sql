create table core.playgroups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null,
  description text not null default '',
  created_by uuid references core.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint playgroups_name_not_blank check (length(btrim(name)) > 0),
  constraint playgroups_slug_shape check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$')
);

create unique index playgroups_slug_key on core.playgroups (slug);

create table core.playgroup_memberships (
  id uuid primary key default gen_random_uuid(),
  playgroup_id uuid not null references core.playgroups (id) on delete cascade,
  user_id uuid not null references core.users (id) on delete cascade,
  role text not null,
  display_name text,
  joined_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint playgroup_memberships_role_check check (
    role in ('owner', 'admin', 'member', 'host', 'guest', 'viewer')
  ),
  constraint playgroup_memberships_display_name_not_blank check (
    display_name is null or length(btrim(display_name)) > 0
  )
);

create unique index playgroup_memberships_user_key
on core.playgroup_memberships (playgroup_id, user_id);

create index playgroup_memberships_user_id_idx
on core.playgroup_memberships (user_id);

create table core.playgroup_invites (
  id uuid primary key default gen_random_uuid(),
  playgroup_id uuid not null references core.playgroups (id) on delete cascade,
  token_hash bytea not null,
  role text not null default 'member',
  email text,
  max_uses integer,
  used_count integer not null default 0,
  expires_at timestamptz,
  revoked_at timestamptz,
  created_by uuid references core.users (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint playgroup_invites_token_hash_length check (length(token_hash) = 32),
  constraint playgroup_invites_role_check check (
    role in ('owner', 'admin', 'member', 'host', 'guest', 'viewer')
  ),
  constraint playgroup_invites_email_lowercase check (email is null or email = lower(email)),
  constraint playgroup_invites_max_uses_positive check (max_uses is null or max_uses > 0),
  constraint playgroup_invites_used_count_nonnegative check (used_count >= 0),
  constraint playgroup_invites_used_count_within_limit check (
    max_uses is null or used_count <= max_uses
  )
);

create unique index playgroup_invites_token_hash_key
on core.playgroup_invites (token_hash);

create index playgroup_invites_playgroup_id_idx
on core.playgroup_invites (playgroup_id);

create table core.playgroup_settings (
  playgroup_id uuid primary key references core.playgroups (id) on delete cascade,
  default_event_visibility text not null default 'members',
  allow_guest_rsvps boolean not null default true,
  show_member_decklists boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint playgroup_settings_default_event_visibility_check check (
    default_event_visibility in ('members', 'invite_only', 'public_safe')
  )
);

create table core.house_rules (
  id uuid primary key default gen_random_uuid(),
  playgroup_id uuid not null references core.playgroups (id) on delete cascade,
  title text not null,
  body text not null,
  visible_to_guests boolean not null default false,
  created_by uuid references core.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint house_rules_title_not_blank check (length(btrim(title)) > 0),
  constraint house_rules_body_not_blank check (length(btrim(body)) > 0)
);

create index house_rules_playgroup_id_idx on core.house_rules (playgroup_id);

create table core.decks (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references core.users (id) on delete cascade,
  playgroup_id uuid references core.playgroups (id) on delete set null,
  name text not null,
  commander text not null,
  color_identity text not null default '',
  claimed_bracket text not null default '',
  archetype text not null default '',
  tags text[] not null default '{}',
  visibility text not null default 'private',
  status text not null default 'active',
  game_changers_count integer not null default 0,
  has_infinite_combo boolean not null default false,
  has_fast_mana boolean not null default false,
  tutor_density text not null default 'none',
  has_extra_turns boolean not null default false,
  has_mass_land_denial boolean not null default false,
  salt_notes text not null default '',
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint decks_name_not_blank check (length(btrim(name)) > 0),
  constraint decks_commander_not_blank check (length(btrim(commander)) > 0),
  constraint decks_color_identity_check check (color_identity ~ '^[WUBRG]*$'),
  constraint decks_visibility_check check (visibility in ('private', 'playgroup', 'public')),
  constraint decks_status_check check (status in ('active', 'retired')),
  constraint decks_game_changers_count_nonnegative check (game_changers_count >= 0),
  constraint decks_tutor_density_check check (tutor_density in ('none', 'low', 'medium', 'high')),
  constraint decks_playgroup_visibility_scope check (visibility <> 'playgroup' or playgroup_id is not null)
);

create index decks_owner_user_id_idx on core.decks (owner_user_id);
create index decks_playgroup_id_idx on core.decks (playgroup_id);
create index decks_visibility_idx on core.decks (visibility);
create index decks_name_trgm_idx on core.decks using gin (name gin_trgm_ops);
create index decks_commander_trgm_idx on core.decks using gin (commander gin_trgm_ops);
create index decks_tags_gin_idx on core.decks using gin (tags);

create table core.event_deck_declarations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references core.events (id) on delete cascade,
  user_id uuid not null references core.users (id) on delete cascade,
  deck_id uuid not null references core.decks (id) on delete cascade,
  preference integer not null default 1,
  testing_notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_deck_declarations_preference_check check (preference between 1 and 5)
);

create unique index event_deck_declarations_event_user_deck_key
  on core.event_deck_declarations (event_id, user_id, deck_id);
create index event_deck_declarations_event_id_idx on core.event_deck_declarations (event_id);
create index event_deck_declarations_user_id_idx on core.event_deck_declarations (user_id);

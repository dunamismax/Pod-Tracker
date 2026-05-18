create table mtg.deck_versions (
  id uuid primary key default gen_random_uuid(),
  deck_id uuid not null references core.decks (id) on delete cascade,
  version_number integer not null,
  source_format text not null,
  source_text text not null,
  imported_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint deck_versions_version_number_positive check (version_number > 0),
  constraint deck_versions_source_format_check check (
    source_format in ('plain_text', 'moxfield', 'archidekt')
  ),
  constraint deck_versions_source_text_not_blank check (length(btrim(source_text)) > 0)
);

create unique index deck_versions_deck_version_key
  on mtg.deck_versions (deck_id, version_number);
create index deck_versions_deck_id_idx on mtg.deck_versions (deck_id);

create table mtg.deck_cards (
  id uuid primary key default gen_random_uuid(),
  deck_version_id uuid not null references mtg.deck_versions (id) on delete cascade,
  oracle_id uuid references mtg.cards (oracle_id) on delete set null,
  quantity integer not null,
  card_name text not null,
  matched_name text,
  section text not null,
  match_status text not null,
  match_method text not null default '',
  name_similarity real,
  is_commander boolean not null default false,
  created_at timestamptz not null default now(),
  constraint deck_cards_quantity_positive check (quantity > 0),
  constraint deck_cards_card_name_not_blank check (length(btrim(card_name)) > 0),
  constraint deck_cards_section_check check (
    section in ('commander', 'main', 'sideboard', 'maybeboard')
  ),
  constraint deck_cards_match_status_check check (
    match_status in ('matched', 'unmatched', 'ambiguous')
  ),
  constraint deck_cards_match_method_check check (
    match_method in ('', 'exact', 'normalized', 'fuzzy')
  )
);

create index deck_cards_version_idx on mtg.deck_cards (deck_version_id);
create index deck_cards_oracle_id_idx on mtg.deck_cards (oracle_id) where oracle_id is not null;
create index deck_cards_match_status_idx on mtg.deck_cards (match_status);

create table mtg.commander_bracket_versions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  source_uri text not null default '',
  effective_date date,
  status text not null default 'draft',
  created_at timestamptz not null default now(),
  constraint commander_bracket_versions_name_not_blank check (length(btrim(name)) > 0),
  constraint commander_bracket_versions_status_check check (
    status in ('draft', 'active', 'retired')
  )
);

create unique index commander_bracket_versions_active_key
  on mtg.commander_bracket_versions (status)
  where status = 'active';

create table mtg.game_changer_lists (
  id uuid primary key default gen_random_uuid(),
  bracket_version_id uuid not null references mtg.commander_bracket_versions (id) on delete cascade,
  name text not null,
  source_uri text not null default '',
  created_at timestamptz not null default now(),
  constraint game_changer_lists_name_not_blank check (length(btrim(name)) > 0)
);

create index game_changer_lists_version_idx on mtg.game_changer_lists (bracket_version_id);

create table mtg.game_changer_cards (
  list_id uuid not null references mtg.game_changer_lists (id) on delete cascade,
  oracle_id uuid not null references mtg.cards (oracle_id) on delete cascade,
  card_name text not null,
  created_at timestamptz not null default now(),
  primary key (list_id, oracle_id),
  constraint game_changer_cards_card_name_not_blank check (length(btrim(card_name)) > 0)
);

create index game_changer_cards_oracle_id_idx on mtg.game_changer_cards (oracle_id);

create table mtg.deck_bracket_snapshots (
  id uuid primary key default gen_random_uuid(),
  deck_version_id uuid not null references mtg.deck_versions (id) on delete cascade,
  bracket_version_id uuid references mtg.commander_bracket_versions (id) on delete set null,
  game_changers_count integer not null default 0,
  commander_names text[] not null default '{}',
  color_identity text not null default '',
  warning_codes text[] not null default '{}',
  warnings text[] not null default '{}',
  created_at timestamptz not null default now(),
  constraint deck_bracket_snapshots_game_changers_nonnegative check (game_changers_count >= 0),
  constraint deck_bracket_snapshots_color_identity_check check (color_identity ~ '^[WUBRG]*$')
);

create unique index deck_bracket_snapshots_version_key
  on mtg.deck_bracket_snapshots (deck_version_id);
create index deck_bracket_snapshots_bracket_version_idx
  on mtg.deck_bracket_snapshots (bracket_version_id);

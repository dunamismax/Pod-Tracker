create schema if not exists mtg;
create schema if not exists search;

create table mtg.scryfall_imports (
  id uuid primary key default gen_random_uuid(),
  bulk_type text not null,
  source_uri text not null,
  download_uri text not null,
  source_updated_at timestamptz not null,
  content_type text not null default 'application/json',
  content_encoding text,
  size_bytes bigint,
  status text not null default 'pending',
  cards_seen integer not null default 0,
  cards_imported integer not null default 0,
  error_message text,
  started_at timestamptz,
  finished_at timestamptz,
  raw_metadata jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scryfall_imports_bulk_type_not_blank check (length(btrim(bulk_type)) > 0),
  constraint scryfall_imports_source_uri_not_blank check (length(btrim(source_uri)) > 0),
  constraint scryfall_imports_download_uri_not_blank check (length(btrim(download_uri)) > 0),
  constraint scryfall_imports_status_check check (
    status in ('pending', 'running', 'succeeded', 'failed')
  ),
  constraint scryfall_imports_cards_seen_nonnegative check (cards_seen >= 0),
  constraint scryfall_imports_cards_imported_nonnegative check (cards_imported >= 0),
  constraint scryfall_imports_size_bytes_positive check (size_bytes is null or size_bytes > 0)
);

create unique index scryfall_imports_bulk_version_key
  on mtg.scryfall_imports (bulk_type, source_updated_at);
create index scryfall_imports_status_idx
  on mtg.scryfall_imports (status, source_updated_at desc);

create table mtg.cards (
  oracle_id uuid primary key,
  name text not null,
  mana_cost text not null default '',
  mana_value double precision,
  type_line text not null default '',
  oracle_text text not null default '',
  colors text[] not null default '{}',
  color_identity text[] not null default '{}',
  layout text not null default '',
  reserved boolean not null default false,
  keywords text[] not null default '{}',
  edhrec_rank integer,
  legal_commander boolean not null default false,
  game_changer boolean not null default false,
  last_import_id uuid references mtg.scryfall_imports (id) on delete set null,
  raw_payload jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cards_name_not_blank check (length(btrim(name)) > 0),
  constraint cards_colors_check check (colors <@ array['W', 'U', 'B', 'R', 'G']::text[]),
  constraint cards_color_identity_check check (
    color_identity <@ array['W', 'U', 'B', 'R', 'G']::text[]
  )
);

create index cards_name_trgm_idx on mtg.cards using gin (name gin_trgm_ops);
create index cards_color_identity_gin_idx on mtg.cards using gin (color_identity);
create index cards_commander_legal_idx on mtg.cards (legal_commander);
create index cards_game_changer_idx on mtg.cards (game_changer) where game_changer;

create table mtg.card_printings (
  scryfall_id uuid primary key,
  oracle_id uuid not null references mtg.cards (oracle_id) on delete cascade,
  set_code text not null,
  collector_number text not null,
  lang text not null default 'en',
  rarity text not null default '',
  released_at date,
  artist text,
  prices jsonb not null default '{}'::jsonb,
  import_id uuid references mtg.scryfall_imports (id) on delete set null,
  raw_payload jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint card_printings_set_code_not_blank check (length(btrim(set_code)) > 0),
  constraint card_printings_collector_number_not_blank check (
    length(btrim(collector_number)) > 0
  )
);

create index card_printings_oracle_id_idx on mtg.card_printings (oracle_id);
create index card_printings_set_collector_idx
  on mtg.card_printings (set_code, collector_number);
create index card_printings_import_id_idx on mtg.card_printings (import_id);

create table mtg.card_faces (
  scryfall_id uuid not null references mtg.card_printings (scryfall_id) on delete cascade,
  face_index integer not null,
  oracle_id uuid not null references mtg.cards (oracle_id) on delete cascade,
  name text not null,
  mana_cost text not null default '',
  type_line text not null default '',
  oracle_text text not null default '',
  colors text[] not null default '{}',
  primary key (scryfall_id, face_index),
  constraint card_faces_face_index_nonnegative check (face_index >= 0),
  constraint card_faces_name_not_blank check (length(btrim(name)) > 0),
  constraint card_faces_colors_check check (colors <@ array['W', 'U', 'B', 'R', 'G']::text[])
);

create index card_faces_oracle_id_idx on mtg.card_faces (oracle_id);
create index card_faces_name_trgm_idx on mtg.card_faces using gin (name gin_trgm_ops);

create table mtg.card_legalities (
  scryfall_id uuid not null references mtg.card_printings (scryfall_id) on delete cascade,
  format text not null,
  status text not null,
  primary key (scryfall_id, format),
  constraint card_legalities_format_not_blank check (length(btrim(format)) > 0),
  constraint card_legalities_status_check check (
    status in ('legal', 'not_legal', 'banned', 'restricted')
  )
);

create index card_legalities_format_status_idx on mtg.card_legalities (format, status);

create table search.card_documents (
  scryfall_id uuid primary key references mtg.card_printings (scryfall_id) on delete cascade,
  oracle_id uuid not null references mtg.cards (oracle_id) on delete cascade,
  name text not null,
  normalized_name text not null,
  type_line text not null default '',
  oracle_text text not null default '',
  color_identity text[] not null default '{}',
  commander_legal boolean not null default false,
  mana_value double precision,
  usd double precision,
  eur double precision,
  tix double precision,
  game_changer boolean not null default false,
  document tsvector not null,
  updated_at timestamptz not null default now(),
  constraint card_documents_name_not_blank check (length(btrim(name)) > 0),
  constraint card_documents_color_identity_check check (
    color_identity <@ array['W', 'U', 'B', 'R', 'G']::text[]
  )
);

create index card_documents_document_gin_idx on search.card_documents using gin (document);
create index card_documents_name_trgm_idx on search.card_documents using gin (name gin_trgm_ops);
create index card_documents_normalized_name_trgm_idx
  on search.card_documents using gin (normalized_name gin_trgm_ops);
create index card_documents_color_identity_gin_idx
  on search.card_documents using gin (color_identity);
create index card_documents_commander_legal_idx on search.card_documents (commander_legal);
create index card_documents_mana_value_idx on search.card_documents (mana_value);
create index card_documents_usd_idx on search.card_documents (usd);
create index card_documents_game_changer_idx
  on search.card_documents (game_changer) where game_changer;

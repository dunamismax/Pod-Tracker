create table core.collections (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references core.users (id) on delete cascade,
  playgroup_id uuid references core.playgroups (id) on delete set null,
  name text not null,
  visibility text not null default 'private',
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint collections_name_not_blank check (length(btrim(name)) > 0),
  constraint collections_visibility_check check (visibility in ('private', 'playgroup', 'public')),
  constraint collections_playgroup_visibility_scope check (
    visibility <> 'playgroup' or playgroup_id is not null
  )
);

create index collections_owner_user_id_idx on core.collections (owner_user_id);
create index collections_playgroup_id_idx on core.collections (playgroup_id);
create index collections_visibility_idx on core.collections (visibility);

create table core.collection_cards (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references core.collections (id) on delete cascade,
  oracle_id uuid not null references mtg.cards (oracle_id) on delete cascade,
  scryfall_id uuid references mtg.card_printings (scryfall_id) on delete set null,
  card_name text not null,
  quantity integer not null,
  foil boolean not null default false,
  condition text not null default 'unknown',
  location text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint collection_cards_card_name_not_blank check (length(btrim(card_name)) > 0),
  constraint collection_cards_quantity_positive check (quantity > 0),
  constraint collection_cards_condition_check check (
    condition in (
      'mint',
      'near_mint',
      'lightly_played',
      'moderately_played',
      'heavily_played',
      'damaged',
      'unknown'
    )
  ),
  constraint collection_cards_location_reasonable check (length(location) <= 500)
);

create index collection_cards_collection_id_idx on core.collection_cards (collection_id);
create index collection_cards_oracle_id_idx on core.collection_cards (oracle_id);
create index collection_cards_scryfall_id_idx
  on core.collection_cards (scryfall_id)
  where scryfall_id is not null;
create index collection_cards_location_trgm_idx
  on core.collection_cards using gin (location gin_trgm_ops);
create unique index collection_cards_unique_printing_idx
  on core.collection_cards (
    collection_id,
    oracle_id,
    coalesce(scryfall_id, '00000000-0000-0000-0000-000000000000'::uuid),
    foil,
    condition,
    location
  );

create table core.wishlists (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references core.users (id) on delete cascade,
  playgroup_id uuid references core.playgroups (id) on delete set null,
  name text not null,
  visibility text not null default 'private',
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wishlists_name_not_blank check (length(btrim(name)) > 0),
  constraint wishlists_visibility_check check (visibility in ('private', 'playgroup', 'public')),
  constraint wishlists_playgroup_visibility_scope check (
    visibility <> 'playgroup' or playgroup_id is not null
  )
);

create index wishlists_owner_user_id_idx on core.wishlists (owner_user_id);
create index wishlists_playgroup_id_idx on core.wishlists (playgroup_id);
create index wishlists_visibility_idx on core.wishlists (visibility);

create table core.wishlist_cards (
  id uuid primary key default gen_random_uuid(),
  wishlist_id uuid not null references core.wishlists (id) on delete cascade,
  oracle_id uuid not null references mtg.cards (oracle_id) on delete cascade,
  card_name text not null,
  desired_quantity integer not null default 1,
  priority text not null default 'medium',
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wishlist_cards_card_name_not_blank check (length(btrim(card_name)) > 0),
  constraint wishlist_cards_desired_quantity_positive check (desired_quantity > 0),
  constraint wishlist_cards_priority_check check (priority in ('low', 'medium', 'high'))
);

create unique index wishlist_cards_wishlist_oracle_key
  on core.wishlist_cards (wishlist_id, oracle_id);
create index wishlist_cards_wishlist_id_idx on core.wishlist_cards (wishlist_id);
create index wishlist_cards_oracle_id_idx on core.wishlist_cards (oracle_id);

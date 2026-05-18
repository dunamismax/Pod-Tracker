create table core.pods (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references core.events (id) on delete cascade,
  name text not null,
  state text not null default 'proposed',
  position integer not null,
  size_fit_score integer not null default 0,
  bracket_compatibility_score integer not null default 0,
  repeat_player_pair_penalty integer not null default 0,
  repeat_deck_matchup_penalty integer not null default 0,
  guest_placement_score integer not null default 0,
  availability_window_score integer not null default 0,
  total_score integer not null default 0,
  scoring_details jsonb not null default '{}'::jsonb,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pods_name_not_blank check (length(btrim(name)) > 0),
  constraint pods_position_positive check (position > 0),
  constraint pods_state_check check (state in ('proposed', 'locked', 'active', 'completed', 'cancelled'))
);

create unique index pods_event_position_key on core.pods (event_id, position);
create index pods_event_id_idx on core.pods (event_id);
create index pods_state_idx on core.pods (state);

create table core.pod_seats (
  id uuid primary key default gen_random_uuid(),
  pod_id uuid not null references core.pods (id) on delete cascade,
  event_id uuid not null references core.events (id) on delete cascade,
  rsvp_id uuid not null references core.event_rsvps (id) on delete cascade,
  user_id uuid references core.users (id) on delete cascade,
  guest_name text,
  deck_declaration_id uuid references core.event_deck_declarations (id) on delete set null,
  deck_id uuid references core.decks (id) on delete set null,
  seat_position integer not null,
  locked boolean not null default false,
  arrival_time timestamptz,
  leaving_time timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pod_seats_position_positive check (seat_position > 0),
  constraint pod_seats_user_or_guest_name check (
    (user_id is not null and guest_name is null) or
    (user_id is null and guest_name is not null and length(btrim(guest_name)) > 0)
  )
);

create unique index pod_seats_pod_position_key on core.pod_seats (pod_id, seat_position);
create unique index pod_seats_event_rsvp_key on core.pod_seats (event_id, rsvp_id);
create index pod_seats_event_id_idx on core.pod_seats (event_id);
create index pod_seats_user_id_idx on core.pod_seats (user_id) where user_id is not null;
create index pod_seats_deck_id_idx on core.pod_seats (deck_id) where deck_id is not null;

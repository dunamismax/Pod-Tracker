create schema if not exists meta;

alter table core.events
  add column completed_at timestamptz;

create table core.games (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references core.events (id) on delete cascade,
  pod_id uuid references core.pods (id) on delete set null,
  logged_by_user_id uuid references core.users (id) on delete set null,
  result_type text not null,
  turn_count integer,
  duration_minutes integer,
  first_player_user_id uuid references core.users (id) on delete set null,
  tags text[] not null default '{}',
  notes text not null default '',
  completed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint games_result_type_check check (
    result_type in (
      'normal_win',
      'combo_win',
      'combat_win',
      'concession',
      'draw',
      'time_called',
      'unfinished',
      'archenemy_win',
      'team_win'
    )
  ),
  constraint games_turn_count_positive check (turn_count is null or turn_count > 0),
  constraint games_duration_minutes_positive check (
    duration_minutes is null or duration_minutes > 0
  )
);

create index games_event_id_idx on core.games (event_id, completed_at desc);
create index games_pod_id_idx on core.games (pod_id) where pod_id is not null;
create index games_result_type_idx on core.games (result_type);
create index games_tags_gin_idx on core.games using gin (tags);

create table core.game_players (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references core.games (id) on delete cascade,
  pod_seat_id uuid references core.pod_seats (id) on delete set null,
  user_id uuid references core.users (id) on delete set null,
  guest_name text,
  deck_id uuid references core.decks (id) on delete set null,
  seat_position integer not null,
  finish_position integer,
  elimination_order integer,
  eliminated_turn integer,
  is_winner boolean not null default false,
  team text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint game_players_seat_position_positive check (seat_position > 0),
  constraint game_players_finish_position_positive check (
    finish_position is null or finish_position > 0
  ),
  constraint game_players_elimination_order_positive check (
    elimination_order is null or elimination_order > 0
  ),
  constraint game_players_eliminated_turn_positive check (
    eliminated_turn is null or eliminated_turn > 0
  ),
  constraint game_players_user_or_guest_name check (
    (user_id is not null and guest_name is null) or
    (user_id is null and guest_name is not null and length(btrim(guest_name)) > 0)
  )
);

create unique index game_players_game_seat_key on core.game_players (game_id, seat_position);
create index game_players_user_id_idx on core.game_players (user_id) where user_id is not null;
create index game_players_deck_id_idx on core.game_players (deck_id) where deck_id is not null;

create table core.game_results (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references core.games (id) on delete cascade,
  result_type text not null,
  winner_user_id uuid references core.users (id) on delete set null,
  winning_deck_id uuid references core.decks (id) on delete set null,
  winning_team text,
  notes text not null default '',
  created_at timestamptz not null default now(),
  constraint game_results_result_type_check check (
    result_type in (
      'normal_win',
      'combo_win',
      'combat_win',
      'concession',
      'draw',
      'time_called',
      'unfinished',
      'archenemy_win',
      'team_win'
    )
  )
);

create unique index game_results_game_id_key on core.game_results (game_id);
create index game_results_winner_user_id_idx on core.game_results (winner_user_id)
  where winner_user_id is not null;
create index game_results_winning_deck_id_idx on core.game_results (winning_deck_id)
  where winning_deck_id is not null;

create table core.game_notes (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references core.games (id) on delete cascade,
  author_user_id uuid references core.users (id) on delete set null,
  note_text text not null,
  created_at timestamptz not null default now(),
  constraint game_notes_text_not_blank check (length(btrim(note_text)) > 0)
);

create index game_notes_game_id_idx on core.game_notes (game_id, created_at);

create table meta.matchup_history (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references core.games (id) on delete cascade,
  event_id uuid not null references core.events (id) on delete cascade,
  playgroup_id uuid not null references core.playgroups (id) on delete cascade,
  left_user_id uuid references core.users (id) on delete set null,
  right_user_id uuid references core.users (id) on delete set null,
  left_deck_id uuid references core.decks (id) on delete set null,
  right_deck_id uuid references core.decks (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint matchup_history_has_pair check (
    (left_user_id is not null and right_user_id is not null) or
    (left_deck_id is not null and right_deck_id is not null)
  )
);

create unique index matchup_history_game_user_pair_key
  on meta.matchup_history (game_id, left_user_id, right_user_id)
  where left_user_id is not null and right_user_id is not null;
create unique index matchup_history_game_deck_pair_key
  on meta.matchup_history (game_id, left_deck_id, right_deck_id)
  where left_deck_id is not null and right_deck_id is not null;
create index matchup_history_playgroup_event_idx on meta.matchup_history (playgroup_id, event_id);
create index matchup_history_user_pair_idx on meta.matchup_history (left_user_id, right_user_id)
  where left_user_id is not null and right_user_id is not null;
create index matchup_history_deck_pair_idx on meta.matchup_history (left_deck_id, right_deck_id)
  where left_deck_id is not null and right_deck_id is not null;

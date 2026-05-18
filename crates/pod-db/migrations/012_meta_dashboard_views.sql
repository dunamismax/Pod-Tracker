create materialized view meta.attendance_summary as
select
  pg.id as playgroup_id,
  pg.name as playgroup_name,
  count(distinct e.id)::int as events_total,
  count(distinct e.id) filter (where e.completed_at is not null)::int as completed_events,
  count(r.id) filter (where r.status = 'yes')::int as confirmed_rsvps,
  count(distinct r.user_id) filter (
    where r.status = 'yes' and r.user_id is not null
  )::int as active_players,
  coalesce(
    (
      count(r.id) filter (where r.status = 'yes') * 100
      / nullif(count(r.id), 0)
    )::int,
    0
  ) as attendance_rate,
  max(e.start_time) as last_event_at
from core.playgroups pg
left join core.events e on e.playgroup_id = pg.id
left join core.event_rsvps r on r.event_id = e.id
group by pg.id, pg.name;

create unique index attendance_summary_playgroup_id_key
  on meta.attendance_summary (playgroup_id);

create materialized view meta.deck_win_rates as
select
  e.playgroup_id,
  gp.deck_id,
  d.name as deck_name,
  d.commander,
  count(distinct gp.game_id)::int as games_played,
  count(distinct gp.game_id) filter (where gp.is_winner)::int as wins,
  coalesce(
    (
      count(distinct gp.game_id) filter (where gp.is_winner) * 100
      / nullif(count(distinct gp.game_id), 0)
    )::int,
    0
  ) as win_rate
from core.game_players gp
join core.games g on g.id = gp.game_id
join core.events e on e.id = g.event_id
join core.decks d on d.id = gp.deck_id
where gp.deck_id is not null
group by e.playgroup_id, gp.deck_id, d.name, d.commander;

create unique index deck_win_rates_playgroup_deck_key
  on meta.deck_win_rates (playgroup_id, deck_id);

create materialized view meta.player_win_rates as
select
  e.playgroup_id,
  gp.user_id,
  u.display_name,
  count(distinct gp.game_id)::int as games_played,
  count(distinct gp.game_id) filter (where gp.is_winner)::int as wins,
  coalesce(
    (
      count(distinct gp.game_id) filter (where gp.is_winner) * 100
      / nullif(count(distinct gp.game_id), 0)
    )::int,
    0
  ) as win_rate
from core.game_players gp
join core.games g on g.id = gp.game_id
join core.events e on e.id = g.event_id
join core.users u on u.id = gp.user_id
where gp.user_id is not null
group by e.playgroup_id, gp.user_id, u.display_name;

create unique index player_win_rates_playgroup_user_key
  on meta.player_win_rates (playgroup_id, user_id);

create materialized view meta.commander_popularity as
with deck_games as (
  select
    e.playgroup_id,
    gp.deck_id,
    count(distinct gp.game_id)::int as games_seen,
    max(g.completed_at) as last_seen_at
  from core.game_players gp
  join core.games g on g.id = gp.game_id
  join core.events e on e.id = g.event_id
  where gp.deck_id is not null
  group by e.playgroup_id, gp.deck_id
)
select
  d.playgroup_id,
  d.commander,
  count(d.id)::int as deck_count,
  coalesce(sum(dg.games_seen), 0)::int as games_seen,
  max(coalesce(dg.last_seen_at, d.updated_at)) as last_seen_at
from core.decks d
left join deck_games dg
  on dg.playgroup_id = d.playgroup_id and dg.deck_id = d.id
where d.playgroup_id is not null
  and d.status = 'active'
group by d.playgroup_id, d.commander;

create unique index commander_popularity_playgroup_commander_key
  on meta.commander_popularity (playgroup_id, commander);

create materialized view meta.bracket_distribution as
select
  d.playgroup_id,
  coalesce(nullif(btrim(d.claimed_bracket), ''), 'Unspecified') as claimed_bracket,
  count(*)::int as deck_count
from core.decks d
where d.playgroup_id is not null
  and d.status = 'active'
group by d.playgroup_id, coalesce(nullif(btrim(d.claimed_bracket), ''), 'Unspecified');

create unique index bracket_distribution_playgroup_bracket_key
  on meta.bracket_distribution (playgroup_id, claimed_bracket);

create materialized view meta.color_identity_distribution as
select
  d.playgroup_id,
  case when d.color_identity = '' then 'Colorless' else d.color_identity end as color_identity,
  count(*)::int as deck_count
from core.decks d
where d.playgroup_id is not null
  and d.status = 'active'
group by d.playgroup_id, case when d.color_identity = '' then 'Colorless' else d.color_identity end;

create unique index color_identity_distribution_playgroup_color_key
  on meta.color_identity_distribution (playgroup_id, color_identity);

create materialized view meta.archetype_distribution as
select
  d.playgroup_id,
  coalesce(nullif(btrim(d.archetype), ''), 'Unspecified') as archetype,
  count(*)::int as deck_count
from core.decks d
where d.playgroup_id is not null
  and d.status = 'active'
group by d.playgroup_id, coalesce(nullif(btrim(d.archetype), ''), 'Unspecified');

create unique index archetype_distribution_playgroup_archetype_key
  on meta.archetype_distribution (playgroup_id, archetype);

create materialized view meta.matchup_summary as
select
  mh.playgroup_id,
  'players'::text as matchup_type,
  mh.left_user_id,
  left_user.display_name as left_label,
  mh.right_user_id,
  right_user.display_name as right_label,
  null::uuid as left_deck_id,
  null::uuid as right_deck_id,
  count(*)::int as games_together,
  max(g.completed_at) as last_played_at
from meta.matchup_history mh
join core.games g on g.id = mh.game_id
join core.users left_user on left_user.id = mh.left_user_id
join core.users right_user on right_user.id = mh.right_user_id
where mh.left_user_id is not null and mh.right_user_id is not null
group by
  mh.playgroup_id,
  mh.left_user_id,
  left_user.display_name,
  mh.right_user_id,
  right_user.display_name
union all
select
  mh.playgroup_id,
  'decks'::text as matchup_type,
  null::uuid as left_user_id,
  left_deck.name as left_label,
  null::uuid as right_user_id,
  right_deck.name as right_label,
  mh.left_deck_id,
  mh.right_deck_id,
  count(*)::int as games_together,
  max(g.completed_at) as last_played_at
from meta.matchup_history mh
join core.games g on g.id = mh.game_id
join core.decks left_deck on left_deck.id = mh.left_deck_id
join core.decks right_deck on right_deck.id = mh.right_deck_id
where mh.left_deck_id is not null and mh.right_deck_id is not null
group by
  mh.playgroup_id,
  mh.left_deck_id,
  left_deck.name,
  mh.right_deck_id,
  right_deck.name;

create index matchup_summary_playgroup_type_idx
  on meta.matchup_summary (playgroup_id, matchup_type, games_together desc);

create materialized view meta.stale_decks as
with deck_last_played as (
  select
    e.playgroup_id,
    gp.deck_id,
    max(g.completed_at) as last_played_at
  from core.game_players gp
  join core.games g on g.id = gp.game_id
  join core.events e on e.id = g.event_id
  where gp.deck_id is not null
  group by e.playgroup_id, gp.deck_id
)
select
  d.playgroup_id,
  d.id as deck_id,
  d.name as deck_name,
  d.commander,
  d.updated_at as deck_updated_at,
  dlp.last_played_at,
  case
    when dlp.last_played_at is null then 'never_played'
    else 'idle_45_days'
  end as stale_reason
from core.decks d
left join deck_last_played dlp
  on dlp.playgroup_id = d.playgroup_id and dlp.deck_id = d.id
where d.playgroup_id is not null
  and d.status = 'active'
  and (
    dlp.last_played_at is null
    or dlp.last_played_at < now() - interval '45 days'
  );

create unique index stale_decks_playgroup_deck_key
  on meta.stale_decks (playgroup_id, deck_id);

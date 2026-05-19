#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ObservatoryEntry {
    pub slug: &'static str,
    pub title: &'static str,
    pub badge: &'static str,
    pub source: &'static str,
    pub sql: &'static str,
    pub inputs: &'static str,
    pub indexes: &'static str,
    pub plan_shape: &'static str,
    pub output: &'static str,
    pub sample_data: &'static str,
}

pub fn observatory_entries() -> &'static [ObservatoryEntry] {
    ENTRIES
}

const ENTRIES: &[ObservatoryEntry] = &[
    ObservatoryEntry {
        slug: "pod-generation",
        title: "Pod generation candidates",
        badge: "candidate SQL",
        source: "PodRepository::generate_candidate_pods",
        sql: r#"select r.id as rsvp_id,
  r.user_id,
  r.guest_name,
  dec.id as deck_declaration_id,
  dec.deck_id,
  d.claimed_bracket,
  d.commander,
  d.color_identity,
  d.archetype,
  r.arrival_time,
  r.leaving_time
from core.event_rsvps r
left join lateral (
  select ed.id, ed.deck_id
  from core.event_deck_declarations ed
  where ed.event_id = r.event_id
    and ed.user_id = r.user_id
  order by ed.preference asc, ed.created_at asc
  limit 1
) dec on true
left join core.decks d on d.id = dec.deck_id
where r.event_id = $1
  and r.status = 'yes'
  and not exists (
    select 1
    from core.pod_seats existing
    where existing.event_id = r.event_id
      and existing.rsvp_id = r.id
  )
order by coalesce(r.arrival_time, r.created_at), r.created_at;"#,
        inputs: "event_id for the event being seated; target pod size is applied in Rust after this candidate set.",
        indexes: "event_rsvps_event_id_idx, event_deck_declarations_event_id_idx, pod_seats_event_rsvp_key, decks primary key.",
        plan_shape: "Index-scope RSVPs by event, lateral-pick each player's preferred deck declaration, anti-join already-seated RSVPs, then sort by availability.",
        output: "Candidate attendee rows with optional user, guest name, deck declaration, deck id, bracket, commander, color identity, archetype, arrival time, and leaving time.",
        sample_data: "Scrubbed fixture: event_id=00000000-0000-7000-8000-000000000013; players Ada, Ben, Cy, Dee; guest label Guest A; no addresses or contact fields.",
    },
    ObservatoryEntry {
        slug: "avoid-repeat-pairing",
        title: "Avoid-repeat and freshness pairing",
        badge: "scoring SQL",
        source: "PodRepository::repeat_player_pair_penalty and repeat_deck_matchup_penalty",
        sql: r#"-- prior player pairings in the same playgroup
with current_event as (
  select playgroup_id, start_time
  from core.events
  where id = $1
),
prior_pairings as (
  select prior_events.start_time
  from core.pod_seats a
  join core.pod_seats b on b.pod_id = a.pod_id and b.user_id = $3
  join core.pods prior_pods on prior_pods.id = a.pod_id
  join core.events prior_events on prior_events.id = prior_pods.event_id
  join current_event current_events on true
  where a.user_id = $2
    and prior_pods.event_id <> $1
    and prior_pods.state in ('locked', 'active', 'completed')
    and prior_events.playgroup_id = current_events.playgroup_id
    and prior_events.start_time < current_events.start_time
)
select count(*)::int as repeat_count,
  extract(day from ((select start_time from current_event) - max(start_time)))::int
    as days_since_last
from prior_pairings;

-- prior deck matchups in the same playgroup
with current_event as (
  select playgroup_id, start_time
  from core.events
  where id = $1
),
prior_matchups as (
  select prior_events.start_time
  from core.pod_seats a
  join core.pod_seats b on b.pod_id = a.pod_id and b.deck_id = $3
  join core.pods prior_pods on prior_pods.id = a.pod_id
  join core.events prior_events on prior_events.id = prior_pods.event_id
  join current_event current_events on true
  where a.deck_id = $2
    and prior_pods.event_id <> $1
    and prior_pods.state in ('locked', 'active', 'completed')
    and prior_events.playgroup_id = current_events.playgroup_id
    and prior_events.start_time < current_events.start_time
)
select count(*)::int as repeat_count,
  extract(day from ((select start_time from current_event) - max(start_time)))::int
    as days_since_last
from prior_matchups;"#,
        inputs: "current event_id plus each candidate user pair or deck pair being scored.",
        indexes: "pod_seats_user_id_idx, pod_seats_deck_id_idx, pods_event_id_idx, pods_state_idx, events primary key.",
        plan_shape: "Probe prior pod seats by user or deck, join to historical pods and events, constrain history to the current playgroup, and keep the latest prior event date for recency weighting.",
        output: "Repeat counts plus days since the latest matchup. Counts produce repeat penalties; recent pairs add freshness penalties before the pod optimizer accepts a swap.",
        sample_data: "Scrubbed fixture: Ada and Ben played together 10 days ago; Atraxa and Yuriko faced each other twice; names are demo labels only.",
    },
    ObservatoryEntry {
        slug: "bracket-compatibility",
        title: "Bracket compatibility",
        badge: "pod score input",
        source: "PodRepository::generate_candidate_pods with pod_core::pods::bracket_compatibility_score",
        sql: r#"select r.id as rsvp_id,
  dec.deck_id,
  d.claimed_bracket
from core.event_rsvps r
left join lateral (
  select ed.deck_id
  from core.event_deck_declarations ed
  where ed.event_id = r.event_id
    and ed.user_id = r.user_id
  order by ed.preference asc, ed.created_at asc
  limit 1
) dec on true
left join core.decks d on d.id = dec.deck_id
where r.event_id = $1
  and r.status = 'yes'
order by d.claimed_bracket nulls last, r.created_at;"#,
        inputs: "event_id for confirmed RSVPs; deck declarations provide optional claimed bracket labels.",
        indexes: "event_rsvps_event_id_idx, event_deck_declarations_event_id_idx, decks primary key.",
        plan_shape: "Fetch declared deck brackets alongside attendees, then score the bracket spread in Rust: spread 0-1 gets 20, spread 2 gets 12, spread 3 gets 4, wider gets 0.",
        output: "Per-attendee bracket inputs used in the stored pod score and scoring_details JSONB.",
        sample_data: "Scrubbed fixture: brackets 2, 2, 3, 3 produce a high-compatibility pod; bracket labels are deck metadata, not private notes.",
    },
    ObservatoryEntry {
        slug: "fuzzy-card-search",
        title: "Fuzzy card search",
        badge: "full-text + trigram",
        source: "ScryfallRepository::search_cards",
        sql: r#"select scryfall_id, oracle_id, name, type_line, oracle_text,
  color_identity, commander_legal, mana_value, usd, game_changer,
  case
    when $1::text is null then 0::real
    else ts_rank_cd(document, websearch_to_tsquery('english', $1))::real
  end as text_rank,
  case
    when $1::text is null then 0::real
    else greatest(
      similarity(name, $1),
      similarity(normalized_name, regexp_replace(lower($1), '[^a-z0-9]+', '', 'g'))
    )::real
  end as name_similarity
from search.card_documents
where (
    $1::text is null
    or document @@ websearch_to_tsquery('english', $1)
    or name % $1
    or normalized_name % regexp_replace(lower($1), '[^a-z0-9]+', '', 'g')
  )
  and ($2::text[] is null or color_identity <@ $2)
  and ($3::boolean is null or commander_legal = $3)
  and ($4::double precision is null or mana_value >= $4)
  and ($5::double precision is null or mana_value <= $5)
  and ($6::double precision is null or usd <= $6)
  and ($7::boolean is null or game_changer = $7)
  and ($8::text is null or type_line ilike '%' || $8 || '%')
order by 11 desc, 12 desc, name asc
limit $9;"#,
        inputs: "query text, optional color identity, commander legality, mana value range, price ceiling, Game Changer flag, type filter, and limit.",
        indexes: "card_documents_document_gin_idx, card_documents_name_trgm_idx, card_documents_normalized_name_trgm_idx, card_documents_color_identity_gin_idx.",
        plan_shape: "Combine full-text and trigram candidate retrieval, apply metadata filters, then rank by text relevance, name similarity, and stable name order.",
        output: "Local Scryfall card rows with legality, mana value, price, Game Changer flag, text rank, and name similarity.",
        sample_data: "Scrubbed fixture: query='atraxa preator'; colors={W,U,B,G}; commander_legal=true; max_usd=50; returns local imported card rows.",
    },
    ObservatoryEntry {
        slug: "game-changers-count",
        title: "Game Changers count",
        badge: "deck snapshot",
        source: "DeckRepository::import_plain_text_decklist",
        sql: r#"select coalesce(sum(dc.quantity), 0)::int as count
from mtg.deck_cards dc
join mtg.cards c on c.oracle_id = dc.oracle_id
where dc.deck_version_id = $1
  and dc.match_status = 'matched'
  and (
    c.game_changer
    or exists (
      select 1
      from mtg.game_changer_lists gcl
      join mtg.game_changer_cards gcc on gcc.list_id = gcl.id
      where gcl.bracket_version_id = $2
        and gcc.oracle_id = dc.oracle_id
    )
  );"#,
        inputs: "deck_version_id and the active commander_bracket_version id.",
        indexes: "deck_cards_version_idx, deck_cards_oracle_id_idx, cards primary key, game_changer_lists_version_idx, game_changer_cards_oracle_id_idx.",
        plan_shape: "Scan matched cards for one deck version, join normalized Scryfall card rows, and check both imported card flags and the versioned Game Changers list.",
        output: "Integer count stored in mtg.deck_bracket_snapshots with warning codes for bracket review.",
        sample_data: "Scrubbed fixture: a 100-card import with one matched Game Changer writes game_changers_count=1 to the latest bracket snapshot.",
    },
    ObservatoryEntry {
        slug: "similar-deck-recommendations",
        title: "Similar deck recommendations",
        badge: "SQL + heuristic",
        source: "DeckRepository::similar_deck_recommendations",
        sql: r#"with source as (
  select d.id, d.tags
  from core.decks d
  left join core.playgroup_memberships source_membership
    on source_membership.playgroup_id = d.playgroup_id
   and source_membership.user_id = $2
  where d.id = $1
    and (
      d.owner_user_id = $2
      or d.visibility = 'public'
      or (d.visibility = 'playgroup' and source_membership.user_id is not null)
    )
),
source_version as (
  select v.id
  from mtg.deck_versions v
  join source s on s.id = v.deck_id
  order by v.version_number desc
  limit 1
),
source_cards as (
  select dc.oracle_id
  from mtg.deck_cards dc
  join source_version sv on sv.id = dc.deck_version_id
  where dc.match_status = 'matched'
    and dc.oracle_id is not null
  group by dc.oracle_id
),
visible_candidates as (
  select distinct d.id, d.name, d.commander, d.color_identity,
    d.claimed_bracket, d.archetype, d.tags, d.updated_at
  from core.decks d
  join source s on true
  left join core.playgroup_memberships m
    on m.playgroup_id = d.playgroup_id
   and m.user_id = $2
  where d.id <> s.id
    and d.status = 'active'
    and (
      d.owner_user_id = $2
      or d.visibility = 'public'
      or (d.visibility = 'playgroup' and m.user_id is not null)
    )
),
candidate_versions as (
  select distinct on (v.deck_id) v.deck_id, v.id
  from mtg.deck_versions v
  join visible_candidates c on c.id = v.deck_id
  order by v.deck_id, v.version_number desc
),
card_overlap as (
  select cv.deck_id, count(distinct dc.oracle_id)::bigint as shared_cards_count
  from candidate_versions cv
  join mtg.deck_cards dc on dc.deck_version_id = cv.id
  join source_cards sc on sc.oracle_id = dc.oracle_id
  where dc.match_status = 'matched'
    and dc.oracle_id is not null
  group by cv.deck_id
)
select c.id, c.name, c.commander, c.color_identity, c.claimed_bracket,
  c.archetype, c.tags, coalesce(o.shared_cards_count, 0) as shared_cards_count
from visible_candidates c
left join card_overlap o on o.deck_id = c.id
order by coalesce(o.shared_cards_count, 0) desc, c.updated_at desc, c.name asc
limit $3;"#,
        inputs: "source deck_id, current user_id, and recommendation limit. SQL scopes the source and candidates to decks visible to that user.",
        indexes: "decks primary key, decks_owner_user_id_idx, decks_playgroup_id_idx, deck_versions_deck_id_idx, deck_cards_version_idx, deck_cards_oracle_id_idx, playgroup membership indexes.",
        plan_shape: "Read the latest imported source list, calculate shared matched-card overlap against visible active candidates, then Rust heuristics add commander, archetype, bracket, color, and tag similarity.",
        output: "Visible deck recommendations with aggregate scores and public-safe reason labels. This is SQL-scoped heuristic matching, not semantic or AI-backed matching.",
        sample_data: "Scrubbed fixture: Atraxa Counters recommends Atraxa Value because it shares imported cards, archetype, bracket, colors, and a tag.",
    },
    ObservatoryEntry {
        slug: "reminders",
        title: "Reminders and job claiming",
        badge: "ops SQL",
        source: "EventRepository::create_event_reminder and OpsRepository::acquire_next_background_job",
        sql: r#"insert into core.event_reminders (
  event_id, scheduled_for, reminder_type, status, created_by
)
values ($1, $2, $3, 'pending', $4)
returning id, event_id, scheduled_for, reminder_type, status,
  created_by, created_at, updated_at;

update ops.background_jobs
set locked_at = now(),
    locked_by = $1,
    attempts = attempts + 1,
    updated_at = now()
where id = (
  select id
  from ops.background_jobs
  where queue = $2
    and run_at <= now()
    and locked_at is null
    and attempts < max_attempts
  order by run_at asc, created_at asc
  limit 1
  for update skip locked
)
returning id, queue, job_type, payload, run_at, locked_at,
  locked_by, attempts, max_attempts, last_error, created_at, updated_at;"#,
        inputs: "event_id, scheduled_for timestamp, reminder_type, creator user id, worker id, and queue.",
        indexes: "event_reminders_scheduled_for_idx and background_jobs_run_at_idx.",
        plan_shape: "Store reminder intent as pending event data; workers claim due jobs atomically with FOR UPDATE SKIP LOCKED to avoid duplicate processing.",
        output: "Pending reminder records and one claimed background job per worker transaction.",
        sample_data: "Scrubbed fixture: reminder_type='event_reminder'; queue='default'; payload contains internal UUIDs only in local test data.",
    },
    ObservatoryEntry {
        slug: "matchup-history",
        title: "Matchup history",
        badge: "write + summary",
        source: "GameRepository::log_game_from_pod and MetaRepository::dashboard_for_user",
        sql: r#"insert into meta.matchup_history (
  game_id, event_id, playgroup_id, left_user_id, right_user_id,
  left_deck_id, right_deck_id
)
select g.id, g.event_id, e.playgroup_id,
  least(a.user_id, b.user_id),
  greatest(a.user_id, b.user_id),
  least(a.deck_id, b.deck_id),
  greatest(a.deck_id, b.deck_id)
from core.games g
join core.events e on e.id = g.event_id
join core.game_players a on a.game_id = g.id
join core.game_players b on b.game_id = g.id and a.id < b.id
where g.id = $1
  and (
    (a.user_id is not null and b.user_id is not null) or
    (a.deck_id is not null and b.deck_id is not null)
  )
on conflict do nothing;

select h.playgroup_id,
  h.matchup_type,
  h.left_label,
  h.right_label,
  h.games_together,
  h.last_played_at
from meta.matchup_summary h
join core.playgroup_memberships m on m.playgroup_id = h.playgroup_id
where m.user_id = $1
order by h.games_together desc, h.last_played_at desc
limit 12;"#,
        inputs: "game_id when logging a completed pod game; user_id when reading scoped dashboard history.",
        indexes: "matchup_history_game_user_pair_key, matchup_history_game_deck_pair_key, matchup_history_playgroup_event_idx, matchup_summary_playgroup_type_idx.",
        plan_shape: "Write canonical sorted player/deck pairs once per logged game, then read the materialized summary only through membership-scoped playgroups.",
        output: "Recent repeated player and deck pair summaries for meta health and future pod freshness decisions.",
        sample_data: "Scrubbed fixture: Ada + Ben have 2 games together; Atraxa + Yuriko have 1 deck matchup; labels are local test names.",
    },
    ObservatoryEntry {
        slug: "meta-dashboard",
        title: "Meta dashboard materialized views",
        badge: "materialized views",
        source: "MetaRepository::refresh_dashboard_views and dashboard_for_user",
        sql: r#"refresh materialized view meta.attendance_summary;
refresh materialized view meta.deck_win_rates;
refresh materialized view meta.player_win_rates;
refresh materialized view meta.commander_popularity;
refresh materialized view meta.bracket_distribution;
refresh materialized view meta.color_identity_distribution;
refresh materialized view meta.archetype_distribution;
refresh materialized view meta.matchup_summary;
refresh materialized view meta.stale_decks;

select a.playgroup_id,
  a.playgroup_name,
  a.events_total,
  a.confirmed_rsvps
from meta.attendance_summary a
join core.playgroup_memberships m on m.playgroup_id = a.playgroup_id
where m.user_id = $1
order by a.playgroup_name asc;"#,
        inputs: "user_id for membership-scoped dashboard reads; refresh jobs run without user input.",
        indexes: "attendance_summary_playgroup_id_key plus distribution and matchup materialized-view indexes by playgroup.",
        plan_shape: "Refresh expensive playgroup summaries in PostgreSQL, then read only playgroups where the current user has membership.",
        output: "Attendance, variety, win-rate, matchup, and stale-deck metrics for the authenticated dashboard.",
        sample_data: "Scrubbed fixture: playgroup_name='Wednesday Commander'; aggregate counts only; no event location or contact fields.",
    },
    ObservatoryEntry {
        slug: "scryfall-jsonb",
        title: "Scryfall JSONB exploration",
        badge: "raw payload",
        source: "ScryfallRepository::upsert_card_from_scryfall_json",
        sql: r#"select p.scryfall_id,
  p.raw_payload #>> '{prices,usd}' as usd,
  p.raw_payload #>> '{legalities,commander}' as commander_status,
  p.raw_payload ->> 'layout' as layout,
  jsonb_array_length(coalesce(p.raw_payload -> 'card_faces', '[]'::jsonb)) as face_count
from mtg.card_printings p
where p.raw_payload @> '{"layout":"normal"}'::jsonb
  and p.raw_payload ? 'prices'
order by p.released_at desc nulls last, p.scryfall_id
limit 25;"#,
        inputs: "local imported Scryfall printings; optional JSONB predicates for layout, prices, legalities, and card faces.",
        indexes: "card_printings_oracle_id_idx, card_printings_set_collector_idx, card_printings_import_id_idx; JSONB is retained for ad hoc local exploration.",
        plan_shape: "Filter stored raw Scryfall payloads with JSONB containment and key checks, then project specific nested fields without external API calls.",
        output: "Public card metadata from local Scryfall import, not user-owned private data.",
        sample_data: "Scrubbed fixture: imported public card payloads include price and legality keys; no player, host, invite, or contact fields exist in this schema.",
    },
];

#[cfg(test)]
mod tests {
    use super::observatory_entries;

    #[test]
    fn entries_cover_phase_thirteen_sql_surface() {
        let slugs = observatory_entries()
            .iter()
            .map(|entry| entry.slug)
            .collect::<Vec<_>>();

        for required in [
            "pod-generation",
            "avoid-repeat-pairing",
            "bracket-compatibility",
            "fuzzy-card-search",
            "game-changers-count",
            "similar-deck-recommendations",
            "reminders",
            "matchup-history",
            "scryfall-jsonb",
        ] {
            assert!(slugs.contains(&required), "missing {required}");
        }
    }

    #[test]
    fn entries_have_plan_context_and_scrubbed_samples() {
        for entry in observatory_entries() {
            assert!(!entry.title.trim().is_empty());
            assert!(!entry.source.trim().is_empty());
            assert!(!entry.sql.trim().is_empty());
            assert!(!entry.inputs.trim().is_empty());
            assert!(!entry.indexes.trim().is_empty());
            assert!(!entry.plan_shape.trim().is_empty());
            assert!(!entry.output.trim().is_empty());
            assert!(!entry.sample_data.trim().is_empty());
        }
    }

    #[test]
    fn entries_do_not_expose_sensitive_product_fields() {
        let sensitive_terms = [
            "address_line1",
            "address_line2",
            "postal_code",
            "invite_token",
            "token_hash",
            "email",
            "phone",
            "to_address",
            "pod_tracker_session",
            "password",
        ];

        for entry in observatory_entries() {
            let combined = format!(
                "{}\n{}\n{}\n{}\n{}\n{}",
                entry.title,
                entry.sql,
                entry.inputs,
                entry.indexes,
                entry.output,
                entry.sample_data
            )
            .to_lowercase();

            for term in sensitive_terms {
                assert!(
                    !combined.contains(term),
                    "{} contains sensitive term {term}",
                    entry.slug
                );
            }
        }
    }
}

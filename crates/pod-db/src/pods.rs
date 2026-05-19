use serde_json::{Value, json};
use sqlx::{PgPool, Postgres, Transaction};
use std::collections::{HashMap, HashSet};
use time::OffsetDateTime;
use uuid::Uuid;

use pod_core::pods::{
    bracket_compatibility_score, deck_variety_score, guest_placement_score,
    matchup_freshness_penalty, pod_size_fit_score,
};

use crate::DbError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PodRecord {
    pub id: Uuid,
    pub event_id: Uuid,
    pub name: String,
    pub state: String,
    pub position: i32,
    pub size_fit_score: i32,
    pub bracket_compatibility_score: i32,
    pub repeat_player_pair_penalty: i32,
    pub repeat_deck_matchup_penalty: i32,
    pub guest_placement_score: i32,
    pub availability_window_score: i32,
    pub total_score: i32,
    pub scoring_details: Value,
    pub published_at: Option<OffsetDateTime>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PodSeatRecord {
    pub id: Uuid,
    pub pod_id: Uuid,
    pub event_id: Uuid,
    pub rsvp_id: Uuid,
    pub user_id: Option<Uuid>,
    pub guest_name: Option<String>,
    pub deck_declaration_id: Option<Uuid>,
    pub deck_id: Option<Uuid>,
    pub seat_position: i32,
    pub locked: bool,
    pub arrival_time: Option<OffsetDateTime>,
    pub leaving_time: Option<OffsetDateTime>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PodWithSeats {
    pub pod: PodRecord,
    pub seats: Vec<PodSeatRecord>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PodGenerationSummary {
    pub pod_count: usize,
    pub seat_count: usize,
}

#[derive(Debug, Clone)]
struct CandidateAttendee {
    rsvp_id: Uuid,
    user_id: Option<Uuid>,
    guest_name: Option<String>,
    deck_declaration_id: Option<Uuid>,
    deck_id: Option<Uuid>,
    claimed_bracket: Option<String>,
    deck_commander: Option<String>,
    deck_color_identity: Option<String>,
    deck_archetype: Option<String>,
    arrival_time: Option<OffsetDateTime>,
    leaving_time: Option<OffsetDateTime>,
}

#[derive(Debug, Clone)]
struct PodScore {
    size_fit_score: i32,
    bracket_compatibility_score: i32,
    repeat_player_pair_penalty: i32,
    repeat_deck_matchup_penalty: i32,
    guest_placement_score: i32,
    availability_window_score: i32,
    total_score: i32,
    scoring_details: Value,
}

#[derive(Debug, Clone, Copy, Default)]
struct MatchupPenalties {
    repeat_penalty: i32,
    freshness_penalty: i32,
}

#[derive(Debug, Default)]
struct ScoringCache {
    player_pair_penalties: HashMap<(Uuid, Uuid), MatchupPenalties>,
    deck_pair_penalties: HashMap<(Uuid, Uuid), MatchupPenalties>,
}

#[derive(Debug, Clone)]
struct PublishedPodRecipient {
    email: String,
    title: String,
}

pub struct PodRepository<'a> {
    pool: &'a PgPool,
}

impl<'a> PodRepository<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }

    pub async fn generate_candidate_pods(
        &self,
        event_id: Uuid,
        target_pod_size: usize,
    ) -> Result<PodGenerationSummary, DbError> {
        let target_pod_size = target_pod_size.clamp(3, 5);
        let mut tx = self.pool.begin().await?;

        sqlx::query!(
            r#"
            delete from core.pod_seats s
            using core.pods p
            where s.pod_id = p.id
              and p.event_id = $1
              and p.state = 'proposed'
              and s.locked = false
            "#,
            event_id,
        )
        .execute(&mut *tx)
        .await?;

        sqlx::query!(
            r#"
            delete from core.pods p
            where p.event_id = $1
              and p.state = 'proposed'
              and not exists (
                select 1
                from core.pod_seats s
                where s.pod_id = p.id
              )
            "#,
            event_id,
        )
        .execute(&mut *tx)
        .await?;

        let attendees = sqlx::query_as!(
            CandidateAttendee,
            r#"
            select r.id as rsvp_id,
              r.user_id,
              r.guest_name,
              dec.id as "deck_declaration_id?",
              dec.deck_id as "deck_id?",
              d.claimed_bracket as "claimed_bracket?",
              d.commander as "deck_commander?",
              d.color_identity as "deck_color_identity?",
              d.archetype as "deck_archetype?",
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
            order by coalesce(r.arrival_time, r.created_at), r.created_at
            "#,
            event_id,
        )
        .fetch_all(&mut *tx)
        .await?;

        if attendees.is_empty() {
            tx.commit().await?;
            return Ok(PodGenerationSummary {
                pod_count: 0,
                seat_count: 0,
            });
        }

        let pod_count = attendees.len().div_ceil(target_pod_size).max(1);
        let mut groups = vec![Vec::new(); pod_count];
        for (index, attendee) in attendees.into_iter().enumerate() {
            groups[index % pod_count].push(attendee);
        }
        let mut scoring_cache = ScoringCache::default();
        let groups = optimize_groups(
            &mut tx,
            event_id,
            groups,
            target_pod_size,
            &mut scoring_cache,
        )
        .await?;

        let starting_position = sqlx::query_scalar!(
            r#"
            select coalesce(max(position), 0)::int + 1
            from core.pods
            where event_id = $1
            "#,
            event_id,
        )
        .fetch_one(&mut *tx)
        .await?
        .unwrap_or(1);

        let mut seat_count = 0;
        for (index, group) in groups.iter().enumerate() {
            let position = starting_position + index as i32;
            let score = score_pod(
                &mut tx,
                event_id,
                group,
                target_pod_size,
                &mut scoring_cache,
            )
            .await?;
            let pod = sqlx::query_as!(
                PodRecord,
                r#"
                insert into core.pods (
                  event_id, name, state, position, size_fit_score,
                  bracket_compatibility_score, repeat_player_pair_penalty,
                  repeat_deck_matchup_penalty, guest_placement_score,
                  availability_window_score, total_score, scoring_details
                )
                values (
                  $1, $2, 'proposed', $3, $4,
                  $5, $6,
                  $7, $8,
                  $9, $10, $11
                )
                returning id, event_id, name, state, position, size_fit_score,
                  bracket_compatibility_score, repeat_player_pair_penalty,
                  repeat_deck_matchup_penalty, guest_placement_score,
                  availability_window_score, total_score, scoring_details,
                  published_at, created_at, updated_at
                "#,
                event_id,
                format!("Pod {position}"),
                position,
                score.size_fit_score,
                score.bracket_compatibility_score,
                score.repeat_player_pair_penalty,
                score.repeat_deck_matchup_penalty,
                score.guest_placement_score,
                score.availability_window_score,
                score.total_score,
                score.scoring_details,
            )
            .fetch_one(&mut *tx)
            .await?;

            for (seat_index, attendee) in group.iter().enumerate() {
                sqlx::query!(
                    r#"
                    insert into core.pod_seats (
                      pod_id, event_id, rsvp_id, user_id, guest_name,
                      deck_declaration_id, deck_id, seat_position,
                      arrival_time, leaving_time
                    )
                    values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
                    "#,
                    pod.id,
                    event_id,
                    attendee.rsvp_id,
                    attendee.user_id,
                    attendee.guest_name,
                    attendee.deck_declaration_id,
                    attendee.deck_id,
                    seat_index as i32 + 1,
                    attendee.arrival_time,
                    attendee.leaving_time,
                )
                .execute(&mut *tx)
                .await?;
                seat_count += 1;
            }
        }

        tx.commit().await?;
        Ok(PodGenerationSummary {
            pod_count,
            seat_count,
        })
    }

    pub async fn list_for_event(&self, event_id: Uuid) -> Result<Vec<PodWithSeats>, DbError> {
        let pods = sqlx::query_as!(
            PodRecord,
            r#"
            select id, event_id, name, state, position, size_fit_score,
              bracket_compatibility_score, repeat_player_pair_penalty,
              repeat_deck_matchup_penalty, guest_placement_score,
              availability_window_score, total_score, scoring_details,
              published_at, created_at, updated_at
            from core.pods
            where event_id = $1
            order by position asc
            "#,
            event_id,
        )
        .fetch_all(self.pool)
        .await?;

        let mut output = Vec::with_capacity(pods.len());
        for pod in pods {
            let seats = self.list_seats(pod.id).await?;
            output.push(PodWithSeats { pod, seats });
        }
        Ok(output)
    }

    pub async fn list_seats(&self, pod_id: Uuid) -> Result<Vec<PodSeatRecord>, DbError> {
        let seats = sqlx::query_as!(
            PodSeatRecord,
            r#"
            select id, pod_id, event_id, rsvp_id, user_id, guest_name,
              deck_declaration_id, deck_id, seat_position, locked,
              arrival_time, leaving_time, created_at, updated_at
            from core.pod_seats
            where pod_id = $1
            order by seat_position asc
            "#,
            pod_id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(seats)
    }

    pub async fn event_id_for_pod(&self, pod_id: Uuid) -> Result<Option<Uuid>, DbError> {
        let event_id = sqlx::query_scalar!(
            r#"
            select event_id
            from core.pods
            where id = $1
            "#,
            pod_id,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(event_id)
    }

    pub async fn lock_pod(&self, pod_id: Uuid) -> Result<Option<PodRecord>, DbError> {
        self.set_pod_state(pod_id, "locked").await
    }

    pub async fn set_pod_state(
        &self,
        pod_id: Uuid,
        state: &str,
    ) -> Result<Option<PodRecord>, DbError> {
        let pod = sqlx::query_as!(
            PodRecord,
            r#"
            update core.pods
            set state = $2,
                updated_at = now()
            where id = $1
              and state in ('proposed', 'locked', 'active')
            returning id, event_id, name, state, position, size_fit_score,
              bracket_compatibility_score, repeat_player_pair_penalty,
              repeat_deck_matchup_penalty, guest_placement_score,
              availability_window_score, total_score, scoring_details,
              published_at, created_at, updated_at
            "#,
            pod_id,
            state,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(pod)
    }

    pub async fn move_seat(
        &self,
        seat_id: Uuid,
        target_pod_id: Uuid,
        seat_position: i32,
    ) -> Result<Option<PodSeatRecord>, DbError> {
        let mut tx = self.pool.begin().await?;
        let target_event_id = sqlx::query_scalar!(
            r#"
            select event_id
            from core.pods
            where id = $1
              and state in ('proposed', 'locked')
            "#,
            target_pod_id,
        )
        .fetch_optional(&mut *tx)
        .await?;
        let Some(target_event_id) = target_event_id else {
            tx.commit().await?;
            return Ok(None);
        };

        let current = sqlx::query!(
            r#"
            select id
            from core.pod_seats
            where id = $1
              and event_id = $2
            "#,
            seat_id,
            target_event_id,
        )
        .fetch_optional(&mut *tx)
        .await?;
        if current.is_none() || seat_position < 1 {
            tx.commit().await?;
            return Ok(None);
        }

        sqlx::query!(
            r#"
            update core.pod_seats
            set seat_position = 10000,
                updated_at = now()
            where id = $1
            "#,
            seat_id,
        )
        .execute(&mut *tx)
        .await?;

        sqlx::query!(
            r#"
            update core.pod_seats
            set seat_position = seat_position + 1000
            where pod_id = $1
              and seat_position >= $2
              and id <> $3
            "#,
            target_pod_id,
            seat_position,
            seat_id,
        )
        .execute(&mut *tx)
        .await?;

        sqlx::query!(
            r#"
            update core.pod_seats
            set seat_position = seat_position - 999,
                updated_at = now()
            where pod_id = $1
              and seat_position >= 1000
              and id <> $2
            "#,
            target_pod_id,
            seat_id,
        )
        .execute(&mut *tx)
        .await?;

        let moved = sqlx::query_as!(
            PodSeatRecord,
            r#"
            update core.pod_seats
            set pod_id = $2,
                seat_position = $3,
                updated_at = now()
            where id = $1
            returning id, pod_id, event_id, rsvp_id, user_id, guest_name,
              deck_declaration_id, deck_id, seat_position, locked,
              arrival_time, leaving_time, created_at, updated_at
            "#,
            seat_id,
            target_pod_id,
            seat_position,
        )
        .fetch_optional(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(moved)
    }

    pub async fn publish_event_pods(&self, event_id: Uuid) -> Result<usize, DbError> {
        let mut tx = self.pool.begin().await?;
        let pods = sqlx::query!(
            r#"
            update core.pods
            set state = 'active',
                published_at = coalesce(published_at, now()),
                updated_at = now()
            where event_id = $1
              and state in ('proposed', 'locked')
            returning id
            "#,
            event_id,
        )
        .fetch_all(&mut *tx)
        .await?;
        let pod_ids = pods.iter().map(|pod| pod.id).collect::<Vec<_>>();
        if !pod_ids.is_empty() {
            let recipients = sqlx::query_as!(
                PublishedPodRecipient,
                r#"
                select distinct u.email, e.title
                from core.pod_seats s
                join core.users u on u.id = s.user_id
                join core.events e on e.id = s.event_id
                where s.event_id = $1
                order by u.email
                "#,
                event_id,
            )
            .fetch_all(&mut *tx)
            .await?;
            for recipient in recipients {
                let body_text = format!(
                    "Pod assignments for {} have been published. Open /events/{}/pods to review your seat.",
                    recipient.title, event_id
                );
                let delivery = sqlx::query!(
                    r#"
                    insert into ops.email_deliveries (to_address, subject, body_text)
                    values ($1, $2, $3)
                    returning id
                    "#,
                    recipient.email,
                    format!("Pod assignments published: {}", recipient.title),
                    body_text,
                )
                .fetch_one(&mut *tx)
                .await?;
                let payload = json!({ "email_delivery_id": delivery.id });
                sqlx::query!(
                    r#"
                    insert into ops.background_jobs (queue, job_type, payload)
                    values ('default', 'send_email', $1)
                    "#,
                    payload,
                )
                .execute(&mut *tx)
                .await?;
            }
        }
        tx.commit().await?;
        Ok(pod_ids.len())
    }
}

async fn score_pod(
    tx: &mut Transaction<'_, Postgres>,
    event_id: Uuid,
    attendees: &[CandidateAttendee],
    target_pod_size: usize,
    scoring_cache: &mut ScoringCache,
) -> Result<PodScore, DbError> {
    let size_fit_score = pod_size_fit_score(attendees.len());
    let brackets = attendees
        .iter()
        .filter_map(|attendee| attendee.claimed_bracket.as_deref())
        .filter_map(parse_bracket)
        .collect::<Vec<_>>();
    let bracket_compatibility_score = bracket_compatibility_score(&brackets);
    let player_penalties =
        repeat_player_pair_penalty(tx, event_id, attendees, scoring_cache).await?;
    let deck_penalties =
        repeat_deck_matchup_penalty(tx, event_id, attendees, scoring_cache).await?;
    let repeat_player_pair_penalty = player_penalties.repeat_penalty;
    let repeat_deck_matchup_penalty = deck_penalties.repeat_penalty;
    let matchup_freshness_penalty =
        player_penalties.freshness_penalty + deck_penalties.freshness_penalty;
    let guest_count = attendees
        .iter()
        .filter(|attendee| attendee.user_id.is_none())
        .count();
    let guest_placement_score = guest_placement_score(guest_count, attendees.len());
    let availability_window_score = availability_window_score(attendees);
    let deck_variety_score = candidate_deck_variety_score(attendees);
    let total_score = size_fit_score
        + bracket_compatibility_score
        + guest_placement_score
        + availability_window_score
        + deck_variety_score
        - repeat_player_pair_penalty
        - repeat_deck_matchup_penalty
        - matchup_freshness_penalty;
    let scoring_details = json!({
        "target_pod_size": target_pod_size,
        "attendee_count": attendees.len(),
        "brackets": brackets,
        "guest_count": guest_count,
        "repeat_player_pair_penalty": repeat_player_pair_penalty,
        "repeat_deck_matchup_penalty": repeat_deck_matchup_penalty,
        "matchup_freshness_penalty": matchup_freshness_penalty,
        "deck_variety_score": deck_variety_score,
    });

    Ok(PodScore {
        size_fit_score,
        bracket_compatibility_score,
        repeat_player_pair_penalty,
        repeat_deck_matchup_penalty,
        guest_placement_score,
        availability_window_score,
        total_score,
        scoring_details,
    })
}

async fn optimize_groups(
    tx: &mut Transaction<'_, Postgres>,
    event_id: Uuid,
    mut groups: Vec<Vec<CandidateAttendee>>,
    target_pod_size: usize,
    scoring_cache: &mut ScoringCache,
) -> Result<Vec<Vec<CandidateAttendee>>, DbError> {
    if groups.len() < 2 {
        return Ok(groups);
    }

    let mut scores = Vec::with_capacity(groups.len());
    for group in &groups {
        scores.push(score_pod(tx, event_id, group, target_pod_size, scoring_cache).await?);
    }

    for _ in 0..16 {
        let mut best_swap = None;
        for left_group_index in 0..groups.len() {
            for right_group_index in (left_group_index + 1)..groups.len() {
                for left_seat_index in 0..groups[left_group_index].len() {
                    for right_seat_index in 0..groups[right_group_index].len() {
                        let mut left_group = groups[left_group_index].clone();
                        let mut right_group = groups[right_group_index].clone();
                        std::mem::swap(
                            &mut left_group[left_seat_index],
                            &mut right_group[right_seat_index],
                        );

                        let left_score =
                            score_pod(tx, event_id, &left_group, target_pod_size, scoring_cache)
                                .await?;
                        let right_score =
                            score_pod(tx, event_id, &right_group, target_pod_size, scoring_cache)
                                .await?;
                        let current_score = scores[left_group_index].total_score
                            + scores[right_group_index].total_score;
                        let candidate_score = left_score.total_score + right_score.total_score;
                        let improvement = candidate_score - current_score;

                        if improvement
                            > best_swap
                                .as_ref()
                                .map(|swap: &PendingSwap| swap.improvement)
                                .unwrap_or(0)
                        {
                            best_swap = Some(PendingSwap {
                                left_group_index,
                                right_group_index,
                                left_seat_index,
                                right_seat_index,
                                left_score,
                                right_score,
                                improvement,
                            });
                        }
                    }
                }
            }
        }

        let Some(swap) = best_swap else {
            break;
        };

        let right_attendee = groups[swap.right_group_index][swap.right_seat_index].clone();
        groups[swap.right_group_index][swap.right_seat_index] =
            groups[swap.left_group_index][swap.left_seat_index].clone();
        groups[swap.left_group_index][swap.left_seat_index] = right_attendee;
        scores[swap.left_group_index] = swap.left_score;
        scores[swap.right_group_index] = swap.right_score;
    }

    Ok(groups)
}

#[derive(Debug)]
struct PendingSwap {
    left_group_index: usize,
    right_group_index: usize,
    left_seat_index: usize,
    right_seat_index: usize,
    left_score: PodScore,
    right_score: PodScore,
    improvement: i32,
}

async fn repeat_player_pair_penalty(
    tx: &mut Transaction<'_, Postgres>,
    event_id: Uuid,
    attendees: &[CandidateAttendee],
    scoring_cache: &mut ScoringCache,
) -> Result<MatchupPenalties, DbError> {
    let mut penalties = MatchupPenalties::default();
    let users = attendees
        .iter()
        .filter_map(|attendee| attendee.user_id)
        .collect::<Vec<_>>();
    for left in 0..users.len() {
        for right in (left + 1)..users.len() {
            let key = ordered_uuid_pair(users[left], users[right]);
            if let Some(cached) = scoring_cache.player_pair_penalties.get(&key) {
                penalties.repeat_penalty += cached.repeat_penalty;
                penalties.freshness_penalty += cached.freshness_penalty;
                continue;
            }

            let row = sqlx::query!(
                r#"
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
                select count(*)::int as "repeat_count!",
                  extract(day from ((select start_time from current_event) - max(start_time)))::int
                    as "days_since_last?"
                from prior_pairings
                "#,
                event_id,
                users[left],
                users[right],
            )
            .fetch_one(&mut **tx)
            .await?;
            let pair_penalties = MatchupPenalties {
                repeat_penalty: row.repeat_count * 4,
                freshness_penalty: matchup_freshness_penalty(row.days_since_last.map(i64::from), 4),
            };
            scoring_cache
                .player_pair_penalties
                .insert(key, pair_penalties);
            penalties.repeat_penalty += pair_penalties.repeat_penalty;
            penalties.freshness_penalty += pair_penalties.freshness_penalty;
        }
    }
    Ok(penalties)
}

async fn repeat_deck_matchup_penalty(
    tx: &mut Transaction<'_, Postgres>,
    event_id: Uuid,
    attendees: &[CandidateAttendee],
    scoring_cache: &mut ScoringCache,
) -> Result<MatchupPenalties, DbError> {
    let mut penalties = MatchupPenalties::default();
    let decks = attendees
        .iter()
        .filter_map(|attendee| attendee.deck_id)
        .collect::<Vec<_>>();
    for left in 0..decks.len() {
        for right in (left + 1)..decks.len() {
            let key = ordered_uuid_pair(decks[left], decks[right]);
            if let Some(cached) = scoring_cache.deck_pair_penalties.get(&key) {
                penalties.repeat_penalty += cached.repeat_penalty;
                penalties.freshness_penalty += cached.freshness_penalty;
                continue;
            }

            let row = sqlx::query!(
                r#"
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
                select count(*)::int as "repeat_count!",
                  extract(day from ((select start_time from current_event) - max(start_time)))::int
                    as "days_since_last?"
                from prior_matchups
                "#,
                event_id,
                decks[left],
                decks[right],
            )
            .fetch_one(&mut **tx)
            .await?;
            let pair_penalties = MatchupPenalties {
                repeat_penalty: row.repeat_count * 3,
                freshness_penalty: matchup_freshness_penalty(row.days_since_last.map(i64::from), 3),
            };
            scoring_cache
                .deck_pair_penalties
                .insert(key, pair_penalties);
            penalties.repeat_penalty += pair_penalties.repeat_penalty;
            penalties.freshness_penalty += pair_penalties.freshness_penalty;
        }
    }
    Ok(penalties)
}

fn ordered_uuid_pair(left: Uuid, right: Uuid) -> (Uuid, Uuid) {
    if left <= right {
        (left, right)
    } else {
        (right, left)
    }
}

fn candidate_deck_variety_score(attendees: &[CandidateAttendee]) -> i32 {
    let declared_decks = attendees
        .iter()
        .filter(|attendee| attendee.deck_id.is_some())
        .count();
    let distinct_commanders = distinct_nonblank(
        attendees
            .iter()
            .filter_map(|attendee| attendee.deck_commander.as_deref()),
    );
    let distinct_archetypes = distinct_nonblank(
        attendees
            .iter()
            .filter_map(|attendee| attendee.deck_archetype.as_deref()),
    );
    let distinct_color_identities = distinct_nonblank(
        attendees
            .iter()
            .filter_map(|attendee| attendee.deck_color_identity.as_deref()),
    );

    deck_variety_score(
        declared_decks,
        distinct_commanders,
        distinct_archetypes,
        distinct_color_identities,
    )
}

fn distinct_nonblank<'a>(values: impl Iterator<Item = &'a str>) -> usize {
    values
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_ascii_lowercase)
        .collect::<HashSet<_>>()
        .len()
}

fn availability_window_score(attendees: &[CandidateAttendee]) -> i32 {
    let latest_arrival = attendees
        .iter()
        .filter_map(|attendee| attendee.arrival_time)
        .max();
    let earliest_leaving = attendees
        .iter()
        .filter_map(|attendee| attendee.leaving_time)
        .min();

    if latest_arrival
        .zip(earliest_leaving)
        .is_some_and(|(arrival, leaving)| arrival > leaving)
    {
        0
    } else {
        10
    }
}

fn parse_bracket(value: &str) -> Option<i32> {
    value
        .chars()
        .find(char::is_ascii_digit)
        .and_then(|character| character.to_digit(10))
        .map(|digit| digit as i32)
}

#[cfg(test)]
mod tests {
    use pod_core::playgroups::PlaygroupRole;

    use crate::{
        CreateDeckInput, CreateEventInput, DeckRepository, EventDeckDeclarationInput,
        EventRepository, IdentityRepository, PlaygroupRepository, PodRepository, RsvpInput,
    };

    struct DeckProfile<'a> {
        name: &'a str,
        commander: &'a str,
        color_identity: &'a str,
        bracket: &'a str,
        archetype: &'a str,
    }

    fn deck_input<'a>(
        owner_user_id: uuid::Uuid,
        playgroup_id: uuid::Uuid,
        name: &'a str,
        bracket: &'a str,
        tags: &'a [String],
    ) -> CreateDeckInput<'a> {
        deck_input_with_profile(
            owner_user_id,
            playgroup_id,
            DeckProfile {
                name,
                commander: "Tatyova, Benthic Druid",
                color_identity: "UG",
                bracket,
                archetype: "Value",
            },
            tags,
        )
    }

    fn deck_input_with_profile<'a>(
        owner_user_id: uuid::Uuid,
        playgroup_id: uuid::Uuid,
        profile: DeckProfile<'a>,
        tags: &'a [String],
    ) -> CreateDeckInput<'a> {
        CreateDeckInput {
            owner_user_id,
            playgroup_id: Some(playgroup_id),
            name: profile.name,
            commander: profile.commander,
            color_identity: profile.color_identity,
            claimed_bracket: profile.bracket,
            archetype: profile.archetype,
            tags,
            visibility: "playgroup",
            status: "active",
            game_changers_count: 0,
            has_infinite_combo: false,
            has_fast_mana: false,
            tutor_density: "low",
            has_extra_turns: false,
            has_mass_land_denial: false,
            salt_notes: "",
            notes: "",
        }
    }

    #[sqlx::test(migrations = "./migrations")]
    async fn generates_scores_locks_moves_and_publishes_pods(pool: sqlx::PgPool) {
        let identity = IdentityRepository::new(&pool);
        let owner = identity
            .create_user(
                "pod-owner@example.test",
                "Pod Owner",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("owner");
        let member_one = identity
            .create_user(
                "pod-member-one@example.test",
                "Pod Member One",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("member one");
        let member_two = identity
            .create_user(
                "pod-member-two@example.test",
                "Pod Member Two",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("member two");
        let member_three = identity
            .create_user(
                "pod-member-three@example.test",
                "Pod Member Three",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("member three");
        let playgroup = PlaygroupRepository::new(&pool)
            .create_playgroup(owner.id, "Pod Group", "pod-group", "")
            .await
            .expect("playgroup");
        for member in [member_one.id, member_two.id, member_three.id] {
            PlaygroupRepository::new(&pool)
                .add_membership(playgroup.id, member, PlaygroupRole::Member, None)
                .await
                .expect("membership");
        }

        let start_time =
            time::OffsetDateTime::from_unix_timestamp(1_800_000_000).expect("valid timestamp");
        let event = EventRepository::new(&pool)
            .create_event(CreateEventInput {
                playgroup_id: playgroup.id,
                title: "Pod Night",
                description: "",
                start_time,
                end_time: None,
                location: None,
                visibility: "members",
                invite_token: "pod-night-token",
                address_visibility: "hidden",
                created_by: owner.id,
            })
            .await
            .expect("event");

        let event_repo = EventRepository::new(&pool);
        for user_id in [owner.id, member_one.id, member_two.id, member_three.id] {
            event_repo
                .upsert_user_rsvp(RsvpInput {
                    event_id: event.id,
                    user_id: Some(user_id),
                    guest_name: None,
                    status: "yes",
                    arrival_time: None,
                    leaving_time: None,
                    guest_count: 0,
                    travel_buffer_minutes: None,
                    notes: "",
                })
                .await
                .expect("rsvp");
        }

        let deck_repo = DeckRepository::new(&pool);
        let tags = vec!["value".to_owned()];
        for (user_id, name, bracket) in [
            (owner.id, "Owner Deck", "2"),
            (member_one.id, "Member One Deck", "2"),
            (member_two.id, "Member Two Deck", "3"),
            (member_three.id, "Member Three Deck", "3"),
        ] {
            let deck = deck_repo
                .create_deck(deck_input(user_id, playgroup.id, name, bracket, &tags))
                .await
                .expect("deck");
            deck_repo
                .declare_event_deck(EventDeckDeclarationInput {
                    event_id: event.id,
                    user_id,
                    deck_id: deck.id,
                    preference: 1,
                    testing_notes: "",
                })
                .await
                .expect("declaration")
                .expect("declaration");
        }

        let pod_repo = PodRepository::new(&pool);
        let summary = pod_repo
            .generate_candidate_pods(event.id, 4)
            .await
            .expect("generate");
        assert_eq!(summary.pod_count, 1);
        assert_eq!(summary.seat_count, 4);

        let pods = pod_repo.list_for_event(event.id).await.expect("pods");
        assert_eq!(pods.len(), 1);
        assert_eq!(pods[0].seats.len(), 4);
        assert_eq!(pods[0].pod.state, "proposed");
        assert!(pods[0].pod.total_score > 0);

        let locked = pod_repo
            .lock_pod(pods[0].pod.id)
            .await
            .expect("lock")
            .expect("locked");
        assert_eq!(locked.state, "locked");

        let moved = pod_repo
            .move_seat(pods[0].seats[0].id, pods[0].pod.id, 2)
            .await
            .expect("move")
            .expect("moved");
        assert_eq!(moved.seat_position, 2);

        let published = pod_repo
            .publish_event_pods(event.id)
            .await
            .expect("publish");
        assert_eq!(published, 1);
        let active = pod_repo
            .list_for_event(event.id)
            .await
            .expect("active pods");
        assert_eq!(active[0].pod.state, "active");
        let delivery_count = sqlx::query_scalar!(
            r#"
            select count(*)::int
            from ops.email_deliveries
            where subject like 'Pod assignments published:%'
            "#
        )
        .fetch_one(&pool)
        .await
        .expect("delivery count")
        .unwrap_or(0);
        let job_count = sqlx::query_scalar!(
            r#"
            select count(*)::int
            from ops.background_jobs
            where job_type = 'send_email'
            "#
        )
        .fetch_one(&pool)
        .await
        .expect("job count")
        .unwrap_or(0);
        assert_eq!(delivery_count, 4);
        assert_eq!(job_count, 4);
    }

    #[sqlx::test(migrations = "./migrations")]
    async fn optimizes_generation_for_recent_matchup_freshness_and_deck_variety(
        pool: sqlx::PgPool,
    ) {
        let identity = IdentityRepository::new(&pool);
        let owner = identity
            .create_user(
                "fresh-pod-owner@example.test",
                "Fresh Pod Owner",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("owner");
        let playgroup = PlaygroupRepository::new(&pool)
            .create_playgroup(owner.id, "Fresh Pod Group", "fresh-pod-group", "")
            .await
            .expect("playgroup");

        let mut users = vec![owner.clone()];
        for index in 1..8 {
            let user = identity
                .create_user(
                    &format!("fresh-pod-member-{index}@example.test"),
                    &format!("Fresh Pod Member {index}"),
                    "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
                )
                .await
                .expect("member");
            PlaygroupRepository::new(&pool)
                .add_membership(playgroup.id, user.id, PlaygroupRole::Member, None)
                .await
                .expect("membership");
            users.push(user);
        }

        let current_start =
            time::OffsetDateTime::from_unix_timestamp(1_800_000_000).expect("valid timestamp");
        let prior_start = current_start - time::Duration::days(10);
        let event_repo = EventRepository::new(&pool);
        let prior_event = event_repo
            .create_event(CreateEventInput {
                playgroup_id: playgroup.id,
                title: "Fresh Prior Night",
                description: "",
                start_time: prior_start,
                end_time: None,
                location: None,
                visibility: "members",
                invite_token: "fresh-prior-token",
                address_visibility: "hidden",
                created_by: owner.id,
            })
            .await
            .expect("prior event");
        let current_event = event_repo
            .create_event(CreateEventInput {
                playgroup_id: playgroup.id,
                title: "Fresh Current Night",
                description: "",
                start_time: current_start,
                end_time: None,
                location: None,
                visibility: "members",
                invite_token: "fresh-current-token",
                address_visibility: "hidden",
                created_by: owner.id,
            })
            .await
            .expect("current event");

        let deck_repo = DeckRepository::new(&pool);
        let tags = vec!["freshness".to_owned()];
        let profiles = [
            ("Even A", "Nadu, Winged Wisdom", "UG", "2", "Combo"),
            (
                "Odd A",
                "Alesha, Who Smiles at Death",
                "RWB",
                "2",
                "Reanimator",
            ),
            ("Even B", "Nadu, Winged Wisdom", "UG", "2", "Combo"),
            ("Odd B", "Muldrotha, the Gravetide", "BGU", "2", "Graveyard"),
            ("Even C", "Nadu, Winged Wisdom", "UG", "2", "Combo"),
            ("Odd C", "Krenko, Mob Boss", "R", "2", "Tokens"),
            ("Even D", "Nadu, Winged Wisdom", "UG", "2", "Combo"),
            ("Odd D", "Teysa Karlov", "WB", "2", "Aristocrats"),
        ];
        let mut decks = Vec::new();
        let mut current_rsvps = Vec::new();
        let mut prior_rsvps = Vec::new();
        for (index, user) in users.iter().enumerate() {
            let (name, commander, color_identity, bracket, archetype) = profiles[index];
            let deck = deck_repo
                .create_deck(deck_input_with_profile(
                    user.id,
                    playgroup.id,
                    DeckProfile {
                        name,
                        commander,
                        color_identity,
                        bracket,
                        archetype,
                    },
                    &tags,
                ))
                .await
                .expect("deck");
            deck_repo
                .declare_event_deck(EventDeckDeclarationInput {
                    event_id: current_event.id,
                    user_id: user.id,
                    deck_id: deck.id,
                    preference: 1,
                    testing_notes: "",
                })
                .await
                .expect("declaration")
                .expect("declaration");
            current_rsvps.push(
                event_repo
                    .upsert_user_rsvp(RsvpInput {
                        event_id: current_event.id,
                        user_id: Some(user.id),
                        guest_name: None,
                        status: "yes",
                        arrival_time: Some(current_start + time::Duration::minutes(index as i64)),
                        leaving_time: None,
                        guest_count: 0,
                        travel_buffer_minutes: None,
                        notes: "",
                    })
                    .await
                    .expect("current rsvp"),
            );
            prior_rsvps.push(
                event_repo
                    .upsert_user_rsvp(RsvpInput {
                        event_id: prior_event.id,
                        user_id: Some(user.id),
                        guest_name: None,
                        status: "yes",
                        arrival_time: Some(prior_start + time::Duration::minutes(index as i64)),
                        leaving_time: None,
                        guest_count: 0,
                        travel_buffer_minutes: None,
                        notes: "",
                    })
                    .await
                    .expect("prior rsvp"),
            );
            decks.push(deck);
        }

        let prior_pod_id = sqlx::query_scalar!(
            r#"
            insert into core.pods (
              event_id, name, state, position, size_fit_score,
              bracket_compatibility_score, total_score
            )
            values ($1, 'Recent Repeated Pod', 'completed', 1, 20, 20, 40)
            returning id
            "#,
            prior_event.id,
        )
        .fetch_one(&pool)
        .await
        .expect("prior pod");
        for (seat_position, index) in [0usize, 2, 4, 6].into_iter().enumerate() {
            sqlx::query!(
                r#"
                insert into core.pod_seats (
                  pod_id, event_id, rsvp_id, user_id, deck_id, seat_position
                )
                values ($1, $2, $3, $4, $5, $6)
                "#,
                prior_pod_id,
                prior_event.id,
                prior_rsvps[index].id,
                users[index].id,
                decks[index].id,
                seat_position as i32 + 1,
            )
            .execute(&pool)
            .await
            .expect("prior seat");
        }

        let pod_repo = PodRepository::new(&pool);
        let summary = pod_repo
            .generate_candidate_pods(current_event.id, 4)
            .await
            .expect("generate");
        assert_eq!(summary.pod_count, 2);
        assert_eq!(summary.seat_count, 8);

        let pods = pod_repo
            .list_for_event(current_event.id)
            .await
            .expect("pods");
        assert_eq!(pods.len(), 2);
        assert!(
            pods.iter().all(|pod| pod
                .seats
                .iter()
                .filter(|seat| {
                    seat.user_id
                        .and_then(|user_id| users.iter().position(|user| user.id == user_id))
                        .is_some_and(|index| index % 2 == 0)
                })
                .count()
                < 4),
            "optimizer should not keep the recently repeated even-indexed pod intact"
        );
        assert!(
            pods.iter().all(|pod| {
                pod.pod
                    .scoring_details
                    .get("deck_variety_score")
                    .and_then(serde_json::Value::as_i64)
                    .unwrap_or(0)
                    > 0
            }),
            "generated pods should carry deck variety scoring details"
        );
        assert!(
            pods.iter().any(|pod| {
                pod.pod
                    .scoring_details
                    .get("matchup_freshness_penalty")
                    .and_then(serde_json::Value::as_i64)
                    .unwrap_or(0)
                    > 0
            }),
            "recent historical matchups should contribute a freshness penalty"
        );
        assert!(current_rsvps.iter().all(|rsvp| {
            pods.iter()
                .flat_map(|pod| &pod.seats)
                .any(|seat| seat.rsvp_id == rsvp.id)
        }));
    }
}

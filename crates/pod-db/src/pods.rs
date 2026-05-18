use serde_json::{Value, json};
use sqlx::{PgPool, Postgres, Transaction};
use time::OffsetDateTime;
use uuid::Uuid;

use pod_core::pods::{bracket_compatibility_score, guest_placement_score, pod_size_fit_score};

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
            let score = score_pod(&mut tx, event_id, group, target_pod_size).await?;
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
) -> Result<PodScore, DbError> {
    let size_fit_score = pod_size_fit_score(attendees.len());
    let brackets = attendees
        .iter()
        .filter_map(|attendee| attendee.claimed_bracket.as_deref())
        .filter_map(parse_bracket)
        .collect::<Vec<_>>();
    let bracket_compatibility_score = bracket_compatibility_score(&brackets);
    let repeat_player_pair_penalty = repeat_player_pair_penalty(tx, event_id, attendees).await?;
    let repeat_deck_matchup_penalty = repeat_deck_matchup_penalty(tx, event_id, attendees).await?;
    let guest_count = attendees
        .iter()
        .filter(|attendee| attendee.user_id.is_none())
        .count();
    let guest_placement_score = guest_placement_score(guest_count, attendees.len());
    let availability_window_score = availability_window_score(attendees);
    let total_score = size_fit_score
        + bracket_compatibility_score
        + guest_placement_score
        + availability_window_score
        - repeat_player_pair_penalty
        - repeat_deck_matchup_penalty;
    let scoring_details = json!({
        "target_pod_size": target_pod_size,
        "attendee_count": attendees.len(),
        "brackets": brackets,
        "guest_count": guest_count,
        "repeat_player_pair_penalty": repeat_player_pair_penalty,
        "repeat_deck_matchup_penalty": repeat_deck_matchup_penalty,
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

async fn repeat_player_pair_penalty(
    tx: &mut Transaction<'_, Postgres>,
    event_id: Uuid,
    attendees: &[CandidateAttendee],
) -> Result<i32, DbError> {
    let mut penalty = 0;
    let users = attendees
        .iter()
        .filter_map(|attendee| attendee.user_id)
        .collect::<Vec<_>>();
    for left in 0..users.len() {
        for right in (left + 1)..users.len() {
            let count = sqlx::query_scalar!(
                r#"
                select count(*)::int
                from core.pod_seats a
                join core.pod_seats b on b.pod_id = a.pod_id and b.user_id = $3
                join core.pods prior_pods on prior_pods.id = a.pod_id
                join core.events prior_events on prior_events.id = prior_pods.event_id
                join core.events current_events on current_events.id = $1
                where a.user_id = $2
                  and prior_pods.event_id <> $1
                  and prior_pods.state in ('locked', 'active', 'completed')
                  and prior_events.playgroup_id = current_events.playgroup_id
                "#,
                event_id,
                users[left],
                users[right],
            )
            .fetch_one(&mut **tx)
            .await?
            .unwrap_or(0);
            penalty += count * 4;
        }
    }
    Ok(penalty)
}

async fn repeat_deck_matchup_penalty(
    tx: &mut Transaction<'_, Postgres>,
    event_id: Uuid,
    attendees: &[CandidateAttendee],
) -> Result<i32, DbError> {
    let mut penalty = 0;
    let decks = attendees
        .iter()
        .filter_map(|attendee| attendee.deck_id)
        .collect::<Vec<_>>();
    for left in 0..decks.len() {
        for right in (left + 1)..decks.len() {
            let count = sqlx::query_scalar!(
                r#"
                select count(*)::int
                from core.pod_seats a
                join core.pod_seats b on b.pod_id = a.pod_id and b.deck_id = $3
                join core.pods prior_pods on prior_pods.id = a.pod_id
                join core.events prior_events on prior_events.id = prior_pods.event_id
                join core.events current_events on current_events.id = $1
                where a.deck_id = $2
                  and prior_pods.event_id <> $1
                  and prior_pods.state in ('locked', 'active', 'completed')
                  and prior_events.playgroup_id = current_events.playgroup_id
                "#,
                event_id,
                decks[left],
                decks[right],
            )
            .fetch_one(&mut **tx)
            .await?
            .unwrap_or(0);
            penalty += count * 3;
        }
    }
    Ok(penalty)
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

    fn deck_input<'a>(
        owner_user_id: uuid::Uuid,
        playgroup_id: uuid::Uuid,
        name: &'a str,
        bracket: &'a str,
        tags: &'a [String],
    ) -> CreateDeckInput<'a> {
        CreateDeckInput {
            owner_user_id,
            playgroup_id: Some(playgroup_id),
            name,
            commander: "Tatyova, Benthic Druid",
            color_identity: "UG",
            claimed_bracket: bracket,
            archetype: "Value",
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
}

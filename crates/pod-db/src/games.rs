use sqlx::PgPool;
use std::collections::HashSet;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::DbError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GameRecord {
    pub id: Uuid,
    pub event_id: Uuid,
    pub pod_id: Option<Uuid>,
    pub logged_by_user_id: Option<Uuid>,
    pub result_type: String,
    pub turn_count: Option<i32>,
    pub duration_minutes: Option<i32>,
    pub first_player_user_id: Option<Uuid>,
    pub tags: Vec<String>,
    pub notes: String,
    pub completed_at: OffsetDateTime,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GamePlayerRecord {
    pub id: Uuid,
    pub game_id: Uuid,
    pub pod_seat_id: Option<Uuid>,
    pub user_id: Option<Uuid>,
    pub guest_name: Option<String>,
    pub deck_id: Option<Uuid>,
    pub seat_position: i32,
    pub finish_position: Option<i32>,
    pub elimination_order: Option<i32>,
    pub eliminated_turn: Option<i32>,
    pub is_winner: bool,
    pub team: Option<String>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GameResultRecord {
    pub id: Uuid,
    pub game_id: Uuid,
    pub result_type: String,
    pub winner_user_id: Option<Uuid>,
    pub winning_deck_id: Option<Uuid>,
    pub winning_team: Option<String>,
    pub notes: String,
    pub created_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GameWithPlayers {
    pub game: GameRecord,
    pub result: GameResultRecord,
    pub players: Vec<GamePlayerRecord>,
}

#[derive(Debug, Clone, Copy)]
pub struct LogGameInput<'a> {
    pub event_id: Uuid,
    pub pod_id: Uuid,
    pub logged_by_user_id: Uuid,
    pub result_type: &'a str,
    pub winner_user_id: Option<Uuid>,
    pub turn_count: Option<i32>,
    pub duration_minutes: Option<i32>,
    pub first_player_user_id: Option<Uuid>,
    pub elimination_order_user_ids: &'a [Uuid],
    pub tags: &'a [String],
    pub notes: &'a str,
    pub winning_team: Option<&'a str>,
    pub complete_event: bool,
}

#[derive(Debug, Clone)]
struct PodSeatForGame {
    pod_seat_id: Uuid,
    user_id: Option<Uuid>,
    guest_name: Option<String>,
    deck_id: Option<Uuid>,
    seat_position: i32,
}

pub struct GameRepository<'a> {
    pool: &'a PgPool,
}

impl<'a> GameRepository<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }

    pub async fn log_game_from_pod(
        &self,
        input: LogGameInput<'_>,
    ) -> Result<Option<GameWithPlayers>, DbError> {
        let mut tx = self.pool.begin().await?;
        let pod = sqlx::query!(
            r#"
            select p.id, p.event_id
            from core.pods p
            where p.id = $1
              and p.event_id = $2
              and p.state in ('active', 'locked', 'completed')
            "#,
            input.pod_id,
            input.event_id,
        )
        .fetch_optional(&mut *tx)
        .await?;
        if pod.is_none() {
            tx.commit().await?;
            return Ok(None);
        }

        let seats = sqlx::query_as!(
            PodSeatForGame,
            r#"
            select id as pod_seat_id, user_id, guest_name, deck_id, seat_position
            from core.pod_seats
            where pod_id = $1
            order by seat_position asc
            "#,
            input.pod_id,
        )
        .fetch_all(&mut *tx)
        .await?;
        if seats.is_empty() {
            tx.commit().await?;
            return Ok(None);
        }

        let winning_deck_id = input.winner_user_id.and_then(|winner_user_id| {
            seats
                .iter()
                .find(|seat| seat.user_id == Some(winner_user_id))
                .and_then(|seat| seat.deck_id)
        });
        let winner_is_seated = input.winner_user_id.is_none_or(|winner_user_id| {
            seats
                .iter()
                .any(|seat| seat.user_id == Some(winner_user_id))
        });
        if !winner_is_seated {
            tx.commit().await?;
            return Ok(None);
        }
        let seated_user_ids = seats
            .iter()
            .filter_map(|seat| seat.user_id)
            .collect::<HashSet<_>>();
        let mut seen_eliminations = HashSet::new();
        for user_id in input.elimination_order_user_ids {
            if input.winner_user_id == Some(*user_id)
                || !seated_user_ids.contains(user_id)
                || !seen_eliminations.insert(*user_id)
            {
                tx.commit().await?;
                return Ok(None);
            }
        }

        let game = sqlx::query_as!(
            GameRecord,
            r#"
            insert into core.games (
              event_id, pod_id, logged_by_user_id, result_type, turn_count,
              duration_minutes, first_player_user_id, tags, notes
            )
            values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            returning id, event_id, pod_id, logged_by_user_id, result_type,
              turn_count, duration_minutes, first_player_user_id, tags, notes,
              completed_at, created_at, updated_at
            "#,
            input.event_id,
            input.pod_id,
            input.logged_by_user_id,
            input.result_type,
            input.turn_count,
            input.duration_minutes,
            input.first_player_user_id,
            input.tags,
            input.notes,
        )
        .fetch_one(&mut *tx)
        .await?;

        let mut players = Vec::with_capacity(seats.len());
        for seat in seats {
            let is_winner = input
                .winner_user_id
                .is_some_and(|winner_user_id| seat.user_id == Some(winner_user_id));
            let elimination_order = seat.user_id.and_then(|user_id| {
                input
                    .elimination_order_user_ids
                    .iter()
                    .position(|eliminated_user_id| *eliminated_user_id == user_id)
                    .map(|index| index as i32 + 1)
            });
            let player = sqlx::query_as!(
                GamePlayerRecord,
                r#"
                insert into core.game_players (
                  game_id, pod_seat_id, user_id, guest_name, deck_id,
                  seat_position, finish_position, elimination_order, is_winner, team
                )
                values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
                returning id, game_id, pod_seat_id, user_id, guest_name, deck_id,
                  seat_position, finish_position, elimination_order, eliminated_turn,
                  is_winner, team, created_at, updated_at
                "#,
                game.id,
                seat.pod_seat_id,
                seat.user_id,
                seat.guest_name,
                seat.deck_id,
                seat.seat_position,
                is_winner.then_some(1),
                elimination_order,
                is_winner,
                input.winning_team,
            )
            .fetch_one(&mut *tx)
            .await?;
            players.push(player);
        }

        let result = sqlx::query_as!(
            GameResultRecord,
            r#"
            insert into core.game_results (
              game_id, result_type, winner_user_id, winning_deck_id,
              winning_team, notes
            )
            values ($1, $2, $3, $4, $5, $6)
            returning id, game_id, result_type, winner_user_id,
              winning_deck_id, winning_team, notes, created_at
            "#,
            game.id,
            input.result_type,
            input.winner_user_id,
            winning_deck_id,
            input.winning_team,
            input.notes,
        )
        .fetch_one(&mut *tx)
        .await?;

        if !input.notes.trim().is_empty() {
            sqlx::query!(
                r#"
                insert into core.game_notes (game_id, author_user_id, note_text)
                values ($1, $2, $3)
                "#,
                game.id,
                input.logged_by_user_id,
                input.notes,
            )
            .execute(&mut *tx)
            .await?;
        }

        sqlx::query!(
            r#"
            insert into meta.matchup_history (
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
            on conflict do nothing
            "#,
            game.id,
        )
        .execute(&mut *tx)
        .await?;

        sqlx::query!(
            r#"
            update core.pods
            set state = 'completed',
                updated_at = now()
            where id = $1
              and state in ('active', 'locked')
            "#,
            input.pod_id,
        )
        .execute(&mut *tx)
        .await?;

        if input.complete_event {
            sqlx::query!(
                r#"
                update core.events
                set completed_at = coalesce(completed_at, now()),
                    updated_at = now()
                where id = $1
                "#,
                input.event_id,
            )
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;
        Ok(Some(GameWithPlayers {
            game,
            result,
            players,
        }))
    }

    pub async fn list_for_event(&self, event_id: Uuid) -> Result<Vec<GameWithPlayers>, DbError> {
        let games = sqlx::query_as!(
            GameRecord,
            r#"
            select id, event_id, pod_id, logged_by_user_id, result_type,
              turn_count, duration_minutes, first_player_user_id, tags, notes,
              completed_at, created_at, updated_at
            from core.games
            where event_id = $1
            order by completed_at desc, created_at desc
            "#,
            event_id,
        )
        .fetch_all(self.pool)
        .await?;

        let mut output = Vec::with_capacity(games.len());
        for game in games {
            let result = sqlx::query_as!(
                GameResultRecord,
                r#"
                select id, game_id, result_type, winner_user_id, winning_deck_id,
                  winning_team, notes, created_at
                from core.game_results
                where game_id = $1
                "#,
                game.id,
            )
            .fetch_one(self.pool)
            .await?;
            let players = sqlx::query_as!(
                GamePlayerRecord,
                r#"
                select id, game_id, pod_seat_id, user_id, guest_name, deck_id,
                  seat_position, finish_position, elimination_order, eliminated_turn,
                  is_winner, team, created_at, updated_at
                from core.game_players
                where game_id = $1
                order by seat_position asc
                "#,
                game.id,
            )
            .fetch_all(self.pool)
            .await?;
            output.push(GameWithPlayers {
                game,
                result,
                players,
            });
        }

        Ok(output)
    }
}

#[cfg(test)]
mod tests {
    use pod_core::playgroups::PlaygroupRole;

    use crate::{
        CreateEventInput, EventRepository, GameRepository, IdentityRepository, LogGameInput,
        PlaygroupRepository, PodRepository, RsvpInput,
    };

    #[sqlx::test(migrations = "./migrations")]
    async fn logs_game_results_notes_completion_and_matchup_history(pool: sqlx::PgPool) {
        let identity = IdentityRepository::new(&pool);
        let owner = identity
            .create_user(
                "game-owner@example.test",
                "Game Owner",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("owner");
        let member = identity
            .create_user(
                "game-member@example.test",
                "Game Member",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("member");
        let playgroup = PlaygroupRepository::new(&pool)
            .create_playgroup(owner.id, "Game Group", "game-group", "")
            .await
            .expect("playgroup");
        PlaygroupRepository::new(&pool)
            .add_membership(playgroup.id, member.id, PlaygroupRole::Member, None)
            .await
            .expect("membership");

        let start_time =
            time::OffsetDateTime::from_unix_timestamp(1_800_000_000).expect("valid timestamp");
        let event = EventRepository::new(&pool)
            .create_event(CreateEventInput {
                playgroup_id: playgroup.id,
                title: "Game Night",
                description: "",
                start_time,
                end_time: None,
                location: None,
                visibility: "members",
                invite_token: "game-night-token",
                address_visibility: "hidden",
                created_by: owner.id,
            })
            .await
            .expect("event");

        let event_repo = EventRepository::new(&pool);
        for user_id in [owner.id, member.id] {
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

        let pod_repo = PodRepository::new(&pool);
        pod_repo
            .generate_candidate_pods(event.id, 4)
            .await
            .expect("generate");
        let pods = pod_repo.list_for_event(event.id).await.expect("pods");
        pod_repo
            .publish_event_pods(event.id)
            .await
            .expect("publish");

        let tags = vec!["combo".to_owned(), "turn six".to_owned()];
        let elimination_order_user_ids = vec![member.id];
        let logged = GameRepository::new(&pool)
            .log_game_from_pod(LogGameInput {
                event_id: event.id,
                pod_id: pods[0].pod.id,
                logged_by_user_id: owner.id,
                result_type: "combo_win",
                winner_user_id: Some(owner.id),
                turn_count: Some(6),
                duration_minutes: Some(52),
                first_player_user_id: Some(member.id),
                elimination_order_user_ids: &elimination_order_user_ids,
                tags: &tags,
                notes: "Food break after this one.",
                winning_team: None,
                complete_event: true,
            })
            .await
            .expect("log")
            .expect("logged");

        assert_eq!(logged.game.result_type, "combo_win");
        assert_eq!(logged.players.len(), 2);
        assert_eq!(logged.result.winner_user_id, Some(owner.id));
        assert!(logged.players.iter().any(|player| player.is_winner));
        assert!(logged.players.iter().any(|player| {
            player.user_id == Some(member.id) && player.elimination_order == Some(1)
        }));

        let note_count = sqlx::query_scalar!(
            "select count(*)::int from core.game_notes where game_id = $1",
            logged.game.id
        )
        .fetch_one(&pool)
        .await
        .expect("note count")
        .unwrap_or(0);
        assert_eq!(note_count, 1);

        let matchup_count = sqlx::query_scalar!(
            "select count(*)::int from meta.matchup_history where game_id = $1",
            logged.game.id
        )
        .fetch_one(&pool)
        .await
        .expect("matchups")
        .unwrap_or(0);
        assert_eq!(matchup_count, 1);

        let completed_at = sqlx::query_scalar!(
            "select completed_at from core.events where id = $1",
            event.id
        )
        .fetch_one(&pool)
        .await
        .expect("completed");
        assert!(completed_at.is_some());
    }
}

use sqlx::{Executor, PgPool, Postgres};
use time::OffsetDateTime;
use uuid::Uuid;

use crate::DbError;

pub const META_DASHBOARD_REFRESH_JOB_TYPE: &str = "meta_dashboard_refresh";

pub(crate) async fn enqueue_meta_dashboard_refresh<'e, E>(executor: E) -> Result<(), DbError>
where
    E: Executor<'e, Database = Postgres>,
{
    sqlx::query!(
        r#"
        insert into ops.background_jobs (queue, job_type, payload)
        values ('default', $1, '{}'::jsonb)
        "#,
        META_DASHBOARD_REFRESH_JOB_TYPE,
    )
    .execute(executor)
    .await?;

    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MetaDashboard {
    pub attendance: Vec<MetaAttendanceSummary>,
    pub deck_win_rates: Vec<MetaDeckWinRate>,
    pub player_win_rates: Vec<MetaPlayerWinRate>,
    pub commander_popularity: Vec<MetaCommanderPopularity>,
    pub bracket_distribution: Vec<MetaDistributionMetric>,
    pub color_identity_distribution: Vec<MetaDistributionMetric>,
    pub archetype_distribution: Vec<MetaDistributionMetric>,
    pub matchup_history: Vec<MetaMatchupSummary>,
    pub stale_decks: Vec<MetaStaleDeck>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MetaAttendanceSummary {
    pub playgroup_id: Uuid,
    pub playgroup_name: String,
    pub events_total: i32,
    pub completed_events: i32,
    pub confirmed_rsvps: i32,
    pub active_players: i32,
    pub attendance_rate: i32,
    pub last_event_at: Option<OffsetDateTime>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MetaDeckWinRate {
    pub playgroup_id: Uuid,
    pub deck_id: Uuid,
    pub deck_name: String,
    pub commander: String,
    pub games_played: i32,
    pub wins: i32,
    pub win_rate: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MetaPlayerWinRate {
    pub playgroup_id: Uuid,
    pub user_id: Uuid,
    pub display_name: String,
    pub games_played: i32,
    pub wins: i32,
    pub win_rate: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MetaCommanderPopularity {
    pub playgroup_id: Uuid,
    pub commander: String,
    pub deck_count: i32,
    pub games_seen: i32,
    pub last_seen_at: Option<OffsetDateTime>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MetaDistributionMetric {
    pub playgroup_id: Uuid,
    pub label: String,
    pub deck_count: i32,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MetaMatchupSummary {
    pub playgroup_id: Uuid,
    pub matchup_type: String,
    pub left_label: String,
    pub right_label: String,
    pub games_together: i32,
    pub last_played_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MetaStaleDeck {
    pub playgroup_id: Uuid,
    pub deck_id: Uuid,
    pub deck_name: String,
    pub commander: String,
    pub deck_updated_at: OffsetDateTime,
    pub last_played_at: Option<OffsetDateTime>,
    pub stale_reason: String,
}

pub struct MetaRepository<'a> {
    pool: &'a PgPool,
}

impl<'a> MetaRepository<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }

    pub async fn refresh_dashboard_views(&self) -> Result<(), DbError> {
        for view in [
            "meta.attendance_summary",
            "meta.deck_win_rates",
            "meta.player_win_rates",
            "meta.commander_popularity",
            "meta.bracket_distribution",
            "meta.color_identity_distribution",
            "meta.archetype_distribution",
            "meta.matchup_summary",
            "meta.stale_decks",
        ] {
            sqlx::query(&format!("refresh materialized view {view}"))
                .execute(self.pool)
                .await?;
        }

        Ok(())
    }

    pub async fn dashboard_for_user(&self, user_id: Uuid) -> Result<MetaDashboard, DbError> {
        let attendance = sqlx::query_as!(
            MetaAttendanceSummary,
            r#"
            select a.playgroup_id as "playgroup_id!",
              a.playgroup_name as "playgroup_name!",
              a.events_total as "events_total!",
              a.completed_events as "completed_events!",
              a.confirmed_rsvps as "confirmed_rsvps!",
              a.active_players as "active_players!",
              a.attendance_rate as "attendance_rate!",
              a.last_event_at
            from meta.attendance_summary a
            join core.playgroup_memberships m on m.playgroup_id = a.playgroup_id
            where m.user_id = $1
            order by a.last_event_at desc nulls last, a.playgroup_name asc
            "#,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        let deck_win_rates = sqlx::query_as!(
            MetaDeckWinRate,
            r#"
            select d.playgroup_id as "playgroup_id!",
              d.deck_id as "deck_id!",
              d.deck_name as "deck_name!",
              d.commander as "commander!",
              d.games_played as "games_played!",
              d.wins as "wins!",
              d.win_rate as "win_rate!"
            from meta.deck_win_rates d
            join core.playgroup_memberships m on m.playgroup_id = d.playgroup_id
            where m.user_id = $1
            order by d.win_rate desc, d.games_played desc, d.deck_name asc
            limit 12
            "#,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        let player_win_rates = sqlx::query_as!(
            MetaPlayerWinRate,
            r#"
            select p.playgroup_id as "playgroup_id!",
              p.user_id as "user_id!",
              p.display_name as "display_name!",
              p.games_played as "games_played!",
              p.wins as "wins!",
              p.win_rate as "win_rate!"
            from meta.player_win_rates p
            join core.playgroup_memberships m on m.playgroup_id = p.playgroup_id
            where m.user_id = $1
            order by p.win_rate desc, p.games_played desc, p.display_name asc
            limit 12
            "#,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        let commander_popularity = sqlx::query_as!(
            MetaCommanderPopularity,
            r#"
            select c.playgroup_id as "playgroup_id!",
              c.commander as "commander!",
              c.deck_count as "deck_count!",
              c.games_seen as "games_seen!",
              c.last_seen_at
            from meta.commander_popularity c
            join core.playgroup_memberships m on m.playgroup_id = c.playgroup_id
            where m.user_id = $1
            order by c.games_seen desc, c.deck_count desc, c.commander asc
            limit 12
            "#,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        let bracket_distribution = sqlx::query_as!(
            MetaDistributionMetric,
            r#"
            select b.playgroup_id as "playgroup_id!",
              b.claimed_bracket as "label!",
              b.deck_count as "deck_count!"
            from meta.bracket_distribution b
            join core.playgroup_memberships m on m.playgroup_id = b.playgroup_id
            where m.user_id = $1
            order by b.playgroup_id, b.deck_count desc, b.claimed_bracket asc
            "#,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        let color_identity_distribution = sqlx::query_as!(
            MetaDistributionMetric,
            r#"
            select c.playgroup_id as "playgroup_id!",
              c.color_identity as "label!",
              c.deck_count as "deck_count!"
            from meta.color_identity_distribution c
            join core.playgroup_memberships m on m.playgroup_id = c.playgroup_id
            where m.user_id = $1
            order by c.playgroup_id, c.deck_count desc, c.color_identity asc
            "#,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        let archetype_distribution = sqlx::query_as!(
            MetaDistributionMetric,
            r#"
            select a.playgroup_id as "playgroup_id!",
              a.archetype as "label!",
              a.deck_count as "deck_count!"
            from meta.archetype_distribution a
            join core.playgroup_memberships m on m.playgroup_id = a.playgroup_id
            where m.user_id = $1
            order by a.playgroup_id, a.deck_count desc, a.archetype asc
            "#,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        let matchup_history = sqlx::query_as!(
            MetaMatchupSummary,
            r#"
            select h.playgroup_id as "playgroup_id!",
              h.matchup_type as "matchup_type!",
              h.left_label as "left_label!",
              h.right_label as "right_label!",
              h.games_together as "games_together!",
              h.last_played_at as "last_played_at!"
            from meta.matchup_summary h
            join core.playgroup_memberships m on m.playgroup_id = h.playgroup_id
            where m.user_id = $1
            order by h.games_together desc, h.last_played_at desc
            limit 12
            "#,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        let stale_decks = sqlx::query_as!(
            MetaStaleDeck,
            r#"
            select s.playgroup_id as "playgroup_id!",
              s.deck_id as "deck_id!",
              s.deck_name as "deck_name!",
              s.commander as "commander!",
              s.deck_updated_at as "deck_updated_at!",
              s.last_played_at,
              s.stale_reason as "stale_reason!"
            from meta.stale_decks s
            join core.playgroup_memberships m on m.playgroup_id = s.playgroup_id
            where m.user_id = $1
            order by s.last_played_at asc nulls first, s.deck_name asc
            limit 12
            "#,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(MetaDashboard {
            attendance,
            deck_win_rates,
            player_win_rates,
            commander_popularity,
            bracket_distribution,
            color_identity_distribution,
            archetype_distribution,
            matchup_history,
            stale_decks,
        })
    }
}

#[cfg(test)]
mod tests {
    use pod_core::playgroups::PlaygroupRole;

    use crate::{
        CreateDeckInput, CreateEventInput, DeckRepository, EventRepository, IdentityRepository,
        MetaRepository, PlaygroupRepository, RsvpInput,
    };

    #[sqlx::test(migrations = "./migrations")]
    async fn refreshes_meta_dashboard_materialized_views(pool: sqlx::PgPool) {
        let identity = IdentityRepository::new(&pool);
        let owner = identity
            .create_user(
                "meta-owner@example.test",
                "Meta Owner",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("owner");
        let member = identity
            .create_user(
                "meta-member@example.test",
                "Meta Member",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("member");

        let playgroup = PlaygroupRepository::new(&pool)
            .create_playgroup(owner.id, "Meta Crew", "meta-crew", "")
            .await
            .expect("playgroup");
        PlaygroupRepository::new(&pool)
            .add_membership(playgroup.id, member.id, PlaygroupRole::Member, None)
            .await
            .expect("membership");

        let event = EventRepository::new(&pool)
            .create_event(CreateEventInput {
                playgroup_id: playgroup.id,
                title: "Meta Night",
                description: "",
                start_time: time::OffsetDateTime::from_unix_timestamp(1_800_000_000)
                    .expect("valid timestamp"),
                end_time: None,
                location: None,
                visibility: "members",
                invite_token: "meta-night-token",
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

        let deck_repo = DeckRepository::new(&pool);
        let owner_tags = vec!["midrange".to_owned()];
        let owner_deck = deck_repo
            .create_deck(CreateDeckInput {
                owner_user_id: owner.id,
                playgroup_id: Some(playgroup.id),
                name: "Counters Again",
                commander: "Atraxa, Praetors' Voice",
                color_identity: "WUBG",
                claimed_bracket: "3",
                archetype: "Counters",
                tags: &owner_tags,
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
            })
            .await
            .expect("owner deck");
        let member_tags = vec!["spells".to_owned()];
        let member_deck = deck_repo
            .create_deck(CreateDeckInput {
                owner_user_id: member.id,
                playgroup_id: Some(playgroup.id),
                name: "Treasure Storm",
                commander: "Storm-Kiln Artist",
                color_identity: "R",
                claimed_bracket: "2",
                archetype: "Spellslinger",
                tags: &member_tags,
                visibility: "playgroup",
                status: "active",
                game_changers_count: 0,
                has_infinite_combo: false,
                has_fast_mana: false,
                tutor_density: "none",
                has_extra_turns: false,
                has_mass_land_denial: false,
                salt_notes: "",
                notes: "",
            })
            .await
            .expect("member deck");
        let stale_tags = vec!["tokens".to_owned()];
        let stale_deck = deck_repo
            .create_deck(CreateDeckInput {
                owner_user_id: owner.id,
                playgroup_id: Some(playgroup.id),
                name: "Shelf Tokens",
                commander: "Rhys the Redeemed",
                color_identity: "WG",
                claimed_bracket: "",
                archetype: "",
                tags: &stale_tags,
                visibility: "playgroup",
                status: "active",
                game_changers_count: 0,
                has_infinite_combo: false,
                has_fast_mana: false,
                tutor_density: "none",
                has_extra_turns: false,
                has_mass_land_denial: false,
                salt_notes: "",
                notes: "",
            })
            .await
            .expect("stale deck");

        let game_id = sqlx::query_scalar!(
            r#"
            insert into core.games (
              event_id, logged_by_user_id, result_type, completed_at
            )
            values ($1, $2, 'normal_win', now())
            returning id
            "#,
            event.id,
            owner.id,
        )
        .fetch_one(&pool)
        .await
        .expect("game");
        sqlx::query!(
            r#"
            insert into core.game_players (
              game_id, user_id, deck_id, seat_position, is_winner
            )
            values
              ($1, $2, $3, 1, true),
              ($1, $4, $5, 2, false)
            "#,
            game_id,
            owner.id,
            owner_deck.id,
            member.id,
            member_deck.id,
        )
        .execute(&pool)
        .await
        .expect("players");
        sqlx::query!(
            r#"
            insert into meta.matchup_history (
              game_id, event_id, playgroup_id, left_user_id, right_user_id,
              left_deck_id, right_deck_id
            )
            values (
              $1, $2, $3, least($4::uuid, $5::uuid), greatest($4::uuid, $5::uuid),
              least($6::uuid, $7::uuid), greatest($6::uuid, $7::uuid)
            )
            "#,
            game_id,
            event.id,
            playgroup.id,
            owner.id,
            member.id,
            owner_deck.id,
            member_deck.id,
        )
        .execute(&pool)
        .await
        .expect("matchup");

        let repo = MetaRepository::new(&pool);
        repo.refresh_dashboard_views().await.expect("refresh");
        let dashboard = repo.dashboard_for_user(owner.id).await.expect("dashboard");

        assert_eq!(dashboard.attendance[0].confirmed_rsvps, 2);
        assert_eq!(dashboard.attendance[0].active_players, 2);
        assert!(
            dashboard
                .deck_win_rates
                .iter()
                .any(|metric| metric.deck_id == owner_deck.id && metric.win_rate == 100)
        );
        assert!(
            dashboard
                .player_win_rates
                .iter()
                .any(|metric| metric.user_id == owner.id && metric.wins == 1)
        );
        assert!(
            dashboard
                .commander_popularity
                .iter()
                .any(|metric| metric.commander == "Atraxa, Praetors' Voice")
        );
        assert!(
            dashboard
                .bracket_distribution
                .iter()
                .any(|metric| metric.label == "Unspecified" && metric.deck_count == 1)
        );
        assert!(
            dashboard
                .color_identity_distribution
                .iter()
                .any(|metric| metric.label == "WUBG")
        );
        assert!(
            dashboard
                .archetype_distribution
                .iter()
                .any(|metric| metric.label == "Spellslinger")
        );
        assert!(
            dashboard
                .matchup_history
                .iter()
                .any(|metric| metric.matchup_type == "players" && metric.games_together == 1)
        );
        assert!(
            dashboard
                .stale_decks
                .iter()
                .any(|metric| metric.deck_id == stale_deck.id
                    && metric.stale_reason == "never_played")
        );

        let maybe_user = identity
            .create_user(
                "meta-maybe@example.test",
                "Meta Maybe",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("maybe user");
        PlaygroupRepository::new(&pool)
            .add_membership(playgroup.id, maybe_user.id, PlaygroupRole::Member, None)
            .await
            .expect("maybe membership");
        event_repo
            .upsert_user_rsvp(RsvpInput {
                event_id: event.id,
                user_id: Some(maybe_user.id),
                guest_name: None,
                status: "yes",
                arrival_time: None,
                leaving_time: None,
                guest_count: 0,
                travel_buffer_minutes: None,
                notes: "",
            })
            .await
            .expect("new rsvp");

        let stale_dashboard = repo
            .dashboard_for_user(owner.id)
            .await
            .expect("dashboard before refresh");
        assert_eq!(stale_dashboard.attendance[0].confirmed_rsvps, 2);

        repo.refresh_dashboard_views().await.expect("refresh again");
        let refreshed_dashboard = repo
            .dashboard_for_user(owner.id)
            .await
            .expect("dashboard after refresh");
        assert_eq!(refreshed_dashboard.attendance[0].confirmed_rsvps, 3);
    }
}

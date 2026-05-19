use serde_json::Value;
use sqlx::PgPool;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::DbError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AuditEventRecord {
    pub id: Uuid,
    pub event_type: String,
    pub actor_user_id: Option<Uuid>,
    pub playgroup_id: Option<Uuid>,
    pub event_id: Option<Uuid>,
    pub subject_table: String,
    pub subject_id: Option<Uuid>,
    pub metadata: Value,
    pub occurred_at: OffsetDateTime,
}

pub struct AuditRepository<'a> {
    pool: &'a PgPool,
}

impl<'a> AuditRepository<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }

    pub async fn record_address_reveal(
        &self,
        event_id: Uuid,
        actor_user_id: Option<Uuid>,
        viewer_scope: &str,
        source: &str,
    ) -> Result<bool, DbError> {
        let inserted = sqlx::query_scalar!(
            r#"
            insert into audit.audit_events (
              event_type, actor_user_id, playgroup_id, event_id,
              subject_table, subject_id, metadata
            )
            select 'event.address_revealed', $2, e.playgroup_id, e.id,
              'core.event_locations', e.location_id,
              jsonb_build_object('viewer_scope', $3::text, 'source', $4::text)
            from core.events e
            where e.id = $1
              and e.location_id is not null
            returning id
            "#,
            event_id,
            actor_user_id,
            viewer_scope,
            source,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(inserted.is_some())
    }

    pub async fn list_for_event(&self, event_id: Uuid) -> Result<Vec<AuditEventRecord>, DbError> {
        let events = sqlx::query_as!(
            AuditEventRecord,
            r#"
            select id, event_type, actor_user_id, playgroup_id, event_id,
              subject_table, subject_id, metadata, occurred_at
            from audit.audit_events
            where event_id = $1
            order by occurred_at asc, id asc
            "#,
            event_id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(events)
    }

    pub async fn list_for_playgroup(
        &self,
        playgroup_id: Uuid,
    ) -> Result<Vec<AuditEventRecord>, DbError> {
        let events = sqlx::query_as!(
            AuditEventRecord,
            r#"
            select id, event_type, actor_user_id, playgroup_id, event_id,
              subject_table, subject_id, metadata, occurred_at
            from audit.audit_events
            where playgroup_id = $1
            order by occurred_at asc, id asc
            "#,
            playgroup_id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(events)
    }
}

#[cfg(test)]
mod tests {
    use pod_core::playgroups::PlaygroupRole;
    use time::{Duration, OffsetDateTime};

    use crate::{
        AuditRepository, CreateEventInput, CreateInvite, EventLocationInput, EventRepository,
        GameRepository, IdentityRepository, LogGameInput, PlaygroupRepository, PodRepository,
        RsvpInput,
    };

    #[sqlx::test(migrations = "./migrations")]
    async fn records_sanitized_auth_membership_invite_event_rsvp_and_address_audit_events(
        pool: sqlx::PgPool,
    ) {
        let identity = IdentityRepository::new(&pool);
        let owner = identity
            .create_user(
                "audit-owner@example.test",
                "Audit Owner",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("owner");
        let member = identity
            .create_user(
                "audit-member@example.test",
                "Audit Member",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("member");
        let session = identity
            .create_session(
                owner.id,
                &[9_u8; 32],
                Some("audit-test"),
                OffsetDateTime::now_utc() + Duration::hours(1),
            )
            .await
            .expect("session");
        assert!(identity.revoke_session(session.id).await.expect("revoke"));

        let playgroups = PlaygroupRepository::new(&pool);
        let playgroup = playgroups
            .create_playgroup(owner.id, "Audit Group", "audit-group", "")
            .await
            .expect("playgroup");
        playgroups
            .add_membership(playgroup.id, member.id, PlaygroupRole::Member, None)
            .await
            .expect("membership");
        playgroups
            .create_invite(CreateInvite {
                playgroup_id: playgroup.id,
                token_hash: &[3_u8; 32],
                role: PlaygroupRole::Viewer,
                email: Some("invitee@example.test"),
                max_uses: Some(1),
                expires_at: None,
                created_by: owner.id,
            })
            .await
            .expect("invite");

        let event_repo = EventRepository::new(&pool);
        let start_time =
            OffsetDateTime::from_unix_timestamp(1_800_000_000).expect("valid timestamp");
        let event = event_repo
            .create_event(CreateEventInput {
                playgroup_id: playgroup.id,
                title: "Audit Night",
                description: "Do not audit prose.",
                start_time,
                end_time: None,
                location: Some(EventLocationInput {
                    name: "Host Table",
                    address_line1: Some("123 Private St"),
                    address_line2: None,
                    city: Some("Durham"),
                    state_province: Some("NC"),
                    postal_code: Some("27701"),
                    country: Some("US"),
                    notes: "Private note",
                }),
                visibility: "public_safe",
                invite_token: "audit-event-token",
                address_visibility: "members",
                created_by: owner.id,
            })
            .await
            .expect("event");
        event_repo
            .upsert_user_rsvp(RsvpInput {
                event_id: event.id,
                user_id: Some(member.id),
                guest_name: None,
                status: "yes",
                arrival_time: None,
                leaving_time: None,
                guest_count: 0,
                travel_buffer_minutes: None,
                notes: "Do not audit notes.",
            })
            .await
            .expect("rsvp");

        let audit = AuditRepository::new(&pool);
        assert!(
            audit
                .record_address_reveal(event.id, Some(member.id), "authenticated", "event_detail")
                .await
                .expect("address audit")
        );

        let event_types = audit
            .list_for_playgroup(playgroup.id)
            .await
            .expect("audit events")
            .into_iter()
            .map(|event| event.event_type)
            .collect::<Vec<_>>();
        for expected in [
            "membership.created",
            "invite.created",
            "event.created",
            "rsvp.created",
            "event.address_revealed",
        ] {
            assert!(
                event_types.iter().any(|event_type| event_type == expected),
                "missing {expected} in {event_types:?}"
            );
        }

        let auth_event_types = sqlx::query_scalar!(
            r#"
            select array_agg(event_type order by event_type) as "event_types!: Vec<String>"
            from audit.audit_events
            where actor_user_id = $1
              and event_type like 'auth.%'
            "#,
            owner.id,
        )
        .fetch_one(&pool)
        .await
        .expect("auth events");
        assert!(auth_event_types.contains(&"auth.user_created".to_owned()));
        assert!(auth_event_types.contains(&"auth.session_created".to_owned()));
        assert!(auth_event_types.contains(&"auth.session_revoked".to_owned()));

        let serialized = sqlx::query_scalar!(
            r#"
            select string_agg(metadata::text, ' ')
            from audit.audit_events
            "#
        )
        .fetch_one(&pool)
        .await
        .expect("metadata")
        .unwrap_or_default();
        assert!(!serialized.contains("audit-owner@example.test"));
        assert!(!serialized.contains("invitee@example.test"));
        assert!(!serialized.contains("audit-event-token"));
        assert!(!serialized.contains("123 Private St"));
        assert!(!serialized.contains("Private note"));
        assert!(!serialized.contains("Do not audit notes."));

        let mutation_result = sqlx::query!(
            r#"
            update audit.audit_events
            set metadata = '{}'::jsonb
            where event_type = 'event.address_revealed'
            "#
        )
        .execute(&pool)
        .await;
        assert!(mutation_result.is_err());
    }

    #[sqlx::test(migrations = "./migrations")]
    async fn records_pod_and_result_audit_events(pool: sqlx::PgPool) {
        let identity = IdentityRepository::new(&pool);
        let owner = identity
            .create_user(
                "audit-pod-owner@example.test",
                "Audit Pod Owner",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("owner");
        let member = identity
            .create_user(
                "audit-pod-member@example.test",
                "Audit Pod Member",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("member");

        let playgroups = PlaygroupRepository::new(&pool);
        let playgroup = playgroups
            .create_playgroup(owner.id, "Audit Pod Group", "audit-pod-group", "")
            .await
            .expect("playgroup");
        playgroups
            .add_membership(playgroup.id, member.id, PlaygroupRole::Member, None)
            .await
            .expect("membership");

        let event_repo = EventRepository::new(&pool);
        let start_time =
            OffsetDateTime::from_unix_timestamp(1_800_000_000).expect("valid timestamp");
        let event = event_repo
            .create_event(CreateEventInput {
                playgroup_id: playgroup.id,
                title: "Audit Result Night",
                description: "",
                start_time,
                end_time: None,
                location: None,
                visibility: "members",
                invite_token: "audit-result-token",
                address_visibility: "hidden",
                created_by: owner.id,
            })
            .await
            .expect("event");

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
            .expect("generate pods");
        let pods = pod_repo.list_for_event(event.id).await.expect("pods");
        pod_repo
            .publish_event_pods(event.id)
            .await
            .expect("publish pods");

        GameRepository::new(&pool)
            .log_game_from_pod(LogGameInput {
                event_id: event.id,
                pod_id: pods[0].pod.id,
                logged_by_user_id: owner.id,
                result_type: "normal_win",
                winner_user_id: Some(owner.id),
                turn_count: Some(7),
                duration_minutes: Some(50),
                first_player_user_id: Some(member.id),
                elimination_order_user_ids: &[member.id],
                tags: &[],
                notes: "Do not audit game notes.",
                winning_team: None,
                complete_event: true,
            })
            .await
            .expect("log game")
            .expect("logged");

        let event_types = AuditRepository::new(&pool)
            .list_for_event(event.id)
            .await
            .expect("audit events")
            .into_iter()
            .map(|event| event.event_type)
            .collect::<Vec<_>>();
        for expected in [
            "pod.created",
            "pod.state_changed",
            "result.created",
            "event.completed",
        ] {
            assert!(
                event_types.iter().any(|event_type| event_type == expected),
                "missing {expected} in {event_types:?}"
            );
        }

        let serialized = sqlx::query_scalar!(
            r#"
            select string_agg(metadata::text, ' ')
            from audit.audit_events
            where event_id = $1
            "#,
            event.id,
        )
        .fetch_one(&pool)
        .await
        .expect("metadata")
        .unwrap_or_default();
        assert!(serialized.contains("normal_win"));
        assert!(!serialized.contains("Do not audit game notes."));
    }
}

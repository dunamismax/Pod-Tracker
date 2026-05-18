use time::OffsetDateTime;
use uuid::Uuid;

use sqlx::PgPool;

use crate::{DbError, meta::enqueue_meta_dashboard_refresh};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventRecord {
    pub id: Uuid,
    pub playgroup_id: Uuid,
    pub title: String,
    pub description: String,
    pub start_time: OffsetDateTime,
    pub end_time: Option<OffsetDateTime>,
    pub location_id: Option<Uuid>,
    pub visibility: String,
    pub invite_token: Option<String>,
    pub created_by: Option<Uuid>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventWithRole {
    pub id: Uuid,
    pub playgroup_id: Uuid,
    pub playgroup_name: String,
    pub title: String,
    pub description: String,
    pub start_time: OffsetDateTime,
    pub end_time: Option<OffsetDateTime>,
    pub location_id: Option<Uuid>,
    pub visibility: String,
    pub invite_token: Option<String>,
    pub created_by: Option<Uuid>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
    pub member_role: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventLocationRecord {
    pub id: Uuid,
    pub playgroup_id: Uuid,
    pub name: String,
    pub address_line1: Option<String>,
    pub address_line2: Option<String>,
    pub city: Option<String>,
    pub state_province: Option<String>,
    pub postal_code: Option<String>,
    pub country: Option<String>,
    pub notes: String,
    pub created_by: Option<Uuid>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventHostRecord {
    pub id: Uuid,
    pub event_id: Uuid,
    pub user_id: Uuid,
    pub address_visibility: String,
    pub created_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventRsvpRecord {
    pub id: Uuid,
    pub event_id: Uuid,
    pub user_id: Option<Uuid>,
    pub guest_name: Option<String>,
    pub status: String,
    pub arrival_time: Option<OffsetDateTime>,
    pub leaving_time: Option<OffsetDateTime>,
    pub guest_count: i32,
    pub travel_buffer_minutes: Option<i32>,
    pub notes: String,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventReminderRecord {
    pub id: Uuid,
    pub event_id: Uuid,
    pub scheduled_for: OffsetDateTime,
    pub reminder_type: String,
    pub status: String,
    pub created_by: Option<Uuid>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CalendarEventRecord {
    pub id: Uuid,
    pub title: String,
    pub description: String,
    pub start_time: OffsetDateTime,
    pub end_time: Option<OffsetDateTime>,
    pub location_name: Option<String>,
}

#[derive(Debug, Clone, Copy)]
pub struct EventLocationInput<'a> {
    pub name: &'a str,
    pub address_line1: Option<&'a str>,
    pub address_line2: Option<&'a str>,
    pub city: Option<&'a str>,
    pub state_province: Option<&'a str>,
    pub postal_code: Option<&'a str>,
    pub country: Option<&'a str>,
    pub notes: &'a str,
}

#[derive(Debug, Clone, Copy)]
pub struct CreateEventInput<'a> {
    pub playgroup_id: Uuid,
    pub title: &'a str,
    pub description: &'a str,
    pub start_time: OffsetDateTime,
    pub end_time: Option<OffsetDateTime>,
    pub location: Option<EventLocationInput<'a>>,
    pub visibility: &'a str,
    pub invite_token: &'a str,
    pub address_visibility: &'a str,
    pub created_by: Uuid,
}

#[derive(Debug, Clone, Copy)]
pub struct UpdateEventInput<'a> {
    pub id: Uuid,
    pub title: &'a str,
    pub description: &'a str,
    pub start_time: OffsetDateTime,
    pub end_time: Option<OffsetDateTime>,
    pub visibility: &'a str,
}

#[derive(Debug, Clone, Copy)]
pub struct RsvpInput<'a> {
    pub event_id: Uuid,
    pub user_id: Option<Uuid>,
    pub guest_name: Option<&'a str>,
    pub status: &'a str,
    pub arrival_time: Option<OffsetDateTime>,
    pub leaving_time: Option<OffsetDateTime>,
    pub guest_count: i32,
    pub travel_buffer_minutes: Option<i32>,
    pub notes: &'a str,
}

#[derive(Debug, Clone, Copy)]
pub struct CreateEventReminderInput<'a> {
    pub event_id: Uuid,
    pub scheduled_for: OffsetDateTime,
    pub reminder_type: &'a str,
    pub status: &'a str,
    pub created_by: Option<Uuid>,
}

pub struct EventRepository<'a> {
    pool: &'a PgPool,
}

impl<'a> EventRepository<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }

    pub async fn create_event(&self, input: CreateEventInput<'_>) -> Result<EventRecord, DbError> {
        let mut tx = self.pool.begin().await?;
        let location_id = if let Some(location) = input.location {
            let location = sqlx::query_as!(
                EventLocationRecord,
                r#"
                insert into core.event_locations (
                  playgroup_id, name, address_line1, address_line2, city,
                  state_province, postal_code, country, notes, created_by
                )
                values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
                returning id, playgroup_id, name, address_line1, address_line2, city,
                  state_province, postal_code, country, notes, created_by, created_at, updated_at
                "#,
                input.playgroup_id,
                location.name,
                location.address_line1,
                location.address_line2,
                location.city,
                location.state_province,
                location.postal_code,
                location.country,
                location.notes,
                input.created_by,
            )
            .fetch_one(&mut *tx)
            .await?;
            Some(location.id)
        } else {
            None
        };

        let event = sqlx::query_as!(
            EventRecord,
            r#"
            insert into core.events (
              playgroup_id, title, description, start_time, end_time,
              location_id, visibility, invite_token, created_by
            )
            values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            returning id, playgroup_id, title, description, start_time, end_time,
              location_id, visibility, invite_token, created_by, created_at, updated_at
            "#,
            input.playgroup_id,
            input.title,
            input.description,
            input.start_time,
            input.end_time,
            location_id,
            input.visibility,
            input.invite_token,
            input.created_by,
        )
        .fetch_one(&mut *tx)
        .await?;

        sqlx::query_as!(
            EventHostRecord,
            r#"
            insert into core.event_hosts (event_id, user_id, address_visibility)
            values ($1, $2, $3)
            returning id, event_id, user_id, address_visibility, created_at
            "#,
            event.id,
            input.created_by,
            input.address_visibility,
        )
        .fetch_one(&mut *tx)
        .await?;

        enqueue_meta_dashboard_refresh(&mut *tx).await?;

        tx.commit().await?;
        Ok(event)
    }

    pub async fn update_event(&self, input: UpdateEventInput<'_>) -> Result<EventRecord, DbError> {
        let event = sqlx::query_as!(
            EventRecord,
            r#"
            update core.events
            set title = $2,
                description = $3,
                start_time = $4,
                end_time = $5,
                visibility = $6,
                updated_at = now()
            where id = $1
            returning id, playgroup_id, title, description, start_time, end_time,
              location_id, visibility, invite_token, created_by, created_at, updated_at
            "#,
            input.id,
            input.title,
            input.description,
            input.start_time,
            input.end_time,
            input.visibility,
        )
        .fetch_one(self.pool)
        .await?;

        Ok(event)
    }

    pub async fn list_for_user(&self, user_id: Uuid) -> Result<Vec<EventWithRole>, DbError> {
        let events = sqlx::query_as!(
            EventWithRole,
            r#"
            select e.id, e.playgroup_id, p.name as playgroup_name, e.title,
              e.description, e.start_time, e.end_time, e.location_id, e.visibility,
              e.invite_token, e.created_by, e.created_at, e.updated_at, m.role as member_role
            from core.events e
            join core.playgroups p on p.id = e.playgroup_id
            join core.playgroup_memberships m on m.playgroup_id = e.playgroup_id
            where m.user_id = $1
            order by e.start_time asc
            "#,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(events)
    }

    pub async fn list_for_playgroup(
        &self,
        playgroup_id: Uuid,
    ) -> Result<Vec<EventRecord>, DbError> {
        let events = sqlx::query_as!(
            EventRecord,
            r#"
            select id, playgroup_id, title, description, start_time, end_time,
              location_id, visibility, invite_token, created_by, created_at, updated_at
            from core.events
            where playgroup_id = $1
            order by start_time asc
            "#,
            playgroup_id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(events)
    }

    pub async fn get_for_user(
        &self,
        event_id: Uuid,
        user_id: Uuid,
    ) -> Result<Option<EventWithRole>, DbError> {
        let event = sqlx::query_as!(
            EventWithRole,
            r#"
            select e.id, e.playgroup_id, p.name as playgroup_name, e.title,
              e.description, e.start_time, e.end_time, e.location_id, e.visibility,
              e.invite_token, e.created_by, e.created_at, e.updated_at, m.role as member_role
            from core.events e
            join core.playgroups p on p.id = e.playgroup_id
            join core.playgroup_memberships m on m.playgroup_id = e.playgroup_id
            where e.id = $1
              and m.user_id = $2
            "#,
            event_id,
            user_id,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(event)
    }

    pub async fn get_by_token(&self, token: &str) -> Result<Option<EventRecord>, DbError> {
        let event = sqlx::query_as!(
            EventRecord,
            r#"
            select id, playgroup_id, title, description, start_time, end_time,
              location_id, visibility, invite_token, created_by, created_at, updated_at
            from core.events
            where invite_token = $1
              and visibility in ('invite_only', 'public_safe')
            "#,
            token,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(event)
    }

    pub async fn get_location_for_event(
        &self,
        event_id: Uuid,
    ) -> Result<Option<EventLocationRecord>, DbError> {
        let location = sqlx::query_as!(
            EventLocationRecord,
            r#"
            select l.id, l.playgroup_id, l.name, l.address_line1, l.address_line2,
              l.city, l.state_province, l.postal_code, l.country, l.notes,
              l.created_by, l.created_at, l.updated_at
            from core.event_locations l
            join core.events e on e.location_id = l.id
            where e.id = $1
            "#,
            event_id,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(location)
    }

    pub async fn list_hosts(&self, event_id: Uuid) -> Result<Vec<EventHostRecord>, DbError> {
        let hosts = sqlx::query_as!(
            EventHostRecord,
            r#"
            select id, event_id, user_id, address_visibility, created_at
            from core.event_hosts
            where event_id = $1
            "#,
            event_id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(hosts)
    }

    pub async fn list_rsvps(&self, event_id: Uuid) -> Result<Vec<EventRsvpRecord>, DbError> {
        let rsvps = sqlx::query_as!(
            EventRsvpRecord,
            r#"
            select id, event_id, user_id, guest_name, status, arrival_time,
              leaving_time, guest_count, travel_buffer_minutes, notes, created_at, updated_at
            from core.event_rsvps
            where event_id = $1
            order by created_at asc
            "#,
            event_id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(rsvps)
    }

    pub async fn get_user_rsvp(
        &self,
        event_id: Uuid,
        user_id: Uuid,
    ) -> Result<Option<EventRsvpRecord>, DbError> {
        let rsvp = sqlx::query_as!(
            EventRsvpRecord,
            r#"
            select id, event_id, user_id, guest_name, status, arrival_time,
              leaving_time, guest_count, travel_buffer_minutes, notes, created_at, updated_at
            from core.event_rsvps
            where event_id = $1
              and user_id = $2
            "#,
            event_id,
            user_id,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(rsvp)
    }

    pub async fn upsert_user_rsvp(&self, input: RsvpInput<'_>) -> Result<EventRsvpRecord, DbError> {
        if let Some(user_id) = input.user_id
            && let Some(existing) = self.get_user_rsvp(input.event_id, user_id).await?
        {
            return self.update_rsvp(existing.id, input).await;
        }

        self.create_rsvp(input).await
    }

    pub async fn create_rsvp(&self, input: RsvpInput<'_>) -> Result<EventRsvpRecord, DbError> {
        let rsvp = sqlx::query_as!(
            EventRsvpRecord,
            r#"
            insert into core.event_rsvps (
              event_id, user_id, guest_name, status, arrival_time, leaving_time,
              guest_count, travel_buffer_minutes, notes
            )
            values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            returning id, event_id, user_id, guest_name, status, arrival_time,
              leaving_time, guest_count, travel_buffer_minutes, notes, created_at, updated_at
            "#,
            input.event_id,
            input.user_id,
            input.guest_name,
            input.status,
            input.arrival_time,
            input.leaving_time,
            input.guest_count,
            input.travel_buffer_minutes,
            input.notes,
        )
        .fetch_one(self.pool)
        .await?;

        enqueue_meta_dashboard_refresh(self.pool).await?;

        Ok(rsvp)
    }

    pub async fn update_rsvp(
        &self,
        rsvp_id: Uuid,
        input: RsvpInput<'_>,
    ) -> Result<EventRsvpRecord, DbError> {
        let rsvp = sqlx::query_as!(
            EventRsvpRecord,
            r#"
            update core.event_rsvps
            set status = $2,
                arrival_time = $3,
                leaving_time = $4,
                guest_count = $5,
                travel_buffer_minutes = $6,
                notes = $7,
                updated_at = now()
            where id = $1
            returning id, event_id, user_id, guest_name, status, arrival_time,
              leaving_time, guest_count, travel_buffer_minutes, notes, created_at, updated_at
            "#,
            rsvp_id,
            input.status,
            input.arrival_time,
            input.leaving_time,
            input.guest_count,
            input.travel_buffer_minutes,
            input.notes,
        )
        .fetch_one(self.pool)
        .await?;

        enqueue_meta_dashboard_refresh(self.pool).await?;

        Ok(rsvp)
    }

    pub async fn list_calendar_events(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<CalendarEventRecord>, DbError> {
        let events = sqlx::query_as!(
            CalendarEventRecord,
            r#"
            select e.id, e.title, e.description, e.start_time, e.end_time,
              l.name as location_name
            from core.events e
            join core.playgroup_memberships m on m.playgroup_id = e.playgroup_id
            left join core.event_locations l on l.id = e.location_id
            where m.user_id = $1
            order by e.start_time asc
            "#,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(events)
    }

    pub async fn create_event_reminder(
        &self,
        input: CreateEventReminderInput<'_>,
    ) -> Result<EventReminderRecord, DbError> {
        let reminder = sqlx::query_as!(
            EventReminderRecord,
            r#"
            insert into core.event_reminders (
              event_id, scheduled_for, reminder_type, status, created_by
            )
            values ($1, $2, $3, $4, $5)
            returning id, event_id, scheduled_for, reminder_type, status,
              created_by, created_at, updated_at
            "#,
            input.event_id,
            input.scheduled_for,
            input.reminder_type,
            input.status,
            input.created_by,
        )
        .fetch_one(self.pool)
        .await?;

        Ok(reminder)
    }
}

#[cfg(test)]
mod tests {
    use pod_core::playgroups::PlaygroupRole;

    use crate::{
        CreateEventInput, CreateEventReminderInput, EventLocationInput, EventRepository,
        IdentityRepository, PlaygroupRepository, RsvpInput,
    };

    #[sqlx::test(migrations = "./migrations")]
    async fn creates_events_locations_hosts_and_rsvps(pool: sqlx::PgPool) {
        let identity = IdentityRepository::new(&pool);
        let owner = identity
            .create_user(
                "event-owner@example.test",
                "Event Owner",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("create owner");
        let member = identity
            .create_user(
                "event-member@example.test",
                "Event Member",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("create member");
        let playgroup = PlaygroupRepository::new(&pool)
            .create_playgroup(owner.id, "Event Group", "event-group", "")
            .await
            .expect("create playgroup");
        PlaygroupRepository::new(&pool)
            .add_membership(playgroup.id, member.id, PlaygroupRole::Member, None)
            .await
            .expect("add member");

        let repo = EventRepository::new(&pool);
        let start_time =
            time::OffsetDateTime::from_unix_timestamp(1_800_000_000).expect("valid timestamp");
        let event = repo
            .create_event(CreateEventInput {
                playgroup_id: playgroup.id,
                title: "Commander Night",
                description: "Pods at seven.",
                start_time,
                end_time: None,
                location: Some(EventLocationInput {
                    name: "Kitchen Table",
                    address_line1: Some("123 Private St"),
                    address_line2: None,
                    city: Some("Durham"),
                    state_province: Some("NC"),
                    postal_code: Some("27701"),
                    country: Some("US"),
                    notes: "",
                }),
                visibility: "public_safe",
                invite_token: "event-token",
                address_visibility: "rsvps",
                created_by: owner.id,
            })
            .await
            .expect("create event");

        assert_eq!(repo.list_hosts(event.id).await.expect("hosts").len(), 1);
        assert!(
            repo.get_location_for_event(event.id)
                .await
                .expect("location")
                .expect("location")
                .address_line1
                .as_deref()
                == Some("123 Private St")
        );

        repo.upsert_user_rsvp(RsvpInput {
            event_id: event.id,
            user_id: Some(member.id),
            guest_name: None,
            status: "yes",
            arrival_time: Some(start_time),
            leaving_time: None,
            guest_count: 1,
            travel_buffer_minutes: Some(15),
            notes: "Bringing a guest.",
        })
        .await
        .expect("member rsvp");
        repo.create_rsvp(RsvpInput {
            event_id: event.id,
            user_id: None,
            guest_name: Some("Guest Player"),
            status: "maybe",
            arrival_time: None,
            leaving_time: None,
            guest_count: 0,
            travel_buffer_minutes: None,
            notes: "",
        })
        .await
        .expect("guest rsvp");

        let rsvps = repo.list_rsvps(event.id).await.expect("list rsvps");
        assert_eq!(rsvps.len(), 2);
        assert_eq!(
            repo.get_for_user(event.id, member.id)
                .await
                .expect("event for member")
                .expect("member event")
                .member_role,
            "member"
        );
        assert!(
            repo.get_by_token("event-token")
                .await
                .expect("event token")
                .is_some()
        );
        assert_eq!(
            repo.list_calendar_events(member.id)
                .await
                .expect("calendar events")
                .len(),
            1
        );

        let reminder = repo
            .create_event_reminder(CreateEventReminderInput {
                event_id: event.id,
                scheduled_for: start_time - time::Duration::hours(24),
                reminder_type: "event_reminder",
                status: "pending",
                created_by: Some(owner.id),
            })
            .await
            .expect("create reminder");
        assert_eq!(reminder.event_id, event.id);
        assert_eq!(reminder.status, "pending");
    }
}

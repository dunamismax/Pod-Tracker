use time::OffsetDateTime;
use uuid::Uuid;

use pod_core::playgroups::PlaygroupRole;
use sqlx::PgPool;

use crate::DbError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaygroupRecord {
    pub id: Uuid,
    pub name: String,
    pub slug: String,
    pub description: String,
    pub created_by: Option<Uuid>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MembershipRecord {
    pub id: Uuid,
    pub playgroup_id: Uuid,
    pub user_id: Uuid,
    pub role: String,
    pub display_name: Option<String>,
    pub joined_at: OffsetDateTime,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaygroupWithRole {
    pub id: Uuid,
    pub name: String,
    pub slug: String,
    pub description: String,
    pub role: String,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaygroupInviteRecord {
    pub id: Uuid,
    pub playgroup_id: Uuid,
    pub token_hash: Vec<u8>,
    pub role: String,
    pub email: Option<String>,
    pub max_uses: Option<i32>,
    pub used_count: i32,
    pub expires_at: Option<OffsetDateTime>,
    pub revoked_at: Option<OffsetDateTime>,
    pub created_by: Option<Uuid>,
    pub created_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaygroupSettingsRecord {
    pub playgroup_id: Uuid,
    pub default_event_visibility: String,
    pub allow_guest_rsvps: bool,
    pub show_member_decklists: bool,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HouseRuleRecord {
    pub id: Uuid,
    pub playgroup_id: Uuid,
    pub title: String,
    pub body: String,
    pub visible_to_guests: bool,
    pub created_by: Option<Uuid>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, Copy)]
pub struct CreateInvite<'a> {
    pub playgroup_id: Uuid,
    pub token_hash: &'a [u8],
    pub role: PlaygroupRole,
    pub email: Option<&'a str>,
    pub max_uses: Option<i32>,
    pub expires_at: Option<OffsetDateTime>,
    pub created_by: Uuid,
}

pub struct PlaygroupRepository<'a> {
    pool: &'a PgPool,
}

impl<'a> PlaygroupRepository<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }

    pub async fn create_playgroup(
        &self,
        owner_id: Uuid,
        name: &str,
        slug: &str,
        description: &str,
    ) -> Result<PlaygroupRecord, DbError> {
        let mut tx = self.pool.begin().await?;
        let playgroup = sqlx::query_as!(
            PlaygroupRecord,
            r#"
            insert into core.playgroups (name, slug, description, created_by)
            values ($1, $2, $3, $4)
            returning id, name, slug, description, created_by, created_at, updated_at
            "#,
            name,
            slug,
            description,
            owner_id
        )
        .fetch_one(&mut *tx)
        .await?;

        sqlx::query_as!(
            MembershipRecord,
            r#"
            insert into core.playgroup_memberships (playgroup_id, user_id, role)
            values ($1, $2, 'owner')
            returning id, playgroup_id, user_id, role, display_name, joined_at, created_at, updated_at
            "#,
            playgroup.id,
            owner_id
        )
        .fetch_one(&mut *tx)
        .await?;

        sqlx::query_as!(
            PlaygroupSettingsRecord,
            r#"
            insert into core.playgroup_settings (playgroup_id)
            values ($1)
            returning playgroup_id, default_event_visibility, allow_guest_rsvps, show_member_decklists, created_at, updated_at
            "#,
            playgroup.id
        )
        .fetch_one(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(playgroup)
    }

    pub async fn list_for_user(&self, user_id: Uuid) -> Result<Vec<PlaygroupWithRole>, DbError> {
        let playgroups = sqlx::query_as!(
            PlaygroupWithRole,
            r#"
            select p.id, p.name, p.slug, p.description, m.role, p.created_at, p.updated_at
            from core.playgroups p
            join core.playgroup_memberships m on m.playgroup_id = p.id
            where m.user_id = $1
            order by p.created_at desc
            "#,
            user_id
        )
        .fetch_all(self.pool)
        .await?;

        Ok(playgroups)
    }

    pub async fn get_by_slug_for_user(
        &self,
        slug: &str,
        user_id: Uuid,
    ) -> Result<Option<PlaygroupWithRole>, DbError> {
        let playgroup = sqlx::query_as!(
            PlaygroupWithRole,
            r#"
            select p.id, p.name, p.slug, p.description, m.role, p.created_at, p.updated_at
            from core.playgroups p
            join core.playgroup_memberships m on m.playgroup_id = p.id
            where p.slug = $1
              and m.user_id = $2
            "#,
            slug,
            user_id
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(playgroup)
    }

    pub async fn add_membership(
        &self,
        playgroup_id: Uuid,
        user_id: Uuid,
        role: PlaygroupRole,
        display_name: Option<&str>,
    ) -> Result<MembershipRecord, DbError> {
        let membership = sqlx::query_as!(
            MembershipRecord,
            r#"
            insert into core.playgroup_memberships (playgroup_id, user_id, role, display_name)
            values ($1, $2, $3, $4)
            returning id, playgroup_id, user_id, role, display_name, joined_at, created_at, updated_at
            "#,
            playgroup_id,
            user_id,
            role.as_str(),
            display_name
        )
        .fetch_one(self.pool)
        .await?;

        Ok(membership)
    }

    pub async fn membership_for_user(
        &self,
        playgroup_id: Uuid,
        user_id: Uuid,
    ) -> Result<Option<MembershipRecord>, DbError> {
        let membership = sqlx::query_as!(
            MembershipRecord,
            r#"
            select id, playgroup_id, user_id, role, display_name, joined_at, created_at, updated_at
            from core.playgroup_memberships
            where playgroup_id = $1
              and user_id = $2
            "#,
            playgroup_id,
            user_id
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(membership)
    }

    pub async fn create_invite(
        &self,
        invite: CreateInvite<'_>,
    ) -> Result<PlaygroupInviteRecord, DbError> {
        let invite = sqlx::query_as!(
            PlaygroupInviteRecord,
            r#"
            insert into core.playgroup_invites (
              playgroup_id, token_hash, role, email, max_uses, expires_at, created_by
            )
            values ($1, $2, $3, lower($4), $5, $6, $7)
            returning id, playgroup_id, token_hash, role, email, max_uses, used_count, expires_at, revoked_at, created_by, created_at
            "#,
            invite.playgroup_id,
            invite.token_hash,
            invite.role.as_str(),
            invite.email,
            invite.max_uses,
            invite.expires_at,
            invite.created_by
        )
        .fetch_one(self.pool)
        .await?;

        Ok(invite)
    }

    pub async fn get_settings(
        &self,
        playgroup_id: Uuid,
    ) -> Result<Option<PlaygroupSettingsRecord>, DbError> {
        let settings = sqlx::query_as!(
            PlaygroupSettingsRecord,
            r#"
            select playgroup_id, default_event_visibility, allow_guest_rsvps, show_member_decklists, created_at, updated_at
            from core.playgroup_settings
            where playgroup_id = $1
            "#,
            playgroup_id
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(settings)
    }

    pub async fn create_house_rule(
        &self,
        playgroup_id: Uuid,
        title: &str,
        body: &str,
        visible_to_guests: bool,
        created_by: Uuid,
    ) -> Result<HouseRuleRecord, DbError> {
        let house_rule = sqlx::query_as!(
            HouseRuleRecord,
            r#"
            insert into core.house_rules (
              playgroup_id, title, body, visible_to_guests, created_by
            )
            values ($1, $2, $3, $4, $5)
            returning id, playgroup_id, title, body, visible_to_guests, created_by, created_at, updated_at
            "#,
            playgroup_id,
            title,
            body,
            visible_to_guests,
            created_by
        )
        .fetch_one(self.pool)
        .await?;

        Ok(house_rule)
    }

    pub async fn list_house_rules(
        &self,
        playgroup_id: Uuid,
        include_guest_hidden: bool,
    ) -> Result<Vec<HouseRuleRecord>, DbError> {
        let house_rules = sqlx::query_as!(
            HouseRuleRecord,
            r#"
            select id, playgroup_id, title, body, visible_to_guests, created_by, created_at, updated_at
            from core.house_rules
            where playgroup_id = $1
              and ($2 or visible_to_guests)
            order by created_at asc
            "#,
            playgroup_id,
            include_guest_hidden
        )
        .fetch_all(self.pool)
        .await?;

        Ok(house_rules)
    }
}

#[cfg(test)]
mod tests {
    use pod_core::playgroups::PlaygroupRole;

    use crate::{CreateInvite, IdentityRepository, PlaygroupRepository};

    #[sqlx::test(migrations = "./migrations")]
    async fn creates_playgroup_owner_membership_settings_invites_and_rules(pool: sqlx::PgPool) {
        let identity = IdentityRepository::new(&pool);
        let owner = identity
            .create_user(
                "owner@example.test",
                "Owner",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("create owner");
        let member = identity
            .create_user(
                "member@example.test",
                "Member",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("create member");

        let repo = PlaygroupRepository::new(&pool);
        let playgroup = repo
            .create_playgroup(
                owner.id,
                "Friday Night Commander",
                "friday-night-commander",
                "Weekly pods",
            )
            .await
            .expect("create playgroup");

        let listed = repo.list_for_user(owner.id).await.expect("list playgroups");
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].role, "owner");

        let owner_membership = repo
            .membership_for_user(playgroup.id, owner.id)
            .await
            .expect("membership query")
            .expect("owner membership");
        assert_eq!(owner_membership.role, "owner");

        let member_membership = repo
            .add_membership(
                playgroup.id,
                member.id,
                PlaygroupRole::Member,
                Some("Regular"),
            )
            .await
            .expect("add member");
        assert_eq!(member_membership.role, "member");

        let settings = repo
            .get_settings(playgroup.id)
            .await
            .expect("settings query")
            .expect("settings");
        assert_eq!(settings.default_event_visibility, "members");
        assert!(settings.allow_guest_rsvps);

        let invite = repo
            .create_invite(CreateInvite {
                playgroup_id: playgroup.id,
                token_hash: &[3_u8; 32],
                role: PlaygroupRole::Viewer,
                email: Some("VIEWER@example.test"),
                max_uses: Some(3),
                expires_at: None,
                created_by: owner.id,
            })
            .await
            .expect("create invite");
        assert_eq!(invite.email.as_deref(), Some("viewer@example.test"));
        assert_eq!(invite.role, "viewer");

        repo.create_house_rule(
            playgroup.id,
            "Rule Zero",
            "Talk about expectations before game one.",
            false,
            owner.id,
        )
        .await
        .expect("private house rule");
        repo.create_house_rule(
            playgroup.id,
            "Guest Rule",
            "Bring a precon if unsure.",
            true,
            owner.id,
        )
        .await
        .expect("guest house rule");

        assert_eq!(
            repo.list_house_rules(playgroup.id, true)
                .await
                .expect("all rules")
                .len(),
            2
        );
        let guest_visible_rules = repo
            .list_house_rules(playgroup.id, false)
            .await
            .expect("guest rules");
        assert_eq!(guest_visible_rules.len(), 1);
        assert_eq!(guest_visible_rules[0].title, "Guest Rule");

        assert!(
            repo.get_by_slug_for_user("friday-night-commander", member.id)
                .await
                .expect("get by slug")
                .is_some()
        );
    }
}

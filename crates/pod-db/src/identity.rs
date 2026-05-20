use time::OffsetDateTime;
use uuid::Uuid;

use sqlx::PgPool;

use crate::DbError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserRecord {
    pub id: Uuid,
    pub email: String,
    pub display_name: String,
    pub password_hash: String,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionRecord {
    pub id: Uuid,
    pub user_id: Uuid,
    pub token_hash: Vec<u8>,
    pub user_agent: Option<String>,
    pub created_at: OffsetDateTime,
    pub last_seen_at: OffsetDateTime,
    pub expires_at: OffsetDateTime,
    pub revoked_at: Option<OffsetDateTime>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AccountRecord {
    pub id: Uuid,
    pub user_id: Uuid,
    pub account_type: String,
    pub label: Option<String>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AuthIdentityRecord {
    pub id: Uuid,
    pub account_id: Uuid,
    pub provider: String,
    pub provider_subject: String,
    pub email: Option<String>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
    pub last_used_at: Option<OffsetDateTime>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserPreferencesRecord {
    pub user_id: Uuid,
    pub locale: String,
    pub timezone: String,
    pub date_time_format: String,
    pub updated_at: OffsetDateTime,
}

pub struct IdentityRepository<'a> {
    pool: &'a PgPool,
}

impl<'a> IdentityRepository<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }

    pub async fn create_user(
        &self,
        email: &str,
        display_name: &str,
        password_hash: &str,
    ) -> Result<UserRecord, DbError> {
        let mut tx = self.pool.begin().await?;
        let user = sqlx::query_as!(
            UserRecord,
            r#"
            insert into core.users (email, display_name, password_hash)
            values (lower($1), $2, $3)
            returning id, email, display_name, password_hash, created_at, updated_at
            "#,
            email,
            display_name,
            password_hash
        )
        .fetch_one(&mut *tx)
        .await?;

        let account = sqlx::query_as!(
            AccountRecord,
            r#"
            insert into core.accounts (user_id, account_type, label)
            values ($1, 'password', 'Email password')
            returning id, user_id, account_type, label, created_at, updated_at
            "#,
            user.id
        )
        .fetch_one(&mut *tx)
        .await?;

        sqlx::query_as!(
            AuthIdentityRecord,
            r#"
            insert into core.auth_identities (account_id, provider, provider_subject, email)
            values ($1, 'email', lower($2), lower($2))
            returning id, account_id, provider, provider_subject, email, created_at, updated_at, last_used_at
            "#,
            account.id,
            email
        )
        .fetch_one(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(user)
    }

    pub async fn find_user_by_email(&self, email: &str) -> Result<Option<UserRecord>, DbError> {
        let user = sqlx::query_as!(
            UserRecord,
            r#"
            select id, email, display_name, password_hash, created_at, updated_at
            from core.users
            where email = lower($1)
            "#,
            email
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(user)
    }

    pub async fn find_user_by_id(&self, user_id: Uuid) -> Result<Option<UserRecord>, DbError> {
        let user = sqlx::query_as!(
            UserRecord,
            r#"
            select id, email, display_name, password_hash, created_at, updated_at
            from core.users
            where id = $1
            "#,
            user_id
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(user)
    }

    pub async fn find_account_for_user(
        &self,
        user_id: Uuid,
    ) -> Result<Option<AccountRecord>, DbError> {
        let account = sqlx::query_as!(
            AccountRecord,
            r#"
            select id, user_id, account_type, label, created_at, updated_at
            from core.accounts
            where user_id = $1
            order by created_at asc
            limit 1
            "#,
            user_id
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(account)
    }

    pub async fn find_auth_identity(
        &self,
        provider: &str,
        provider_subject: &str,
    ) -> Result<Option<AuthIdentityRecord>, DbError> {
        let identity = sqlx::query_as!(
            AuthIdentityRecord,
            r#"
            select id, account_id, provider, provider_subject, email, created_at, updated_at, last_used_at
            from core.auth_identities
            where provider = $1
              and provider_subject = lower($2)
            "#,
            provider,
            provider_subject
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(identity)
    }

    pub async fn get_user_preferences(
        &self,
        user_id: Uuid,
    ) -> Result<Option<UserPreferencesRecord>, DbError> {
        let preferences = sqlx::query_as!(
            UserPreferencesRecord,
            r#"
            select id as user_id, locale, timezone, date_time_format, updated_at
            from core.users
            where id = $1
            "#,
            user_id
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(preferences)
    }

    pub async fn update_user_preferences(
        &self,
        user_id: Uuid,
        locale: &str,
        timezone: &str,
        date_time_format: &str,
    ) -> Result<Option<UserPreferencesRecord>, DbError> {
        let preferences = sqlx::query_as!(
            UserPreferencesRecord,
            r#"
            update core.users
            set locale = $2,
                timezone = $3,
                date_time_format = $4,
                updated_at = now()
            where id = $1
            returning id as user_id, locale, timezone, date_time_format, updated_at
            "#,
            user_id,
            locale,
            timezone,
            date_time_format
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(preferences)
    }

    pub async fn create_session(
        &self,
        user_id: Uuid,
        token_hash: &[u8],
        user_agent: Option<&str>,
        expires_at: OffsetDateTime,
    ) -> Result<SessionRecord, DbError> {
        let session = sqlx::query_as!(
            SessionRecord,
            r#"
            insert into core.sessions (user_id, token_hash, user_agent, expires_at)
            values ($1, $2, $3, $4)
            returning id, user_id, token_hash, user_agent, created_at, last_seen_at, expires_at, revoked_at
            "#,
            user_id,
            token_hash,
            user_agent,
            expires_at
        )
        .fetch_one(self.pool)
        .await?;

        Ok(session)
    }

    pub async fn find_active_session_by_token_hash(
        &self,
        token_hash: &[u8],
    ) -> Result<Option<SessionRecord>, DbError> {
        let session = sqlx::query_as!(
            SessionRecord,
            r#"
            select id, user_id, token_hash, user_agent, created_at, last_seen_at, expires_at, revoked_at
            from core.sessions
            where token_hash = $1
              and revoked_at is null
              and expires_at > now()
            "#,
            token_hash
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(session)
    }

    pub async fn touch_session(&self, session_id: Uuid) -> Result<Option<SessionRecord>, DbError> {
        let session = sqlx::query_as!(
            SessionRecord,
            r#"
            update core.sessions
            set last_seen_at = now()
            where id = $1
              and revoked_at is null
              and expires_at > now()
            returning id, user_id, token_hash, user_agent, created_at, last_seen_at, expires_at, revoked_at
            "#,
            session_id
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(session)
    }

    pub async fn revoke_session(&self, session_id: Uuid) -> Result<bool, DbError> {
        let row = sqlx::query!(
            r#"
            update core.sessions
            set revoked_at = now()
            where id = $1
              and revoked_at is null
            returning id
            "#,
            session_id
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(row.is_some())
    }

    pub async fn revoke_session_by_token_hash(&self, token_hash: &[u8]) -> Result<bool, DbError> {
        let row = sqlx::query!(
            r#"
            update core.sessions
            set revoked_at = now()
            where token_hash = $1
              and revoked_at is null
            returning id
            "#,
            token_hash
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(row.is_some())
    }
}

#[cfg(test)]
mod tests {
    use time::{Duration, OffsetDateTime};

    use super::IdentityRepository;

    #[sqlx::test(migrations = "./migrations")]
    async fn creates_finds_touches_and_revokes_session(pool: sqlx::PgPool) {
        let repo = IdentityRepository::new(&pool);
        let user = repo
            .create_user(
                "PLAYER@example.test",
                "Player One",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("create user");

        assert_eq!(user.email, "player@example.test");
        let account = repo
            .find_account_for_user(user.id)
            .await
            .expect("find account")
            .expect("account exists");
        assert_eq!(account.account_type, "password");
        assert_eq!(
            repo.find_auth_identity("email", "PLAYER@example.test")
                .await
                .expect("find auth identity")
                .expect("auth identity exists")
                .account_id,
            account.id
        );
        assert_eq!(
            repo.find_user_by_email("player@example.test")
                .await
                .expect("find user")
                .expect("user exists")
                .id,
            user.id
        );

        let token_hash = [7_u8; 32];
        let expires_at = OffsetDateTime::now_utc() + Duration::hours(1);
        let session = repo
            .create_session(user.id, &token_hash, Some("pod-db-test"), expires_at)
            .await
            .expect("create session");

        assert_eq!(session.user_id, user.id);
        assert_eq!(session.token_hash, token_hash);

        let touched = repo
            .touch_session(session.id)
            .await
            .expect("touch session")
            .expect("active session");
        assert!(touched.last_seen_at >= session.last_seen_at);

        assert!(
            repo.find_active_session_by_token_hash(&token_hash)
                .await
                .expect("find active session")
                .is_some()
        );
        assert!(
            repo.revoke_session(session.id)
                .await
                .expect("revoke session")
        );
        assert!(
            repo.find_active_session_by_token_hash(&token_hash)
                .await
                .expect("find revoked session")
                .is_none()
        );

        let second_token_hash = [8_u8; 32];
        let session = repo
            .create_session(user.id, &second_token_hash, Some("pod-db-test"), expires_at)
            .await
            .expect("create second session");
        assert_eq!(session.user_id, user.id);
        assert!(
            repo.revoke_session_by_token_hash(&second_token_hash)
                .await
                .expect("revoke second session")
        );
    }

    #[sqlx::test(migrations = "./migrations")]
    async fn stores_user_locale_timezone_and_display_preferences(pool: sqlx::PgPool) {
        let repo = IdentityRepository::new(&pool);
        let user = repo
            .create_user(
                "preferences@example.test",
                "Preference Player",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("create user");

        let defaults = repo
            .get_user_preferences(user.id)
            .await
            .expect("get preferences")
            .expect("preferences");
        assert_eq!(defaults.locale, "en-US");
        assert_eq!(defaults.timezone, "UTC");
        assert_eq!(defaults.date_time_format, "locale_default");

        let updated = repo
            .update_user_preferences(user.id, "en-US", "America/New_York", "iso_24h")
            .await
            .expect("update preferences")
            .expect("preferences");
        assert_eq!(updated.locale, "en-US");
        assert_eq!(updated.timezone, "America/New_York");
        assert_eq!(updated.date_time_format, "iso_24h");
        assert!(updated.updated_at >= defaults.updated_at);
    }
}

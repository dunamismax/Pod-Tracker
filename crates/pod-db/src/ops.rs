use serde_json::json;
use sqlx::PgPool;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::{DbError, META_DASHBOARD_REFRESH_JOB_TYPE};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BackgroundJobRecord {
    pub id: Uuid,
    pub queue: String,
    pub job_type: String,
    pub payload: serde_json::Value,
    pub run_at: OffsetDateTime,
    pub locked_at: Option<OffsetDateTime>,
    pub locked_by: Option<String>,
    pub attempts: i32,
    pub max_attempts: i32,
    pub last_error: Option<String>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EmailDeliveryRecord {
    pub id: Uuid,
    pub to_address: String,
    pub subject: String,
    pub body_text: Option<String>,
    pub body_html: Option<String>,
    pub status: String,
    pub error_message: Option<String>,
    pub sent_at: Option<OffsetDateTime>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, Copy)]
pub struct EmailDeliveryInput<'a> {
    pub to_address: &'a str,
    pub subject: &'a str,
    pub body_text: Option<&'a str>,
    pub body_html: Option<&'a str>,
}

#[derive(Debug, Clone, Copy)]
pub struct BackgroundJobInput<'a> {
    pub queue: &'a str,
    pub job_type: &'a str,
    pub payload: &'a serde_json::Value,
    pub run_at: OffsetDateTime,
}

pub struct OpsRepository<'a> {
    pool: &'a PgPool,
}

impl<'a> OpsRepository<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }

    #[tracing::instrument(
        name = "db.operation",
        skip_all,
        fields(db.system = "postgresql", db.repository = "ops", db.operation = "insert_email_delivery")
    )]
    pub async fn insert_email_delivery(
        &self,
        input: EmailDeliveryInput<'_>,
    ) -> Result<EmailDeliveryRecord, DbError> {
        let delivery = sqlx::query_as!(
            EmailDeliveryRecord,
            r#"
            insert into ops.email_deliveries (
              to_address, subject, body_text, body_html
            )
            values ($1, $2, $3, $4)
            returning id, to_address, subject, body_text, body_html, status,
              error_message, sent_at, created_at, updated_at
            "#,
            input.to_address,
            input.subject,
            input.body_text,
            input.body_html,
        )
        .fetch_one(self.pool)
        .await?;

        Ok(delivery)
    }

    #[tracing::instrument(
        name = "db.operation",
        skip_all,
        fields(db.system = "postgresql", db.repository = "ops", db.operation = "get_email_delivery")
    )]
    pub async fn get_email_delivery(
        &self,
        id: Uuid,
    ) -> Result<Option<EmailDeliveryRecord>, DbError> {
        let delivery = sqlx::query_as!(
            EmailDeliveryRecord,
            r#"
            select id, to_address, subject, body_text, body_html, status,
              error_message, sent_at, created_at, updated_at
            from ops.email_deliveries
            where id = $1
            "#,
            id,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(delivery)
    }

    #[tracing::instrument(
        name = "db.operation",
        skip_all,
        fields(db.system = "postgresql", db.repository = "ops", db.operation = "update_email_delivery_status")
    )]
    pub async fn update_email_delivery_status(
        &self,
        id: Uuid,
        status: &str,
        error_message: Option<&str>,
    ) -> Result<EmailDeliveryRecord, DbError> {
        let delivery = sqlx::query_as!(
            EmailDeliveryRecord,
            r#"
            update ops.email_deliveries
            set status = $2,
                error_message = $3,
                sent_at = case when $2 = 'sent' then now() else sent_at end,
                updated_at = now()
            where id = $1
            returning id, to_address, subject, body_text, body_html, status,
              error_message, sent_at, created_at, updated_at
            "#,
            id,
            status,
            error_message,
        )
        .fetch_one(self.pool)
        .await?;

        Ok(delivery)
    }

    #[tracing::instrument(
        name = "db.operation",
        skip_all,
        fields(db.system = "postgresql", db.repository = "ops", db.operation = "insert_background_job")
    )]
    pub async fn insert_background_job(
        &self,
        input: BackgroundJobInput<'_>,
    ) -> Result<BackgroundJobRecord, DbError> {
        let job = sqlx::query_as!(
            BackgroundJobRecord,
            r#"
            insert into ops.background_jobs (
              queue, job_type, payload, run_at
            )
            values ($1, $2, $3, $4)
            returning id, queue, job_type, payload, run_at, locked_at,
              locked_by, attempts, max_attempts, last_error, created_at, updated_at
            "#,
            input.queue,
            input.job_type,
            input.payload,
            input.run_at,
        )
        .fetch_one(self.pool)
        .await?;

        Ok(job)
    }

    #[tracing::instrument(
        name = "db.operation",
        skip_all,
        fields(db.system = "postgresql", db.repository = "ops", db.operation = "enqueue_email_delivery")
    )]
    pub async fn enqueue_email_delivery(
        &self,
        input: EmailDeliveryInput<'_>,
        run_at: OffsetDateTime,
    ) -> Result<(EmailDeliveryRecord, BackgroundJobRecord), DbError> {
        let mut tx = self.pool.begin().await?;
        let delivery = sqlx::query_as!(
            EmailDeliveryRecord,
            r#"
            insert into ops.email_deliveries (
              to_address, subject, body_text, body_html
            )
            values ($1, $2, $3, $4)
            returning id, to_address, subject, body_text, body_html, status,
              error_message, sent_at, created_at, updated_at
            "#,
            input.to_address,
            input.subject,
            input.body_text,
            input.body_html,
        )
        .fetch_one(&mut *tx)
        .await?;

        let payload = json!({ "email_delivery_id": delivery.id });
        let job = sqlx::query_as!(
            BackgroundJobRecord,
            r#"
            insert into ops.background_jobs (
              queue, job_type, payload, run_at
            )
            values ('default', 'send_email', $1, $2)
            returning id, queue, job_type, payload, run_at, locked_at,
              locked_by, attempts, max_attempts, last_error, created_at, updated_at
            "#,
            payload,
            run_at,
        )
        .fetch_one(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok((delivery, job))
    }

    #[tracing::instrument(
        name = "db.operation",
        skip_all,
        fields(db.system = "postgresql", db.repository = "ops", db.operation = "enqueue_scryfall_bulk_import")
    )]
    pub async fn enqueue_scryfall_bulk_import(
        &self,
        bulk_type: &str,
        run_at: OffsetDateTime,
    ) -> Result<BackgroundJobRecord, DbError> {
        let payload = json!({ "bulk_type": bulk_type });
        self.insert_background_job(BackgroundJobInput {
            queue: "default",
            job_type: "scryfall_bulk_import",
            payload: &payload,
            run_at,
        })
        .await
    }

    #[tracing::instrument(
        name = "db.operation",
        skip_all,
        fields(db.system = "postgresql", db.repository = "ops", db.operation = "enqueue_meta_dashboard_refresh")
    )]
    pub async fn enqueue_meta_dashboard_refresh(
        &self,
        run_at: OffsetDateTime,
    ) -> Result<BackgroundJobRecord, DbError> {
        let payload = json!({});
        self.insert_background_job(BackgroundJobInput {
            queue: "default",
            job_type: META_DASHBOARD_REFRESH_JOB_TYPE,
            payload: &payload,
            run_at,
        })
        .await
    }

    #[tracing::instrument(
        name = "db.operation",
        skip_all,
        fields(db.system = "postgresql", db.repository = "ops", db.operation = "acquire_next_background_job")
    )]
    pub async fn acquire_next_background_job(
        &self,
        worker_id: &str,
        queue: &str,
    ) -> Result<Option<BackgroundJobRecord>, DbError> {
        let job = sqlx::query_as!(
            BackgroundJobRecord,
            r#"
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
              locked_by, attempts, max_attempts, last_error, created_at, updated_at
            "#,
            worker_id,
            queue,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(job)
    }

    #[tracing::instrument(
        name = "db.operation",
        skip_all,
        fields(db.system = "postgresql", db.repository = "ops", db.operation = "complete_background_job")
    )]
    pub async fn complete_background_job(&self, id: Uuid) -> Result<(), DbError> {
        sqlx::query!(
            r#"
            delete from ops.background_jobs
            where id = $1
            "#,
            id,
        )
        .execute(self.pool)
        .await?;

        Ok(())
    }

    #[tracing::instrument(
        name = "db.operation",
        skip_all,
        fields(db.system = "postgresql", db.repository = "ops", db.operation = "fail_background_job")
    )]
    pub async fn fail_background_job(&self, id: Uuid, last_error: &str) -> Result<(), DbError> {
        sqlx::query!(
            r#"
            update ops.background_jobs
            set locked_at = null,
                locked_by = null,
                last_error = $2,
                run_at = now() + (pow(2, attempts) * interval '1 minute'),
                updated_at = now()
            where id = $1
            "#,
            id,
            last_error,
        )
        .execute(self.pool)
        .await?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::{EmailDeliveryInput, OpsRepository};

    #[sqlx::test(migrations = "./migrations")]
    async fn queues_claims_updates_and_completes_email_jobs(pool: sqlx::PgPool) {
        let repo = OpsRepository::new(&pool);
        let (delivery, job) = repo
            .enqueue_email_delivery(
                EmailDeliveryInput {
                    to_address: "player@example.test",
                    subject: "Commander night reminder",
                    body_text: Some("Pods start soon."),
                    body_html: None,
                },
                time::OffsetDateTime::now_utc(),
            )
            .await
            .expect("queue email");

        assert_eq!(delivery.status, "pending");
        assert_eq!(job.job_type, "send_email");
        assert_eq!(
            job.payload["email_delivery_id"],
            serde_json::Value::String(delivery.id.to_string())
        );

        let claimed = repo
            .acquire_next_background_job("worker-test", "default")
            .await
            .expect("claim job")
            .expect("job should be due");
        assert_eq!(claimed.id, job.id);
        assert_eq!(claimed.locked_by.as_deref(), Some("worker-test"));
        assert_eq!(claimed.attempts, 1);

        let failed = repo
            .update_email_delivery_status(delivery.id, "failed", Some("smtp unavailable"))
            .await
            .expect("mark failed");
        assert_eq!(failed.status, "failed");
        assert_eq!(failed.error_message.as_deref(), Some("smtp unavailable"));

        repo.fail_background_job(claimed.id, "smtp unavailable")
            .await
            .expect("fail job");
        let retried = sqlx::query!(
            r#"
            select locked_at, locked_by, attempts, last_error
            from ops.background_jobs
            where id = $1
            "#,
            claimed.id,
        )
        .fetch_one(&pool)
        .await
        .expect("fetch retry");
        assert!(retried.locked_at.is_none());
        assert!(retried.locked_by.is_none());
        assert_eq!(retried.attempts, 1);
        assert_eq!(retried.last_error.as_deref(), Some("smtp unavailable"));

        repo.complete_background_job(claimed.id)
            .await
            .expect("complete job");
        assert!(
            repo.acquire_next_background_job("worker-test", "default")
                .await
                .expect("claim none")
                .is_none()
        );
    }

    #[sqlx::test(migrations = "./migrations")]
    async fn queues_scryfall_bulk_import_jobs(pool: sqlx::PgPool) {
        let repo = OpsRepository::new(&pool);
        let job = repo
            .enqueue_scryfall_bulk_import("default_cards", time::OffsetDateTime::now_utc())
            .await
            .expect("queue import");

        assert_eq!(job.queue, "default");
        assert_eq!(job.job_type, "scryfall_bulk_import");
        assert_eq!(job.payload["bulk_type"], "default_cards");
    }

    #[sqlx::test(migrations = "./migrations")]
    async fn queues_meta_dashboard_refresh_jobs(pool: sqlx::PgPool) {
        let repo = OpsRepository::new(&pool);
        let job = repo
            .enqueue_meta_dashboard_refresh(time::OffsetDateTime::now_utc())
            .await
            .expect("queue refresh");

        assert_eq!(job.queue, "default");
        assert_eq!(job.job_type, "meta_dashboard_refresh");
        assert_eq!(job.payload, serde_json::json!({}));
    }
}

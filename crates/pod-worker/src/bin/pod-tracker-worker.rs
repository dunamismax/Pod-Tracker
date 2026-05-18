use std::time::Duration;

use anyhow::Context;
use pod_core::config::AppConfig;
use pod_db::{BackgroundJobRecord, MetaRepository, OpsRepository, ScryfallRepository};
use pod_worker::{
    META_DASHBOARD_REFRESH_JOB_TYPE, SCRYFALL_BULK_IMPORT_JOB_TYPE, ScryfallBulkClient,
    process_meta_dashboard_refresh_job, process_scryfall_bulk_import_job,
};
use serde::{Deserialize, Serialize};
use tokio::time;
use uuid::Uuid;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::dotenv();
    let config = AppConfig::from_env();
    init_tracing();

    let db = pod_db::connect(config.database_url.as_deref())
        .await
        .context("connect database")?;

    tracing::info!(
        environment = %config.environment,
        database_configured = config.database_configured(),
        "pod_tracker_worker_starting"
    );

    let worker_id = worker_id();
    let email_client = Smtp2GoClient::new(config.smtp2go_api_key.clone(), config.smtp_sender);
    let scryfall_client = ScryfallBulkClient::new();
    let mut ticker = time::interval(Duration::from_secs(5));
    loop {
        tokio::select! {
            _ = shutdown_signal() => {
                tracing::info!("pod_tracker_worker_stopping");
                return Ok(());
            }
            _ = ticker.tick() => {
                if let Some(pool) = db.as_ref()
                    && let Err(err) = pod_db::check_database(pool).await
                {
                    tracing::warn!(err = %err, "worker database check failed");
                }
                if let Some(pool) = db.as_ref()
                    && let Err(err) = process_due_jobs(pool, &OpsRepository::new(pool), &email_client, &scryfall_client, &worker_id).await
                {
                    tracing::error!(err = %err, "worker job processing failed");
                }
            }
        }
    }
}

async fn process_due_jobs(
    pool: &sqlx::PgPool,
    ops: &OpsRepository<'_>,
    email_client: &Smtp2GoClient,
    scryfall_client: &ScryfallBulkClient,
    worker_id: &str,
) -> anyhow::Result<()> {
    loop {
        let Some(job) = ops
            .acquire_next_background_job(worker_id, "default")
            .await
            .context("acquire background job")?
        else {
            return Ok(());
        };

        tracing::info!(job_id = %job.id, job_type = %job.job_type, "worker_job_claimed");
        let scryfall_repo = ScryfallRepository::new(pool);
        let meta_repo = MetaRepository::new(pool);
        let result = process_job(
            ops,
            &scryfall_repo,
            &meta_repo,
            email_client,
            scryfall_client,
            &job,
        )
        .await;
        match result {
            Ok(()) => {
                ops.complete_background_job(job.id)
                    .await
                    .context("complete background job")?;
                tracing::info!(job_id = %job.id, "worker_job_completed");
            }
            Err(err) => {
                ops.fail_background_job(job.id, &err.to_string())
                    .await
                    .context("fail background job")?;
                tracing::warn!(job_id = %job.id, err = %err, "worker_job_failed");
            }
        }
    }
}

async fn process_job(
    ops: &OpsRepository<'_>,
    scryfall_repo: &ScryfallRepository<'_>,
    meta_repo: &MetaRepository<'_>,
    email_client: &Smtp2GoClient,
    scryfall_client: &ScryfallBulkClient,
    job: &BackgroundJobRecord,
) -> anyhow::Result<()> {
    match job.job_type.as_str() {
        "send_email" => process_send_email_job(ops, email_client, job).await,
        SCRYFALL_BULK_IMPORT_JOB_TYPE => {
            let import = process_scryfall_bulk_import_job(scryfall_repo, scryfall_client, job)
                .await
                .context("process Scryfall bulk import")?;
            tracing::info!(
                import_id = %import.id,
                bulk_type = %import.bulk_type,
                cards_imported = import.cards_imported,
                "scryfall_bulk_import_completed"
            );
            Ok(())
        }
        META_DASHBOARD_REFRESH_JOB_TYPE => {
            process_meta_dashboard_refresh_job(meta_repo)
                .await
                .context("process meta dashboard refresh")?;
            tracing::info!(job_id = %job.id, "meta_dashboard_refresh_completed");
            Ok(())
        }
        other => anyhow::bail!("unknown job type: {other}"),
    }
}

#[derive(Debug, Deserialize)]
struct SendEmailPayload {
    email_delivery_id: Uuid,
}

async fn process_send_email_job(
    ops: &OpsRepository<'_>,
    email_client: &Smtp2GoClient,
    job: &BackgroundJobRecord,
) -> anyhow::Result<()> {
    let payload: SendEmailPayload =
        serde_json::from_value(job.payload.clone()).context("parse send_email payload")?;
    let delivery = ops
        .get_email_delivery(payload.email_delivery_id)
        .await
        .context("get email delivery")?
        .context("email delivery not found")?;

    let send_result = email_client
        .send(
            &delivery.to_address,
            &delivery.subject,
            delivery.body_text.as_deref().unwrap_or(""),
            delivery.body_html.as_deref().unwrap_or(""),
        )
        .await;

    match send_result {
        Ok(()) => {
            ops.update_email_delivery_status(delivery.id, "sent", None)
                .await
                .context("mark email sent")?;
            Ok(())
        }
        Err(err) => {
            let err_msg = err.to_string();
            ops.update_email_delivery_status(delivery.id, "failed", Some(&err_msg))
                .await
                .context("mark email failed")?;
            Err(err)
        }
    }
}

#[derive(Clone)]
struct Smtp2GoClient {
    api_key: Option<String>,
    sender: String,
    http: reqwest::Client,
}

impl Smtp2GoClient {
    fn new(api_key: Option<String>, sender: String) -> Self {
        Self {
            api_key,
            sender,
            http: reqwest::Client::builder()
                .timeout(Duration::from_secs(10))
                .build()
                .expect("build HTTP client"),
        }
    }

    async fn send(
        &self,
        to: &str,
        subject: &str,
        text_body: &str,
        html_body: &str,
    ) -> anyhow::Result<()> {
        let api_key = self
            .api_key
            .as_deref()
            .filter(|key| !key.is_empty())
            .context("smtp2go api key not configured")?;

        let payload = Smtp2GoPayload {
            api_key,
            to: vec![to],
            sender: &self.sender,
            subject,
            text_body,
            html_body: if html_body.is_empty() {
                None
            } else {
                Some(html_body)
            },
        };

        let response = self
            .http
            .post("https://api.smtp2go.com/v3/email/send")
            .json(&payload)
            .send()
            .await
            .context("send smtp2go request")?;

        if response.status().is_client_error() || response.status().is_server_error() {
            anyhow::bail!("smtp2go error: status {}", response.status());
        }

        Ok(())
    }
}

#[derive(Serialize)]
struct Smtp2GoPayload<'a> {
    api_key: &'a str,
    to: Vec<&'a str>,
    sender: &'a str,
    subject: &'a str,
    text_body: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    html_body: Option<&'a str>,
}

fn worker_id() -> String {
    let host = std::env::var("HOSTNAME").unwrap_or_else(|_| "local".to_owned());
    format!("{host}-{}", std::process::id())
}

fn init_tracing() {
    let _ = tracing_subscriber::fmt()
        .json()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "pod_worker=info,pod_db=info".into()),
        )
        .try_init();
}

async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
}

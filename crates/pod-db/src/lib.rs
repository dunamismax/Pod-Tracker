use std::time::Duration;

use sqlx::postgres::PgPoolOptions;
use sqlx::{Executor, PgPool, Postgres, Transaction};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum DbError {
    #[error("database URL is not configured")]
    MissingDatabaseUrl,
    #[error("database error: {0}")]
    Sqlx(#[from] sqlx::Error),
}

pub async fn connect(database_url: Option<&str>) -> Result<Option<PgPool>, DbError> {
    let Some(database_url) = database_url else {
        return Ok(None);
    };

    let pool = PgPoolOptions::new()
        .max_connections(10)
        .acquire_timeout(Duration::from_secs(5))
        .connect(database_url)
        .await?;

    check_database(&pool).await?;
    Ok(Some(pool))
}

pub async fn check_database(pool: &PgPool) -> Result<(), DbError> {
    let value: i64 = sqlx::query_scalar("select 1::bigint")
        .fetch_one(pool)
        .await?;
    if value == 1 {
        Ok(())
    } else {
        Err(sqlx::Error::RowNotFound.into())
    }
}

pub async fn with_tx<T, F>(pool: &PgPool, f: F) -> Result<T, DbError>
where
    for<'tx> F: AsyncFnOnce(&'tx mut Transaction<'_, Postgres>) -> Result<T, DbError>,
{
    let mut tx = pool.begin().await?;
    let output = f(&mut tx).await?;
    tx.commit().await?;
    Ok(output)
}

pub async fn migrations_table_exists(pool: &PgPool) -> Result<bool, DbError> {
    let exists: bool = sqlx::query_scalar(
        r#"
        select exists (
          select 1
          from information_schema.tables
          where table_schema = 'public'
            and table_name in ('goose_db_version', '_sqlx_migrations')
        )
        "#,
    )
    .fetch_one(pool)
    .await?;

    Ok(exists)
}

pub async fn table_exists(pool: &PgPool, table_name: &str) -> Result<bool, DbError> {
    let exists: bool = sqlx::query_scalar(
        r#"
        select exists (
          select 1
          from information_schema.tables
          where table_schema = 'public'
            and table_name = $1
        )
        "#,
    )
    .bind(table_name)
    .fetch_one(pool)
    .await?;

    Ok(exists)
}

pub async fn run_migrations(pool: &PgPool) -> Result<(), sqlx::migrate::MigrateError> {
    sqlx::migrate!("../../migrations").run(pool).await
}

pub async fn set_application_name<'c, E>(executor: E) -> Result<(), DbError>
where
    E: Executor<'c, Database = Postgres>,
{
    executor
        .execute("set application_name = 'pod_tracker_rust'")
        .await?;
    Ok(())
}

use anyhow::{Context, bail};
use sqlx::postgres::PgPoolOptions;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::dotenv();
    let command = std::env::args().nth(1).unwrap_or_else(|| "up".to_owned());
    let database_url = migration_database_url()?;

    let pool = PgPoolOptions::new()
        .max_connections(1)
        .connect(&database_url)
        .await
        .context("connect migration database")?;

    match command.as_str() {
        "up" => {
            pod_db::run_migrations(&pool)
                .await
                .context("run sqlx migrations")?;
            println!("migrations applied");
        }
        "status" => print_status(&pool).await?,
        other => bail!("unknown migration command {other:?}; expected up or status"),
    }

    Ok(())
}

fn migration_database_url() -> anyhow::Result<String> {
    std::env::var("POD_TRACKER_MIGRATION_DATABASE_URL")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .or_else(|| {
            std::env::var("POD_TRACKER_DATABASE_URL")
                .ok()
                .filter(|value| !value.trim().is_empty())
        })
        .context("POD_TRACKER_MIGRATION_DATABASE_URL or POD_TRACKER_DATABASE_URL is required")
}

async fn print_status(pool: &sqlx::PgPool) -> anyhow::Result<()> {
    let table_exists: bool = sqlx::query_scalar(
        r#"
        select exists (
          select 1
          from information_schema.tables
          where table_schema = 'public'
            and table_name = '_sqlx_migrations'
        )
        "#,
    )
    .fetch_one(pool)
    .await
    .context("check migration table")?;

    if !table_exists {
        println!("no sqlx migrations table found");
        return Ok(());
    }

    let rows = sqlx::query_as::<_, (i64, String, bool)>(
        r#"
        select version, description, success
        from _sqlx_migrations
        order by version
        "#,
    )
    .fetch_all(pool)
    .await
    .context("read migration status")?;

    for (version, description, success) in rows {
        println!(
            "{version}\t{description}\t{}",
            if success { "ok" } else { "failed" }
        );
    }

    Ok(())
}

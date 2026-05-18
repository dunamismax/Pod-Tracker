use std::time::Duration;

use sqlx::postgres::PgPoolOptions;
use sqlx::{Executor, PgPool, Postgres, Transaction};
use thiserror::Error;

pub mod decks;
pub mod events;
pub mod games;
pub mod health;
pub mod identity;
pub mod migrations;
pub mod ops;
pub mod playgroups;
pub mod pods;

pub use decks::{
    CreateDeckInput, DeckRecord, DeckRepository, EventDeckDeclarationInput,
    EventDeckDeclarationRecord, EventDeckDeclarationWithDeck,
};
pub use events::{
    CalendarEventRecord, CreateEventInput, CreateEventReminderInput, EventHostRecord,
    EventLocationInput, EventLocationRecord, EventRecord, EventReminderRecord, EventRepository,
    EventRsvpRecord, EventWithRole, RsvpInput, UpdateEventInput,
};
pub use games::{
    GamePlayerRecord, GameRecord, GameRepository, GameResultRecord, GameWithPlayers, LogGameInput,
};
pub use health::HealthRepository;
pub use identity::{
    AccountRecord, AuthIdentityRecord, IdentityRepository, SessionRecord, UserRecord,
};
pub use ops::{
    BackgroundJobInput, BackgroundJobRecord, EmailDeliveryInput, EmailDeliveryRecord, OpsRepository,
};
pub use playgroups::{
    CreateInvite, HouseRuleRecord, MembershipRecord, PlaygroupInviteRecord, PlaygroupRecord,
    PlaygroupRepository, PlaygroupSettingsRecord, PlaygroupWithRole,
};
pub use pods::{PodGenerationSummary, PodRecord, PodRepository, PodSeatRecord, PodWithSeats};

#[derive(Debug, Error)]
pub enum DbError {
    #[error("database URL is not configured")]
    MissingDatabaseUrl,
    #[error("database error: {0}")]
    Sqlx(#[from] sqlx::Error),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PoolConfig {
    pub max_connections: u32,
    pub acquire_timeout: Duration,
}

impl Default for PoolConfig {
    fn default() -> Self {
        Self {
            max_connections: 10,
            acquire_timeout: Duration::from_secs(5),
        }
    }
}

pub async fn connect(database_url: Option<&str>) -> Result<Option<PgPool>, DbError> {
    connect_with_config(database_url, PoolConfig::default()).await
}

pub async fn connect_with_config(
    database_url: Option<&str>,
    config: PoolConfig,
) -> Result<Option<PgPool>, DbError> {
    let Some(database_url) = database_url else {
        return Ok(None);
    };

    let pool = PgPoolOptions::new()
        .max_connections(config.max_connections)
        .acquire_timeout(config.acquire_timeout)
        .connect(database_url)
        .await?;

    check_database(&pool).await?;
    Ok(Some(pool))
}

pub async fn check_database(pool: &PgPool) -> Result<(), DbError> {
    HealthRepository::new(pool).ping().await
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
    HealthRepository::new(pool).migrations_table_exists().await
}

pub async fn table_exists(pool: &PgPool, table_name: &str) -> Result<bool, DbError> {
    HealthRepository::new(pool).table_exists(table_name).await
}

pub async fn run_migrations(pool: &PgPool) -> Result<(), sqlx::migrate::MigrateError> {
    migrations::run(pool).await
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

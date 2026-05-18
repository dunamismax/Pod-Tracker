use sqlx::PgPool;

use crate::DbError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TablePresence {
    pub table_schema: String,
    pub table_name: String,
}

pub struct HealthRepository<'a> {
    pool: &'a PgPool,
}

impl<'a> HealthRepository<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }

    pub async fn ping(&self) -> Result<(), DbError> {
        let row = sqlx::query!("select 1::bigint as \"value!\"")
            .fetch_one(self.pool)
            .await?;

        if row.value == 1 {
            Ok(())
        } else {
            Err(sqlx::Error::RowNotFound.into())
        }
    }

    pub async fn migrations_table_exists(&self) -> Result<bool, DbError> {
        let row = sqlx::query!(
            r#"
            select exists (
              select 1
              from information_schema.tables
              where table_schema = 'public'
                and table_name in ('goose_db_version', '_sqlx_migrations')
            ) as "exists!"
            "#
        )
        .fetch_one(self.pool)
        .await?;

        Ok(row.exists)
    }

    pub async fn table_exists(&self, table_name: &str) -> Result<bool, DbError> {
        let row = sqlx::query!(
            r#"
            select exists (
              select 1
              from information_schema.tables
              where table_schema = 'public'
                and table_name = $1
            ) as "exists!"
            "#,
            table_name
        )
        .fetch_one(self.pool)
        .await?;

        Ok(row.exists)
    }

    pub async fn schema_table_exists(
        &self,
        table_schema: &str,
        table_name: &str,
    ) -> Result<bool, DbError> {
        let row = sqlx::query!(
            r#"
            select exists (
              select 1
              from information_schema.tables
              where table_schema = $1
                and table_name = $2
            ) as "exists!"
            "#,
            table_schema,
            table_name
        )
        .fetch_one(self.pool)
        .await?;

        Ok(row.exists)
    }

    pub async fn first_missing_readiness_check(&self) -> Result<Option<&'static str>, DbError> {
        if !self.migrations_table_exists().await? {
            return Ok(Some("migrations"));
        }

        for (check, schema, table) in [
            ("identity_tables", "core", "users"),
            ("job_tables", "ops", "background_jobs"),
            ("email_tables", "ops", "email_deliveries"),
        ] {
            if !self.schema_table_exists(schema, table).await? {
                return Ok(Some(check));
            }
        }

        Ok(None)
    }
}

#[cfg(test)]
mod tests {
    use super::HealthRepository;

    #[sqlx::test(migrations = "./migrations")]
    async fn reports_migration_and_schema_tables(pool: sqlx::PgPool) {
        let repo = HealthRepository::new(&pool);

        repo.ping().await.expect("database ping");
        assert!(
            repo.migrations_table_exists()
                .await
                .expect("migration table check")
        );
        assert!(
            repo.schema_table_exists("core", "users")
                .await
                .expect("core.users check")
        );
        for table in [
            "event_locations",
            "events",
            "event_hosts",
            "event_rsvps",
            "event_guests",
            "event_reminders",
            "decks",
            "event_deck_declarations",
        ] {
            assert!(
                repo.schema_table_exists("core", table)
                    .await
                    .expect("event table check"),
                "core.{table} should exist"
            );
        }
        assert!(
            repo.schema_table_exists("ops", "background_jobs")
                .await
                .expect("ops.background_jobs check")
        );
        assert!(
            repo.schema_table_exists("ops", "email_deliveries")
                .await
                .expect("ops.email_deliveries check")
        );
        assert_eq!(
            repo.first_missing_readiness_check()
                .await
                .expect("readiness checks"),
            None
        );
    }
}

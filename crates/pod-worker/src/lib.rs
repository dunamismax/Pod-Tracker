pub mod scryfall;

use anyhow::Context;
use pod_db::MetaRepository;

pub use pod_db::META_DASHBOARD_REFRESH_JOB_TYPE;
pub use scryfall::{
    SCRYFALL_BULK_IMPORT_JOB_TYPE, ScryfallBulkClient, ScryfallBulkMetadata,
    ScryfallImportJobPayload, import_scryfall_bulk_reader, parse_scryfall_import_payload,
    process_scryfall_bulk_import_from_reader, process_scryfall_bulk_import_job,
    select_bulk_metadata,
};

pub async fn process_meta_dashboard_refresh_job(repo: &MetaRepository<'_>) -> anyhow::Result<()> {
    repo.refresh_dashboard_views()
        .await
        .context("refresh meta dashboard materialized views")
}

#[cfg(test)]
mod tests {
    use super::process_meta_dashboard_refresh_job;

    #[sqlx::test(migrations = "../pod-db/migrations")]
    async fn processes_meta_dashboard_refresh_job(pool: sqlx::PgPool) {
        let repo = pod_db::MetaRepository::new(&pool);

        process_meta_dashboard_refresh_job(&repo)
            .await
            .expect("refresh meta views");
    }
}

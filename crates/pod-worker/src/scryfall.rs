use std::fmt;
use std::io::Read;
use std::time::Duration;

use anyhow::{Context, anyhow};
use pod_db::{BackgroundJobRecord, ScryfallImportInput, ScryfallImportRecord, ScryfallRepository};
use reqwest::header::{ACCEPT, HeaderValue};
use serde::Deserialize;
use serde::de::{self, Deserializer as _, SeqAccess, Visitor};
use serde_json::Value;
use tempfile::NamedTempFile;
use time::format_description::well_known::Rfc3339;
use tokio::io::AsyncWriteExt;

pub const SCRYFALL_BULK_IMPORT_JOB_TYPE: &str = "scryfall_bulk_import";
const DEFAULT_BULK_TYPE: &str = "default_cards";
const DEFAULT_BULK_DATA_URI: &str = "https://api.scryfall.com/bulk-data";
const SCRYFALL_ACCEPT: &str = "application/json;q=0.9,*/*;q=0.8";
const SCRYFALL_USER_AGENT: &str = "PodTracker/0.1 (+https://pod-tracker.app)";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScryfallImportJobPayload {
    pub bulk_type: String,
    pub bulk_data_uri: String,
}

#[derive(Debug, Deserialize)]
struct RawScryfallImportJobPayload {
    #[serde(default = "default_bulk_type")]
    bulk_type: String,
    #[serde(default = "default_bulk_data_uri")]
    bulk_data_uri: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ScryfallBulkMetadata {
    pub bulk_type: String,
    pub source_uri: String,
    pub download_uri: String,
    pub source_updated_at: time::OffsetDateTime,
    pub content_type: String,
    pub content_encoding: Option<String>,
    pub size_bytes: Option<i64>,
    pub raw_metadata: Value,
}

#[derive(Clone)]
pub struct ScryfallBulkClient {
    http: reqwest::Client,
}

impl ScryfallBulkClient {
    pub fn new() -> Self {
        let http = reqwest::Client::builder()
            .user_agent(SCRYFALL_USER_AGENT)
            .timeout(Duration::from_secs(900))
            .build()
            .expect("build Scryfall HTTP client");
        Self { http }
    }

    pub async fn fetch_bulk_catalog(&self, bulk_data_uri: &str) -> anyhow::Result<Value> {
        let response = self
            .http
            .get(bulk_data_uri)
            .header(ACCEPT, HeaderValue::from_static(SCRYFALL_ACCEPT))
            .send()
            .await
            .context("fetch Scryfall bulk metadata")?
            .error_for_status()
            .context("Scryfall bulk metadata status")?;

        response
            .json::<Value>()
            .await
            .context("decode Scryfall bulk metadata")
    }

    pub async fn download_bulk_file(&self, download_uri: &str) -> anyhow::Result<NamedTempFile> {
        let mut response = self
            .http
            .get(download_uri)
            .header(ACCEPT, HeaderValue::from_static(SCRYFALL_ACCEPT))
            .send()
            .await
            .context("download Scryfall bulk file")?
            .error_for_status()
            .context("Scryfall bulk download status")?;

        let temp = NamedTempFile::new().context("create Scryfall import temp file")?;
        let mut file =
            tokio::fs::File::from_std(temp.reopen().context("open Scryfall import temp file")?);

        while let Some(chunk) = response.chunk().await.context("read Scryfall bulk chunk")? {
            file.write_all(&chunk)
                .await
                .context("write Scryfall bulk chunk")?;
        }
        file.flush().await.context("flush Scryfall bulk file")?;
        drop(file);

        Ok(temp)
    }
}

impl Default for ScryfallBulkClient {
    fn default() -> Self {
        Self::new()
    }
}

pub fn parse_scryfall_import_payload(value: Value) -> anyhow::Result<ScryfallImportJobPayload> {
    let payload: RawScryfallImportJobPayload =
        serde_json::from_value(value).context("parse scryfall_bulk_import payload")?;
    let bulk_type = payload.bulk_type.trim();
    let bulk_data_uri = payload.bulk_data_uri.trim();

    if bulk_type.is_empty() {
        anyhow::bail!("scryfall bulk_type cannot be blank");
    }
    if bulk_data_uri.is_empty() {
        anyhow::bail!("scryfall bulk_data_uri cannot be blank");
    }
    if !bulk_data_uri.starts_with("https://") {
        anyhow::bail!("scryfall bulk_data_uri must use https");
    }

    Ok(ScryfallImportJobPayload {
        bulk_type: bulk_type.to_owned(),
        bulk_data_uri: bulk_data_uri.to_owned(),
    })
}

pub fn select_bulk_metadata(
    catalog: &Value,
    bulk_type: &str,
) -> anyhow::Result<ScryfallBulkMetadata> {
    let data = catalog
        .get("data")
        .and_then(Value::as_array)
        .context("Scryfall bulk catalog missing data array")?;
    let raw = data
        .iter()
        .find(|item| item.get("type").and_then(Value::as_str) == Some(bulk_type))
        .cloned()
        .with_context(|| format!("Scryfall bulk type not found: {bulk_type}"))?;

    let source_uri = required_str(&raw, "uri")?;
    let download_uri = required_str(&raw, "download_uri")?;
    if !source_uri.starts_with("https://") || !download_uri.starts_with("https://") {
        anyhow::bail!("Scryfall bulk metadata must use https URLs");
    }

    let updated_at = required_str(&raw, "updated_at")?;
    let source_updated_at = time::OffsetDateTime::parse(updated_at, &Rfc3339)
        .with_context(|| format!("parse Scryfall updated_at: {updated_at}"))?;

    Ok(ScryfallBulkMetadata {
        bulk_type: bulk_type.to_owned(),
        source_uri: source_uri.to_owned(),
        download_uri: download_uri.to_owned(),
        source_updated_at,
        content_type: raw
            .get("content_type")
            .and_then(Value::as_str)
            .unwrap_or("application/json")
            .to_owned(),
        content_encoding: raw
            .get("content_encoding")
            .and_then(Value::as_str)
            .filter(|value| !value.trim().is_empty())
            .map(ToOwned::to_owned),
        size_bytes: raw
            .get("size")
            .or_else(|| raw.get("compressed_size"))
            .and_then(Value::as_i64),
        raw_metadata: raw,
    })
}

pub async fn process_scryfall_bulk_import_job(
    repo: &ScryfallRepository<'_>,
    client: &ScryfallBulkClient,
    job: &BackgroundJobRecord,
) -> anyhow::Result<ScryfallImportRecord> {
    let payload = parse_scryfall_import_payload(job.payload.clone())?;
    let catalog = client.fetch_bulk_catalog(&payload.bulk_data_uri).await?;
    let metadata = select_bulk_metadata(&catalog, &payload.bulk_type)?;
    let temp = client.download_bulk_file(&metadata.download_uri).await?;
    let reader = temp
        .reopen()
        .context("open downloaded Scryfall bulk file")?;

    import_scryfall_bulk_reader(repo, metadata, reader).await
}

pub async fn process_scryfall_bulk_import_from_reader<R>(
    repo: &ScryfallRepository<'_>,
    job_payload: Value,
    catalog: &Value,
    reader: R,
) -> anyhow::Result<ScryfallImportRecord>
where
    R: Read + Send + 'static,
{
    let payload = parse_scryfall_import_payload(job_payload)?;
    let metadata = select_bulk_metadata(catalog, &payload.bulk_type)?;
    import_scryfall_bulk_reader(repo, metadata, reader).await
}

pub async fn import_scryfall_bulk_reader<R>(
    repo: &ScryfallRepository<'_>,
    metadata: ScryfallBulkMetadata,
    reader: R,
) -> anyhow::Result<ScryfallImportRecord>
where
    R: Read + Send + 'static,
{
    let import = repo
        .create_import(ScryfallImportInput {
            bulk_type: &metadata.bulk_type,
            source_uri: &metadata.source_uri,
            download_uri: &metadata.download_uri,
            source_updated_at: metadata.source_updated_at,
            content_type: &metadata.content_type,
            content_encoding: metadata.content_encoding.as_deref(),
            size_bytes: metadata.size_bytes,
            raw_metadata: &metadata.raw_metadata,
        })
        .await
        .context("create Scryfall import")?;

    repo.mark_import_running(import.id)
        .await
        .context("mark Scryfall import running")?;

    match import_cards_from_reader(repo, import.id, reader).await {
        Ok(()) => {
            repo.mark_import_succeeded(import.id)
                .await
                .context("mark Scryfall import succeeded")?;
            repo.get_import(import.id)
                .await
                .context("load completed Scryfall import")?
                .context("completed Scryfall import missing")
        }
        Err(err) => {
            let error_message = err.to_string();
            repo.mark_import_failed(import.id, &error_message)
                .await
                .context("mark Scryfall import failed")?;
            Err(err)
        }
    }
}

async fn import_cards_from_reader<R>(
    repo: &ScryfallRepository<'_>,
    import_id: uuid::Uuid,
    reader: R,
) -> anyhow::Result<()>
where
    R: Read + Send + 'static,
{
    let (sender, mut receiver) = tokio::sync::mpsc::channel::<Result<Value, String>>(32);
    let parse_handle = tokio::task::spawn_blocking(move || parse_card_array(reader, sender));
    let mut import_result = Ok(());

    while let Some(card) = receiver.recv().await {
        match card {
            Ok(raw_card) => {
                if let Err(err) = repo
                    .upsert_card_from_scryfall_json(import_id, &raw_card)
                    .await
                {
                    import_result = Err(anyhow!(err).context("upsert Scryfall card"));
                    break;
                }
            }
            Err(err) => {
                import_result = Err(anyhow!(err).context("parse Scryfall card"));
                break;
            }
        }
    }

    drop(receiver);
    let parse_result = parse_handle.await.context("join Scryfall card parser")?;
    if import_result.is_ok() {
        parse_result?;
    }

    import_result
}

fn parse_card_array<R>(
    reader: R,
    sender: tokio::sync::mpsc::Sender<Result<Value, String>>,
) -> anyhow::Result<usize>
where
    R: Read,
{
    let mut deserializer = serde_json::Deserializer::from_reader(reader);
    deserializer
        .deserialize_seq(CardArrayVisitor { sender })
        .context("parse Scryfall card array")
}

struct CardArrayVisitor {
    sender: tokio::sync::mpsc::Sender<Result<Value, String>>,
}

impl<'de> Visitor<'de> for CardArrayVisitor {
    type Value = usize;

    fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("a Scryfall bulk JSON array")
    }

    fn visit_seq<A>(self, mut seq: A) -> Result<Self::Value, A::Error>
    where
        A: SeqAccess<'de>,
    {
        let mut count = 0;
        while let Some(card) = seq.next_element::<Value>()? {
            self.sender
                .blocking_send(Ok(card))
                .map_err(|_| de::Error::custom("Scryfall import receiver closed"))?;
            count += 1;
        }
        Ok(count)
    }
}

fn required_str<'a>(value: &'a Value, key: &str) -> anyhow::Result<&'a str> {
    value
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .with_context(|| format!("Scryfall bulk metadata missing {key}"))
}

fn default_bulk_type() -> String {
    DEFAULT_BULK_TYPE.to_owned()
}

fn default_bulk_data_uri() -> String {
    DEFAULT_BULK_DATA_URI.to_owned()
}

#[cfg(test)]
mod tests {
    use std::io::Cursor;

    use pod_db::{CardSearchFilters, ScryfallRepository};
    use serde_json::json;

    use super::{
        DEFAULT_BULK_DATA_URI, parse_scryfall_import_payload,
        process_scryfall_bulk_import_from_reader, select_bulk_metadata,
    };

    #[test]
    fn parses_scryfall_import_payload_defaults() {
        let payload = parse_scryfall_import_payload(json!({})).expect("payload");
        assert_eq!(payload.bulk_type, "default_cards");
        assert_eq!(payload.bulk_data_uri, DEFAULT_BULK_DATA_URI);
    }

    #[test]
    fn rejects_non_https_scryfall_metadata_url() {
        let err = parse_scryfall_import_payload(json!({
            "bulk_type": "default_cards",
            "bulk_data_uri": "http://api.scryfall.com/bulk-data"
        }))
        .expect_err("non-https should fail");
        assert!(err.to_string().contains("https"));
    }

    #[test]
    fn selects_default_cards_metadata_from_catalog() {
        let catalog = bulk_catalog();
        let metadata = select_bulk_metadata(&catalog, "default_cards").expect("metadata");

        assert_eq!(metadata.bulk_type, "default_cards");
        assert_eq!(
            metadata.download_uri,
            "https://data.scryfall.io/default-cards/default-cards-20260518090927.json"
        );
        assert_eq!(metadata.content_encoding.as_deref(), Some("gzip"));
        assert_eq!(metadata.size_bytes, Some(538_716_896));
        assert_eq!(metadata.raw_metadata["name"], "Default Cards");
    }

    #[sqlx::test(migrations = "../pod-db/migrations")]
    async fn imports_cards_through_scryfall_job_path_and_searches(pool: sqlx::PgPool) {
        let repo = ScryfallRepository::new(&pool);
        let cards = json!([atraxa_card(), storm_kiln_artist_card()]).to_string();
        let import = process_scryfall_bulk_import_from_reader(
            &repo,
            json!({ "bulk_type": "default_cards" }),
            &bulk_catalog(),
            Cursor::new(cards.into_bytes()),
        )
        .await
        .expect("import");

        assert_eq!(import.status, "succeeded");
        assert_eq!(import.cards_seen, 2);
        assert_eq!(import.cards_imported, 2);
        assert_eq!(import.raw_metadata["type"], "default_cards");

        let results = repo
            .search_cards(CardSearchFilters {
                query: Some("treasure token"),
                commander_legal: Some(true),
                ..CardSearchFilters::default()
            })
            .await
            .expect("search cards");
        assert_eq!(results[0].name, "Storm-Kiln Artist");
    }

    #[sqlx::test(migrations = "../pod-db/migrations")]
    async fn records_failed_import_status_and_error(pool: sqlx::PgPool) {
        let repo = ScryfallRepository::new(&pool);
        let cards = json!([{
            "id": "not-a-uuid",
            "oracle_id": "also-not-a-uuid",
            "name": "Broken Card",
            "legalities": {}
        }])
        .to_string();
        let err = process_scryfall_bulk_import_from_reader(
            &repo,
            json!({ "bulk_type": "default_cards" }),
            &bulk_catalog(),
            Cursor::new(cards.into_bytes()),
        )
        .await
        .expect_err("invalid card should fail");
        assert!(err.to_string().contains("upsert Scryfall card"));

        let failed = sqlx::query!(
            r#"
            select status, cards_seen, cards_imported, error_message
            from mtg.scryfall_imports
            where bulk_type = 'default_cards'
            "#
        )
        .fetch_one(&pool)
        .await
        .expect("failed import");
        assert_eq!(failed.status, "failed");
        assert_eq!(failed.cards_seen, 0);
        assert_eq!(failed.cards_imported, 0);
        assert!(
            failed
                .error_message
                .as_deref()
                .expect("error message")
                .contains("upsert Scryfall card")
        );
    }

    fn bulk_catalog() -> serde_json::Value {
        json!({
            "object": "list",
            "data": [{
                "object": "bulk_data",
                "type": "default_cards",
                "updated_at": "2026-05-18T09:09:27.689+00:00",
                "uri": "https://api.scryfall.com/bulk-data/e2ef41e3-5778-4bc2-af3f-78eca4dd9c23",
                "name": "Default Cards",
                "download_uri": "https://data.scryfall.io/default-cards/default-cards-20260518090927.json",
                "content_type": "application/json",
                "content_encoding": "gzip",
                "size": 538716896
            }]
        })
    }

    fn atraxa_card() -> serde_json::Value {
        json!({
            "id": "00000000-0000-7000-8000-000000000101",
            "oracle_id": "10000000-0000-7000-8000-000000000101",
            "name": "Atraxa, Praetors' Voice",
            "lang": "en",
            "released_at": "2016-11-11",
            "layout": "normal",
            "mana_cost": "{G}{W}{U}{B}",
            "cmc": 4.0,
            "type_line": "Legendary Creature - Phyrexian Angel Horror",
            "oracle_text": "Flying, vigilance, deathtouch, lifelink. At the beginning of your end step, proliferate.",
            "colors": ["W", "U", "B", "G"],
            "color_identity": ["W", "U", "B", "G"],
            "keywords": ["Flying", "Vigilance", "Deathtouch", "Lifelink", "Proliferate"],
            "legalities": {
                "commander": "legal"
            },
            "reserved": false,
            "game_changer": true,
            "edhrec_rank": 46,
            "set": "c16",
            "collector_number": "28",
            "rarity": "mythic",
            "artist": "Victor Adame Minguez",
            "prices": {
                "usd": "24.50",
                "eur": "18.10",
                "tix": "0.04"
            }
        })
    }

    fn storm_kiln_artist_card() -> serde_json::Value {
        json!({
            "id": "00000000-0000-7000-8000-000000000102",
            "oracle_id": "10000000-0000-7000-8000-000000000102",
            "name": "Storm-Kiln Artist",
            "lang": "en",
            "released_at": "2021-04-23",
            "layout": "normal",
            "mana_cost": "{3}{R}",
            "cmc": 4.0,
            "type_line": "Creature - Dwarf Shaman",
            "oracle_text": "Magecraft - Whenever you cast or copy an instant or sorcery spell, create a Treasure token.",
            "colors": ["R"],
            "color_identity": ["R"],
            "keywords": ["Magecraft"],
            "legalities": {
                "commander": "legal"
            },
            "reserved": false,
            "game_changer": false,
            "edhrec_rank": 135,
            "set": "stx",
            "collector_number": "115",
            "rarity": "uncommon",
            "artist": "Manuel Castanon",
            "prices": {
                "usd": "0.25",
                "eur": "0.12",
                "tix": "0.03"
            }
        })
    }
}

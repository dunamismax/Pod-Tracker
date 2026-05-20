use serde_json::Value;
use sqlx::PgPool;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::DbError;

#[derive(Debug, Clone, PartialEq)]
pub struct ScryfallImportRecord {
    pub id: Uuid,
    pub bulk_type: String,
    pub source_uri: String,
    pub download_uri: String,
    pub source_updated_at: OffsetDateTime,
    pub content_type: String,
    pub content_encoding: Option<String>,
    pub size_bytes: Option<i64>,
    pub status: String,
    pub cards_seen: i32,
    pub cards_imported: i32,
    pub error_message: Option<String>,
    pub started_at: Option<OffsetDateTime>,
    pub finished_at: Option<OffsetDateTime>,
    pub raw_metadata: Value,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, Copy)]
pub struct ScryfallImportInput<'a> {
    pub bulk_type: &'a str,
    pub source_uri: &'a str,
    pub download_uri: &'a str,
    pub source_updated_at: OffsetDateTime,
    pub content_type: &'a str,
    pub content_encoding: Option<&'a str>,
    pub size_bytes: Option<i64>,
    pub raw_metadata: &'a Value,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImportedCardRecord {
    pub scryfall_id: Uuid,
    pub oracle_id: Uuid,
    pub name: String,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct CardSearchFilters<'a> {
    pub query: Option<&'a str>,
    pub color_identity: Option<&'a [String]>,
    pub commander_legal: Option<bool>,
    pub min_mana_value: Option<f64>,
    pub max_mana_value: Option<f64>,
    pub type_line: Option<&'a str>,
    pub max_usd: Option<f64>,
    pub game_changer: Option<bool>,
    pub limit: Option<i64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CardSearchResult {
    pub scryfall_id: Uuid,
    pub oracle_id: Uuid,
    pub name: String,
    pub lang: String,
    pub printed_name: Option<String>,
    pub display_name: String,
    pub type_line: String,
    pub printed_type_line: Option<String>,
    pub display_type_line: String,
    pub oracle_text: String,
    pub printed_text: Option<String>,
    pub display_text: String,
    pub color_identity: Vec<String>,
    pub commander_legal: bool,
    pub mana_value: Option<f64>,
    pub usd: Option<f64>,
    pub game_changer: bool,
    pub text_rank: f32,
    pub name_similarity: f32,
}

pub struct ScryfallRepository<'a> {
    pool: &'a PgPool,
}

impl<'a> ScryfallRepository<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }

    pub async fn create_import(
        &self,
        input: ScryfallImportInput<'_>,
    ) -> Result<ScryfallImportRecord, DbError> {
        let import = sqlx::query_as!(
            ScryfallImportRecord,
            r#"
            insert into mtg.scryfall_imports (
              bulk_type, source_uri, download_uri, source_updated_at,
              content_type, content_encoding, size_bytes, raw_metadata
            )
            values ($1, $2, $3, $4, $5, $6, $7, $8)
            on conflict (bulk_type, source_updated_at) do update
            set source_uri = excluded.source_uri,
                download_uri = excluded.download_uri,
                content_type = excluded.content_type,
                content_encoding = excluded.content_encoding,
                size_bytes = excluded.size_bytes,
                status = 'pending',
                cards_seen = 0,
                cards_imported = 0,
                error_message = null,
                started_at = null,
                finished_at = null,
                raw_metadata = excluded.raw_metadata,
                updated_at = now()
            returning id, bulk_type, source_uri, download_uri, source_updated_at,
              content_type, content_encoding, size_bytes, status, cards_seen,
              cards_imported, error_message, started_at, finished_at,
              raw_metadata, created_at, updated_at
            "#,
            input.bulk_type,
            input.source_uri,
            input.download_uri,
            input.source_updated_at,
            input.content_type,
            input.content_encoding,
            input.size_bytes,
            input.raw_metadata,
        )
        .fetch_one(self.pool)
        .await?;

        Ok(import)
    }

    pub async fn mark_import_running(&self, import_id: Uuid) -> Result<(), DbError> {
        sqlx::query!(
            r#"
            update mtg.scryfall_imports
            set status = 'running',
                started_at = coalesce(started_at, now()),
                updated_at = now()
            where id = $1
            "#,
            import_id,
        )
        .execute(self.pool)
        .await?;

        Ok(())
    }

    pub async fn mark_import_succeeded(&self, import_id: Uuid) -> Result<(), DbError> {
        sqlx::query!(
            r#"
            update mtg.scryfall_imports
            set status = 'succeeded',
                error_message = null,
                finished_at = now(),
                updated_at = now()
            where id = $1
            "#,
            import_id,
        )
        .execute(self.pool)
        .await?;

        Ok(())
    }

    pub async fn mark_import_failed(
        &self,
        import_id: Uuid,
        error_message: &str,
    ) -> Result<(), DbError> {
        sqlx::query!(
            r#"
            update mtg.scryfall_imports
            set status = 'failed',
                error_message = $2,
                finished_at = now(),
                updated_at = now()
            where id = $1
            "#,
            import_id,
            error_message,
        )
        .execute(self.pool)
        .await?;

        Ok(())
    }

    pub async fn get_import(
        &self,
        import_id: Uuid,
    ) -> Result<Option<ScryfallImportRecord>, DbError> {
        let import = sqlx::query_as!(
            ScryfallImportRecord,
            r#"
            select id, bulk_type, source_uri, download_uri, source_updated_at,
              content_type, content_encoding, size_bytes, status, cards_seen,
              cards_imported, error_message, started_at, finished_at,
              raw_metadata, created_at, updated_at
            from mtg.scryfall_imports
            where id = $1
            "#,
            import_id,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(import)
    }

    pub async fn upsert_card_from_scryfall_json(
        &self,
        import_id: Uuid,
        raw_card: &Value,
    ) -> Result<ImportedCardRecord, DbError> {
        let mut tx = self.pool.begin().await?;

        let imported = sqlx::query_as!(
            ImportedCardRecord,
            r#"
            with payload as (
              select $2::jsonb as raw
            ),
            card_upsert as (
              insert into mtg.cards (
                oracle_id, name, mana_cost, mana_value, type_line, oracle_text,
                colors, color_identity, layout, reserved, keywords, edhrec_rank,
                legal_commander, game_changer, last_import_id, raw_payload
              )
              select
                (raw->>'oracle_id')::uuid,
                raw->>'name',
                coalesce(raw->>'mana_cost', ''),
                nullif(raw->>'cmc', '')::double precision,
                coalesce(raw->>'type_line', ''),
                coalesce(raw->>'oracle_text', ''),
                coalesce(
                  array(select jsonb_array_elements_text(coalesce(raw->'colors', '[]'::jsonb))),
                  '{}'::text[]
                ),
                coalesce(
                  array(select jsonb_array_elements_text(coalesce(raw->'color_identity', '[]'::jsonb))),
                  '{}'::text[]
                ),
                coalesce(raw->>'layout', ''),
                coalesce((raw->>'reserved')::boolean, false),
                coalesce(
                  array(select jsonb_array_elements_text(coalesce(raw->'keywords', '[]'::jsonb))),
                  '{}'::text[]
                ),
                nullif(raw->>'edhrec_rank', '')::integer,
                coalesce(raw #>> '{legalities,commander}', 'not_legal') = 'legal',
                coalesce((raw->>'game_changer')::boolean, false),
                $1,
                raw
              from payload
              on conflict (oracle_id) do update
              set name = excluded.name,
                  mana_cost = excluded.mana_cost,
                  mana_value = excluded.mana_value,
                  type_line = excluded.type_line,
                  oracle_text = excluded.oracle_text,
                  colors = excluded.colors,
                  color_identity = excluded.color_identity,
                  layout = excluded.layout,
                  reserved = excluded.reserved,
                  keywords = excluded.keywords,
                  edhrec_rank = excluded.edhrec_rank,
                  legal_commander = excluded.legal_commander,
                  game_changer = excluded.game_changer,
                  last_import_id = excluded.last_import_id,
                  raw_payload = excluded.raw_payload,
                  updated_at = now()
              returning oracle_id
            ),
            printing_upsert as (
              insert into mtg.card_printings (
                scryfall_id, oracle_id, set_code, collector_number, lang, rarity,
                printed_name, printed_type_line, printed_text, released_at, artist,
                prices, import_id, raw_payload
              )
              select
                (raw->>'id')::uuid,
                card_upsert.oracle_id,
                lower(coalesce(nullif(raw->>'set', ''), 'unknown')),
                coalesce(nullif(raw->>'collector_number', ''), 'unknown'),
                lower(coalesce(nullif(raw->>'lang', ''), 'en')),
                coalesce(raw->>'rarity', ''),
                nullif(raw->>'printed_name', ''),
                nullif(raw->>'printed_type_line', ''),
                nullif(raw->>'printed_text', ''),
                nullif(raw->>'released_at', '')::date,
                raw->>'artist',
                coalesce(raw->'prices', '{}'::jsonb),
                $1,
                raw
              from payload, card_upsert
              on conflict (scryfall_id) do update
              set oracle_id = excluded.oracle_id,
                  set_code = excluded.set_code,
                  collector_number = excluded.collector_number,
                  lang = excluded.lang,
                  rarity = excluded.rarity,
                  printed_name = excluded.printed_name,
                  printed_type_line = excluded.printed_type_line,
                  printed_text = excluded.printed_text,
                  released_at = excluded.released_at,
                  artist = excluded.artist,
                  prices = excluded.prices,
                  import_id = excluded.import_id,
                  raw_payload = excluded.raw_payload,
                  updated_at = now()
              returning scryfall_id, oracle_id
            )
            select printing_upsert.scryfall_id, printing_upsert.oracle_id, raw->>'name' as "name!"
            from payload, printing_upsert
            "#,
            import_id,
            raw_card,
        )
        .fetch_one(&mut *tx)
        .await?;

        sqlx::query!(
            r#"
            delete from mtg.card_legalities
            where scryfall_id = $1
            "#,
            imported.scryfall_id,
        )
        .execute(&mut *tx)
        .await?;

        sqlx::query!(
            r#"
            with payload as (
              select $2::jsonb as raw
            )
            insert into mtg.card_legalities (scryfall_id, format, status)
            select $1, legalities.key, legalities.value
            from payload,
              lateral jsonb_each_text(coalesce(raw->'legalities', '{}'::jsonb)) as legalities(key, value)
            where legalities.value in ('legal', 'not_legal', 'banned', 'restricted')
            "#,
            imported.scryfall_id,
            raw_card,
        )
        .execute(&mut *tx)
        .await?;

        sqlx::query!(
            r#"
            delete from mtg.card_faces
            where scryfall_id = $1
            "#,
            imported.scryfall_id,
        )
        .execute(&mut *tx)
        .await?;

        sqlx::query!(
            r#"
            with payload as (
              select $3::jsonb as raw
            ),
            faces as (
              select
                $1::uuid as scryfall_id,
                (face.ordinality - 1)::integer as face_index,
                $2::uuid as oracle_id,
                coalesce(face.value->>'name', raw->>'name') as name,
                coalesce(face.value->>'mana_cost', '') as mana_cost,
                coalesce(face.value->>'type_line', '') as type_line,
                coalesce(face.value->>'oracle_text', '') as oracle_text,
                nullif(face.value->>'printed_name', '') as printed_name,
                nullif(face.value->>'printed_type_line', '') as printed_type_line,
                nullif(face.value->>'printed_text', '') as printed_text,
                coalesce(
                  array(select jsonb_array_elements_text(coalesce(face.value->'colors', '[]'::jsonb))),
                  '{}'::text[]
                ) as colors
              from payload,
                lateral jsonb_array_elements(coalesce(raw->'card_faces', '[]'::jsonb))
                  with ordinality as face(value, ordinality)
              union all
              select
                $1,
                0,
                $2,
                raw->>'name',
                coalesce(raw->>'mana_cost', ''),
                coalesce(raw->>'type_line', ''),
                coalesce(raw->>'oracle_text', ''),
                nullif(raw->>'printed_name', ''),
                nullif(raw->>'printed_type_line', ''),
                nullif(raw->>'printed_text', ''),
                coalesce(
                  array(select jsonb_array_elements_text(coalesce(raw->'colors', '[]'::jsonb))),
                  '{}'::text[]
                )
              from payload
              where jsonb_array_length(coalesce(raw->'card_faces', '[]'::jsonb)) = 0
            )
            insert into mtg.card_faces (
              scryfall_id, face_index, oracle_id, name, mana_cost, type_line,
              oracle_text, printed_name, printed_type_line, printed_text, colors
            )
            select scryfall_id, face_index, oracle_id, name, mana_cost, type_line,
              oracle_text, printed_name, printed_type_line, printed_text, colors
            from faces
            "#,
            imported.scryfall_id,
            imported.oracle_id,
            raw_card,
        )
        .execute(&mut *tx)
        .await?;

        sqlx::query!(
            r#"
            with payload as (
              select $3::jsonb as raw
            ),
            face_text as (
              select string_agg(coalesce(face.value->>'oracle_text', ''), ' ' order by face.ordinality) as oracle_text
              from payload,
                lateral jsonb_array_elements(coalesce(raw->'card_faces', '[]'::jsonb))
                  with ordinality as face(value, ordinality)
            ),
            printed_face_text as (
              select string_agg(coalesce(face.value->>'printed_text', ''), ' ' order by face.ordinality) as printed_text
              from payload,
                lateral jsonb_array_elements(coalesce(raw->'card_faces', '[]'::jsonb))
                  with ordinality as face(value, ordinality)
            ),
            document_input as (
              select
                raw->>'name' as name,
                regexp_replace(lower(coalesce(raw->>'name', '')), '[^a-z0-9]+', '', 'g') as normalized_name,
                lower(coalesce(nullif(raw->>'lang', ''), 'en')) as lang,
                nullif(raw->>'printed_name', '') as printed_name,
                nullif(
                  regexp_replace(lower(coalesce(raw->>'printed_name', '')), '[^[:alnum:]]+', '', 'g'),
                  ''
                ) as normalized_printed_name,
                coalesce(raw->>'type_line', '') as type_line,
                nullif(raw->>'printed_type_line', '') as printed_type_line,
                coalesce(raw->>'oracle_text', face_text.oracle_text, '') as oracle_text,
                coalesce(nullif(raw->>'printed_text', ''), printed_face_text.printed_text, '') as printed_text,
                coalesce(
                  array(select jsonb_array_elements_text(coalesce(raw->'color_identity', '[]'::jsonb))),
                  '{}'::text[]
                ) as color_identity,
                coalesce(raw #>> '{legalities,commander}', 'not_legal') = 'legal' as commander_legal,
                nullif(raw->>'cmc', '')::double precision as mana_value,
                nullif(raw #>> '{prices,usd}', '')::double precision as usd,
                nullif(raw #>> '{prices,eur}', '')::double precision as eur,
                nullif(raw #>> '{prices,tix}', '')::double precision as tix,
                coalesce((raw->>'game_changer')::boolean, false) as game_changer
              from payload, face_text, printed_face_text
            )
            insert into search.card_documents (
              scryfall_id, oracle_id, name, normalized_name, lang, printed_name,
              normalized_printed_name, type_line, printed_type_line, oracle_text,
              printed_text, color_identity, commander_legal, mana_value, usd, eur,
              tix, game_changer, document, printed_document
            )
            select
              $1, $2, name, normalized_name, lang, printed_name,
              normalized_printed_name, type_line, printed_type_line, oracle_text,
              nullif(printed_text, ''), color_identity, commander_legal, mana_value,
              usd, eur, tix,
              game_changer,
              setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
              setweight(to_tsvector('english', coalesce(type_line, '')), 'B') ||
              setweight(to_tsvector('english', coalesce(oracle_text, '')), 'C'),
              setweight(to_tsvector('simple', coalesce(printed_name, '')), 'A') ||
              setweight(to_tsvector('simple', coalesce(printed_type_line, '')), 'B') ||
              setweight(to_tsvector('simple', coalesce(printed_text, '')), 'C')
            from document_input
            on conflict (scryfall_id) do update
            set oracle_id = excluded.oracle_id,
                name = excluded.name,
                normalized_name = excluded.normalized_name,
                lang = excluded.lang,
                printed_name = excluded.printed_name,
                normalized_printed_name = excluded.normalized_printed_name,
                type_line = excluded.type_line,
                printed_type_line = excluded.printed_type_line,
                oracle_text = excluded.oracle_text,
                printed_text = excluded.printed_text,
                color_identity = excluded.color_identity,
                commander_legal = excluded.commander_legal,
                mana_value = excluded.mana_value,
                usd = excluded.usd,
                eur = excluded.eur,
                tix = excluded.tix,
                game_changer = excluded.game_changer,
                document = excluded.document,
                printed_document = excluded.printed_document,
                updated_at = now()
            "#,
            imported.scryfall_id,
            imported.oracle_id,
            raw_card,
        )
        .execute(&mut *tx)
        .await?;

        sqlx::query!(
            r#"
            update mtg.scryfall_imports
            set cards_seen = cards_seen + 1,
                cards_imported = cards_imported + 1,
                updated_at = now()
            where id = $1
            "#,
            import_id,
        )
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(imported)
    }

    pub async fn search_cards(
        &self,
        filters: CardSearchFilters<'_>,
    ) -> Result<Vec<CardSearchResult>, DbError> {
        let query = filters
            .query
            .map(str::trim)
            .filter(|query| !query.is_empty());
        let color_identity = filters.color_identity.filter(|colors| !colors.is_empty());
        let limit = filters.limit.unwrap_or(25).clamp(1, 100);

        let cards = sqlx::query_as!(
            CardSearchResult,
            r#"
            select scryfall_id, oracle_id, name, lang, printed_name,
              coalesce(printed_name, name) as "display_name!",
              type_line, printed_type_line,
              coalesce(printed_type_line, type_line) as "display_type_line!",
              oracle_text, printed_text,
              coalesce(printed_text, oracle_text) as "display_text!",
              color_identity, commander_legal, mana_value, usd, game_changer,
              case
                when $1::text is null then 0::real
                else greatest(
                  ts_rank_cd(document, websearch_to_tsquery('english', $1)),
                  ts_rank_cd(printed_document, websearch_to_tsquery('simple', $1))
                )::real
              end as "text_rank!",
              case
                when $1::text is null then 0::real
                else greatest(
                  similarity(name, $1),
                  similarity(normalized_name, regexp_replace(lower($1), '[^a-z0-9]+', '', 'g')),
                  similarity(coalesce(printed_name, ''), $1),
                  similarity(
                    coalesce(normalized_printed_name, ''),
                    regexp_replace(lower($1), '[^[:alnum:]]+', '', 'g')
                  )
                )::real
              end as "name_similarity!"
            from search.card_documents
            where (
                $1::text is null
                or document @@ websearch_to_tsquery('english', $1)
                or printed_document @@ websearch_to_tsquery('simple', $1)
                or name % $1
                or normalized_name % regexp_replace(lower($1), '[^a-z0-9]+', '', 'g')
                or printed_name % $1
                or normalized_printed_name % regexp_replace(lower($1), '[^[:alnum:]]+', '', 'g')
              )
              and ($2::text[] is null or color_identity <@ $2)
              and ($3::boolean is null or commander_legal = $3)
              and ($4::double precision is null or mana_value >= $4)
              and ($5::double precision is null or mana_value <= $5)
              and ($6::double precision is null or usd <= $6)
              and ($7::boolean is null or game_changer = $7)
              and (
                $8::text is null
                or type_line ilike '%' || $8 || '%'
                or printed_type_line ilike '%' || $8 || '%'
              )
            order by 18 desc, 19 desc, coalesce(printed_name, name) asc, name asc
            limit $9
            "#,
            query,
            color_identity,
            filters.commander_legal,
            filters.min_mana_value,
            filters.max_mana_value,
            filters.max_usd,
            filters.game_changer,
            filters
                .type_line
                .map(str::trim)
                .filter(|value| !value.is_empty()),
            limit,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(cards)
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;
    use time::format_description::well_known::Rfc3339;

    use super::{CardSearchFilters, ScryfallImportInput, ScryfallRepository};

    #[sqlx::test(migrations = "./migrations")]
    async fn imports_raw_scryfall_payload_and_normalizes_card_rows(pool: sqlx::PgPool) {
        let repo = ScryfallRepository::new(&pool);
        let metadata = json!({
            "object": "bulk_data",
            "type": "default_cards",
            "updated_at": "2026-05-18T09:09:27.689+00:00",
            "uri": "https://api.scryfall.com/bulk-data/e2ef41e3-5778-4bc2-af3f-78eca4dd9c23",
            "download_uri": "https://data.scryfall.io/default-cards/default-cards-20260518090927.json",
            "content_type": "application/json",
            "content_encoding": "gzip",
            "size": 538716896
        });
        let import = repo
            .create_import(ScryfallImportInput {
                bulk_type: "default_cards",
                source_uri: metadata["uri"].as_str().expect("uri"),
                download_uri: metadata["download_uri"].as_str().expect("download_uri"),
                source_updated_at: time::OffsetDateTime::parse(
                    metadata["updated_at"].as_str().expect("updated_at"),
                    &Rfc3339,
                )
                .expect("updated_at"),
                content_type: "application/json",
                content_encoding: Some("gzip"),
                size_bytes: Some(538_716_896),
                raw_metadata: &metadata,
            })
            .await
            .expect("create import");

        repo.mark_import_running(import.id)
            .await
            .expect("mark running");

        let raw = atraxa_card();
        let imported = repo
            .upsert_card_from_scryfall_json(import.id, &raw)
            .await
            .expect("import card");

        assert_eq!(imported.name, "Atraxa, Praetors' Voice");

        let stored = sqlx::query!(
            r#"
            select c.name, c.legal_commander, c.raw_payload, p.prices
            from mtg.cards c
            join mtg.card_printings p on p.oracle_id = c.oracle_id
            where p.scryfall_id = $1
            "#,
            imported.scryfall_id,
        )
        .fetch_one(&pool)
        .await
        .expect("stored card");
        assert_eq!(stored.name, "Atraxa, Praetors' Voice");
        assert!(stored.legal_commander);
        assert_eq!(stored.raw_payload["id"], raw["id"]);
        assert_eq!(stored.prices["usd"], json!("24.50"));

        let faces = sqlx::query_scalar!(
            r#"
            select count(*) from mtg.card_faces where scryfall_id = $1
            "#,
            imported.scryfall_id,
        )
        .fetch_one(&pool)
        .await
        .expect("face count");
        assert_eq!(faces, Some(1));

        repo.mark_import_succeeded(import.id)
            .await
            .expect("mark succeeded");
        let finished = repo
            .get_import(import.id)
            .await
            .expect("get import")
            .expect("import exists");
        assert_eq!(finished.status, "succeeded");
        assert_eq!(finished.cards_seen, 1);
        assert_eq!(finished.cards_imported, 1);
        assert_eq!(finished.raw_metadata["type"], json!("default_cards"));
    }

    #[sqlx::test(migrations = "./migrations")]
    async fn searches_cards_with_full_text_trigram_and_filters(pool: sqlx::PgPool) {
        let repo = ScryfallRepository::new(&pool);
        let metadata = json!({
            "type": "default_cards",
            "updated_at": "2026-05-18T09:09:27.689+00:00",
            "uri": "https://api.scryfall.com/bulk-data/e2ef41e3-5778-4bc2-af3f-78eca4dd9c23",
            "download_uri": "https://data.scryfall.io/default-cards/default-cards-20260518090927.json"
        });
        let import = repo
            .create_import(ScryfallImportInput {
                bulk_type: "default_cards",
                source_uri: metadata["uri"].as_str().expect("uri"),
                download_uri: metadata["download_uri"].as_str().expect("download_uri"),
                source_updated_at: time::OffsetDateTime::parse(
                    metadata["updated_at"].as_str().expect("updated_at"),
                    &Rfc3339,
                )
                .expect("updated_at"),
                content_type: "application/json",
                content_encoding: Some("gzip"),
                size_bytes: Some(538_716_896),
                raw_metadata: &metadata,
            })
            .await
            .expect("create import");

        repo.upsert_card_from_scryfall_json(import.id, &atraxa_card())
            .await
            .expect("import atraxa");
        repo.upsert_card_from_scryfall_json(import.id, &storm_kiln_artist_card())
            .await
            .expect("import storm-kiln artist");

        let full_text = repo
            .search_cards(CardSearchFilters {
                query: Some("treasure token"),
                commander_legal: Some(true),
                ..CardSearchFilters::default()
            })
            .await
            .expect("full-text search");
        assert_eq!(full_text[0].name, "Storm-Kiln Artist");

        let fuzzy = repo
            .search_cards(CardSearchFilters {
                query: Some("Atraxaa Praetors Voice"),
                commander_legal: Some(true),
                ..CardSearchFilters::default()
            })
            .await
            .expect("fuzzy search");
        assert_eq!(fuzzy[0].name, "Atraxa, Praetors' Voice");
        assert!(fuzzy[0].name_similarity > 0.0);

        let red = vec!["R".to_owned()];
        let filtered = repo
            .search_cards(CardSearchFilters {
                query: Some("artist"),
                color_identity: Some(&red),
                max_mana_value: Some(4.0),
                type_line: Some("Shaman"),
                max_usd: Some(2.0),
                ..CardSearchFilters::default()
            })
            .await
            .expect("filtered search");
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].name, "Storm-Kiln Artist");

        let expensive = repo
            .search_cards(CardSearchFilters {
                query: Some("atraxa"),
                max_usd: Some(2.0),
                ..CardSearchFilters::default()
            })
            .await
            .expect("price filter");
        assert!(expensive.is_empty());
    }

    #[sqlx::test(migrations = "./migrations")]
    async fn preserves_printed_language_fields_and_searches_localized_names(pool: sqlx::PgPool) {
        let repo = ScryfallRepository::new(&pool);
        let metadata = json!({
            "type": "all_cards",
            "updated_at": "2026-05-18T09:09:27.689+00:00",
            "uri": "https://api.scryfall.com/bulk-data/all-cards",
            "download_uri": "https://data.scryfall.io/all-cards/all-cards-20260518090927.json"
        });
        let import = repo
            .create_import(ScryfallImportInput {
                bulk_type: "all_cards",
                source_uri: metadata["uri"].as_str().expect("uri"),
                download_uri: metadata["download_uri"].as_str().expect("download_uri"),
                source_updated_at: time::OffsetDateTime::parse(
                    metadata["updated_at"].as_str().expect("updated_at"),
                    &Rfc3339,
                )
                .expect("updated_at"),
                content_type: "application/json",
                content_encoding: Some("gzip"),
                size_bytes: Some(800_000_000),
                raw_metadata: &metadata,
            })
            .await
            .expect("create import");

        let raw = french_lightning_bolt_card();
        let imported = repo
            .upsert_card_from_scryfall_json(import.id, &raw)
            .await
            .expect("import localized card");

        let printing = sqlx::query!(
            r#"
            select lang, printed_name, printed_type_line, printed_text
            from mtg.card_printings
            where scryfall_id = $1
            "#,
            imported.scryfall_id,
        )
        .fetch_one(&pool)
        .await
        .expect("printing");
        assert_eq!(printing.lang, "fr");
        assert_eq!(printing.printed_name.as_deref(), Some("Foudre"));
        assert_eq!(printing.printed_type_line.as_deref(), Some("Ephémère"));
        assert_eq!(
            printing.printed_text.as_deref(),
            Some("La Foudre inflige 3 blessures à n'importe quelle cible.")
        );

        let face = sqlx::query!(
            r#"
            select printed_name, printed_type_line, printed_text
            from mtg.card_faces
            where scryfall_id = $1 and face_index = 0
            "#,
            imported.scryfall_id,
        )
        .fetch_one(&pool)
        .await
        .expect("face");
        assert_eq!(face.printed_name.as_deref(), Some("Foudre"));
        assert_eq!(face.printed_type_line.as_deref(), Some("Ephémère"));

        let localized = repo
            .search_cards(CardSearchFilters {
                query: Some("Foudre blessures"),
                commander_legal: Some(true),
                ..CardSearchFilters::default()
            })
            .await
            .expect("localized search");
        assert_eq!(localized[0].name, "Lightning Bolt");
        assert_eq!(localized[0].lang, "fr");
        assert_eq!(localized[0].printed_name.as_deref(), Some("Foudre"));
        assert_eq!(localized[0].display_name, "Foudre");
        assert_eq!(localized[0].display_type_line, "Ephémère");
        assert!(localized[0].display_text.contains("blessures"));
        assert!(localized[0].text_rank > 0.0 || localized[0].name_similarity > 0.0);
    }

    fn atraxa_card() -> serde_json::Value {
        json!({
            "id": "00000000-0000-7000-8000-000000000001",
            "oracle_id": "10000000-0000-7000-8000-000000000001",
            "name": "Atraxa, Praetors' Voice",
            "lang": "en",
            "released_at": "2016-11-11",
            "uri": "https://api.scryfall.com/cards/00000000-0000-7000-8000-000000000001",
            "layout": "normal",
            "mana_cost": "{G}{W}{U}{B}",
            "cmc": 4.0,
            "type_line": "Legendary Creature - Phyrexian Angel Horror",
            "oracle_text": "Flying, vigilance, deathtouch, lifelink. At the beginning of your end step, proliferate.",
            "colors": ["W", "U", "B", "G"],
            "color_identity": ["W", "U", "B", "G"],
            "keywords": ["Flying", "Vigilance", "Deathtouch", "Lifelink", "Proliferate"],
            "legalities": {
                "standard": "not_legal",
                "commander": "legal",
                "modern": "not_legal"
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
            "id": "00000000-0000-7000-8000-000000000002",
            "oracle_id": "10000000-0000-7000-8000-000000000002",
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
                "commander": "legal",
                "modern": "legal",
                "standard": "not_legal"
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

    fn french_lightning_bolt_card() -> serde_json::Value {
        json!({
            "id": "00000000-0000-7000-8000-000000000003",
            "oracle_id": "10000000-0000-7000-8000-000000000003",
            "name": "Lightning Bolt",
            "printed_name": "Foudre",
            "printed_type_line": "Ephémère",
            "printed_text": "La Foudre inflige 3 blessures à n'importe quelle cible.",
            "lang": "fr",
            "released_at": "2017-03-17",
            "layout": "normal",
            "mana_cost": "{R}",
            "cmc": 1.0,
            "type_line": "Instant",
            "oracle_text": "Lightning Bolt deals 3 damage to any target.",
            "colors": ["R"],
            "color_identity": ["R"],
            "keywords": [],
            "legalities": {
                "commander": "legal",
                "modern": "legal"
            },
            "reserved": false,
            "game_changer": false,
            "edhrec_rank": 85,
            "set": "a25",
            "collector_number": "141",
            "rarity": "uncommon",
            "artist": "Christopher Rush",
            "prices": {
                "usd": "1.25",
                "eur": "1.00",
                "tix": "0.03"
            }
        })
    }
}

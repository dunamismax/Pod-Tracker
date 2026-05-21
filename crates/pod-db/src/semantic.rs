use sqlx::{FromRow, PgPool};
use uuid::Uuid;

use crate::{DbError, DeckRecord};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SemanticSearchStatus {
    pub pgvector_available: bool,
    pub card_embeddings_ready: bool,
    pub deck_embeddings_ready: bool,
}

impl SemanticSearchStatus {
    pub fn enabled(&self) -> bool {
        self.pgvector_available && (self.card_embeddings_ready || self.deck_embeddings_ready)
    }
}

#[derive(Debug, Clone, Copy)]
pub struct SemanticSearchInput<'a> {
    pub model: &'a str,
    pub embedding: &'a [f32],
    pub limit: Option<i64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SemanticCardSearchResult {
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
    pub semantic_similarity: f32,
    pub semantic_distance: f32,
    pub embedding_model: String,
    pub embedding_dimensions: i32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SemanticDeckSearchResult {
    pub deck: DeckRecord,
    pub semantic_similarity: f32,
    pub semantic_distance: f32,
    pub embedding_model: String,
    pub embedding_dimensions: i32,
}

#[derive(Debug, FromRow)]
struct SemanticCardSearchRow {
    scryfall_id: Uuid,
    oracle_id: Uuid,
    name: String,
    lang: String,
    printed_name: Option<String>,
    display_name: String,
    type_line: String,
    printed_type_line: Option<String>,
    display_type_line: String,
    oracle_text: String,
    printed_text: Option<String>,
    display_text: String,
    color_identity: Vec<String>,
    commander_legal: bool,
    mana_value: Option<f64>,
    usd: Option<f64>,
    game_changer: bool,
    semantic_similarity: f32,
    semantic_distance: f32,
    embedding_model: String,
    embedding_dimensions: i32,
}

#[derive(Debug, FromRow)]
struct SemanticDeckSearchRow {
    id: Uuid,
    owner_user_id: Uuid,
    playgroup_id: Option<Uuid>,
    name: String,
    commander: String,
    color_identity: String,
    claimed_bracket: String,
    archetype: String,
    tags: Vec<String>,
    visibility: String,
    status: String,
    game_changers_count: i32,
    has_infinite_combo: bool,
    has_fast_mana: bool,
    tutor_density: String,
    has_extra_turns: bool,
    has_mass_land_denial: bool,
    salt_notes: String,
    notes: String,
    created_at: time::OffsetDateTime,
    updated_at: time::OffsetDateTime,
    semantic_similarity: f32,
    semantic_distance: f32,
    embedding_model: String,
    embedding_dimensions: i32,
}

pub struct SemanticSearchRepository<'a> {
    pool: &'a PgPool,
}

impl<'a> SemanticSearchRepository<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }

    pub async fn status(&self) -> Result<SemanticSearchStatus, DbError> {
        let pgvector_available = extension_exists(self.pool, "vector").await?;
        if !pgvector_available {
            return Ok(SemanticSearchStatus {
                pgvector_available,
                card_embeddings_ready: false,
                deck_embeddings_ready: false,
            });
        }

        let card_embeddings_ready = table_exists(self.pool, "search", "card_semantic_embeddings")
            .await?
            && table_has_rows(self.pool, "search.card_semantic_embeddings").await?;
        let deck_embeddings_ready = table_exists(self.pool, "search", "deck_semantic_embeddings")
            .await?
            && table_has_rows(self.pool, "search.deck_semantic_embeddings").await?;

        Ok(SemanticSearchStatus {
            pgvector_available,
            card_embeddings_ready,
            deck_embeddings_ready,
        })
    }

    pub async fn search_cards(
        &self,
        input: SemanticSearchInput<'_>,
    ) -> Result<Vec<SemanticCardSearchResult>, DbError> {
        let Some(query_embedding) = vector_literal(input.embedding) else {
            return Ok(Vec::new());
        };
        let model = input.model.trim();
        if model.is_empty()
            || !extension_exists(self.pool, "vector").await?
            || !table_exists(self.pool, "search", "card_semantic_embeddings").await?
        {
            return Ok(Vec::new());
        }

        let limit = input.limit.unwrap_or(25).clamp(1, 100);
        let rows = sqlx::query_as::<_, SemanticCardSearchRow>(
            r#"
            select d.scryfall_id, d.oracle_id, d.name, d.lang, d.printed_name,
              coalesce(d.printed_name, d.name) as display_name,
              d.type_line, d.printed_type_line,
              coalesce(d.printed_type_line, d.type_line) as display_type_line,
              d.oracle_text, d.printed_text,
              coalesce(d.printed_text, d.oracle_text) as display_text,
              d.color_identity, d.commander_legal, d.mana_value, d.usd, d.game_changer,
              (1 - (e.embedding <=> $2::vector))::real as semantic_similarity,
              (e.embedding <=> $2::vector)::real as semantic_distance,
              e.model as embedding_model,
              e.dimensions as embedding_dimensions
            from search.card_semantic_embeddings e
            join search.card_documents d on d.oracle_id = e.oracle_id
            where e.model = $1
              and e.dimensions = $3
            order by e.embedding <=> $2::vector, d.name asc, d.scryfall_id asc
            limit $4
            "#,
        )
        .bind(model)
        .bind(&query_embedding)
        .bind(input.embedding.len() as i32)
        .bind(limit)
        .fetch_all(self.pool)
        .await?;

        Ok(rows
            .into_iter()
            .map(|row| SemanticCardSearchResult {
                scryfall_id: row.scryfall_id,
                oracle_id: row.oracle_id,
                name: row.name,
                lang: row.lang,
                printed_name: row.printed_name,
                display_name: row.display_name,
                type_line: row.type_line,
                printed_type_line: row.printed_type_line,
                display_type_line: row.display_type_line,
                oracle_text: row.oracle_text,
                printed_text: row.printed_text,
                display_text: row.display_text,
                color_identity: row.color_identity,
                commander_legal: row.commander_legal,
                mana_value: row.mana_value,
                usd: row.usd,
                game_changer: row.game_changer,
                semantic_similarity: row.semantic_similarity,
                semantic_distance: row.semantic_distance,
                embedding_model: row.embedding_model,
                embedding_dimensions: row.embedding_dimensions,
            })
            .collect())
    }

    pub async fn search_decks(
        &self,
        user_id: Uuid,
        input: SemanticSearchInput<'_>,
    ) -> Result<Vec<SemanticDeckSearchResult>, DbError> {
        let Some(query_embedding) = vector_literal(input.embedding) else {
            return Ok(Vec::new());
        };
        let model = input.model.trim();
        if model.is_empty()
            || !extension_exists(self.pool, "vector").await?
            || !table_exists(self.pool, "search", "deck_semantic_embeddings").await?
        {
            return Ok(Vec::new());
        }

        let limit = input.limit.unwrap_or(25).clamp(1, 100);
        let rows = sqlx::query_as::<_, SemanticDeckSearchRow>(
            r#"
            select d.id, d.owner_user_id, d.playgroup_id, d.name, d.commander,
              d.color_identity, d.claimed_bracket, d.archetype, d.tags, d.visibility,
              d.status, d.game_changers_count, d.has_infinite_combo, d.has_fast_mana,
              d.tutor_density, d.has_extra_turns, d.has_mass_land_denial,
              d.salt_notes, d.notes, d.created_at, d.updated_at,
              (1 - (e.embedding <=> $3::vector))::real as semantic_similarity,
              (e.embedding <=> $3::vector)::real as semantic_distance,
              e.model as embedding_model,
              e.dimensions as embedding_dimensions
            from search.deck_semantic_embeddings e
            join core.decks d on d.id = e.deck_id
            left join core.playgroup_memberships m
              on m.playgroup_id = d.playgroup_id
             and m.user_id = $1
            where e.model = $2
              and e.dimensions = $4
              and d.status = 'active'
              and (
                d.owner_user_id = $1
                or d.visibility = 'public'
                or (d.visibility = 'playgroup' and m.user_id is not null)
              )
            order by e.embedding <=> $3::vector, d.updated_at desc, d.name asc
            limit $5
            "#,
        )
        .bind(user_id)
        .bind(model)
        .bind(&query_embedding)
        .bind(input.embedding.len() as i32)
        .bind(limit)
        .fetch_all(self.pool)
        .await?;

        Ok(rows
            .into_iter()
            .map(|row| SemanticDeckSearchResult {
                deck: DeckRecord {
                    id: row.id,
                    owner_user_id: row.owner_user_id,
                    playgroup_id: row.playgroup_id,
                    name: row.name,
                    commander: row.commander,
                    color_identity: row.color_identity,
                    claimed_bracket: row.claimed_bracket,
                    archetype: row.archetype,
                    tags: row.tags,
                    visibility: row.visibility,
                    status: row.status,
                    game_changers_count: row.game_changers_count,
                    has_infinite_combo: row.has_infinite_combo,
                    has_fast_mana: row.has_fast_mana,
                    tutor_density: row.tutor_density,
                    has_extra_turns: row.has_extra_turns,
                    has_mass_land_denial: row.has_mass_land_denial,
                    salt_notes: row.salt_notes,
                    notes: row.notes,
                    created_at: row.created_at,
                    updated_at: row.updated_at,
                },
                semantic_similarity: row.semantic_similarity,
                semantic_distance: row.semantic_distance,
                embedding_model: row.embedding_model,
                embedding_dimensions: row.embedding_dimensions,
            })
            .collect())
    }
}

async fn extension_exists(pool: &PgPool, extension_name: &str) -> Result<bool, DbError> {
    let exists = sqlx::query_scalar::<_, bool>(
        r#"
        select exists (
          select 1
          from pg_extension
          where extname = $1
        )
        "#,
    )
    .bind(extension_name)
    .fetch_one(pool)
    .await?;

    Ok(exists)
}

async fn table_exists(pool: &PgPool, schema: &str, table: &str) -> Result<bool, DbError> {
    let exists = sqlx::query_scalar::<_, bool>(
        r#"
        select exists (
          select 1
          from information_schema.tables
          where table_schema = $1
            and table_name = $2
        )
        "#,
    )
    .bind(schema)
    .bind(table)
    .fetch_one(pool)
    .await?;

    Ok(exists)
}

async fn table_has_rows(pool: &PgPool, qualified_table: &str) -> Result<bool, DbError> {
    let sql = match qualified_table {
        "search.card_semantic_embeddings" => {
            "select exists (select 1 from search.card_semantic_embeddings limit 1)"
        }
        "search.deck_semantic_embeddings" => {
            "select exists (select 1 from search.deck_semantic_embeddings limit 1)"
        }
        _ => return Ok(false),
    };

    let has_rows = sqlx::query_scalar::<_, bool>(sql).fetch_one(pool).await?;

    Ok(has_rows)
}

fn vector_literal(values: &[f32]) -> Option<String> {
    if values.is_empty() || values.iter().any(|value| !value.is_finite()) {
        return None;
    }

    let values = values
        .iter()
        .map(|value| format!("{value:.8}"))
        .collect::<Vec<_>>()
        .join(",");

    Some(format!("[{values}]"))
}

#[cfg(test)]
mod tests {
    use super::{SemanticSearchInput, SemanticSearchRepository, vector_literal};
    use uuid::Uuid;

    #[test]
    fn vector_literal_rejects_empty_or_non_finite_embeddings() {
        assert_eq!(vector_literal(&[]), None);
        assert_eq!(vector_literal(&[1.0, f32::NAN]), None);
        assert_eq!(
            vector_literal(&[1.0, -0.25]),
            Some("[1.00000000,-0.25000000]".to_owned())
        );
    }

    #[sqlx::test(migrations = "./migrations")]
    async fn semantic_search_is_disabled_without_pgvector(pool: sqlx::PgPool) {
        let repo = SemanticSearchRepository::new(&pool);
        let status = repo.status().await.expect("status");
        assert!(!status.pgvector_available);
        assert!(!status.card_embeddings_ready);
        assert!(!status.deck_embeddings_ready);
        assert!(!status.enabled());

        let input = SemanticSearchInput {
            model: "local-test",
            embedding: &[0.1, 0.2, 0.3],
            limit: Some(5),
        };

        let cards = repo.search_cards(input).await.expect("card search");
        assert!(cards.is_empty());

        let decks = repo
            .search_decks(Uuid::now_v7(), input)
            .await
            .expect("deck search");
        assert!(decks.is_empty());
    }
}

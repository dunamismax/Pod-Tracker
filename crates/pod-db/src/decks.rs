use time::OffsetDateTime;
use uuid::Uuid;

use sqlx::PgPool;

use crate::{DbError, meta::enqueue_meta_dashboard_refresh};
use pod_core::{
    decklists::{DecklistEntry, parse_plain_text_decklist},
    decks::{SimilarDeckScoreInput, bracket_distance, color_overlap_count, similar_deck_score},
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeckRecord {
    pub id: Uuid,
    pub owner_user_id: Uuid,
    pub playgroup_id: Option<Uuid>,
    pub name: String,
    pub commander: String,
    pub color_identity: String,
    pub claimed_bracket: String,
    pub archetype: String,
    pub tags: Vec<String>,
    pub visibility: String,
    pub status: String,
    pub game_changers_count: i32,
    pub has_infinite_combo: bool,
    pub has_fast_mana: bool,
    pub tutor_density: String,
    pub has_extra_turns: bool,
    pub has_mass_land_denial: bool,
    pub salt_notes: String,
    pub notes: String,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventDeckDeclarationRecord {
    pub id: Uuid,
    pub event_id: Uuid,
    pub user_id: Uuid,
    pub deck_id: Uuid,
    pub preference: i32,
    pub testing_notes: String,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EventDeckDeclarationWithDeck {
    pub id: Uuid,
    pub event_id: Uuid,
    pub user_id: Uuid,
    pub deck_id: Uuid,
    pub preference: i32,
    pub testing_notes: String,
    pub deck_name: String,
    pub commander: String,
    pub color_identity: String,
    pub claimed_bracket: String,
    pub archetype: String,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeckVersionRecord {
    pub id: Uuid,
    pub deck_id: Uuid,
    pub version_number: i32,
    pub source_format: String,
    pub source_text: String,
    pub imported_at: OffsetDateTime,
    pub created_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DeckCardRecord {
    pub id: Uuid,
    pub deck_version_id: Uuid,
    pub oracle_id: Option<Uuid>,
    pub line_number: i32,
    pub quantity: i32,
    pub card_name: String,
    pub matched_name: Option<String>,
    pub section: String,
    pub match_status: String,
    pub match_method: String,
    pub name_similarity: Option<f32>,
    pub is_commander: bool,
    pub created_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeckBracketSnapshotRecord {
    pub id: Uuid,
    pub deck_version_id: Uuid,
    pub bracket_version_id: Option<Uuid>,
    pub game_changers_count: i32,
    pub commander_names: Vec<String>,
    pub color_identity: String,
    pub warning_codes: Vec<String>,
    pub warnings: Vec<String>,
    pub created_at: OffsetDateTime,
}

#[derive(Debug, Clone, Copy)]
pub struct DecklistImportInput<'a> {
    pub deck_id: Uuid,
    pub owner_user_id: Uuid,
    pub source_text: &'a str,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DecklistImportSummary {
    pub version: DeckVersionRecord,
    pub cards: Vec<DeckCardRecord>,
    pub snapshot: DeckBracketSnapshotRecord,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DecklistExportRecord {
    pub deck: DeckRecord,
    pub version: DeckVersionRecord,
    pub cards: Vec<DeckCardRecord>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SimilarDeckRecommendation {
    pub deck: DeckRecord,
    pub score: i32,
    pub shared_cards_count: i64,
    pub shared_tags: Vec<String>,
    pub reasons: Vec<String>,
}

#[derive(Debug, Clone, Copy)]
pub struct CreateDeckInput<'a> {
    pub owner_user_id: Uuid,
    pub playgroup_id: Option<Uuid>,
    pub name: &'a str,
    pub commander: &'a str,
    pub color_identity: &'a str,
    pub claimed_bracket: &'a str,
    pub archetype: &'a str,
    pub tags: &'a [String],
    pub visibility: &'a str,
    pub status: &'a str,
    pub game_changers_count: i32,
    pub has_infinite_combo: bool,
    pub has_fast_mana: bool,
    pub tutor_density: &'a str,
    pub has_extra_turns: bool,
    pub has_mass_land_denial: bool,
    pub salt_notes: &'a str,
    pub notes: &'a str,
}

#[derive(Debug, Clone, Copy)]
pub struct EventDeckDeclarationInput<'a> {
    pub event_id: Uuid,
    pub user_id: Uuid,
    pub deck_id: Uuid,
    pub preference: i32,
    pub testing_notes: &'a str,
}

#[derive(Debug, Clone, PartialEq)]
struct CardNameCandidate {
    oracle_id: Uuid,
    name: String,
    name_similarity: f32,
}

#[derive(Debug, Clone, PartialEq)]
struct CardNameResolution {
    oracle_id: Option<Uuid>,
    matched_name: Option<String>,
    match_status: &'static str,
    match_method: &'static str,
    name_similarity: Option<f32>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct SimilarDeckCandidateRow {
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
    created_at: OffsetDateTime,
    updated_at: OffsetDateTime,
    shared_cards_count: i64,
    shared_tags: Vec<String>,
}

pub struct DeckRepository<'a> {
    pool: &'a PgPool,
}

impl<'a> DeckRepository<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }

    pub async fn create_deck(&self, input: CreateDeckInput<'_>) -> Result<DeckRecord, DbError> {
        let deck = sqlx::query_as!(
            DeckRecord,
            r#"
            insert into core.decks (
              owner_user_id, playgroup_id, name, commander, color_identity,
              claimed_bracket, archetype, tags, visibility, status,
              game_changers_count, has_infinite_combo, has_fast_mana,
              tutor_density, has_extra_turns, has_mass_land_denial,
              salt_notes, notes
            )
            values (
              $1, $2, $3, $4, $5,
              $6, $7, $8, $9, $10,
              $11, $12, $13,
              $14, $15, $16,
              $17, $18
            )
            returning id, owner_user_id, playgroup_id, name, commander, color_identity,
              claimed_bracket, archetype, tags, visibility, status,
              game_changers_count, has_infinite_combo, has_fast_mana,
              tutor_density, has_extra_turns, has_mass_land_denial,
              salt_notes, notes, created_at, updated_at
            "#,
            input.owner_user_id,
            input.playgroup_id,
            input.name,
            input.commander,
            input.color_identity,
            input.claimed_bracket,
            input.archetype,
            input.tags,
            input.visibility,
            input.status,
            input.game_changers_count,
            input.has_infinite_combo,
            input.has_fast_mana,
            input.tutor_density,
            input.has_extra_turns,
            input.has_mass_land_denial,
            input.salt_notes,
            input.notes,
        )
        .fetch_one(self.pool)
        .await?;

        enqueue_meta_dashboard_refresh(self.pool).await?;

        Ok(deck)
    }

    pub async fn list_for_user(
        &self,
        user_id: Uuid,
        search: Option<&str>,
    ) -> Result<Vec<DeckRecord>, DbError> {
        let search = search.map(str::trim).filter(|value| !value.is_empty());
        let decks = sqlx::query_as!(
            DeckRecord,
            r#"
            select distinct d.id, d.owner_user_id, d.playgroup_id, d.name, d.commander,
              d.color_identity, d.claimed_bracket, d.archetype, d.tags, d.visibility,
              d.status, d.game_changers_count, d.has_infinite_combo, d.has_fast_mana,
              d.tutor_density, d.has_extra_turns, d.has_mass_land_denial,
              d.salt_notes, d.notes, d.created_at, d.updated_at
            from core.decks d
            left join core.playgroup_memberships m
              on m.playgroup_id = d.playgroup_id
             and m.user_id = $1
            where (
                d.owner_user_id = $1
                or d.visibility = 'public'
                or (d.visibility = 'playgroup' and m.user_id is not null)
              )
              and (
                $2::text is null
                or d.name ilike '%' || $2 || '%'
                or d.commander ilike '%' || $2 || '%'
                or d.archetype ilike '%' || $2 || '%'
                or exists (
                  select 1
                  from unnest(d.tags) as tag
                  where tag ilike '%' || $2 || '%'
                )
              )
            order by d.updated_at desc, d.name asc
            "#,
            user_id,
            search,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(decks)
    }

    pub async fn list_owned_active_for_user(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<DeckRecord>, DbError> {
        let decks = sqlx::query_as!(
            DeckRecord,
            r#"
            select id, owner_user_id, playgroup_id, name, commander, color_identity,
              claimed_bracket, archetype, tags, visibility, status,
              game_changers_count, has_infinite_combo, has_fast_mana,
              tutor_density, has_extra_turns, has_mass_land_denial,
              salt_notes, notes, created_at, updated_at
            from core.decks
            where owner_user_id = $1
              and status = 'active'
            order by name asc
            "#,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(decks)
    }

    pub async fn get_for_user(
        &self,
        deck_id: Uuid,
        user_id: Uuid,
    ) -> Result<Option<DeckRecord>, DbError> {
        let deck = sqlx::query_as!(
            DeckRecord,
            r#"
            select distinct d.id, d.owner_user_id, d.playgroup_id, d.name, d.commander,
              d.color_identity, d.claimed_bracket, d.archetype, d.tags, d.visibility,
              d.status, d.game_changers_count, d.has_infinite_combo, d.has_fast_mana,
              d.tutor_density, d.has_extra_turns, d.has_mass_land_denial,
              d.salt_notes, d.notes, d.created_at, d.updated_at
            from core.decks d
            left join core.playgroup_memberships m
              on m.playgroup_id = d.playgroup_id
             and m.user_id = $2
            where d.id = $1
              and (
                d.owner_user_id = $2
                or d.visibility = 'public'
                or (d.visibility = 'playgroup' and m.user_id is not null)
              )
            "#,
            deck_id,
            user_id,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(deck)
    }

    pub async fn similar_deck_recommendations(
        &self,
        deck_id: Uuid,
        user_id: Uuid,
        limit: i64,
    ) -> Result<Vec<SimilarDeckRecommendation>, DbError> {
        let Some(source) = self.get_for_user(deck_id, user_id).await? else {
            return Ok(Vec::new());
        };
        let fetch_limit = limit.max(1).saturating_mul(8);
        let candidates = sqlx::query_as!(
            SimilarDeckCandidateRow,
            r#"
            with source as (
              select d.id, d.tags
              from core.decks d
              left join core.playgroup_memberships source_membership
                on source_membership.playgroup_id = d.playgroup_id
               and source_membership.user_id = $2
              where d.id = $1
                and (
                  d.owner_user_id = $2
                  or d.visibility = 'public'
                  or (
                    d.visibility = 'playgroup'
                    and source_membership.user_id is not null
                  )
                )
            ),
            source_version as (
              select v.id
              from mtg.deck_versions v
              join source s on s.id = v.deck_id
              order by v.version_number desc
              limit 1
            ),
            source_cards as (
              select dc.oracle_id
              from mtg.deck_cards dc
              join source_version sv on sv.id = dc.deck_version_id
              where dc.match_status = 'matched'
                and dc.oracle_id is not null
              group by dc.oracle_id
            ),
            visible_candidates as (
              select distinct d.id, d.owner_user_id, d.playgroup_id, d.name, d.commander,
                d.color_identity, d.claimed_bracket, d.archetype, d.tags, d.visibility,
                d.status, d.game_changers_count, d.has_infinite_combo, d.has_fast_mana,
                d.tutor_density, d.has_extra_turns, d.has_mass_land_denial,
                d.salt_notes, d.notes, d.created_at, d.updated_at
              from core.decks d
              join source s on true
              left join core.playgroup_memberships m
                on m.playgroup_id = d.playgroup_id
               and m.user_id = $2
              where d.id <> s.id
                and d.status = 'active'
                and (
                  d.owner_user_id = $2
                  or d.visibility = 'public'
                  or (d.visibility = 'playgroup' and m.user_id is not null)
                )
            ),
            candidate_versions as (
              select distinct on (v.deck_id) v.deck_id, v.id
              from mtg.deck_versions v
              join visible_candidates c on c.id = v.deck_id
              order by v.deck_id, v.version_number desc
            ),
            card_overlap as (
              select cv.deck_id, count(distinct dc.oracle_id)::bigint as shared_cards_count
              from candidate_versions cv
              join mtg.deck_cards dc on dc.deck_version_id = cv.id
              join source_cards sc on sc.oracle_id = dc.oracle_id
              where dc.match_status = 'matched'
                and dc.oracle_id is not null
              group by cv.deck_id
            )
            select c.id, c.owner_user_id, c.playgroup_id, c.name, c.commander,
              c.color_identity, c.claimed_bracket, c.archetype, c.tags, c.visibility,
              c.status, c.game_changers_count, c.has_infinite_combo, c.has_fast_mana,
              c.tutor_density, c.has_extra_turns, c.has_mass_land_denial,
              c.salt_notes, c.notes, c.created_at, c.updated_at,
              coalesce(o.shared_cards_count, 0)::bigint as "shared_cards_count!",
              coalesce(
                array(
                  select candidate_tag
                  from unnest(c.tags) as candidate_tag
                  join source s on candidate_tag = any(s.tags)
                  order by candidate_tag
                ),
                '{}'
              ) as "shared_tags!"
            from visible_candidates c
            left join card_overlap o on o.deck_id = c.id
            order by coalesce(o.shared_cards_count, 0) desc, c.updated_at desc, c.name asc
            limit $3
            "#,
            deck_id,
            user_id,
            fetch_limit,
        )
        .fetch_all(self.pool)
        .await?;

        let mut recommendations = candidates
            .into_iter()
            .map(|candidate| build_similar_deck_recommendation(&source, candidate))
            .collect::<Vec<_>>();
        recommendations.sort_by(|left, right| {
            right
                .score
                .cmp(&left.score)
                .then_with(|| right.shared_cards_count.cmp(&left.shared_cards_count))
                .then_with(|| right.deck.updated_at.cmp(&left.deck.updated_at))
                .then_with(|| left.deck.name.cmp(&right.deck.name))
        });
        recommendations.truncate(limit.max(0) as usize);

        Ok(recommendations)
    }

    pub async fn declare_event_deck(
        &self,
        input: EventDeckDeclarationInput<'_>,
    ) -> Result<Option<EventDeckDeclarationRecord>, DbError> {
        let declaration = sqlx::query_as!(
            EventDeckDeclarationRecord,
            r#"
            insert into core.event_deck_declarations (
              event_id, user_id, deck_id, preference, testing_notes
            )
            select e.id, $2, d.id, $4, $5
            from core.events e
            join core.playgroup_memberships m
              on m.playgroup_id = e.playgroup_id
             and m.user_id = $2
            join core.decks d
              on d.id = $3
             and d.owner_user_id = $2
             and d.status = 'active'
            where e.id = $1
            on conflict (event_id, user_id, deck_id)
            do update set
              preference = excluded.preference,
              testing_notes = excluded.testing_notes,
              updated_at = now()
            returning id, event_id, user_id, deck_id, preference, testing_notes,
              created_at, updated_at
            "#,
            input.event_id,
            input.user_id,
            input.deck_id,
            input.preference,
            input.testing_notes,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(declaration)
    }

    pub async fn list_event_declarations(
        &self,
        event_id: Uuid,
    ) -> Result<Vec<EventDeckDeclarationWithDeck>, DbError> {
        let declarations = sqlx::query_as!(
            EventDeckDeclarationWithDeck,
            r#"
            select dec.id, dec.event_id, dec.user_id, dec.deck_id, dec.preference,
              dec.testing_notes, d.name as deck_name, d.commander, d.color_identity,
              d.claimed_bracket, d.archetype, dec.created_at, dec.updated_at
            from core.event_deck_declarations dec
            join core.decks d on d.id = dec.deck_id
            where dec.event_id = $1
            order by dec.preference asc, dec.created_at asc
            "#,
            event_id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(declarations)
    }

    pub async fn import_plain_text_decklist(
        &self,
        input: DecklistImportInput<'_>,
    ) -> Result<Option<DecklistImportSummary>, DbError> {
        let parsed = parse_plain_text_decklist(input.source_text);
        if parsed.entries.is_empty() {
            return Ok(None);
        }

        let mut tx = self.pool.begin().await?;
        let deck_exists = sqlx::query_scalar!(
            r#"
            select exists(
              select 1
              from core.decks
              where id = $1 and owner_user_id = $2
            ) as "exists!"
            "#,
            input.deck_id,
            input.owner_user_id,
        )
        .fetch_one(&mut *tx)
        .await?;
        if !deck_exists {
            tx.rollback().await?;
            return Ok(None);
        }

        let version_number = sqlx::query_scalar!(
            r#"
            select coalesce(max(version_number), 0)::int + 1 as "version_number!"
            from mtg.deck_versions
            where deck_id = $1
            "#,
            input.deck_id,
        )
        .fetch_one(&mut *tx)
        .await?;

        let version = sqlx::query_as!(
            DeckVersionRecord,
            r#"
            insert into mtg.deck_versions (
              deck_id, version_number, source_format, source_text
            )
            values ($1, $2, 'plain_text', $3)
            returning id, deck_id, version_number, source_format, source_text,
              imported_at, created_at
            "#,
            input.deck_id,
            version_number,
            input.source_text,
        )
        .fetch_one(&mut *tx)
        .await?;

        let mut cards = Vec::with_capacity(parsed.entries.len());
        for entry in &parsed.entries {
            let resolution = resolve_card_name(&mut tx, &entry.name).await?;
            cards.push(insert_deck_card(&mut tx, version.id, entry, resolution).await?);
        }

        let bracket_version_id = sqlx::query_scalar!(
            r#"
            select id
            from mtg.commander_bracket_versions
            where status = 'active'
            order by effective_date desc nulls last, created_at desc
            limit 1
            "#
        )
        .fetch_optional(&mut *tx)
        .await?;

        let game_changers_count = sqlx::query_scalar!(
            r#"
            select coalesce(sum(dc.quantity), 0)::int as "count!"
            from mtg.deck_cards dc
            join mtg.cards c on c.oracle_id = dc.oracle_id
            where dc.deck_version_id = $1
              and dc.match_status = 'matched'
              and (
                c.game_changer
                or exists (
                  select 1
                  from mtg.game_changer_lists gcl
                  join mtg.game_changer_cards gcc on gcc.list_id = gcl.id
                  where gcl.bracket_version_id = $2
                    and gcc.oracle_id = dc.oracle_id
                )
              )
            "#,
            version.id,
            bracket_version_id,
        )
        .fetch_one(&mut *tx)
        .await?;

        let color_identity = sqlx::query_scalar!(
            r#"
            with colors as (
              select distinct unnest(c.color_identity) as color
              from mtg.deck_cards dc
              join mtg.cards c on c.oracle_id = dc.oracle_id
              where dc.deck_version_id = $1
                and dc.match_status = 'matched'
            )
            select coalesce(
              string_agg(
                color,
                ''
                order by case color
                  when 'W' then 1
                  when 'U' then 2
                  when 'B' then 3
                  when 'R' then 4
                  when 'G' then 5
                  else 6
                end
              ),
              ''
            ) as "color_identity!"
            from colors
            "#,
            version.id,
        )
        .fetch_one(&mut *tx)
        .await?;

        let commander_names = parsed.commander_names();
        let unmatched_count = cards
            .iter()
            .filter(|card| card.match_status == "unmatched")
            .count();
        let ambiguous_count = cards
            .iter()
            .filter(|card| card.match_status == "ambiguous")
            .count();
        let (warning_codes, warnings) = bracket_warnings(
            game_changers_count,
            unmatched_count,
            ambiguous_count,
            commander_names.len(),
        );

        let snapshot = sqlx::query_as!(
            DeckBracketSnapshotRecord,
            r#"
            insert into mtg.deck_bracket_snapshots (
              deck_version_id, bracket_version_id, game_changers_count,
              commander_names, color_identity, warning_codes, warnings
            )
            values ($1, $2, $3, $4, $5, $6, $7)
            returning id, deck_version_id, bracket_version_id,
              game_changers_count, commander_names, color_identity,
              warning_codes, warnings, created_at
            "#,
            version.id,
            bracket_version_id,
            game_changers_count,
            &commander_names,
            color_identity,
            &warning_codes,
            &warnings,
        )
        .fetch_one(&mut *tx)
        .await?;

        let commander = commander_names.join(" / ");
        let commander = (!commander.is_empty()).then_some(commander);
        sqlx::query!(
            r#"
            update core.decks
            set commander = coalesce($2, commander),
                color_identity = $3,
                game_changers_count = $4,
                updated_at = now()
            where id = $1
            "#,
            input.deck_id,
            commander,
            snapshot.color_identity,
            snapshot.game_changers_count,
        )
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(Some(DecklistImportSummary {
            version,
            cards,
            snapshot,
        }))
    }

    pub async fn latest_bracket_snapshot_for_user(
        &self,
        deck_id: Uuid,
        user_id: Uuid,
    ) -> Result<Option<DeckBracketSnapshotRecord>, DbError> {
        let snapshot = sqlx::query_as!(
            DeckBracketSnapshotRecord,
            r#"
            select s.id, s.deck_version_id, s.bracket_version_id,
              s.game_changers_count, s.commander_names, s.color_identity,
              s.warning_codes, s.warnings, s.created_at
            from mtg.deck_bracket_snapshots s
            join mtg.deck_versions v on v.id = s.deck_version_id
            join core.decks d on d.id = v.deck_id
            left join core.playgroup_memberships m
              on m.playgroup_id = d.playgroup_id
             and m.user_id = $2
            where d.id = $1
              and (
                d.owner_user_id = $2
                or d.visibility = 'public'
                or (d.visibility = 'playgroup' and m.user_id is not null)
              )
            order by v.version_number desc
            limit 1
            "#,
            deck_id,
            user_id,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(snapshot)
    }

    pub async fn latest_decklist_export_for_owner(
        &self,
        deck_id: Uuid,
        owner_user_id: Uuid,
    ) -> Result<Option<DecklistExportRecord>, DbError> {
        let Some(deck) = self.get_owned_deck(deck_id, owner_user_id).await? else {
            return Ok(None);
        };
        let Some(version) = sqlx::query_as!(
            DeckVersionRecord,
            r#"
            select id, deck_id, version_number, source_format, source_text,
              imported_at, created_at
            from mtg.deck_versions
            where deck_id = $1
            order by version_number desc
            limit 1
            "#,
            deck_id,
        )
        .fetch_optional(self.pool)
        .await?
        else {
            return Ok(None);
        };

        let cards = sqlx::query_as!(
            DeckCardRecord,
            r#"
            select id, deck_version_id, oracle_id, line_number, quantity, card_name,
              matched_name, section, match_status, match_method, name_similarity,
              is_commander, created_at
            from mtg.deck_cards
            where deck_version_id = $1
            order by line_number asc, created_at asc, id asc
            "#,
            version.id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(Some(DecklistExportRecord {
            deck,
            version,
            cards,
        }))
    }

    async fn get_owned_deck(
        &self,
        deck_id: Uuid,
        owner_user_id: Uuid,
    ) -> Result<Option<DeckRecord>, DbError> {
        let deck = sqlx::query_as!(
            DeckRecord,
            r#"
            select id, owner_user_id, playgroup_id, name, commander, color_identity,
              claimed_bracket, archetype, tags, visibility, status,
              game_changers_count, has_infinite_combo, has_fast_mana,
              tutor_density, has_extra_turns, has_mass_land_denial,
              salt_notes, notes, created_at, updated_at
            from core.decks
            where id = $1 and owner_user_id = $2
            "#,
            deck_id,
            owner_user_id,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(deck)
    }
}

fn build_similar_deck_recommendation(
    source: &DeckRecord,
    candidate: SimilarDeckCandidateRow,
) -> SimilarDeckRecommendation {
    let deck = candidate.deck_record();
    let score = similar_deck_score(SimilarDeckScoreInput {
        current_commander: &source.commander,
        candidate_commander: &deck.commander,
        current_color_identity: &source.color_identity,
        candidate_color_identity: &deck.color_identity,
        current_claimed_bracket: &source.claimed_bracket,
        candidate_claimed_bracket: &deck.claimed_bracket,
        current_archetype: &source.archetype,
        candidate_archetype: &deck.archetype,
        shared_cards_count: candidate.shared_cards_count,
        shared_tags_count: candidate.shared_tags.len(),
    });
    let reasons = similar_deck_reasons(
        source,
        &deck,
        candidate.shared_cards_count,
        &candidate.shared_tags,
    );

    SimilarDeckRecommendation {
        deck,
        score,
        shared_cards_count: candidate.shared_cards_count,
        shared_tags: candidate.shared_tags,
        reasons,
    }
}

impl SimilarDeckCandidateRow {
    fn deck_record(&self) -> DeckRecord {
        DeckRecord {
            id: self.id,
            owner_user_id: self.owner_user_id,
            playgroup_id: self.playgroup_id,
            name: self.name.clone(),
            commander: self.commander.clone(),
            color_identity: self.color_identity.clone(),
            claimed_bracket: self.claimed_bracket.clone(),
            archetype: self.archetype.clone(),
            tags: self.tags.clone(),
            visibility: self.visibility.clone(),
            status: self.status.clone(),
            game_changers_count: self.game_changers_count,
            has_infinite_combo: self.has_infinite_combo,
            has_fast_mana: self.has_fast_mana,
            tutor_density: self.tutor_density.clone(),
            has_extra_turns: self.has_extra_turns,
            has_mass_land_denial: self.has_mass_land_denial,
            salt_notes: self.salt_notes.clone(),
            notes: self.notes.clone(),
            created_at: self.created_at,
            updated_at: self.updated_at,
        }
    }
}

fn similar_deck_reasons(
    source: &DeckRecord,
    candidate: &DeckRecord,
    shared_cards_count: i64,
    shared_tags: &[String],
) -> Vec<String> {
    let mut reasons = Vec::new();
    if shared_cards_count > 0 {
        reasons.push(format!("{shared_cards_count} shared imported cards"));
    }
    if source.commander.eq_ignore_ascii_case(&candidate.commander) {
        reasons.push("Same commander".to_owned());
    }
    if source.archetype.eq_ignore_ascii_case(&candidate.archetype) {
        reasons.push(format!("Same archetype: {}", candidate.archetype));
    }
    match bracket_distance(&source.claimed_bracket, &candidate.claimed_bracket) {
        Some(0) => reasons.push(format!("Same bracket: {}", candidate.claimed_bracket)),
        Some(1) => reasons.push(format!("Nearby bracket: {}", candidate.claimed_bracket)),
        _ => {}
    }
    let color_overlap = color_overlap_count(&source.color_identity, &candidate.color_identity);
    if color_overlap > 0 {
        reasons.push(format!(
            "{color_overlap} shared colors: {}",
            candidate.color_identity
        ));
    }
    if !shared_tags.is_empty() {
        reasons.push(format!("Shared tags: {}", shared_tags.join(", ")));
    }

    reasons
}

async fn insert_deck_card(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    deck_version_id: Uuid,
    entry: &DecklistEntry,
    resolution: CardNameResolution,
) -> Result<DeckCardRecord, DbError> {
    let card = sqlx::query_as!(
        DeckCardRecord,
        r#"
        insert into mtg.deck_cards (
          deck_version_id, oracle_id, line_number, quantity, card_name, matched_name,
          section, match_status, match_method, name_similarity, is_commander
        )
        values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        returning id, deck_version_id, oracle_id, line_number, quantity, card_name,
          matched_name, section, match_status, match_method, name_similarity,
          is_commander, created_at
        "#,
        deck_version_id,
        resolution.oracle_id,
        entry.line_number,
        entry.quantity,
        entry.name,
        resolution.matched_name,
        entry.section.as_str(),
        resolution.match_status,
        resolution.match_method,
        resolution.name_similarity,
        entry.is_commander,
    )
    .fetch_one(&mut **tx)
    .await?;

    Ok(card)
}

async fn resolve_card_name(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    name: &str,
) -> Result<CardNameResolution, DbError> {
    let exact = sqlx::query_as!(
        CardNameCandidate,
        r#"
        select distinct on (oracle_id)
          oracle_id,
          name,
          1::real as "name_similarity!"
        from search.card_documents
        where lower(name) = lower($1)
        order by oracle_id, name asc
        "#,
        name,
    )
    .fetch_all(&mut **tx)
    .await?;
    if let Some(resolution) = resolve_candidates(exact, "exact") {
        return Ok(resolution);
    }

    let normalized = pod_core::decklists::normalize_card_name(name);
    if !normalized.is_empty() {
        let normalized_matches = sqlx::query_as!(
            CardNameCandidate,
            r#"
            select distinct on (oracle_id)
              oracle_id,
              name,
              1::real as "name_similarity!"
            from search.card_documents
            where normalized_name = $1
            order by oracle_id, name asc
            "#,
            normalized,
        )
        .fetch_all(&mut **tx)
        .await?;
        if let Some(resolution) = resolve_candidates(normalized_matches, "normalized") {
            return Ok(resolution);
        }
    }

    let fuzzy = sqlx::query_as!(
        CardNameCandidate,
        r#"
        with candidates as (
          select
            oracle_id,
            name,
            greatest(
              similarity(name, $1),
              similarity(normalized_name, regexp_replace(lower($1), '[^a-z0-9]+', '', 'g'))
            )::real as name_similarity
          from search.card_documents
          where name % $1
            or normalized_name % regexp_replace(lower($1), '[^a-z0-9]+', '', 'g')
        )
        select distinct on (oracle_id)
          oracle_id,
          name,
          name_similarity as "name_similarity!"
        from candidates
        order by oracle_id, name_similarity desc, name asc
        limit 5
        "#,
        name,
    )
    .fetch_all(&mut **tx)
    .await?;

    Ok(
        resolve_candidates(fuzzy, "fuzzy").unwrap_or(CardNameResolution {
            oracle_id: None,
            matched_name: None,
            match_status: "unmatched",
            match_method: "",
            name_similarity: None,
        }),
    )
}

fn resolve_candidates(
    candidates: Vec<CardNameCandidate>,
    method: &'static str,
) -> Option<CardNameResolution> {
    match candidates.as_slice() {
        [] => None,
        [candidate] => Some(CardNameResolution {
            oracle_id: Some(candidate.oracle_id),
            matched_name: Some(candidate.name.clone()),
            match_status: "matched",
            match_method: method,
            name_similarity: Some(candidate.name_similarity),
        }),
        [first, ..] => Some(CardNameResolution {
            oracle_id: None,
            matched_name: Some(first.name.clone()),
            match_status: "ambiguous",
            match_method: method,
            name_similarity: Some(first.name_similarity),
        }),
    }
}

fn bracket_warnings(
    game_changers_count: i32,
    unmatched_count: usize,
    ambiguous_count: usize,
    commander_count: usize,
) -> (Vec<String>, Vec<String>) {
    let mut codes = Vec::new();
    let mut warnings = Vec::new();

    if commander_count == 0 {
        codes.push("missing_commander".to_owned());
        warnings
            .push("No commander was detected from a section header or commander tag.".to_owned());
    } else if commander_count > 2 {
        codes.push("too_many_commanders".to_owned());
        warnings.push(
            "More than two commanders were detected; review partner/background assumptions."
                .to_owned(),
        );
    }
    if game_changers_count > 0 {
        codes.push("game_changers_present".to_owned());
        warnings.push(format!(
            "{game_changers_count} Game Changer card(s) were matched in this list."
        ));
    }
    if unmatched_count > 0 {
        codes.push("unmatched_cards".to_owned());
        warnings.push(format!(
            "{unmatched_count} decklist line(s) did not match the local Scryfall index."
        ));
    }
    if ambiguous_count > 0 {
        codes.push("ambiguous_cards".to_owned());
        warnings.push(format!(
            "{ambiguous_count} decklist line(s) matched multiple local cards and need review."
        ));
    }

    (codes, warnings)
}

#[cfg(test)]
mod tests {
    use pod_core::playgroups::PlaygroupRole;
    use serde_json::json;

    use crate::{
        CreateDeckInput, CreateEventInput, DeckRepository, EventDeckDeclarationInput,
        EventRepository, IdentityRepository, PlaygroupRepository, ScryfallImportInput,
        ScryfallRepository,
    };

    fn deck_input<'a>(
        owner_user_id: uuid::Uuid,
        playgroup_id: Option<uuid::Uuid>,
        name: &'a str,
        visibility: &'a str,
        tags: &'a [String],
    ) -> CreateDeckInput<'a> {
        CreateDeckInput {
            owner_user_id,
            playgroup_id,
            name,
            commander: "Atraxa, Praetors' Voice",
            color_identity: "WUBG",
            claimed_bracket: "3",
            archetype: "Counters",
            tags,
            visibility,
            status: "active",
            game_changers_count: 1,
            has_infinite_combo: false,
            has_fast_mana: true,
            tutor_density: "medium",
            has_extra_turns: false,
            has_mass_land_denial: false,
            salt_notes: "Fast mana warning.",
            notes: "Main game-night deck.",
        }
    }

    #[sqlx::test(migrations = "./migrations")]
    async fn enforces_deck_visibility_and_event_declarations(pool: sqlx::PgPool) {
        let identity = IdentityRepository::new(&pool);
        let owner = identity
            .create_user(
                "deck-owner@example.test",
                "Deck Owner",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("owner");
        let member = identity
            .create_user(
                "deck-member@example.test",
                "Deck Member",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("member");
        let outsider = identity
            .create_user(
                "deck-outsider@example.test",
                "Deck Outsider",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("outsider");
        let playgroup = PlaygroupRepository::new(&pool)
            .create_playgroup(owner.id, "Deck Group", "deck-group", "")
            .await
            .expect("playgroup");
        PlaygroupRepository::new(&pool)
            .add_membership(playgroup.id, member.id, PlaygroupRole::Member, None)
            .await
            .expect("member membership");

        let repo = DeckRepository::new(&pool);
        let tags = vec!["counters".to_owned(), "midrange".to_owned()];
        let private_deck = repo
            .create_deck(deck_input(
                owner.id,
                None,
                "Private Atraxa",
                "private",
                &tags,
            ))
            .await
            .expect("private deck");
        let playgroup_deck = repo
            .create_deck(deck_input(
                owner.id,
                Some(playgroup.id),
                "Playgroup Atraxa",
                "playgroup",
                &tags,
            ))
            .await
            .expect("playgroup deck");
        let public_deck = repo
            .create_deck(deck_input(owner.id, None, "Public Atraxa", "public", &tags))
            .await
            .expect("public deck");

        assert!(
            repo.get_for_user(private_deck.id, member.id)
                .await
                .expect("private as member")
                .is_none()
        );
        assert!(
            repo.get_for_user(playgroup_deck.id, member.id)
                .await
                .expect("playgroup as member")
                .is_some()
        );
        assert!(
            repo.get_for_user(playgroup_deck.id, outsider.id)
                .await
                .expect("playgroup as outsider")
                .is_none()
        );
        assert!(
            repo.get_for_user(public_deck.id, outsider.id)
                .await
                .expect("public as outsider")
                .is_some()
        );
        assert_eq!(
            repo.list_for_user(member.id, Some("midrange"))
                .await
                .expect("search")
                .len(),
            2
        );

        let start_time =
            time::OffsetDateTime::from_unix_timestamp(1_800_000_000).expect("valid timestamp");
        let event = EventRepository::new(&pool)
            .create_event(CreateEventInput {
                playgroup_id: playgroup.id,
                title: "Deck Declaration Night",
                description: "",
                start_time,
                end_time: None,
                location: None,
                visibility: "members",
                invite_token: "deck-declaration-token",
                address_visibility: "hidden",
                created_by: owner.id,
            })
            .await
            .expect("event");

        assert!(
            repo.declare_event_deck(EventDeckDeclarationInput {
                event_id: event.id,
                user_id: member.id,
                deck_id: public_deck.id,
                preference: 2,
                testing_notes: "Borrowed deck attempt.",
            })
            .await
            .expect("borrowed declaration")
            .is_none()
        );
        let declaration = repo
            .declare_event_deck(EventDeckDeclarationInput {
                event_id: event.id,
                user_id: owner.id,
                deck_id: private_deck.id,
                preference: 1,
                testing_notes: "Testing a faster list.",
            })
            .await
            .expect("own declaration")
            .expect("own declaration");
        assert_eq!(declaration.preference, 1);
        assert_eq!(
            repo.list_event_declarations(event.id)
                .await
                .expect("declarations")
                .len(),
            1
        );
    }

    #[sqlx::test(migrations = "./migrations")]
    async fn imports_plain_text_decklists_with_matching_snapshots_and_owner_scope(
        pool: sqlx::PgPool,
    ) {
        let identity = IdentityRepository::new(&pool);
        let owner = identity
            .create_user(
                "deck-import-owner@example.test",
                "Deck Import Owner",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("owner");
        let outsider = identity
            .create_user(
                "deck-import-outsider@example.test",
                "Deck Import Outsider",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("outsider");

        let scryfall = ScryfallRepository::new(&pool);
        let metadata = json!({
            "type": "default_cards",
            "updated_at": "2026-05-18T09:09:27.689+00:00",
            "uri": "https://api.scryfall.com/bulk-data/e2ef41e3-5778-4bc2-af3f-78eca4dd9c23",
            "download_uri": "https://data.scryfall.io/default-cards/default-cards-20260518090927.json"
        });
        let import = scryfall
            .create_import(ScryfallImportInput {
                bulk_type: "default_cards",
                source_uri: metadata["uri"].as_str().expect("uri"),
                download_uri: metadata["download_uri"].as_str().expect("download_uri"),
                source_updated_at: time::OffsetDateTime::now_utc(),
                content_type: "application/json",
                content_encoding: Some("gzip"),
                size_bytes: Some(538_716_896),
                raw_metadata: &metadata,
            })
            .await
            .expect("create import");
        for card in [
            card_json(
                "00000000-0000-7000-8000-000000000101",
                "10000000-0000-7000-8000-000000000101",
                "Atraxa, Praetors' Voice",
                &["W", "U", "B", "G"],
                "Legendary Creature - Phyrexian Angel Horror",
                false,
            ),
            card_json(
                "00000000-0000-7000-8000-000000000102",
                "10000000-0000-7000-8000-000000000102",
                "Sol Ring",
                &[],
                "Artifact",
                false,
            ),
            card_json(
                "00000000-0000-7000-8000-000000000103",
                "10000000-0000-7000-8000-000000000103",
                "Storm-Kiln Artist",
                &["R"],
                "Creature - Dwarf Shaman",
                false,
            ),
            card_json(
                "00000000-0000-7000-8000-000000000104",
                "10000000-0000-7000-8000-000000000104",
                "Counterspell",
                &["U"],
                "Instant",
                false,
            ),
            card_json(
                "00000000-0000-7000-8000-000000000105",
                "10000000-0000-7000-8000-000000000105",
                "Fire/Ice",
                &["U", "R"],
                "Instant",
                false,
            ),
            card_json(
                "00000000-0000-7000-8000-000000000106",
                "10000000-0000-7000-8000-000000000106",
                "Fire Ice",
                &["U", "R"],
                "Instant",
                false,
            ),
        ] {
            scryfall
                .upsert_card_from_scryfall_json(import.id, &card)
                .await
                .expect("upsert card");
        }
        let bracket_version_id = sqlx::query_scalar!(
            r#"
            insert into mtg.commander_bracket_versions (name, source_uri, status)
            values ('Fixture Brackets', 'https://example.test/game-changers', 'active')
            returning id
            "#
        )
        .fetch_one(&pool)
        .await
        .expect("bracket version");
        let game_changer_list_id = sqlx::query_scalar!(
            r#"
            insert into mtg.game_changer_lists (bracket_version_id, name, source_uri)
            values ($1, 'Fixture Game Changers', 'https://example.test/game-changers')
            returning id
            "#,
            bracket_version_id
        )
        .fetch_one(&pool)
        .await
        .expect("game changer list");
        sqlx::query!(
            r#"
            insert into mtg.game_changer_cards (list_id, oracle_id, card_name)
            values ($1, $2, 'Sol Ring')
            "#,
            game_changer_list_id,
            uuid::Uuid::parse_str("10000000-0000-7000-8000-000000000102")
                .expect("sol ring oracle id"),
        )
        .execute(&pool)
        .await
        .expect("game changer card");

        let repo = DeckRepository::new(&pool);
        let tags = Vec::new();
        let deck = repo
            .create_deck(CreateDeckInput {
                owner_user_id: owner.id,
                playgroup_id: None,
                name: "Import Test Deck",
                commander: "Unreviewed Commander",
                color_identity: "",
                claimed_bracket: "3",
                archetype: "Midrange",
                tags: &tags,
                visibility: "private",
                status: "active",
                game_changers_count: 0,
                has_infinite_combo: false,
                has_fast_mana: false,
                tutor_density: "none",
                has_extra_turns: false,
                has_mass_land_denial: false,
                salt_notes: "",
                notes: "",
            })
            .await
            .expect("deck");

        let source = r#"
Commander
1 Atraxa, Praetors' Voice

Deck
1 Sol Ring
1 Storm Kiln Artist
1 Counterspel
1 Missing Card
1 Fire // Ice
"#;
        let denied = repo
            .import_plain_text_decklist(super::DecklistImportInput {
                deck_id: deck.id,
                owner_user_id: outsider.id,
                source_text: source,
            })
            .await
            .expect("outsider import");
        assert!(denied.is_none());

        let summary = repo
            .import_plain_text_decklist(super::DecklistImportInput {
                deck_id: deck.id,
                owner_user_id: owner.id,
                source_text: source,
            })
            .await
            .expect("owner import")
            .expect("summary");
        assert_eq!(summary.version.version_number, 1);
        assert_eq!(
            summary.snapshot.commander_names,
            vec!["Atraxa, Praetors' Voice"]
        );
        assert_eq!(summary.snapshot.color_identity, "WUBRG");
        assert_eq!(summary.snapshot.game_changers_count, 1);
        assert!(
            summary
                .snapshot
                .warning_codes
                .contains(&"game_changers_present".to_owned())
        );
        assert!(
            summary
                .snapshot
                .warning_codes
                .contains(&"unmatched_cards".to_owned())
        );
        assert!(
            summary
                .snapshot
                .warning_codes
                .contains(&"ambiguous_cards".to_owned())
        );

        assert!(summary.cards.iter().any(|card| {
            card.card_name == "Atraxa, Praetors' Voice"
                && card.line_number == 1
                && card.match_status == "matched"
                && card.match_method == "exact"
                && card.is_commander
        }));
        assert!(summary.cards.iter().any(|card| {
            card.card_name == "Storm Kiln Artist"
                && card.match_status == "matched"
                && card.match_method == "normalized"
        }));
        assert!(summary.cards.iter().any(|card| {
            card.card_name == "Counterspel"
                && card.match_status == "matched"
                && card.match_method == "fuzzy"
        }));
        assert!(
            summary.cards.iter().any(|card| {
                card.card_name == "Missing Card" && card.match_status == "unmatched"
            })
        );
        assert!(
            summary.cards.iter().any(|card| {
                card.card_name == "Fire // Ice" && card.match_status == "ambiguous"
            })
        );

        let updated = repo
            .get_for_user(deck.id, owner.id)
            .await
            .expect("updated deck")
            .expect("updated deck");
        assert_eq!(updated.commander, "Atraxa, Praetors' Voice");
        assert_eq!(updated.color_identity, "WUBRG");
        assert_eq!(updated.game_changers_count, 1);

        let outsider_export = repo
            .latest_decklist_export_for_owner(deck.id, outsider.id)
            .await
            .expect("outsider export");
        assert!(outsider_export.is_none());

        let export = repo
            .latest_decklist_export_for_owner(deck.id, owner.id)
            .await
            .expect("owner export")
            .expect("export");
        assert_eq!(export.version.id, summary.version.id);
        assert_eq!(export.cards.len(), 6);
        assert_eq!(export.cards[0].card_name, "Atraxa, Praetors' Voice");
        assert!(export.cards[0].is_commander);
        assert_eq!(export.cards[0].section, "commander");
        assert_eq!(export.cards[5].card_name, "Fire // Ice");
        assert_eq!(export.cards[5].match_status, "ambiguous");
    }

    #[sqlx::test(migrations = "./migrations")]
    async fn recommends_similar_decks_with_visible_scope_and_import_overlap(pool: sqlx::PgPool) {
        let identity = IdentityRepository::new(&pool);
        let owner = identity
            .create_user(
                "deck-rec-owner@example.test",
                "Deck Recommendation Owner",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("owner");
        let member = identity
            .create_user(
                "deck-rec-member@example.test",
                "Deck Recommendation Member",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("member");
        let outsider = identity
            .create_user(
                "deck-rec-outsider@example.test",
                "Deck Recommendation Outsider",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("outsider");
        let playgroup = PlaygroupRepository::new(&pool)
            .create_playgroup(owner.id, "Recommendation Group", "recommendation-group", "")
            .await
            .expect("playgroup");
        PlaygroupRepository::new(&pool)
            .add_membership(playgroup.id, member.id, PlaygroupRole::Member, None)
            .await
            .expect("member membership");

        let scryfall = ScryfallRepository::new(&pool);
        let metadata = json!({
            "type": "default_cards",
            "updated_at": "2026-05-19T09:09:27.689+00:00",
            "uri": "https://api.scryfall.com/bulk-data/recommendations",
            "download_uri": "https://data.scryfall.io/default-cards/recommendations.json"
        });
        let import = scryfall
            .create_import(ScryfallImportInput {
                bulk_type: "default_cards",
                source_uri: metadata["uri"].as_str().expect("uri"),
                download_uri: metadata["download_uri"].as_str().expect("download_uri"),
                source_updated_at: time::OffsetDateTime::now_utc(),
                content_type: "application/json",
                content_encoding: Some("gzip"),
                size_bytes: Some(128),
                raw_metadata: &metadata,
            })
            .await
            .expect("create import");
        for card in [
            card_json(
                "00000000-0000-7000-8000-000000000301",
                "10000000-0000-7000-8000-000000000301",
                "Atraxa, Praetors' Voice",
                &["W", "U", "B", "G"],
                "Legendary Creature - Phyrexian Angel Horror",
                false,
            ),
            card_json(
                "00000000-0000-7000-8000-000000000302",
                "10000000-0000-7000-8000-000000000302",
                "Sol Ring",
                &[],
                "Artifact",
                false,
            ),
            card_json(
                "00000000-0000-7000-8000-000000000303",
                "10000000-0000-7000-8000-000000000303",
                "Counterspell",
                &["U"],
                "Instant",
                false,
            ),
        ] {
            scryfall
                .upsert_card_from_scryfall_json(import.id, &card)
                .await
                .expect("upsert card");
        }

        let repo = DeckRepository::new(&pool);
        let source_tags = vec!["counters".to_owned(), "midrange".to_owned()];
        let similar_tags = vec!["counters".to_owned(), "value".to_owned()];
        let distant_tags = vec!["tokens".to_owned()];
        let source = repo
            .create_deck(CreateDeckInput {
                owner_user_id: owner.id,
                playgroup_id: Some(playgroup.id),
                name: "Atraxa Counters",
                commander: "Atraxa, Praetors' Voice",
                color_identity: "WUBG",
                claimed_bracket: "3",
                archetype: "Counters",
                tags: &source_tags,
                visibility: "private",
                status: "active",
                game_changers_count: 0,
                has_infinite_combo: false,
                has_fast_mana: false,
                tutor_density: "low",
                has_extra_turns: false,
                has_mass_land_denial: false,
                salt_notes: "",
                notes: "",
            })
            .await
            .expect("source deck");
        let similar = repo
            .create_deck(CreateDeckInput {
                owner_user_id: member.id,
                playgroup_id: Some(playgroup.id),
                name: "Atraxa Value",
                commander: "Atraxa, Praetors' Voice",
                color_identity: "WUG",
                claimed_bracket: "3",
                archetype: "Counters",
                tags: &similar_tags,
                visibility: "playgroup",
                status: "active",
                game_changers_count: 0,
                has_infinite_combo: false,
                has_fast_mana: false,
                tutor_density: "low",
                has_extra_turns: false,
                has_mass_land_denial: false,
                salt_notes: "",
                notes: "",
            })
            .await
            .expect("similar deck");
        let distant = repo
            .create_deck(CreateDeckInput {
                owner_user_id: member.id,
                playgroup_id: Some(playgroup.id),
                name: "Krenko Tokens",
                commander: "Krenko, Mob Boss",
                color_identity: "R",
                claimed_bracket: "1",
                archetype: "Tokens",
                tags: &distant_tags,
                visibility: "playgroup",
                status: "active",
                game_changers_count: 0,
                has_infinite_combo: false,
                has_fast_mana: false,
                tutor_density: "none",
                has_extra_turns: false,
                has_mass_land_denial: false,
                salt_notes: "",
                notes: "",
            })
            .await
            .expect("distant deck");
        let hidden = repo
            .create_deck(CreateDeckInput {
                owner_user_id: outsider.id,
                playgroup_id: None,
                name: "Hidden Atraxa",
                commander: "Atraxa, Praetors' Voice",
                color_identity: "WUBG",
                claimed_bracket: "3",
                archetype: "Counters",
                tags: &source_tags,
                visibility: "private",
                status: "active",
                game_changers_count: 0,
                has_infinite_combo: false,
                has_fast_mana: false,
                tutor_density: "low",
                has_extra_turns: false,
                has_mass_land_denial: false,
                salt_notes: "",
                notes: "",
            })
            .await
            .expect("hidden deck");

        let source_text =
            "Commander\n1 Atraxa, Praetors' Voice\n\nDeck\n1 Sol Ring\n1 Counterspell";
        repo.import_plain_text_decklist(super::DecklistImportInput {
            deck_id: source.id,
            owner_user_id: owner.id,
            source_text,
        })
        .await
        .expect("import source")
        .expect("source summary");
        repo.import_plain_text_decklist(super::DecklistImportInput {
            deck_id: similar.id,
            owner_user_id: member.id,
            source_text,
        })
        .await
        .expect("import similar")
        .expect("similar summary");
        repo.import_plain_text_decklist(super::DecklistImportInput {
            deck_id: hidden.id,
            owner_user_id: outsider.id,
            source_text,
        })
        .await
        .expect("import hidden")
        .expect("hidden summary");

        let recommendations = repo
            .similar_deck_recommendations(source.id, owner.id, 5)
            .await
            .expect("recommendations");
        assert_eq!(recommendations[0].deck.id, similar.id);
        assert!(recommendations[0].score > 0);
        assert!(recommendations[0].shared_cards_count >= 3);
        assert!(
            recommendations[0]
                .shared_tags
                .contains(&"counters".to_owned())
        );
        assert!(
            recommendations[0]
                .reasons
                .iter()
                .any(|reason| reason.contains("shared imported cards"))
        );
        assert!(recommendations.iter().any(|rec| rec.deck.id == distant.id));
        assert!(!recommendations.iter().any(|rec| rec.deck.id == hidden.id));
    }

    fn card_json(
        scryfall_id: &str,
        oracle_id: &str,
        name: &str,
        color_identity: &[&str],
        type_line: &str,
        game_changer: bool,
    ) -> serde_json::Value {
        json!({
            "id": scryfall_id,
            "oracle_id": oracle_id,
            "name": name,
            "lang": "en",
            "released_at": "2026-01-01",
            "layout": "normal",
            "mana_cost": "",
            "cmc": 1.0,
            "type_line": type_line,
            "oracle_text": "Fixture card.",
            "colors": color_identity,
            "color_identity": color_identity,
            "keywords": [],
            "legalities": {
                "commander": "legal"
            },
            "reserved": false,
            "game_changer": game_changer,
            "edhrec_rank": 100,
            "set": "tst",
            "collector_number": "1",
            "rarity": "rare",
            "artist": "Fixture Artist",
            "prices": {
                "usd": "1.00"
            }
        })
    }
}

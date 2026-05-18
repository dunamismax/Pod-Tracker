use time::OffsetDateTime;
use uuid::Uuid;

use sqlx::PgPool;

use crate::DbError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CollectionRecord {
    pub id: Uuid,
    pub owner_user_id: Uuid,
    pub playgroup_id: Option<Uuid>,
    pub name: String,
    pub visibility: String,
    pub notes: String,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CollectionCardRecord {
    pub id: Uuid,
    pub collection_id: Uuid,
    pub oracle_id: Uuid,
    pub scryfall_id: Option<Uuid>,
    pub card_name: String,
    pub quantity: i32,
    pub foil: bool,
    pub condition: String,
    pub location: String,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WishlistRecord {
    pub id: Uuid,
    pub owner_user_id: Uuid,
    pub playgroup_id: Option<Uuid>,
    pub name: String,
    pub visibility: String,
    pub notes: String,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WishlistCardRecord {
    pub id: Uuid,
    pub wishlist_id: Uuid,
    pub oracle_id: Uuid,
    pub card_name: String,
    pub desired_quantity: i32,
    pub priority: String,
    pub notes: String,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeckMissingCardRecord {
    pub oracle_id: Uuid,
    pub card_name: String,
    pub section: String,
    pub is_commander: bool,
    pub required_quantity: i64,
    pub owned_quantity: i64,
    pub missing_quantity: i64,
}

#[derive(Debug, Clone, Copy)]
pub struct CreateCollectionInput<'a> {
    pub owner_user_id: Uuid,
    pub playgroup_id: Option<Uuid>,
    pub name: &'a str,
    pub visibility: &'a str,
    pub notes: &'a str,
}

#[derive(Debug, Clone, Copy)]
pub struct AddCollectionCardInput<'a> {
    pub collection_id: Uuid,
    pub owner_user_id: Uuid,
    pub card_name: &'a str,
    pub set_code: Option<&'a str>,
    pub collector_number: Option<&'a str>,
    pub quantity: i32,
    pub foil: bool,
    pub condition: &'a str,
    pub location: &'a str,
}

#[derive(Debug, Clone, Copy)]
pub struct CreateWishlistInput<'a> {
    pub owner_user_id: Uuid,
    pub playgroup_id: Option<Uuid>,
    pub name: &'a str,
    pub visibility: &'a str,
    pub notes: &'a str,
}

#[derive(Debug, Clone, Copy)]
pub struct AddWishlistCardInput<'a> {
    pub wishlist_id: Uuid,
    pub owner_user_id: Uuid,
    pub card_name: &'a str,
    pub desired_quantity: i32,
    pub priority: &'a str,
    pub notes: &'a str,
}

#[derive(Debug, Clone, PartialEq)]
struct CardResolution {
    oracle_id: Uuid,
    scryfall_id: Option<Uuid>,
    name: String,
    name_similarity: f32,
}

pub struct CollectionRepository<'a> {
    pool: &'a PgPool,
}

impl<'a> CollectionRepository<'a> {
    pub fn new(pool: &'a PgPool) -> Self {
        Self { pool }
    }

    pub async fn create_collection(
        &self,
        input: CreateCollectionInput<'_>,
    ) -> Result<Option<CollectionRecord>, DbError> {
        let collection = sqlx::query_as!(
            CollectionRecord,
            r#"
            insert into core.collections (
              owner_user_id, playgroup_id, name, visibility, notes
            )
            select $1, $2, $3, $4, $5
            where $2::uuid is null
               or exists (
                 select 1
                 from core.playgroup_memberships
                 where playgroup_id = $2 and user_id = $1
               )
            returning id, owner_user_id, playgroup_id, name, visibility, notes,
              created_at, updated_at
            "#,
            input.owner_user_id,
            input.playgroup_id,
            input.name,
            input.visibility,
            input.notes,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(collection)
    }

    pub async fn list_collections_for_user(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<CollectionRecord>, DbError> {
        let collections = sqlx::query_as!(
            CollectionRecord,
            r#"
            select distinct c.id, c.owner_user_id, c.playgroup_id, c.name,
              c.visibility, c.notes, c.created_at, c.updated_at
            from core.collections c
            left join core.playgroup_memberships m
              on m.playgroup_id = c.playgroup_id
             and m.user_id = $1
            where c.owner_user_id = $1
               or c.visibility = 'public'
               or (c.visibility = 'playgroup' and m.user_id is not null)
            order by c.updated_at desc, c.name asc
            "#,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(collections)
    }

    pub async fn get_collection_for_user(
        &self,
        collection_id: Uuid,
        user_id: Uuid,
    ) -> Result<Option<CollectionRecord>, DbError> {
        let collection = sqlx::query_as!(
            CollectionRecord,
            r#"
            select distinct c.id, c.owner_user_id, c.playgroup_id, c.name,
              c.visibility, c.notes, c.created_at, c.updated_at
            from core.collections c
            left join core.playgroup_memberships m
              on m.playgroup_id = c.playgroup_id
             and m.user_id = $2
            where c.id = $1
              and (
                c.owner_user_id = $2
                or c.visibility = 'public'
                or (c.visibility = 'playgroup' and m.user_id is not null)
              )
            "#,
            collection_id,
            user_id,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(collection)
    }

    pub async fn list_collection_cards_for_user(
        &self,
        collection_id: Uuid,
        user_id: Uuid,
    ) -> Result<Vec<CollectionCardRecord>, DbError> {
        let cards = sqlx::query_as!(
            CollectionCardRecord,
            r#"
            select cc.id, cc.collection_id, cc.oracle_id, cc.scryfall_id,
              cc.card_name, cc.quantity, cc.foil, cc.condition, cc.location,
              cc.created_at, cc.updated_at
            from core.collection_cards cc
            join core.collections c on c.id = cc.collection_id
            left join core.playgroup_memberships m
              on m.playgroup_id = c.playgroup_id
             and m.user_id = $2
            where cc.collection_id = $1
              and (
                c.owner_user_id = $2
                or c.visibility = 'public'
                or (c.visibility = 'playgroup' and m.user_id is not null)
              )
            order by cc.card_name asc, cc.foil desc, cc.condition asc, cc.location asc
            "#,
            collection_id,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(cards)
    }

    pub async fn add_collection_card(
        &self,
        input: AddCollectionCardInput<'_>,
    ) -> Result<Option<CollectionCardRecord>, DbError> {
        if input.quantity <= 0 {
            return Ok(None);
        }
        let Some(resolution) = resolve_card(
            self.pool,
            input.card_name,
            input.set_code,
            input.collector_number,
        )
        .await?
        else {
            return Ok(None);
        };

        let mut tx = self.pool.begin().await?;
        let owns_collection = sqlx::query_scalar!(
            r#"
            select exists(
              select 1
              from core.collections
              where id = $1 and owner_user_id = $2
            ) as "owns_collection!"
            "#,
            input.collection_id,
            input.owner_user_id,
        )
        .fetch_one(&mut *tx)
        .await?;
        if !owns_collection {
            tx.rollback().await?;
            return Ok(None);
        }

        let existing_id = sqlx::query_scalar!(
            r#"
            select id
            from core.collection_cards
            where collection_id = $1
              and oracle_id = $2
              and scryfall_id is not distinct from $3
              and foil = $4
              and condition = $5
              and location = $6
            "#,
            input.collection_id,
            resolution.oracle_id,
            resolution.scryfall_id,
            input.foil,
            input.condition,
            input.location,
        )
        .fetch_optional(&mut *tx)
        .await?;

        let card = if let Some(existing_id) = existing_id {
            sqlx::query_as!(
                CollectionCardRecord,
                r#"
                update core.collection_cards
                set quantity = quantity + $2,
                    card_name = $3,
                    updated_at = now()
                where id = $1
                returning id, collection_id, oracle_id, scryfall_id, card_name,
                  quantity, foil, condition, location, created_at, updated_at
                "#,
                existing_id,
                input.quantity,
                resolution.name,
            )
            .fetch_one(&mut *tx)
            .await?
        } else {
            sqlx::query_as!(
                CollectionCardRecord,
                r#"
                insert into core.collection_cards (
                  collection_id, oracle_id, scryfall_id, card_name, quantity,
                  foil, condition, location
                )
                values ($1, $2, $3, $4, $5, $6, $7, $8)
                returning id, collection_id, oracle_id, scryfall_id, card_name,
                  quantity, foil, condition, location, created_at, updated_at
                "#,
                input.collection_id,
                resolution.oracle_id,
                resolution.scryfall_id,
                resolution.name,
                input.quantity,
                input.foil,
                input.condition,
                input.location,
            )
            .fetch_one(&mut *tx)
            .await?
        };

        tx.commit().await?;
        Ok(Some(card))
    }

    pub async fn missing_cards_for_deck(
        &self,
        deck_id: Uuid,
        collection_id: Uuid,
        user_id: Uuid,
    ) -> Result<Vec<DeckMissingCardRecord>, DbError> {
        let missing = sqlx::query_as!(
            DeckMissingCardRecord,
            r#"
            with visible_deck as (
              select d.id
              from core.decks d
              left join core.playgroup_memberships m
                on m.playgroup_id = d.playgroup_id
               and m.user_id = $3
              where d.id = $1
                and (
                  d.owner_user_id = $3
                  or d.visibility = 'public'
                  or (d.visibility = 'playgroup' and m.user_id is not null)
                )
            ),
            visible_collection as (
              select c.id
              from core.collections c
              left join core.playgroup_memberships m
                on m.playgroup_id = c.playgroup_id
               and m.user_id = $3
              where c.id = $2
                and (
                  c.owner_user_id = $3
                  or c.visibility = 'public'
                  or (c.visibility = 'playgroup' and m.user_id is not null)
                )
            ),
            latest_version as (
              select v.id
              from mtg.deck_versions v
              join visible_deck d on d.id = v.deck_id
              order by v.version_number desc
              limit 1
            ),
            required_cards as (
              select
                dc.oracle_id,
                coalesce(dc.matched_name, dc.card_name) as card_name,
                dc.section,
                bool_or(dc.is_commander) as is_commander,
                sum(dc.quantity)::bigint as required_quantity
              from mtg.deck_cards dc
              join latest_version v on v.id = dc.deck_version_id
              where dc.oracle_id is not null
                and dc.match_status = 'matched'
              group by dc.oracle_id, coalesce(dc.matched_name, dc.card_name), dc.section
            ),
            owned_cards as (
              select cc.oracle_id, sum(cc.quantity)::bigint as owned_quantity
              from core.collection_cards cc
              join visible_collection c on c.id = cc.collection_id
              group by cc.oracle_id
            )
            select
              r.oracle_id as "oracle_id!",
              r.card_name as "card_name!",
              r.section as "section!",
              r.is_commander as "is_commander!",
              r.required_quantity as "required_quantity!",
              coalesce(o.owned_quantity, 0)::bigint as "owned_quantity!",
              greatest(r.required_quantity - coalesce(o.owned_quantity, 0), 0)::bigint
                as "missing_quantity!"
            from required_cards r
            left join owned_cards o on o.oracle_id = r.oracle_id
            where greatest(r.required_quantity - coalesce(o.owned_quantity, 0), 0) > 0
            order by r.is_commander desc, r.section asc, r.card_name asc
            "#,
            deck_id,
            collection_id,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(missing)
    }

    pub async fn create_wishlist(
        &self,
        input: CreateWishlistInput<'_>,
    ) -> Result<Option<WishlistRecord>, DbError> {
        let wishlist = sqlx::query_as!(
            WishlistRecord,
            r#"
            insert into core.wishlists (
              owner_user_id, playgroup_id, name, visibility, notes
            )
            select $1, $2, $3, $4, $5
            where $2::uuid is null
               or exists (
                 select 1
                 from core.playgroup_memberships
                 where playgroup_id = $2 and user_id = $1
               )
            returning id, owner_user_id, playgroup_id, name, visibility, notes,
              created_at, updated_at
            "#,
            input.owner_user_id,
            input.playgroup_id,
            input.name,
            input.visibility,
            input.notes,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(wishlist)
    }

    pub async fn list_wishlists_for_user(
        &self,
        user_id: Uuid,
    ) -> Result<Vec<WishlistRecord>, DbError> {
        let wishlists = sqlx::query_as!(
            WishlistRecord,
            r#"
            select distinct w.id, w.owner_user_id, w.playgroup_id, w.name,
              w.visibility, w.notes, w.created_at, w.updated_at
            from core.wishlists w
            left join core.playgroup_memberships m
              on m.playgroup_id = w.playgroup_id
             and m.user_id = $1
            where w.owner_user_id = $1
               or w.visibility = 'public'
               or (w.visibility = 'playgroup' and m.user_id is not null)
            order by w.updated_at desc, w.name asc
            "#,
            user_id,
        )
        .fetch_all(self.pool)
        .await?;

        Ok(wishlists)
    }

    pub async fn add_wishlist_card(
        &self,
        input: AddWishlistCardInput<'_>,
    ) -> Result<Option<WishlistCardRecord>, DbError> {
        if input.desired_quantity <= 0 {
            return Ok(None);
        }
        let Some(resolution) = resolve_card(self.pool, input.card_name, None, None).await? else {
            return Ok(None);
        };

        let card = sqlx::query_as!(
            WishlistCardRecord,
            r#"
            insert into core.wishlist_cards (
              wishlist_id, oracle_id, card_name, desired_quantity, priority, notes
            )
            select w.id, $3, $4, $5, $6, $7
            from core.wishlists w
            where w.id = $1 and w.owner_user_id = $2
            on conflict (wishlist_id, oracle_id)
            do update set
              card_name = excluded.card_name,
              desired_quantity = excluded.desired_quantity,
              priority = excluded.priority,
              notes = excluded.notes,
              updated_at = now()
            returning id, wishlist_id, oracle_id, card_name, desired_quantity,
              priority, notes, created_at, updated_at
            "#,
            input.wishlist_id,
            input.owner_user_id,
            resolution.oracle_id,
            resolution.name,
            input.desired_quantity,
            input.priority,
            input.notes,
        )
        .fetch_optional(self.pool)
        .await?;

        Ok(card)
    }
}

async fn resolve_card(
    pool: &PgPool,
    card_name: &str,
    set_code: Option<&str>,
    collector_number: Option<&str>,
) -> Result<Option<CardResolution>, DbError> {
    let set_code = set_code.map(str::trim).filter(|value| !value.is_empty());
    let collector_number = collector_number
        .map(str::trim)
        .filter(|value| !value.is_empty());
    if let (Some(set_code), Some(collector_number)) = (set_code, collector_number) {
        let printing = sqlx::query_as!(
            CardResolution,
            r#"
            select c.oracle_id, p.scryfall_id, c.name, 1::real as "name_similarity!"
            from mtg.card_printings p
            join mtg.cards c on c.oracle_id = p.oracle_id
            where lower(p.set_code) = lower($1)
              and p.collector_number = $2
            order by p.released_at desc nulls last, c.name asc
            limit 1
            "#,
            set_code,
            collector_number,
        )
        .fetch_optional(pool)
        .await?;
        if printing.is_some() {
            return Ok(printing);
        }
    }

    let exact = sqlx::query_as!(
        CardResolution,
        r#"
        select distinct on (oracle_id)
          oracle_id,
          scryfall_id,
          name,
          1::real as "name_similarity!"
        from search.card_documents
        where lower(name) = lower($1)
        order by oracle_id, name asc
        limit 1
        "#,
        card_name,
    )
    .fetch_optional(pool)
    .await?;
    if exact.is_some() {
        return Ok(exact);
    }

    let normalized = pod_core::decklists::normalize_card_name(card_name);
    if !normalized.is_empty() {
        let normalized_match = sqlx::query_as!(
            CardResolution,
            r#"
            select distinct on (oracle_id)
              oracle_id,
              scryfall_id,
              name,
              1::real as "name_similarity!"
            from search.card_documents
            where normalized_name = $1
            order by oracle_id, name asc
            limit 1
            "#,
            normalized,
        )
        .fetch_optional(pool)
        .await?;
        if normalized_match.is_some() {
            return Ok(normalized_match);
        }
    }

    let fuzzy = sqlx::query_as!(
        CardResolution,
        r#"
        with candidates as (
          select
            oracle_id,
            scryfall_id,
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
          scryfall_id,
          name,
          name_similarity as "name_similarity!"
        from candidates
        order by oracle_id, name_similarity desc, name asc
        limit 1
        "#,
        card_name,
    )
    .fetch_optional(pool)
    .await?;

    Ok(fuzzy.filter(|candidate| candidate.name_similarity >= 0.35))
}

#[cfg(test)]
mod tests {
    use pod_core::playgroups::PlaygroupRole;
    use serde_json::json;

    use crate::{
        AddCollectionCardInput, AddWishlistCardInput, CollectionRepository, CreateCollectionInput,
        CreateDeckInput, CreateWishlistInput, DeckRepository, DecklistImportInput,
        IdentityRepository, PlaygroupRepository, ScryfallImportInput, ScryfallRepository,
    };

    #[sqlx::test(migrations = "./migrations")]
    async fn tracks_collection_quantities_missing_cards_proxy_lists_and_privacy(
        pool: sqlx::PgPool,
    ) {
        let identity = IdentityRepository::new(&pool);
        let owner = identity
            .create_user(
                "collection-owner@example.test",
                "Collection Owner",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("owner");
        let member = identity
            .create_user(
                "collection-member@example.test",
                "Collection Member",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("member");
        let outsider = identity
            .create_user(
                "collection-outsider@example.test",
                "Collection Outsider",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("outsider");
        let playgroup = PlaygroupRepository::new(&pool)
            .create_playgroup(owner.id, "Collection Crew", "collection-crew", "")
            .await
            .expect("playgroup");
        PlaygroupRepository::new(&pool)
            .add_membership(playgroup.id, member.id, PlaygroupRole::Member, None)
            .await
            .expect("member membership");

        seed_cards(&pool).await;

        let collection_repo = CollectionRepository::new(&pool);
        let collection = collection_repo
            .create_collection(CreateCollectionInput {
                owner_user_id: owner.id,
                playgroup_id: Some(playgroup.id),
                name: "Trade Binder",
                visibility: "playgroup",
                notes: "Bring on Commander nights.",
            })
            .await
            .expect("create collection")
            .expect("collection");
        assert!(
            collection_repo
                .get_collection_for_user(collection.id, member.id)
                .await
                .expect("member collection")
                .is_some()
        );
        assert!(
            collection_repo
                .get_collection_for_user(collection.id, outsider.id)
                .await
                .expect("outsider collection")
                .is_none()
        );

        let sol_ring = collection_repo
            .add_collection_card(AddCollectionCardInput {
                collection_id: collection.id,
                owner_user_id: owner.id,
                card_name: "Sol Ring",
                set_code: Some("cmm"),
                collector_number: Some("400"),
                quantity: 1,
                foil: true,
                condition: "near_mint",
                location: "Blue binder",
            })
            .await
            .expect("add sol ring")
            .expect("sol ring");
        assert_eq!(sol_ring.quantity, 1);
        assert_eq!(sol_ring.condition, "near_mint");
        assert_eq!(sol_ring.location, "Blue binder");
        let sol_ring = collection_repo
            .add_collection_card(AddCollectionCardInput {
                collection_id: collection.id,
                owner_user_id: owner.id,
                card_name: "Sol Ring",
                set_code: Some("cmm"),
                collector_number: Some("400"),
                quantity: 1,
                foil: true,
                condition: "near_mint",
                location: "Blue binder",
            })
            .await
            .expect("add another sol ring")
            .expect("sol ring");
        assert_eq!(sol_ring.quantity, 2);
        assert!(
            collection_repo
                .add_collection_card(AddCollectionCardInput {
                    collection_id: collection.id,
                    owner_user_id: outsider.id,
                    card_name: "Counterspell",
                    set_code: None,
                    collector_number: None,
                    quantity: 1,
                    foil: false,
                    condition: "unknown",
                    location: "",
                })
                .await
                .expect("outsider add")
                .is_none()
        );

        let tags = Vec::new();
        let deck = DeckRepository::new(&pool)
            .create_deck(CreateDeckInput {
                owner_user_id: owner.id,
                playgroup_id: Some(playgroup.id),
                name: "Collection Check",
                commander: "Atraxa, Praetors' Voice",
                color_identity: "WUBG",
                claimed_bracket: "3",
                archetype: "Midrange",
                tags: &tags,
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
            .expect("deck");
        DeckRepository::new(&pool)
            .import_plain_text_decklist(DecklistImportInput {
                deck_id: deck.id,
                owner_user_id: owner.id,
                source_text: "Commander\n1 Atraxa, Praetors' Voice\n\nDeck\n3 Sol Ring\n1 Counterspell\n",
            })
            .await
            .expect("import decklist")
            .expect("decklist summary");

        let missing = collection_repo
            .missing_cards_for_deck(deck.id, collection.id, member.id)
            .await
            .expect("missing cards");
        assert_eq!(missing.len(), 3);
        assert!(missing.iter().any(|card| {
            card.card_name == "Sol Ring"
                && card.required_quantity == 3
                && card.owned_quantity == 2
                && card.missing_quantity == 1
        }));
        assert!(missing.iter().any(|card| {
            card.card_name == "Counterspell"
                && card.required_quantity == 1
                && card.owned_quantity == 0
                && card.missing_quantity == 1
        }));
        assert!(
            collection_repo
                .missing_cards_for_deck(deck.id, collection.id, outsider.id)
                .await
                .expect("outsider missing")
                .is_empty()
        );

        let entries = missing
            .iter()
            .map(|card| pod_core::collections::ProxyPrintEntry {
                quantity: card.missing_quantity,
                card_name: &card.card_name,
                section: &card.section,
                is_commander: card.is_commander,
            })
            .collect::<Vec<_>>();
        let proxy_list = pod_core::collections::export_proxy_print_list(&entries);
        assert!(proxy_list.contains("Commander\n1 Atraxa, Praetors' Voice"));
        assert!(proxy_list.contains("Deck\n1 Counterspell\n1 Sol Ring"));
    }

    #[sqlx::test(migrations = "./migrations")]
    async fn tracks_wishlists_with_owner_scoped_card_updates(pool: sqlx::PgPool) {
        let identity = IdentityRepository::new(&pool);
        let owner = identity
            .create_user(
                "wishlist-owner@example.test",
                "Wishlist Owner",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("owner");
        let outsider = identity
            .create_user(
                "wishlist-outsider@example.test",
                "Wishlist Outsider",
                "$argon2id$v=19$m=19456,t=2,p=1$placeholder",
            )
            .await
            .expect("outsider");
        seed_cards(&pool).await;

        let repo = CollectionRepository::new(&pool);
        let wishlist = repo
            .create_wishlist(CreateWishlistInput {
                owner_user_id: owner.id,
                playgroup_id: None,
                name: "Upgrade Targets",
                visibility: "private",
                notes: "Low priority pickups.",
            })
            .await
            .expect("create wishlist")
            .expect("wishlist");
        let card = repo
            .add_wishlist_card(AddWishlistCardInput {
                wishlist_id: wishlist.id,
                owner_user_id: owner.id,
                card_name: "Counterspel",
                desired_quantity: 2,
                priority: "high",
                notes: "Need a spare.",
            })
            .await
            .expect("add wishlist card")
            .expect("wishlist card");
        assert_eq!(card.card_name, "Counterspell");
        assert_eq!(card.desired_quantity, 2);
        assert!(
            repo.add_wishlist_card(AddWishlistCardInput {
                wishlist_id: wishlist.id,
                owner_user_id: outsider.id,
                card_name: "Sol Ring",
                desired_quantity: 1,
                priority: "medium",
                notes: "",
            })
            .await
            .expect("outsider add")
            .is_none()
        );
        assert_eq!(
            repo.list_wishlists_for_user(owner.id)
                .await
                .expect("owner wishlists")
                .len(),
            1
        );
        assert!(
            repo.list_wishlists_for_user(outsider.id)
                .await
                .expect("outsider wishlists")
                .is_empty()
        );
    }

    async fn seed_cards(pool: &sqlx::PgPool) {
        let scryfall = ScryfallRepository::new(pool);
        let metadata = json!({
            "type": "default_cards",
            "updated_at": "2026-05-18T09:09:27.689+00:00",
            "uri": "https://api.scryfall.com/bulk-data/collection-fixture",
            "download_uri": "https://data.scryfall.io/default-cards/collection-fixture.json"
        });
        let import = scryfall
            .create_import(ScryfallImportInput {
                bulk_type: "default_cards",
                source_uri: metadata["uri"].as_str().expect("uri"),
                download_uri: metadata["download_uri"].as_str().expect("download uri"),
                source_updated_at: time::OffsetDateTime::now_utc(),
                content_type: "application/json",
                content_encoding: None,
                size_bytes: Some(4096),
                raw_metadata: &metadata,
            })
            .await
            .expect("create import");
        for card in [
            card_json(
                "00000000-0000-7100-8000-000000000001",
                "10000000-0000-7100-8000-000000000001",
                "Atraxa, Praetors' Voice",
                "c16",
                "28",
                &["W", "U", "B", "G"],
                "Legendary Creature - Phyrexian Angel Horror",
            ),
            card_json(
                "00000000-0000-7100-8000-000000000002",
                "10000000-0000-7100-8000-000000000002",
                "Sol Ring",
                "cmm",
                "400",
                &[],
                "Artifact",
            ),
            card_json(
                "00000000-0000-7100-8000-000000000003",
                "10000000-0000-7100-8000-000000000003",
                "Counterspell",
                "clu",
                "105",
                &["U"],
                "Instant",
            ),
        ] {
            scryfall
                .upsert_card_from_scryfall_json(import.id, &card)
                .await
                .expect("upsert card");
        }
    }

    fn card_json(
        scryfall_id: &str,
        oracle_id: &str,
        name: &str,
        set_code: &str,
        collector_number: &str,
        color_identity: &[&str],
        type_line: &str,
    ) -> serde_json::Value {
        json!({
            "id": scryfall_id,
            "oracle_id": oracle_id,
            "name": name,
            "mana_cost": "",
            "cmc": 1.0,
            "type_line": type_line,
            "oracle_text": "Fixture text.",
            "colors": color_identity,
            "color_identity": color_identity,
            "layout": "normal",
            "reserved": false,
            "keywords": [],
            "edhrec_rank": 100,
            "legalities": { "commander": "legal" },
            "game_changer": false,
            "set": set_code,
            "collector_number": collector_number,
            "lang": "en",
            "rarity": "rare",
            "released_at": "2020-01-01",
            "artist": "Fixture Artist",
            "prices": { "usd": "1.25" }
        })
    }
}

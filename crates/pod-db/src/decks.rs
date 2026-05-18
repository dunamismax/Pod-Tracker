use time::OffsetDateTime;
use uuid::Uuid;

use sqlx::PgPool;

use crate::DbError;

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
}

#[cfg(test)]
mod tests {
    use pod_core::playgroups::PlaygroupRole;

    use crate::{
        CreateDeckInput, CreateEventInput, DeckRepository, EventDeckDeclarationInput,
        EventRepository, IdentityRepository, PlaygroupRepository,
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
}

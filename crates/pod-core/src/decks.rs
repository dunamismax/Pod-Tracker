#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeckVisibility {
    Private,
    Playgroup,
    Public,
}

impl DeckVisibility {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Private => "private",
            Self::Playgroup => "playgroup",
            Self::Public => "public",
        }
    }
}

impl TryFrom<&str> for DeckVisibility {
    type Error = ();

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "private" => Ok(Self::Private),
            "playgroup" => Ok(Self::Playgroup),
            "public" => Ok(Self::Public),
            _ => Err(()),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeckStatus {
    Active,
    Retired,
}

impl DeckStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Active => "active",
            Self::Retired => "retired",
        }
    }
}

impl TryFrom<&str> for DeckStatus {
    type Error = ();

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "active" => Ok(Self::Active),
            "retired" => Ok(Self::Retired),
            _ => Err(()),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TutorDensity {
    None,
    Low,
    Medium,
    High,
}

impl TutorDensity {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::None => "none",
            Self::Low => "low",
            Self::Medium => "medium",
            Self::High => "high",
        }
    }
}

impl TryFrom<&str> for TutorDensity {
    type Error = ();

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "none" => Ok(Self::None),
            "low" => Ok(Self::Low),
            "medium" => Ok(Self::Medium),
            "high" => Ok(Self::High),
            _ => Err(()),
        }
    }
}

pub fn normalize_tags(tags: &str) -> Vec<String> {
    let mut normalized = tags
        .split(',')
        .map(str::trim)
        .filter(|tag| !tag.is_empty())
        .map(str::to_lowercase)
        .collect::<Vec<_>>();
    normalized.sort();
    normalized.dedup();
    normalized
}

pub fn normalize_color_identity(value: &str) -> String {
    let mut colors = value
        .chars()
        .filter_map(|character| match character.to_ascii_uppercase() {
            'W' => Some('W'),
            'U' => Some('U'),
            'B' => Some('B'),
            'R' => Some('R'),
            'G' => Some('G'),
            _ => None,
        })
        .collect::<Vec<_>>();
    colors.sort_by_key(|color| match color {
        'W' => 0,
        'U' => 1,
        'B' => 2,
        'R' => 3,
        'G' => 4,
        _ => 5,
    });
    colors.dedup();
    colors.into_iter().collect()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SimilarDeckScoreInput<'a> {
    pub current_commander: &'a str,
    pub candidate_commander: &'a str,
    pub current_color_identity: &'a str,
    pub candidate_color_identity: &'a str,
    pub current_claimed_bracket: &'a str,
    pub candidate_claimed_bracket: &'a str,
    pub current_archetype: &'a str,
    pub candidate_archetype: &'a str,
    pub shared_cards_count: i64,
    pub shared_tags_count: usize,
}

pub fn color_overlap_count(left: &str, right: &str) -> usize {
    let left = normalize_color_identity(left);
    let right = normalize_color_identity(right);
    left.chars().filter(|color| right.contains(*color)).count()
}

pub fn similar_deck_score(input: SimilarDeckScoreInput<'_>) -> i32 {
    let mut score = 0;
    score += input.shared_cards_count.clamp(0, 20) as i32 * 3;
    score += (input.shared_tags_count.min(4) as i32) * 5;
    score += (color_overlap_count(input.current_color_identity, input.candidate_color_identity)
        as i32)
        * 4;

    if input
        .current_commander
        .eq_ignore_ascii_case(input.candidate_commander)
    {
        score += 30;
    }
    if input
        .current_archetype
        .eq_ignore_ascii_case(input.candidate_archetype)
    {
        score += 18;
    }

    match bracket_distance(
        input.current_claimed_bracket,
        input.candidate_claimed_bracket,
    ) {
        Some(0) => score += 10,
        Some(1) => score += 6,
        Some(2) => score += 2,
        _ => {}
    }

    score
}

pub fn bracket_distance(left: &str, right: &str) -> Option<i32> {
    let left = left.trim().parse::<i32>().ok()?;
    let right = right.trim().parse::<i32>().ok()?;
    Some((left - right).abs())
}

#[cfg(test)]
mod tests {
    use super::{
        DeckStatus, DeckVisibility, SimilarDeckScoreInput, TutorDensity, color_overlap_count,
        normalize_color_identity, normalize_tags, similar_deck_score,
    };

    #[test]
    fn validates_deck_enums() {
        assert_eq!(
            DeckVisibility::try_from("playgroup"),
            Ok(DeckVisibility::Playgroup)
        );
        assert_eq!(DeckStatus::try_from("retired"), Ok(DeckStatus::Retired));
        assert_eq!(TutorDensity::try_from("high"), Ok(TutorDensity::High));
        assert!(DeckVisibility::try_from("friends").is_err());
    }

    #[test]
    fn normalizes_tags_and_color_identity() {
        assert_eq!(
            normalize_tags("Tokens, Combo, tokens, "),
            vec!["combo".to_owned(), "tokens".to_owned()]
        );
        assert_eq!(normalize_color_identity("gwuux"), "WUG");
    }

    #[test]
    fn scores_similar_decks_from_metadata_and_overlap() {
        let close = similar_deck_score(SimilarDeckScoreInput {
            current_commander: "Atraxa, Praetors' Voice",
            candidate_commander: "Atraxa, Praetors' Voice",
            current_color_identity: "WUBG",
            candidate_color_identity: "WUG",
            current_claimed_bracket: "3",
            candidate_claimed_bracket: "3",
            current_archetype: "Counters",
            candidate_archetype: "Counters",
            shared_cards_count: 12,
            shared_tags_count: 2,
        });
        let distant = similar_deck_score(SimilarDeckScoreInput {
            current_commander: "Atraxa, Praetors' Voice",
            candidate_commander: "Krenko, Mob Boss",
            current_color_identity: "WUBG",
            candidate_color_identity: "R",
            current_claimed_bracket: "3",
            candidate_claimed_bracket: "1",
            current_archetype: "Counters",
            candidate_archetype: "Tokens",
            shared_cards_count: 1,
            shared_tags_count: 0,
        });

        assert_eq!(color_overlap_count("WUBG", "WUG"), 3);
        assert!(close > distant);
    }
}

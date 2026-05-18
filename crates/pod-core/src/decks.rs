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

#[cfg(test)]
mod tests {
    use super::{
        DeckStatus, DeckVisibility, TutorDensity, normalize_color_identity, normalize_tags,
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
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CollectionVisibility {
    Private,
    Playgroup,
    Public,
}

impl CollectionVisibility {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Private => "private",
            Self::Playgroup => "playgroup",
            Self::Public => "public",
        }
    }
}

impl TryFrom<&str> for CollectionVisibility {
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
pub enum CardCondition {
    Mint,
    NearMint,
    LightlyPlayed,
    ModeratelyPlayed,
    HeavilyPlayed,
    Damaged,
    Unknown,
}

impl CardCondition {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Mint => "mint",
            Self::NearMint => "near_mint",
            Self::LightlyPlayed => "lightly_played",
            Self::ModeratelyPlayed => "moderately_played",
            Self::HeavilyPlayed => "heavily_played",
            Self::Damaged => "damaged",
            Self::Unknown => "unknown",
        }
    }
}

impl TryFrom<&str> for CardCondition {
    type Error = ();

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "mint" => Ok(Self::Mint),
            "near_mint" => Ok(Self::NearMint),
            "lightly_played" => Ok(Self::LightlyPlayed),
            "moderately_played" => Ok(Self::ModeratelyPlayed),
            "heavily_played" => Ok(Self::HeavilyPlayed),
            "damaged" => Ok(Self::Damaged),
            "unknown" => Ok(Self::Unknown),
            _ => Err(()),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WishlistPriority {
    Low,
    Medium,
    High,
}

impl WishlistPriority {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Low => "low",
            Self::Medium => "medium",
            Self::High => "high",
        }
    }
}

impl TryFrom<&str> for WishlistPriority {
    type Error = ();

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "low" => Ok(Self::Low),
            "medium" => Ok(Self::Medium),
            "high" => Ok(Self::High),
            _ => Err(()),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProxyPrintEntry<'a> {
    pub quantity: i64,
    pub card_name: &'a str,
    pub section: &'a str,
    pub is_commander: bool,
}

pub fn export_proxy_print_list(entries: &[ProxyPrintEntry<'_>]) -> String {
    let mut output = String::new();
    for section in ["commander", "main", "sideboard", "maybeboard"] {
        let section_entries = entries
            .iter()
            .copied()
            .filter(|entry| proxy_section(*entry) == section)
            .collect::<Vec<_>>();
        if section_entries.is_empty() {
            continue;
        }
        if !output.is_empty() {
            output.push('\n');
        }
        output.push_str(match section {
            "commander" => "Commander",
            "main" => "Deck",
            "sideboard" => "Sideboard",
            "maybeboard" => "Maybeboard",
            _ => section,
        });
        output.push('\n');
        for entry in section_entries {
            output.push_str(&format!("{} {}\n", entry.quantity, entry.card_name));
        }
    }
    output
}

fn proxy_section(entry: ProxyPrintEntry<'_>) -> &str {
    if entry.is_commander {
        "commander"
    } else {
        entry.section
    }
}

#[cfg(test)]
mod tests {
    use super::{ProxyPrintEntry, export_proxy_print_list};

    #[test]
    fn formats_proxy_print_list_by_deck_section() {
        let entries = [
            ProxyPrintEntry {
                quantity: 1,
                card_name: "Atraxa, Praetors' Voice",
                section: "commander",
                is_commander: true,
            },
            ProxyPrintEntry {
                quantity: 2,
                card_name: "Sol Ring",
                section: "main",
                is_commander: false,
            },
        ];

        assert_eq!(
            export_proxy_print_list(&entries),
            "Commander\n1 Atraxa, Praetors' Voice\n\nDeck\n2 Sol Ring\n"
        );
    }
}

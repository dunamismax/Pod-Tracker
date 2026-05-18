#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecklistSection {
    Commander,
    Main,
    Sideboard,
    Maybeboard,
}

impl DecklistSection {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Commander => "commander",
            Self::Main => "main",
            Self::Sideboard => "sideboard",
            Self::Maybeboard => "maybeboard",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecklistEntry {
    pub quantity: i32,
    pub name: String,
    pub section: DecklistSection,
    pub is_commander: bool,
    pub raw_line: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedDecklist {
    pub entries: Vec<DecklistEntry>,
}

impl ParsedDecklist {
    pub fn commander_names(&self) -> Vec<String> {
        self.entries
            .iter()
            .filter(|entry| entry.is_commander)
            .map(|entry| entry.name.clone())
            .collect()
    }
}

pub fn parse_plain_text_decklist(input: &str) -> ParsedDecklist {
    let mut section = DecklistSection::Main;
    let mut entries = Vec::new();

    for raw_line in input.lines() {
        let trimmed = raw_line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }

        if let Some(next_section) = parse_section_header(trimmed) {
            section = next_section;
            continue;
        }

        let (quantity, rest) = parse_quantity(trimmed);
        let (name_source, tagged_commander) = strip_commander_tag(rest);
        let name = clean_card_name(name_source);
        if name.is_empty() {
            continue;
        }

        let is_commander = section == DecklistSection::Commander || tagged_commander;
        entries.push(DecklistEntry {
            quantity,
            name,
            section,
            is_commander,
            raw_line: raw_line.to_owned(),
        });
    }

    ParsedDecklist { entries }
}

pub fn normalize_card_name(value: &str) -> String {
    value
        .chars()
        .filter(|character| character.is_ascii_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect()
}

fn parse_section_header(value: &str) -> Option<DecklistSection> {
    let normalized = value
        .trim_matches(|character| matches!(character, '[' | ']' | ':' | '*'))
        .trim()
        .to_ascii_lowercase();
    match normalized.as_str() {
        "commander" | "commanders" | "commander(s)" => Some(DecklistSection::Commander),
        "deck" | "main" | "mainboard" | "main deck" => Some(DecklistSection::Main),
        "sideboard" => Some(DecklistSection::Sideboard),
        "maybeboard" | "maybe" => Some(DecklistSection::Maybeboard),
        _ => None,
    }
}

fn parse_quantity(value: &str) -> (i32, &str) {
    let mut parts = value.splitn(2, char::is_whitespace);
    let Some(first) = parts.next() else {
        return (1, value);
    };
    let Some(rest) = parts.next() else {
        return (1, value);
    };
    let quantity = first.trim_end_matches(['x', 'X']);
    match quantity.parse::<i32>() {
        Ok(quantity) if quantity > 0 => (quantity, rest.trim()),
        _ => (1, value),
    }
}

fn strip_commander_tag(value: &str) -> (&str, bool) {
    let tags = [
        " *commander*",
        " *cmdr*",
        " [commander]",
        " [cmdr]",
        " #commander",
        " #cmdr",
    ];
    let lower = value.to_ascii_lowercase();
    for tag in tags {
        if lower.ends_with(tag) {
            let end = value.len() - tag.len();
            return (value[..end].trim(), true);
        }
    }
    (value, false)
}

fn clean_card_name(value: &str) -> String {
    let mut name = value.trim();
    if let Some((before, after)) = name.rsplit_once('(')
        && after.contains(')')
    {
        name = before.trim();
    }
    name.trim_matches(|character| matches!(character, '"' | '\''))
        .trim()
        .to_owned()
}

#[cfg(test)]
mod tests {
    use super::{DecklistSection, normalize_card_name, parse_plain_text_decklist};

    #[test]
    fn parses_quantities_sections_and_commander_headers() {
        let parsed = parse_plain_text_decklist(
            r#"
Commander
1 Atraxa, Praetors' Voice

Deck
1x Sol Ring
12 Forest
1 Farseek (M13) 170

Maybeboard:
1 Counterspell
"#,
        );

        assert_eq!(parsed.entries.len(), 5);
        assert_eq!(parsed.entries[0].name, "Atraxa, Praetors' Voice");
        assert_eq!(parsed.entries[0].quantity, 1);
        assert!(parsed.entries[0].is_commander);
        assert_eq!(parsed.entries[1].name, "Sol Ring");
        assert_eq!(parsed.entries[2].quantity, 12);
        assert_eq!(parsed.entries[3].name, "Farseek");
        assert_eq!(parsed.entries[4].section, DecklistSection::Maybeboard);
    }

    #[test]
    fn detects_commander_tags_outside_commander_section() {
        let parsed = parse_plain_text_decklist(
            r#"
1 Kraum, Ludevic's Opus #commander
1 Tymna the Weaver [CMDR]
1 Arcane Signet
"#,
        );

        assert_eq!(
            parsed.commander_names(),
            vec!["Kraum, Ludevic's Opus", "Tymna the Weaver"]
        );
        assert!(!parsed.entries[2].is_commander);
    }

    #[test]
    fn normalizes_card_names_for_lookup() {
        assert_eq!(
            normalize_card_name("Atraxa, Praetors' Voice"),
            "atraxapraetorsvoice"
        );
        assert_eq!(normalize_card_name("Fire // Ice"), "fireice");
    }
}

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
    pub line_number: i32,
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
    let mut line_number = 0;

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
        line_number += 1;
        entries.push(DecklistEntry {
            line_number,
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecklistExportFormat {
    PlainText,
    Moxfield,
    Archidekt,
}

impl DecklistExportFormat {
    pub fn extension(self) -> &'static str {
        "txt"
    }

    pub fn slug(self) -> &'static str {
        match self {
            Self::PlainText => "plain-text",
            Self::Moxfield => "moxfield",
            Self::Archidekt => "archidekt",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DecklistExportEntry<'a> {
    pub quantity: i32,
    pub card_name: &'a str,
    pub matched_name: Option<&'a str>,
    pub section: DecklistSection,
    pub match_status: &'a str,
    pub is_commander: bool,
}

impl<'a> DecklistExportEntry<'a> {
    fn display_name(self) -> &'a str {
        if self.match_status == "matched" {
            self.matched_name.unwrap_or(self.card_name)
        } else {
            self.card_name
        }
    }
}

pub fn export_decklist(
    entries: &[DecklistExportEntry<'_>],
    format: DecklistExportFormat,
) -> String {
    match format {
        DecklistExportFormat::PlainText => export_with_headers(entries, HeaderStyle::Plain),
        DecklistExportFormat::Moxfield => export_with_headers(entries, HeaderStyle::Moxfield),
        DecklistExportFormat::Archidekt => export_archidekt(entries),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum HeaderStyle {
    Plain,
    Moxfield,
}

fn export_with_headers(entries: &[DecklistExportEntry<'_>], style: HeaderStyle) -> String {
    let mut output = String::new();
    for section in [
        DecklistSection::Commander,
        DecklistSection::Main,
        DecklistSection::Sideboard,
        DecklistSection::Maybeboard,
    ] {
        let section_entries = entries
            .iter()
            .copied()
            .filter(|entry| export_section(*entry) == section)
            .collect::<Vec<_>>();
        if section_entries.is_empty() {
            continue;
        }
        if !output.is_empty() {
            output.push('\n');
        }
        output.push_str(match (style, section) {
            (HeaderStyle::Plain, DecklistSection::Commander) => "Commander",
            (HeaderStyle::Plain, DecklistSection::Main) => "Deck",
            (HeaderStyle::Plain, DecklistSection::Sideboard) => "Sideboard",
            (HeaderStyle::Plain, DecklistSection::Maybeboard) => "Maybeboard",
            (HeaderStyle::Moxfield, DecklistSection::Commander) => "COMMANDER:",
            (HeaderStyle::Moxfield, DecklistSection::Main) => "MAINBOARD:",
            (HeaderStyle::Moxfield, DecklistSection::Sideboard) => "SIDEBOARD:",
            (HeaderStyle::Moxfield, DecklistSection::Maybeboard) => "MAYBEBOARD:",
        });
        output.push('\n');
        for entry in section_entries {
            output.push_str(&format!("{} {}\n", entry.quantity, entry.display_name()));
        }
    }
    output
}

fn export_archidekt(entries: &[DecklistExportEntry<'_>]) -> String {
    let mut output = String::new();
    for entry in entries {
        let category = match export_section(*entry) {
            DecklistSection::Commander => "Commander",
            DecklistSection::Main => "Mainboard",
            DecklistSection::Sideboard => "Sideboard",
            DecklistSection::Maybeboard => "Maybeboard",
        };
        output.push_str(&format!(
            "{}x {} `{}`\n",
            entry.quantity,
            entry.display_name(),
            category
        ));
    }
    output
}

fn export_section(entry: DecklistExportEntry<'_>) -> DecklistSection {
    if entry.is_commander {
        DecklistSection::Commander
    } else {
        entry.section
    }
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
    use super::{
        DecklistExportEntry, DecklistExportFormat, DecklistSection, export_decklist,
        normalize_card_name, parse_plain_text_decklist,
    };

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
        assert_eq!(parsed.entries[0].line_number, 1);
        assert_eq!(parsed.entries[4].line_number, 5);
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

    #[test]
    fn exports_plain_moxfield_and_archidekt_shapes() {
        let entries = [
            DecklistExportEntry {
                quantity: 1,
                card_name: "Atraxa, Praetors' Voice",
                matched_name: Some("Atraxa, Praetors' Voice"),
                section: DecklistSection::Commander,
                match_status: "matched",
                is_commander: true,
            },
            DecklistExportEntry {
                quantity: 2,
                card_name: "Counterspel",
                matched_name: Some("Counterspell"),
                section: DecklistSection::Main,
                match_status: "matched",
                is_commander: false,
            },
            DecklistExportEntry {
                quantity: 1,
                card_name: "Fire // Ice",
                matched_name: Some("Fire/Ice"),
                section: DecklistSection::Sideboard,
                match_status: "ambiguous",
                is_commander: false,
            },
            DecklistExportEntry {
                quantity: 1,
                card_name: "Missing Card",
                matched_name: None,
                section: DecklistSection::Maybeboard,
                match_status: "unmatched",
                is_commander: false,
            },
        ];

        assert_eq!(
            export_decklist(&entries, DecklistExportFormat::PlainText),
            "Commander\n1 Atraxa, Praetors' Voice\n\nDeck\n2 Counterspell\n\nSideboard\n1 Fire // Ice\n\nMaybeboard\n1 Missing Card\n"
        );
        assert_eq!(
            export_decklist(&entries, DecklistExportFormat::Moxfield),
            "COMMANDER:\n1 Atraxa, Praetors' Voice\n\nMAINBOARD:\n2 Counterspell\n\nSIDEBOARD:\n1 Fire // Ice\n\nMAYBEBOARD:\n1 Missing Card\n"
        );
        assert_eq!(
            export_decklist(&entries, DecklistExportFormat::Archidekt),
            "1x Atraxa, Praetors' Voice `Commander`\n2x Counterspell `Mainboard`\n1x Fire // Ice `Sideboard`\n1x Missing Card `Maybeboard`\n"
        );
    }
}

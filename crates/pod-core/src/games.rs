#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GameResultType {
    NormalWin,
    ComboWin,
    CombatWin,
    Concession,
    Draw,
    TimeCalled,
    Unfinished,
    ArchenemyWin,
    TeamWin,
}

impl GameResultType {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::NormalWin => "normal_win",
            Self::ComboWin => "combo_win",
            Self::CombatWin => "combat_win",
            Self::Concession => "concession",
            Self::Draw => "draw",
            Self::TimeCalled => "time_called",
            Self::Unfinished => "unfinished",
            Self::ArchenemyWin => "archenemy_win",
            Self::TeamWin => "team_win",
        }
    }

    pub fn needs_winner(self) -> bool {
        matches!(
            self,
            Self::NormalWin
                | Self::ComboWin
                | Self::CombatWin
                | Self::Concession
                | Self::ArchenemyWin
                | Self::TeamWin
        )
    }
}

impl TryFrom<&str> for GameResultType {
    type Error = ();

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "normal_win" => Ok(Self::NormalWin),
            "combo_win" => Ok(Self::ComboWin),
            "combat_win" => Ok(Self::CombatWin),
            "concession" => Ok(Self::Concession),
            "draw" => Ok(Self::Draw),
            "time_called" => Ok(Self::TimeCalled),
            "unfinished" => Ok(Self::Unfinished),
            "archenemy_win" => Ok(Self::ArchenemyWin),
            "team_win" => Ok(Self::TeamWin),
            _ => Err(()),
        }
    }
}

pub fn normalize_game_tags(value: &str) -> Vec<String> {
    value
        .split(',')
        .map(str::trim)
        .filter(|tag| !tag.is_empty())
        .map(|tag| tag.to_lowercase())
        .fold(Vec::new(), |mut tags, tag| {
            if !tags.contains(&tag) {
                tags.push(tag);
            }
            tags
        })
}

#[cfg(test)]
mod tests {
    use super::{GameResultType, normalize_game_tags};

    #[test]
    fn validates_game_result_types() {
        assert_eq!(
            GameResultType::try_from("combo_win"),
            Ok(GameResultType::ComboWin)
        );
        assert!(GameResultType::try_from("unknown").is_err());
        assert!(GameResultType::NormalWin.needs_winner());
        assert!(!GameResultType::Draw.needs_winner());
    }

    #[test]
    fn normalizes_tags() {
        assert_eq!(
            normalize_game_tags("Combo, Late Game, combo"),
            vec!["combo", "late game"]
        );
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PodState {
    Proposed,
    Locked,
    Active,
    Completed,
    Cancelled,
}

impl PodState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Proposed => "proposed",
            Self::Locked => "locked",
            Self::Active => "active",
            Self::Completed => "completed",
            Self::Cancelled => "cancelled",
        }
    }
}

impl TryFrom<&str> for PodState {
    type Error = ();

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "proposed" => Ok(Self::Proposed),
            "locked" => Ok(Self::Locked),
            "active" => Ok(Self::Active),
            "completed" => Ok(Self::Completed),
            "cancelled" => Ok(Self::Cancelled),
            _ => Err(()),
        }
    }
}

pub fn pod_size_fit_score(size: usize) -> i32 {
    match size {
        4 => 20,
        3 => 16,
        2 | 5 => 8,
        1 => 2,
        _ => 0,
    }
}

pub fn bracket_compatibility_score(brackets: &[i32]) -> i32 {
    let Some(minimum) = brackets.iter().min() else {
        return 10;
    };
    let Some(maximum) = brackets.iter().max() else {
        return 10;
    };

    match maximum - minimum {
        0 | 1 => 20,
        2 => 12,
        3 => 4,
        _ => 0,
    }
}

pub fn guest_placement_score(guest_count: usize, pod_size: usize) -> i32 {
    if guest_count == 0 || guest_count == pod_size {
        10
    } else if guest_count <= 2 {
        8
    } else {
        4
    }
}

pub fn deck_variety_score(
    declared_decks: usize,
    distinct_commanders: usize,
    distinct_archetypes: usize,
    distinct_color_identities: usize,
) -> i32 {
    if declared_decks < 2 {
        return 0;
    }

    let commander_score = if distinct_commanders == declared_decks {
        4
    } else {
        0
    };
    let archetype_score = distinct_archetypes.saturating_sub(1).min(4) as i32 * 2;
    let color_score = distinct_color_identities.saturating_sub(1).min(2) as i32 * 2;

    commander_score + archetype_score + color_score
}

pub fn matchup_freshness_penalty(days_since_last_matchup: Option<i64>, base_penalty: i32) -> i32 {
    let Some(days_since_last_matchup) = days_since_last_matchup else {
        return 0;
    };

    if days_since_last_matchup <= 30 {
        base_penalty * 2
    } else if days_since_last_matchup <= 90 {
        base_penalty
    } else {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::{
        PodState, bracket_compatibility_score, deck_variety_score, guest_placement_score,
        matchup_freshness_penalty, pod_size_fit_score,
    };

    #[test]
    fn validates_pod_states() {
        assert_eq!(PodState::try_from("locked"), Ok(PodState::Locked));
        assert_eq!(PodState::Completed.as_str(), "completed");
        assert!(PodState::try_from("draft").is_err());
    }

    #[test]
    fn scores_pod_shape_inputs() {
        assert_eq!(pod_size_fit_score(4), 20);
        assert_eq!(pod_size_fit_score(3), 16);
        assert_eq!(bracket_compatibility_score(&[2, 3, 3, 2]), 20);
        assert_eq!(bracket_compatibility_score(&[1, 4]), 4);
        assert_eq!(guest_placement_score(1, 4), 8);
        assert_eq!(guest_placement_score(4, 4), 10);
    }

    #[test]
    fn scores_deck_variety_and_matchup_freshness() {
        assert_eq!(deck_variety_score(1, 1, 1, 1), 0);
        assert_eq!(deck_variety_score(4, 4, 4, 3), 14);
        assert_eq!(deck_variety_score(4, 2, 1, 1), 0);
        assert_eq!(matchup_freshness_penalty(None, 4), 0);
        assert_eq!(matchup_freshness_penalty(Some(14), 4), 8);
        assert_eq!(matchup_freshness_penalty(Some(75), 4), 4);
        assert_eq!(matchup_freshness_penalty(Some(120), 4), 0);
    }
}

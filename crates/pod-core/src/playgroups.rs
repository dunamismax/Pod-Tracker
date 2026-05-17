#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlaygroupRole {
    Owner,
    Admin,
    Member,
    Host,
    Guest,
    Viewer,
}

impl PlaygroupRole {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Owner => "owner",
            Self::Admin => "admin",
            Self::Member => "member",
            Self::Host => "host",
            Self::Guest => "guest",
            Self::Viewer => "viewer",
        }
    }

    pub fn can_manage_playgroup(self) -> bool {
        matches!(self, Self::Owner | Self::Admin)
    }

    pub fn can_host_event(self) -> bool {
        matches!(self, Self::Owner | Self::Admin | Self::Host)
    }

    pub fn can_edit_house_rules(self) -> bool {
        matches!(self, Self::Owner | Self::Admin)
    }

    pub fn can_view_member_content(self) -> bool {
        matches!(
            self,
            Self::Owner | Self::Admin | Self::Member | Self::Host | Self::Viewer
        )
    }
}

impl TryFrom<&str> for PlaygroupRole {
    type Error = ();

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "owner" => Ok(Self::Owner),
            "admin" => Ok(Self::Admin),
            "member" => Ok(Self::Member),
            "host" => Ok(Self::Host),
            "guest" => Ok(Self::Guest),
            "viewer" => Ok(Self::Viewer),
            _ => Err(()),
        }
    }
}

pub fn slugify(value: &str) -> String {
    let mut slug = String::new();
    let mut previous_was_separator = false;

    for character in value.trim().chars().flat_map(char::to_lowercase) {
        if character.is_ascii_alphanumeric() {
            slug.push(character);
            previous_was_separator = false;
        } else if !previous_was_separator && !slug.is_empty() {
            slug.push('-');
            previous_was_separator = true;
        }
    }

    slug.trim_matches('-').to_owned()
}

#[cfg(test)]
mod tests {
    use super::{PlaygroupRole, slugify};

    #[test]
    fn validates_known_roles() {
        assert_eq!(PlaygroupRole::try_from("owner"), Ok(PlaygroupRole::Owner));
        assert!(PlaygroupRole::try_from("outsider").is_err());
    }

    #[test]
    fn exposes_role_permissions() {
        assert!(PlaygroupRole::Owner.can_manage_playgroup());
        assert!(PlaygroupRole::Admin.can_edit_house_rules());
        assert!(PlaygroupRole::Host.can_host_event());
        assert!(PlaygroupRole::Viewer.can_view_member_content());
        assert!(!PlaygroupRole::Guest.can_view_member_content());
        assert!(!PlaygroupRole::Member.can_manage_playgroup());
    }

    #[test]
    fn slugifies_playgroup_names() {
        assert_eq!(
            slugify(" Friday Night Commander "),
            "friday-night-commander"
        );
        assert_eq!(slugify("!!!"), "");
        assert_eq!(slugify("Pods & Pizza"), "pods-pizza");
    }
}

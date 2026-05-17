use crate::playgroups::PlaygroupRole;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventVisibility {
    Members,
    InviteOnly,
    PublicSafe,
}

impl EventVisibility {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Members => "members",
            Self::InviteOnly => "invite_only",
            Self::PublicSafe => "public_safe",
        }
    }
}

impl TryFrom<&str> for EventVisibility {
    type Error = ();

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "members" => Ok(Self::Members),
            "invite_only" => Ok(Self::InviteOnly),
            "public_safe" => Ok(Self::PublicSafe),
            _ => Err(()),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AddressVisibility {
    Rsvps,
    Members,
    Public,
    Hidden,
}

impl AddressVisibility {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Rsvps => "rsvps",
            Self::Members => "members",
            Self::Public => "public",
            Self::Hidden => "hidden",
        }
    }
}

impl TryFrom<&str> for AddressVisibility {
    type Error = ();

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "rsvps" => Ok(Self::Rsvps),
            "members" => Ok(Self::Members),
            "public" => Ok(Self::Public),
            "hidden" => Ok(Self::Hidden),
            _ => Err(()),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RsvpStatus {
    Yes,
    Maybe,
    No,
    Waitlist,
}

impl RsvpStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Yes => "yes",
            Self::Maybe => "maybe",
            Self::No => "no",
            Self::Waitlist => "waitlist",
        }
    }

    pub fn can_see_rsvp_only_address(self) -> bool {
        matches!(self, Self::Yes | Self::Maybe | Self::Waitlist)
    }
}

impl TryFrom<&str> for RsvpStatus {
    type Error = ();

    fn try_from(value: &str) -> Result<Self, Self::Error> {
        match value {
            "yes" => Ok(Self::Yes),
            "maybe" => Ok(Self::Maybe),
            "no" => Ok(Self::No),
            "waitlist" => Ok(Self::Waitlist),
            _ => Err(()),
        }
    }
}

pub fn can_manage_event(role: PlaygroupRole) -> bool {
    role.can_host_event()
}

pub fn can_show_event_address(
    hosts: &[AddressVisibility],
    viewer_is_host: bool,
    viewer_role: Option<PlaygroupRole>,
    viewer_rsvp: Option<RsvpStatus>,
    guest_scope: bool,
) -> bool {
    if viewer_is_host {
        return true;
    }

    let strongest_visibility =
        hosts
            .iter()
            .fold(AddressVisibility::Hidden, |current, host| {
                match (current, *host) {
                    (AddressVisibility::Public, _) | (_, AddressVisibility::Public) => {
                        AddressVisibility::Public
                    }
                    (AddressVisibility::Members, _) | (_, AddressVisibility::Members) => {
                        AddressVisibility::Members
                    }
                    (AddressVisibility::Rsvps, _) | (_, AddressVisibility::Rsvps) => {
                        AddressVisibility::Rsvps
                    }
                    _ => AddressVisibility::Hidden,
                }
            });

    if guest_scope {
        return strongest_visibility == AddressVisibility::Public;
    }

    if viewer_role.is_some_and(can_manage_event) {
        return true;
    }

    match strongest_visibility {
        AddressVisibility::Public | AddressVisibility::Members => true,
        AddressVisibility::Rsvps => viewer_rsvp.is_some_and(RsvpStatus::can_see_rsvp_only_address),
        AddressVisibility::Hidden => false,
    }
}

#[cfg(test)]
mod tests {
    use super::{
        AddressVisibility, EventVisibility, RsvpStatus, can_manage_event, can_show_event_address,
    };
    use crate::playgroups::PlaygroupRole;

    #[test]
    fn validates_event_inputs() {
        assert_eq!(
            EventVisibility::try_from("public_safe"),
            Ok(EventVisibility::PublicSafe)
        );
        assert_eq!(RsvpStatus::try_from("waitlist"), Ok(RsvpStatus::Waitlist));
        assert!(AddressVisibility::try_from("everyone").is_err());
    }

    #[test]
    fn resolves_address_visibility() {
        assert!(can_manage_event(PlaygroupRole::Host));
        assert!(!can_manage_event(PlaygroupRole::Member));
        assert!(can_show_event_address(
            &[AddressVisibility::Rsvps],
            false,
            Some(PlaygroupRole::Member),
            Some(RsvpStatus::Maybe),
            false,
        ));
        assert!(!can_show_event_address(
            &[AddressVisibility::Rsvps],
            false,
            Some(PlaygroupRole::Member),
            Some(RsvpStatus::No),
            false,
        ));
        assert!(!can_show_event_address(
            &[AddressVisibility::Rsvps],
            false,
            None,
            None,
            true,
        ));
        assert!(can_show_event_address(
            &[AddressVisibility::Public],
            false,
            None,
            None,
            true,
        ));
    }
}

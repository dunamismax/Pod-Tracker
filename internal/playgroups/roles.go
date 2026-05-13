package playgroups

type Role string

const (
	RoleOwner  Role = "owner"
	RoleAdmin  Role = "admin"
	RoleMember Role = "member"
	RoleHost   Role = "host"
	RoleGuest  Role = "guest"
	RoleViewer Role = "viewer"
)

func IsValidRole(role Role) bool {
	switch role {
	case RoleOwner, RoleAdmin, RoleMember, RoleHost, RoleGuest, RoleViewer:
		return true
	default:
		return false
	}
}

func CanManagePlaygroup(role Role) bool {
	return role == RoleOwner || role == RoleAdmin
}

func CanHostEvent(role Role) bool {
	return role == RoleOwner || role == RoleAdmin || role == RoleHost
}

func CanEditHouseRules(role Role) bool {
	return role == RoleOwner || role == RoleAdmin
}

func CanViewMemberContent(role Role) bool {
	switch role {
	case RoleOwner, RoleAdmin, RoleMember, RoleHost, RoleViewer:
		return true
	default:
		return false
	}
}

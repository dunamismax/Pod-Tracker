package playgroups

import "testing"

func TestRoleChecks(t *testing.T) {
	if !CanManagePlaygroup(RoleOwner) || !CanManagePlaygroup(RoleAdmin) {
		t.Fatalf("owners and admins should manage playgroups")
	}
	if CanManagePlaygroup(RoleMember) || CanManagePlaygroup(RoleGuest) {
		t.Fatalf("members and guests should not manage playgroups")
	}
	if !CanHostEvent(RoleHost) {
		t.Fatalf("hosts should be able to host events")
	}
	if CanViewMemberContent(RoleGuest) {
		t.Fatalf("guests should not see member-only content by default")
	}
	for _, role := range []Role{RoleOwner, RoleAdmin, RoleMember, RoleHost, RoleGuest, RoleViewer} {
		if !IsValidRole(role) {
			t.Fatalf("%s should be valid", role)
		}
	}
	if IsValidRole("stranger") {
		t.Fatalf("unknown roles should be invalid")
	}
}

require "test_helper"

class GameNightInvitationTest < ActiveSupport::TestCase
  setup do
    @host = users(:one)
    @invitee = users(:two)
    @game_night = @host.game_nights.create!(name: "Friday", played_on: Date.new(2026, 5, 5))
  end

  test "normalizes email and resolves invited user" do
    invitation = @game_night.game_night_invitations.create!(email_address: "  Two@Example.COM ", position: 1)

    assert_equal "two@example.com", invitation.email_address
    assert_equal @invitee, invitation.invited_user
    assert invitation.token.present?
    assert invitation.invited_at.present?
    assert invitation.pending?
  end

  test "rejects invalid email" do
    invitation = @game_night.game_night_invitations.new(email_address: "nope", position: 1)
    assert_not invitation.valid?
    assert invitation.errors[:email_address].any?
  end

  test "enforces unique email per game night" do
    @game_night.game_night_invitations.create!(email_address: "two@example.com", position: 1)
    duplicate = @game_night.game_night_invitations.new(email_address: "TWO@example.com", position: 2)
    assert_not duplicate.valid?
  end
end

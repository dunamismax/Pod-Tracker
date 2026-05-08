require "test_helper"

module GameNights
  class InviterTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @host = users(:one)
      @game_night = @host.game_nights.create!(name: "Friday", played_on: Date.new(2026, 5, 5))
    end

    test "creates invitations for each unique email" do
      result = nil
      assert_difference -> { GameNightInvitation.count } => 2,
                        -> { ActionMailer::Base.deliveries.size } => 2 do
        ActionMailer::Base.deliveries.clear
        result = Inviter.call(@game_night,
          rows: [
            { email_address: "alice@example.com", display_name: "Alice" },
            { email_address: "BOB@example.com" }
          ],
          host: @host,
          deliver: true)
        perform_enqueued_jobs
      end

      assert result.success?
      assert_equal [ "alice@example.com", "bob@example.com" ], result.invitations.map(&:email_address).sort
      assert_equal "Alice", result.invitations.find { |i| i.email_address == "alice@example.com" }.display_name
    end

    test "rejects duplicates and host email" do
      result = Inviter.call(@game_night,
        rows: [
          { email_address: "alice@example.com" },
          { email_address: "alice@example.com" },
          { email_address: @host.email_address }
        ],
        host: @host,
        deliver: false)

      assert_not result.success?
      assert(result.errors.any? { |e| e.include?("duplicates") })
      assert(result.errors.any? { |e| e.include?("host") })
    end
  end
end

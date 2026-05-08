require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "application seeds do not create user accounts" do
    assert_no_difference "User.count" do
      load Rails.root.join("db/seeds.rb")
    end
  end
end

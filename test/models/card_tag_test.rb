require "test_helper"

class CardTagTest < ActiveSupport::TestCase
  test "requires a slug, category, and label" do
    tag = CardTag.new
    assert_not tag.valid?
    assert_includes tag.errors[:slug], "can't be blank"
    assert_includes tag.errors[:category], "can't be blank"
    assert_includes tag.errors[:label], "can't be blank"
  end

  test "rejects invalid slugs and categories" do
    tag = CardTag.new(slug: "Bad-Slug", category: "vibes", label: "Bad")
    assert_not tag.valid?
    assert_includes tag.errors[:slug], "must be lowercase letters, digits, or underscores"
    assert_includes tag.errors[:category], "is not included in the list"
  end

  test "scopes by category" do
    role = CardTag.create!(slug: "role_test", category: "role", label: "Role")
    salt = CardTag.create!(slug: "salt_test", category: "salt", label: "Salt", salt_weight: 5.0)
    friction = CardTag.create!(slug: "friction_test", category: "social_friction", label: "Friction", friction_weight: 4.0)

    assert_includes CardTag.role, role
    assert_includes CardTag.salt, salt
    assert_includes CardTag.social_friction, friction
    assert_not_includes CardTag.role, salt
  end
end

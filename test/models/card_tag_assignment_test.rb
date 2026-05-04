require "test_helper"

class CardTagAssignmentTest < ActiveSupport::TestCase
  setup do
    @tag = CardTag.create!(
      slug: "salt_test_driver",
      category: "salt",
      label: "Salt test driver",
      salt_weight: 8.0,
      default_severity: "high"
    )
  end

  test "normalizes the card name and links to the matching oracle card on save" do
    oracle = OracleCard.create!(
      scryfall_oracle_id: SecureRandom.uuid,
      name: "Mana Crypt"
    )

    assignment = CardTagAssignment.create!(
      card_tag: @tag,
      card_name: " Mana Crypt "
    )

    assert_equal "mana crypt", assignment.normalized_card_name
    assert_equal oracle, assignment.oracle_card
  end

  test "uses tag defaults when assignment weight and severity are blank" do
    assignment = CardTagAssignment.create!(
      card_tag: @tag,
      card_name: "Jeweled Lotus"
    )

    assert_equal 8.0, assignment.effective_weight
    assert_equal "high", assignment.effective_severity
  end

  test "respects per-assignment overrides for weight and severity" do
    assignment = CardTagAssignment.create!(
      card_tag: @tag,
      card_name: "Sol Ring",
      weight: 2.5,
      severity: "low"
    )

    assert_equal 2.5, assignment.effective_weight
    assert_equal "low", assignment.effective_severity
  end

  test "rejects duplicate assignments for the same tag and card" do
    CardTagAssignment.create!(card_tag: @tag, card_name: "Jeweled Lotus")
    duplicate = CardTagAssignment.new(card_tag: @tag, card_name: "Jeweled Lotus")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:card_tag_id], "has already been taken"
  end

  test "for_card_name scope returns assignments for that name regardless of formatting" do
    CardTagAssignment.create!(card_tag: @tag, card_name: "Hypothetical Test Card")

    assert_equal 1, CardTagAssignment.for_card_name(" hypothetical  test  card ").count
  end

  test "backfills oracle linkage when the oracle card is created later" do
    assignment = CardTagAssignment.create!(card_tag: @tag, card_name: "Mox Diamond")
    assert_nil assignment.oracle_card

    oracle = OracleCard.create!(
      scryfall_oracle_id: SecureRandom.uuid,
      name: "Mox Diamond"
    )

    assert_equal oracle, assignment.reload.oracle_card
  end
end

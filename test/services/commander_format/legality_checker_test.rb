require "test_helper"

module CommanderFormat
  class LegalityCheckerTest < ActiveSupport::TestCase
    setup do
      @library = Decks::FixtureLibrary.new
      @snapshot = LegalitySnapshot.find_or_create_by!(
        source: "mtgcommander", format: "commander", effective_on: Date.new(2024, 9, 23)
      ) do |snap|
        snap.banned_names = [ "Mana Crypt", "Jeweled Lotus" ]
      end
      @snapshot.update!(banned_names: [ "Mana Crypt", "Jeweled Lotus" ])
    end

    test "approves a fully legal mono-green deck against the current banlist" do
      deck = @library.build_deck("mono_green_omnath_stompy")
      deck.save!

      lookup = lookup_for([
        oracle_attrs("Omnath, Locus of Mana", color_identity: %w[G], type_line: "Legendary Creature - Elemental")
      ])

      result = LegalityChecker.new(snapshot: @snapshot, oracle_lookup: lookup).check(deck.reload)

      assert(result.legal?, "expected legal deck but got errors: #{result.errors.map(&:message)}")
      assert_equal([], result.errors)
    end

    test "rejects decks containing cards on the banned list" do
      deck = @library.build_deck("illegal_banned_card_demo")
      deck.save!

      result = LegalityChecker.new(snapshot: @snapshot).check(deck.reload)

      assert_not(result.legal?)
      assert(result.errors.any? { |i| i.code == "banned_card" && i.card_name == "Mana Crypt" })
    end

    test "rejects decks that violate the singleton rule" do
      deck = @library.build_deck("illegal_singleton_violation_demo")
      deck.save!

      result = LegalityChecker.new(snapshot: @snapshot).check(deck.reload)

      assert_not(result.legal?)
      singleton_errors = result.errors.select { |i| i.code == "singleton_violation" }
      assert_equal(1, singleton_errors.size)
      assert_equal("Goblin Piledriver", singleton_errors.first.card_name)
      assert_equal(4, singleton_errors.first.metadata["count"])
    end

    test "permits unlimited copies of basic lands and singleton-exempt names" do
      user = users(:one)
      deck = Deck.create!(
        user: user,
        name: "Rats Test",
        format: "commander",
        status: "imported",
        visibility: "private"
      )
      deck.commanders.create!(name: "Marrow-Gnawer", position: 1)
      30.times { |i| deck.deck_cards.create!(name: "Relentless Rats", quantity: 1, board: "main", position: i) }
      deck.deck_cards.create!(name: "Sol Ring", quantity: 1, board: "main", position: 100)
      deck.deck_cards.create!(name: "Swamp", quantity: 68, board: "main", position: 101)

      result = LegalityChecker.new(snapshot: @snapshot).check(deck.reload)

      assert(result.errors.none? { |i| i.code == "singleton_violation" }, "expected Relentless Rats to be exempt")
    end

    test "flags decks whose main board contains cards outside the commander color identity" do
      deck = @library.build_deck("illegal_color_identity_demo")
      deck.save!

      lookup = lookup_for([
        oracle_attrs("Krenko, Mob Boss", color_identity: %w[R], type_line: "Legendary Creature - Goblin Warrior"),
        oracle_attrs("Counterspell", color_identity: %w[U], type_line: "Instant")
      ])

      result = LegalityChecker.new(snapshot: @snapshot, oracle_lookup: lookup).check(deck.reload)

      identity_errors = result.errors.select { |i| i.code == "color_identity_violation" }
      assert_equal(1, identity_errors.size)
      assert_equal("Counterspell", identity_errors.first.card_name)
    end

    test "rejects commanders whose oracle type line is not legendary creature or planeswalker" do
      user = users(:one)
      deck = Deck.create!(user: user, name: "Sol Ring as Commander",
        format: "commander", status: "imported", visibility: "private")
      deck.commanders.create!(name: "Sol Ring", position: 1)
      deck.deck_cards.create!(name: "Mountain", quantity: 99, board: "main", position: 1)

      lookup = lookup_for([ oracle_attrs("Sol Ring", color_identity: [], type_line: "Artifact") ])

      result = LegalityChecker.new(snapshot: @snapshot, oracle_lookup: lookup).check(deck.reload)

      assert(result.errors.any? { |i| i.code == "commander_invalid_typeline" })
    end

    test "warns when no legality snapshot is loaded" do
      deck = @library.build_deck("krenko_goblin_tribal")
      deck.save!

      result = LegalityChecker.new(snapshot: nil).check(deck.reload)

      assert(result.issues.any? { |i| i.code == "missing_snapshot" })
    end

    test "renders a JSON-serializable summary suitable for analysis run snapshots" do
      deck = @library.build_deck("illegal_banned_card_demo")
      deck.save!

      result = LegalityChecker.new(snapshot: @snapshot).check(deck.reload)
      payload = result.to_h

      assert_equal(false, payload[:legal])
      assert_equal(@snapshot.id, payload[:snapshot_id])
      assert(payload[:issues].any? { |i| i["code"] == "banned_card" })
    end

    private

    def lookup_for(attrs_array)
      records = attrs_array.each_with_object({}) do |attrs, mapping|
        oracle = OracleCard.create!(attrs.except(:normalized_name))
        mapping[oracle.normalized_name] = oracle
      end
      OracleCardLookup.new(records: records)
    end

    def oracle_attrs(name, color_identity:, type_line:)
      {
        scryfall_oracle_id: SecureRandom.uuid,
        name: name,
        color_identity: color_identity,
        type_line: type_line,
        legalities: { "commander" => "legal" }
      }
    end
  end
end

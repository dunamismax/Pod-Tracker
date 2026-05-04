require "test_helper"

class DomainFoundationTest < ActiveSupport::TestCase
  test "card corpus records normalize names and connect printings to oracle cards and sets" do
    oracle = OracleCard.create!(
      scryfall_oracle_id: SecureRandom.uuid,
      name: "Sol Ring",
      color_identity: [],
      legalities: { "commander" => "legal" }
    )
    card_set = CardSet.create!(code: " CMM ", name: "Commander Masters")
    printing = CardPrinting.create!(
      oracle_card: oracle,
      card_set: card_set,
      scryfall_id: SecureRandom.uuid,
      name: "Sol Ring",
      collector_number: "703"
    )

    assert_equal("sol ring", oracle.normalized_name)
    assert_equal("cmm", card_set.code)
    assert_equal("sol ring", printing.normalized_name)
    assert_equal(oracle, printing.oracle_card)
    assert_equal(card_set, printing.card_set)
  end

  test "decks own deck cards commanders provider links analysis runs and audit events" do
    user = users(:one)
    deck = user.decks.create!(name: "Kinnan Test Deck", commander_names: [ "Kinnan, Bonder Prodigy" ])
    commander = deck.commanders.create!(name: "Kinnan, Bonder Prodigy")
    deck_card = deck.deck_cards.create!(name: "Sol Ring", quantity: 1)
    provider_link = deck.provider_links.create!(
      provider: "moxfield",
      external_id: "abc123",
      url: "https://www.moxfield.com/decks/abc123"
    )
    analysis_run = deck.analysis_runs.create!(user: user, rubric_version: "2026-05-03")
    audit_event = deck.audit_events.create!(user: user, event_name: "deck.imported")

    assert_equal("kinnan bonder prodigy", commander.normalized_name)
    assert_equal("sol ring", deck_card.normalized_name)
    assert_equal(provider_link, deck.provider_links.first)
    assert_equal(analysis_run, deck.analysis_runs.first)
    assert_equal(audit_event, deck.audit_events.first)
  end

  test "scorecards and salt social friction evidence enforce score bounds and evidence type" do
    analysis_run = AnalysisRun.create!(rubric_version: "2026-05-03")
    scorecard = analysis_run.create_scorecard!(
      power_score: 72,
      speed_score: 61,
      interaction_score: 54,
      consistency_score: 67,
      salt_score: 35,
      social_friction_score: 42,
      confidence: 0.75
    )
    evidence = analysis_run.salt_social_friction_evidences.create!(
      evidence_type: "salt",
      category: "fast_mana",
      label: "Fast mana density"
    )

    assert_predicate(scorecard, :valid?)
    assert_predicate(evidence, :valid?)
    assert_not analysis_run.build_scorecard(power_score: 101).valid?
    assert_not analysis_run.salt_social_friction_evidences.build(
      evidence_type: "mood",
      category: "tone",
      label: "Invalid"
    ).valid?
  end

  test "legality snapshots and pod evaluations keep deterministic source metadata" do
    snapshot = LegalitySnapshot.create!(
      source: "mtgcommander",
      effective_on: Date.new(2026, 5, 3),
      banned_names: [ "Biorhythm" ],
      source_url: "https://mtgcommander.net/index.php/rules/"
    )
    pod = users(:one).pod_evaluations.create!(
      name: "Friday pod",
      deck_count: 4,
      rubric_version: "2026-05-03",
      deck_snapshot: [ { "deck" => "Kinnan Test Deck" } ]
    )

    assert_includes(snapshot.banned_names, "Biorhythm")
    assert_not_nil(snapshot.fetched_at)
    assert_equal(4, pod.deck_count)
    assert_equal("draft", pod.status)
  end
end

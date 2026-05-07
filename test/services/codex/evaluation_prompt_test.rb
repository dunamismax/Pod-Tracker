require "test_helper"

module Codex
  class EvaluationPromptTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      CommanderFormat::CardTagImporter.new.import!
      LegalitySnapshot.find_or_create_by!(
        source: "mtgcommander",
        format: "commander",
        effective_on: Date.new(2026, 2, 9)
      )
      @library = Decks::FixtureLibrary.new
    end

    test "deck prompt packages deterministic facts, decklist, rubric, and response schema" do
      deck = @library.build_deck("high_power_najeela_5c", user: @user)
      deck.save!
      run = Decks::Analyzer.run(deck, user: @user)

      payload = DeckEvaluationPrompt.new.call(deck, analysis_run: run)

      assert_equal DeckEvaluationPrompt::PROMPT_VERSION, payload["prompt_version"]
      assert_equal ScorecardResponseSchema::VERSION, payload["schema_version"]
      assert_equal ScorecardResponseSchema::VERSION, payload.dig("response_schema", "properties", "schema_version", "const")
      assert_equal deck.name, payload.dig("input", "deck", "name")
      assert_equal deck.deck_cards.where(board: %w[commander main]).count, payload.dig("input", "deck", "cards").size

      fact_ids = payload.dig("input", "deterministic_facts").map { |fact| fact["id"] }
      assert_includes fact_ids, "fact.score.power"
      assert_includes fact_ids, "fact.bracket.combo_pairs"
      assert_includes fact_ids, "fact.features.roles"

      user_message = payload["messages"].last.fetch("content")
      parsed = JSON.parse(user_message)
      assert_equal payload["input"], parsed
    end

    test "recorded response fixture only references fact ids the deck prompt can provide" do
      deck = @library.build_deck("high_power_najeela_5c", user: @user)
      deck.save!
      run = Decks::Analyzer.run(deck, user: @user)
      prompt = DeckEvaluationPrompt.new.call(deck, analysis_run: run)
      fact_ids = prompt.dig("input", "deterministic_facts").map { |fact| fact["id"] }
      response = ScorecardResponseValidator.new.validate!(
        JSON.parse(file_fixture("codex_scorecard_response_v1.json").read)
      )

      refs = response.fetch("adjustments").values.flat_map { |entry| entry.fetch("deterministic_fact_refs") }
      refs += response.fetch("friction_drivers").flat_map { |entry| entry.fetch("deterministic_fact_refs") }
      refs += response.fetch("rule_zero_talking_points").flat_map { |entry| entry.fetch("deterministic_fact_refs") }
      refs += response.fetch("recommendations").flat_map { |entry| entry.fetch("deterministic_fact_refs") }

      assert_empty refs.uniq - fact_ids
    end

    test "pod prompt packages pod snapshot and pod-aware fact ids" do
      pod = build_pod_from_fixtures(%w[
        precon_korlash_mono_black
        atraxa_superfriends_upgraded
        cedh_tymna_thrasios_thoracle
      ])
      run = Pods::Analyzer.run(pod, user: @user)

      payload = PodEvaluationPrompt.new.call(pod, pod_analysis_run: run)

      assert_equal PodEvaluationPrompt::PROMPT_VERSION, payload["prompt_version"]
      assert_equal ScorecardResponseSchema::VERSION, payload["schema_version"]
      assert_equal 3, payload.dig("input", "pod", "slots").size

      fact_ids = payload.dig("input", "deterministic_facts").map { |fact| fact["id"] }
      assert_includes fact_ids, "fact.pod.bracket"
      assert_includes fact_ids, "fact.pod.aggregate.power"
      assert_includes fact_ids, "fact.pod.slot1.identity"
      assert_includes fact_ids, "fact.pod.warnings"
    end

    private

    def build_pod_from_fixtures(slugs)
      decks = slugs.map do |slug|
        deck = @library.build_deck(slug, user: @user)
        deck.save!
        Decks::Analyzer.run(deck, user: @user)
        deck
      end

      Pod.create!(user: @user, name: "Codex prompt pod", format: "commander", status: "draft").tap do |pod|
        decks.each_with_index do |deck, idx|
          pod.pod_slots.create!(deck: deck, position: idx + 1)
        end
      end
    end
  end
end

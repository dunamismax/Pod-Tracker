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

    test "deck prompt packages bracket briefing, decklist, deterministic signals, and v2 schema" do
      deck = @library.build_deck("high_power_najeela_5c", user: @user)
      deck.save!
      run = Decks::Analyzer.run(deck, user: @user)

      payload = DeckEvaluationPrompt.new.call(deck, analysis_run: run)

      assert_equal DeckEvaluationPrompt::PROMPT_VERSION, payload["prompt_version"]
      assert_equal DeckEvaluationSchema::VERSION, payload["schema_version"]
      assert_equal DeckEvaluationSchema::VERSION, payload.dig("response_schema", "properties", "schema_version", "const")
      assert_equal deck.name, payload.dig("input", "deck", "name")
      assert_equal deck.deck_cards.where(board: %w[commander main]).count, payload.dig("input", "deck", "cards").size

      context = payload.dig("input", "context")
      assert_equal BracketBriefing::BRACKETS_VERSION, context["version"]
      assert_equal 5, Array(context["brackets"]).size
      assert_includes Array(context.dig("game_changers", "cards")).map { |c| c["name"] }, "Demonic Tutor"
      assert_includes Array(context.dig("banlist", "banned_names")), "Mana Crypt"

      assert_equal "commander", payload.dig("input", "deck", "format")
      assert payload.dig("input", "deterministic_signals", "available")

      user_message = payload["messages"].last.fetch("content")
      parsed = JSON.parse(user_message)
      assert_equal payload["input"], parsed
    end

    test "deck prompt builds even when the deck has no deterministic run yet" do
      deck = @library.build_deck("high_power_najeela_5c", user: @user)
      deck.save!

      payload = DeckEvaluationPrompt.new.call(deck, analysis_run: nil)

      assert_equal DeckEvaluationSchema::VERSION, payload["schema_version"]
      assert_equal false, payload.dig("input", "deterministic_signals", "available")
    end

    test "recorded v2 deck-evaluation fixture validates against the deck schema" do
      payload = JSON.parse(file_fixture("codex_deck_evaluation_response_v2.json").read)
      result = DeckEvaluationValidator.new.validate(payload)

      assert result.valid?, result.errors.join("\n")
      assert_equal 4, result.payload.dig("bracket", "value")
      assert_equal 6, result.payload.dig("axes").size
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

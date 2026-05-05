module Decks
  class Analyzer
    def self.run(deck, user: nil)
      new.run(deck, user: user)
    end

    def run(deck, user: nil)
      raise ArgumentError, "Analyzer requires a persisted deck" unless deck&.persisted?

      ActiveRecord::Base.transaction do
        analysis_run = AnalysisRun.create!(
          deck: deck,
          user: user || deck.user,
          kind: "deterministic",
          status: "running",
          rubric_version: Scorer::RUBRIC_VERSION,
          queued_at: Time.current,
          started_at: Time.current
        )

        features = FeatureExtractor.new.call(deck.reload)
        scoring = Scorer.new.call(features)
        legality = CommanderFormat::LegalityChecker.new.check(deck)

        card_names = deck.deck_cards.where(board: %w[main commander]).pluck(:name) +
                     deck.commanders.pluck(:name)
        provisional_scorecard = Struct.new(:power_score, :speed_score).new(
          scoring.scores["power"].value, scoring.scores["speed"].value
        )
        bracket = BracketEvaluator.new.call(
          features: features,
          card_names: card_names,
          scorecard: provisional_scorecard
        )

        analysis_run.update!(
          feature_vector: features.to_h,
          deterministic_snapshot: {
            "legality" => legality.to_h,
            "rubric_version" => scoring.rubric_version,
            "bracket" => bracket.to_h
          }
        )

        Scorecard.create!(
          analysis_run: analysis_run,
          power_score: scoring.scores["power"].value,
          speed_score: scoring.scores["speed"].value,
          interaction_score: scoring.scores["interaction"].value,
          consistency_score: scoring.scores["consistency"].value,
          salt_score: scoring.scores["salt"].value,
          social_friction_score: scoring.scores["social_friction"].value,
          bracket: bracket.bracket,
          bracket_sub_band: bracket.sub_band,
          bracket_payload: bracket.to_h,
          confidence: confidence_for(features),
          evidence: scoring.scores.transform_values(&:to_h),
          improvement_suggestions: scoring.recommendations,
          raw_payload: {
            "rubric_version" => scoring.rubric_version,
            "bracket_catalog_version" => bracket.version,
            "computed_at" => Time.current.iso8601
          }
        )

        persist_salt_friction_evidence(analysis_run, scoring, deck)

        analysis_run.update!(status: "succeeded", completed_at: Time.current)
        analysis_run
      end
    end

    private

    def confidence_for(features)
      return 1.0 if features.total_cards.zero?

      missing_ratio = features.missing_oracle_count.to_f / features.total_cards
      [ (1.0 - missing_ratio).round(4), 0.0 ].max
    end

    def persist_salt_friction_evidence(analysis_run, scoring, deck)
      deck_card_index = deck.deck_cards.includes(:oracle_card).each_with_object({}) do |dc, h|
        h[dc.normalized_name] ||= dc
      end

      Array(scoring.scores["salt"].evidence["drivers"]).each do |driver|
        Array(driver["cards"]).each do |card_name|
          dc = deck_card_index[ApplicationRecord.normalize_card_name(card_name)]
          SaltSocialFrictionEvidence.create!(
            analysis_run: analysis_run,
            deck_card: dc,
            oracle_card: dc&.oracle_card,
            evidence_type: "salt",
            category: driver["tag"],
            label: driver["label"],
            score_delta: driver["weight"],
            severity: nil,
            explanation: "Driver: #{driver['label']} (count #{driver['count']})"
          )
        end
      end

      Array(scoring.scores["social_friction"].evidence["drivers"]).each do |driver|
        Array(driver["cards"]).each do |card_name|
          dc = deck_card_index[ApplicationRecord.normalize_card_name(card_name)]
          SaltSocialFrictionEvidence.create!(
            analysis_run: analysis_run,
            deck_card: dc,
            oracle_card: dc&.oracle_card,
            evidence_type: "social_friction",
            category: driver["tag"],
            label: driver["label"],
            score_delta: 1.0,
            severity: nil,
            explanation: "Driver: #{driver['label']} (count #{driver['count']})"
          )
        end
      end
    end
  end
end

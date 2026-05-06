require "set"

module Collections
  class RecommendationOwnership
    CATEGORY_ROLE_TAGS = {
      "mana" => %w[ramp fast_mana],
      "ramp" => %w[ramp fast_mana],
      "draw" => %w[card_draw],
      "interaction" => %w[removal stack_interaction board_wipe protection]
    }.freeze

    def self.annotate(user:, deck:, recommendations:)
      new(user:, deck:, recommendations:).call
    end

    def initialize(user:, deck:, recommendations:)
      @user = user
      @deck = deck
      @recommendations = Array(recommendations)
    end

    def call
      @recommendations.map do |recommendation|
        rec = recommendation.deep_dup
        rec["ownership"] = ownership_for(rec["category"])
        rec
      end
    end

    private

      def ownership_for(category)
        candidates = candidate_names_for(category)

        if candidates.any?
          {
            "status" => "owned_options",
            "label" => "Owned options available",
            "detail" => "Your collection has #{candidates.first(5).to_sentence}."
          }
        else
          {
            "status" => "needs_acquisition",
            "label" => "No matching owned options found",
            "detail" => "This upgrade likely needs a borrow, trade, or purchase."
          }
        end
      end

      def candidate_names_for(category)
        collection_candidates.select do |card|
          next land_candidate?(card) if category == "lands"
          next salt_replacement_candidate?(card) if category == "salt"

          tags = CATEGORY_ROLE_TAGS.fetch(category, [])
          tags.any? && (card[:role_tags] & tags).any?
        end.pluck(:name).sort
      end

      def collection_candidates
        @collection_candidates ||= begin
          deck_names = deck_normalized_names
          role_tags_by_name = role_tags_by_normalized_name

          @user.collection_cards.includes(:oracle_card).filter_map do |collection_card|
            next if deck_names.include?(collection_card.normalized_name)

            {
              name: collection_card.name,
              normalized_name: collection_card.normalized_name,
              oracle_card: collection_card.oracle_card,
              role_tags: role_tags_by_name.fetch(collection_card.normalized_name, [])
            }
          end
        end
      end

      def deck_normalized_names
        @deck_normalized_names ||= begin
          names = @deck.deck_cards.where(board: %w[main commander]).pluck(:normalized_name) +
                  @deck.commanders.pluck(:normalized_name)
          names.compact.to_set
        end
      end

      def role_tags_by_normalized_name
        @role_tags_by_normalized_name ||= CardTagAssignment
          .role
          .where(normalized_card_name: @user.collection_cards.select(:normalized_name))
          .joins(:card_tag)
          .pluck(:normalized_card_name, "card_tags.slug")
          .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(normalized_name, slug), hash|
            hash[normalized_name] << slug
          end
      end

      def land_candidate?(card)
        card[:oracle_card]&.type_line.to_s.include?("Land")
      end

      def salt_replacement_candidate?(card)
        card[:role_tags].any? && !salt_tag_names.include?(card[:normalized_name])
      end

      def salt_tag_names
        @salt_tag_names ||= CardTagAssignment.salt.pluck(:normalized_card_name).to_set
      end
  end
end

require "json"

class PublicController < ApplicationController
  allow_unauthenticated_access

  def home
  end

  def brackets
    @catalog = load_brackets_catalog
    @combo_catalog = load_combo_catalog
    @bracket_meta = Decks::BracketEvaluator::BRACKETS
    @banned_list = load_banned_list
  end

  def game_changers
    @catalog = load_brackets_catalog
  end

  def pregame_template
  end

  def about
  end

  def privacy
  end

  def terms
  end

  private

  def load_brackets_catalog
    JSON.parse(File.read(Rails.root.join("db/seeds/commander/brackets/game_changers.json")))
  end

  def load_combo_catalog
    JSON.parse(File.read(Rails.root.join("db/seeds/commander/brackets/two_card_combos.json")))
  end

  def load_banned_list
    snapshot = LegalitySnapshot.current_commander
    return { "names" => [], "categories" => [], "snapshot" => nil } unless snapshot

    {
      "names" => Array(snapshot.banned_names).sort,
      "categories" => Array(snapshot.category_bans),
      "snapshot" => {
        "source" => snapshot.source,
        "effective_on" => snapshot.effective_on,
        "source_url" => snapshot.source_url
      }
    }
  rescue StandardError
    { "names" => [], "categories" => [], "snapshot" => nil }
  end
end

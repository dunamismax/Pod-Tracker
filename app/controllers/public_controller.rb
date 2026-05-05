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

  def sitemap
    @entries = sitemap_entries
    respond_to do |format|
      format.xml
    end
  end

  private

  def sitemap_entries
    today = Date.current.iso8601
    [
      { loc: root_url, changefreq: "weekly", priority: "1.0", lastmod: today },
      { loc: brackets_url, changefreq: "monthly", priority: "0.9", lastmod: today },
      { loc: game_changers_url, changefreq: "monthly", priority: "0.8", lastmod: today },
      { loc: pregame_template_url, changefreq: "monthly", priority: "0.8", lastmod: today },
      { loc: about_url, changefreq: "yearly", priority: "0.4", lastmod: today },
      { loc: privacy_url, changefreq: "yearly", priority: "0.2", lastmod: today },
      { loc: terms_url, changefreq: "yearly", priority: "0.2", lastmod: today }
    ]
  end

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

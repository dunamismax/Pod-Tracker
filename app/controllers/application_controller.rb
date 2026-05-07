class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :mobile_nav_section

  # Highlights the active item in the mobile bottom nav. Subclasses may set
  # `@mobile_nav_section` directly; otherwise we map controller_path to a key
  # the partial recognizes.
  def mobile_nav_section
    return @mobile_nav_section if defined?(@mobile_nav_section) && @mobile_nav_section

    case controller_path
    when "decks", "deck_ai_evaluations", "deck_shares", "public_decks" then "decks"
    when "pods", "pod_ai_evaluations", "pod_shares", "public_pods" then "pods"
    when "game_nights" then "sessions"
    when "matchup_notes" then "journal"
    when "collections", "collection_imports", "collection_cards", "unresolved_entries" then "collection"
    when "dashboard" then "decks"
    end
  end
end

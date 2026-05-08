module GameNightsHelper
  # Renders the deck name as a link only when the current user owns the deck;
  # otherwise renders the snapshot as plain text. This keeps the host from
  # 404ing when they click an invitee's deck.
  def deck_label_for_game_night(night_deck)
    deck = night_deck&.deck
    label = night_deck&.deck_name_snapshot || deck&.name
    return "" if label.blank?

    if deck && deck.user_id == current_user_for_view&.id
      link_to(label, deck_path(deck), class: "text-emerald-300 hover:text-emerald-200")
    else
      content_tag(:span, label, class: "text-zinc-200")
    end
  end

  # Same idea for accepted invitations — the deck belongs to the invitee, so
  # the host should not get a deck link.
  def deck_label_for_invitation(invitation)
    deck = invitation.deck
    label = deck&.name
    return "" if label.blank?

    if deck.user_id == current_user_for_view&.id
      link_to(label, deck_path(deck), class: "text-emerald-300 hover:text-emerald-200")
    else
      content_tag(:span, label, class: "text-zinc-200")
    end
  end

  def deck_label_for_seat(seat)
    deck = seat.deck
    label = seat.deck_name_snapshot

    if deck && deck.user_id == current_user_for_view&.id
      link_to(label, deck_path(deck), class: "text-emerald-300 hover:text-emerald-200")
    else
      content_tag(:span, label, class: "text-zinc-200")
    end
  end

  # Pick a deck the current user owns from a pod for the matchup-note
  # capture link, since matchup notes scope by current_user.decks.
  def host_owned_deck_id_in_pod(seats)
    seats.detect { |seat| seat.deck && seat.deck.user_id == current_user_for_view&.id }&.deck_id
  end

  def invitation_badge_classes(status)
    case status
    when "accepted"  then "bg-emerald-950/60 text-emerald-200"
    when "declined"  then "bg-zinc-800 text-zinc-300"
    when "cancelled" then "bg-zinc-800 text-zinc-400"
    else                  "bg-amber-950/40 text-amber-200"
    end
  end

  private

  def current_user_for_view
    Current.session&.user
  end
end

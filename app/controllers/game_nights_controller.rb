class GameNightsController < ApplicationController
  before_action :load_game_night, only: %i[show destroy]

  def index
    @game_nights = current_user.game_nights
                              .includes(game_night_players: :player, game_night_decks: :deck)
                              .order(played_on: :desc, updated_at: :desc)
                              .limit(50)
  end

  def show
    @checked_in = @game_night.game_night_players.includes(:player)
    @decks_by_player_id = @game_night.game_night_decks.includes(:deck).index_by(&:player_id)
  end

  def new
    @form = GameNightForm.new(
      name: default_name,
      played_on: Date.current
    )
    load_form_context
  end

  def create
    @form = GameNightForm.new(game_night_params)
    @form.user = current_user
    load_form_context

    unless @form.valid?
      render :new, status: :unprocessable_entity
      return
    end

    game_night = nil
    GameNight.transaction do
      game_night = current_user.game_nights.create!(
        name: @form.name.to_s.strip,
        played_on: @form.played_on,
        location: @form.location.to_s.strip.presence,
        notes: @form.notes.to_s.strip.presence,
        status: "draft"
      )

      @form.populated_check_ins.each_with_index do |row, index|
        player = find_or_create_player(row.fetch("player_name"))
        deck = current_user.decks.find(row.fetch("deck_id"))
        position = index + 1

        game_night.game_night_players.create!(
          player: player,
          position: position
        )
        game_night.game_night_decks.create!(
          player: player,
          deck: deck,
          position: position
        )
      end
    end

    record_audit("game_night.created", game_night: game_night)
    redirect_to game_night_path(game_night), notice: "Session created."
  rescue ActiveRecord::RecordInvalid => e
    @form.errors.add(:base, e.message)
    render :new, status: :unprocessable_entity
  end

  def destroy
    @game_night.destroy
    record_audit("game_night.removed", game_night: @game_night)
    redirect_to game_nights_path, notice: "Session removed."
  end

  private

  def current_user
    Current.session.user
  end

  def load_game_night
    @game_night = current_user.game_nights.find(params[:id])
  end

  def load_form_context
    @decks = current_user.decks.order(updated_at: :desc).limit(100)
  end

  def game_night_params
    params.require(:game_night_form).permit(:name, :played_on, :location, :notes, check_ins: %i[player_name deck_id])
  end

  def default_name
    "Commander night #{Date.current.to_fs(:long)}"
  end

  def find_or_create_player(name)
    normalized_name = Player.normalize_card_name(name)
    current_user.players.find_or_create_by!(normalized_name: normalized_name) do |player|
      player.name = name
    end
  end

  def record_audit(event_name, game_night:)
    AuditEvent.create!(
      user: current_user,
      auditable: game_night,
      event_name: event_name,
      occurred_at: Time.current,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: {
        session_name: game_night.name,
        checked_in_count: game_night.game_night_players.size
      }
    )
  end
end

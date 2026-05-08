class GameNightsController < ApplicationController
  before_action :load_game_night, only: %i[show seat_pods pod_results destroy]

  def index
    @game_nights = current_user.game_nights
                              .includes(game_night_players: :player, game_night_decks: :deck)
                              .order(played_on: :desc, updated_at: :desc)
                              .limit(50)
    @pending_invitations = GameNightInvitation
                              .where(status: "pending")
                              .where("LOWER(email_address) = ?", current_user.email_address.to_s.downcase)
                              .includes(game_night: :user)
                              .order(invited_at: :desc)
  end

  def show
    @checked_in = @game_night.game_night_players.includes(:player)
    @decks_by_player_id = @game_night.game_night_decks.includes(:deck).index_by(&:player_id)
    @seating_rows = seating_rows
    @pod_seats_by_number = @game_night.pod_seats_by_number
    @pod_results_by_number = @game_night.pod_results_by_number
    @post_game_prompts = Meta::PerformanceSummary.for_user(current_user).post_game_prompts(@game_night)
    @prior_notes_by_pod = Matchups::SessionContext.for_seating(
      user: current_user,
      game_night: @game_night,
      seating_rows: @seating_rows,
      decks_by_player_id: @decks_by_player_id
    )
    @invitations = @game_night.game_night_invitations.includes(:invited_user, :responded_user, :deck).to_a
    @invitations_by_status = @invitations.group_by(&:status)
  end

  def seat_pods
    result = GameNights::PodSeater.call(@game_night, assignments: seating_params)

    if result.success?
      record_audit("game_night.seated", game_night: @game_night)
      redirect_to game_night_path(@game_night), notice: "Pods seated."
    else
      redirect_to game_night_path(@game_night), alert: result.errors.to_sentence
    end
  end

  def pod_results
    result = GameNights::ResultRecorder.call(@game_night, results: result_params)

    if result.success?
      record_audit("game_night.results_recorded", game_night: @game_night)
      redirect_to game_night_path(@game_night), notice: "Results recorded."
    else
      redirect_to game_night_path(@game_night), alert: result.errors.to_sentence
    end
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

      invitation_rows = @form.populated_invitations.each_with_index.map do |row, index|
        {
          email_address: row["email_address"],
          display_name: row["display_name"],
          message: @form.invitation_message
        }
      end
      if invitation_rows.any?
        invite_result = GameNights::Inviter.call(game_night, rows: invitation_rows, host: current_user)
        unless invite_result.success?
          @form.errors.add(:invitations, invite_result.errors.to_sentence)
          raise ActiveRecord::Rollback
        end
      end
    end

    if @form.errors.any?
      render :new, status: :unprocessable_entity
      return
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
    params.require(:game_night_form).permit(
      :name, :played_on, :location, :notes, :invitation_message,
      check_ins: %i[player_name deck_id],
      invitations: %i[email_address display_name]
    )
  end

  def seating_params
    params.fetch(:seating, ActionController::Parameters.new)
          .permit(rows: %i[player_id pod_number seat_number])
          .fetch(:rows, [])
  end

  def result_params
    params.fetch(:results, ActionController::Parameters.new)
          .permit(rows: %i[pod_number winner_player_id draw turns win_condition notes])
          .fetch(:rows, [])
  end

  def seating_rows
    existing_rows = @game_night.game_night_pod_seats.map do |seat|
      {
        "player_id" => seat.player_id.to_s,
        "pod_number" => seat.pod_number.to_s,
        "seat_number" => seat.seat_number.to_s
      }
    end

    existing_rows.presence || GameNights::SeatingSuggester.call(@game_night)
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

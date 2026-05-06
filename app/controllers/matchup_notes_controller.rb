class MatchupNotesController < ApplicationController
  before_action :load_matchup_note, only: %i[show edit update destroy]
  before_action :load_form_context, only: %i[index new edit create update]

  def index
    @filters = filter_params
    @matchup_notes = filtered_notes.limit(100)
  end

  def show
  end

  def new
    @matchup_note = current_user.matchup_notes.new(
      deck: prefilled_deck,
      commander: prefilled_commander,
      opponent: prefilled_opponent,
      pod: prefilled_pod,
      game_night: prefilled_game_night,
      game_night_pod_number: params[:game_night_pod_number],
      happened_at: Time.current
    )
  end

  def create
    @matchup_note = current_user.matchup_notes.new(matchup_note_params)

    if @matchup_note.save
      record_audit("matchup_note.created", @matchup_note)
      redirect_to matchup_note_path(@matchup_note), notice: "Matchup note saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @matchup_note.update(matchup_note_params)
      record_audit("matchup_note.updated", @matchup_note)
      redirect_to matchup_note_path(@matchup_note), notice: "Matchup note updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @matchup_note.destroy
    record_audit("matchup_note.removed", @matchup_note)
    redirect_to matchup_notes_path, notice: "Matchup note removed."
  end

  private

  def current_user
    Current.session.user
  end

  def load_matchup_note
    @matchup_note = current_user.matchup_notes.find(params[:id])
  end

  def load_form_context
    @decks = current_user.decks.order(:name)
    @commanders = Commander.joins(:deck)
                           .where(decks: { user_id: current_user.id })
                           .includes(:deck)
                           .order("decks.name ASC", :position)
    @players = current_user.players.order(:name)
    @pods = current_user.pods.order(updated_at: :desc).limit(100)
    @game_nights = current_user.game_nights.order(played_on: :desc, updated_at: :desc).limit(100)
  end

  def filtered_notes
    notes = current_user.matchup_notes
                        .includes(:deck, :commander, :opponent, :pod, :game_night)
                        .recent

    notes = notes.where(deck_id: @filters[:deck_id]) if @filters[:deck_id].present?
    notes = notes.where(commander_id: @filters[:commander_id]) if @filters[:commander_id].present?
    notes = notes.where(opponent_id: @filters[:opponent_id]) if @filters[:opponent_id].present?
    notes = notes.where(pod_id: @filters[:pod_id]) if @filters[:pod_id].present?
    notes = notes.where(game_night_id: @filters[:game_night_id]) if @filters[:game_night_id].present?

    if @filters[:tag].present?
      tag = MatchupNote.parse_tags(@filters[:tag]).first
      notes = notes.where("? = ANY(tags)", tag) if tag.present?
    end

    if @filters[:q].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(@filters[:q].strip)}%"
      notes = notes.where("matchup_notes.body ILIKE :query OR matchup_notes.tags::text ILIKE :query", query: query)
    end

    notes
  end

  def matchup_note_params
    params.require(:matchup_note)
          .permit(:deck_id, :commander_id, :opponent_id, :pod_id, :game_night_id, :game_night_pod_number, :body, :happened_at, :tag_list)
          .tap { |attributes| normalize_blank_ids(attributes) }
  end

  def filter_params
    params.permit(:q, :tag, :deck_id, :commander_id, :opponent_id, :pod_id, :game_night_id)
  end

  def normalize_blank_ids(attributes)
    %i[commander_id opponent_id pod_id game_night_id game_night_pod_number].each do |key|
      attributes[key] = nil if attributes[key].blank?
    end
  end

  def prefilled_deck
    current_user.decks.find_by(id: params[:deck_id])
  end

  def prefilled_commander
    return unless prefilled_deck

    prefilled_deck.commanders.find_by(id: params[:commander_id])
  end

  def prefilled_opponent
    current_user.players.find_by(id: params[:opponent_id])
  end

  def prefilled_pod
    current_user.pods.find_by(id: params[:pod_id])
  end

  def prefilled_game_night
    current_user.game_nights.find_by(id: params[:game_night_id])
  end

  def record_audit(event_name, matchup_note)
    AuditEvent.create!(
      user: current_user,
      auditable: matchup_note,
      event_name: event_name,
      occurred_at: Time.current,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: {
        deck_name: matchup_note.deck&.name,
        opponent_name: matchup_note.opponent&.name,
        tags: matchup_note.tags
      }.compact
    )
  end
end

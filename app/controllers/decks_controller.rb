class DecksController < ApplicationController
  rate_limit to: 30, within: 5.minutes, only: :create,
             with: -> { redirect_to new_deck_path, alert: "Too many imports. Try again shortly." }

  before_action :load_deck, only: %i[show destroy]

  def index
    @search = params[:q].to_s.strip
    @bracket_filter = params[:bracket].to_s.strip
    @status_filter = params[:status].to_s.strip

    scope = current_user.decks.order(updated_at: :desc)

    if @search.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@search)}%"
      scope = scope.where(
        "decks.name ILIKE :pattern OR EXISTS (SELECT 1 FROM unnest(decks.commander_names) AS cn WHERE cn ILIKE :pattern)",
        pattern: pattern
      )
    end

    if Deck::STATUSES.include?(@status_filter)
      scope = scope.where(status: @status_filter)
    end

    if (1..5).cover?(@bracket_filter.to_i) && @bracket_filter.to_i.to_s == @bracket_filter
      bracket = @bracket_filter.to_i
      scope = scope.where(<<~SQL, bracket: bracket)
        EXISTS (
          SELECT 1
            FROM analysis_runs ar
            JOIN scorecards s ON s.analysis_run_id = ar.id
           WHERE ar.deck_id = decks.id
             AND ar.kind = 'deterministic'
             AND ar.status = 'succeeded'
             AND s.bracket = :bracket
        )
      SQL
    end

    @total_decks = current_user.decks.count
    @decks = scope.limit(100)
  end

  def show
    @analysis_run = @deck.latest_deterministic_run
    @scorecard = @analysis_run&.scorecard
    @legality = @analysis_run&.deterministic_snapshot&.dig("legality")
    @ai_run = @deck.latest_ai_run
    @ai_evaluation = Decks::AiEvaluationPresenter.for(@ai_run)
    @codex_account = current_user.codex_account
    @ownership = Collections::Ownership.for_deck(user: current_user, deck: @deck)
    base_recommendations = @ai_evaluation&.recommendations.presence || @scorecard&.improvement_suggestions
    @recommendations = Collections::RecommendationOwnership.annotate(
      user: current_user,
      deck: @deck,
      recommendations: base_recommendations
    )
    performance = Meta::PerformanceSummary.for_user(current_user)
    @deck_performance = performance.deck_performance(@deck)
    @revision_performance = performance.revision_performance(@deck)
  end

  def new
    @form = DeckImportForm.new
  end

  def create
    @form = DeckImportForm.new(import_params)

    unless @form.valid?
      render :new, status: :unprocessable_entity
      return
    end

    result =
      if @form.archidekt_url_provided?
        Decks::Importer.import_archidekt_url(
          user: current_user,
          url: @form.normalized_archidekt_url,
          name: @form.name,
          commander_hint: @form.commander_hint
        )
      elsif @form.moxfield_url_provided?
        Decks::Importer.import_moxfield_url(
          user: current_user,
          url: @form.normalized_moxfield_url,
          name: @form.name,
          commander_hint: @form.commander_hint
        )
      elsif @form.upload_provided?
        Decks::Importer.import_text_file(
          user: current_user,
          file: @form.decklist_file,
          name: @form.name,
          commander_hint: @form.commander_hint
        )
      else
        Decks::Importer.import_pasted_text(
          user: current_user,
          payload: @form.decklist,
          name: @form.name,
          commander_hint: @form.commander_hint
        )
      end

    if result.success?
      record_audit("deck.imported", deck: result.deck, parsed: result.parsed)
      redirect_to deck_path(result.deck), notice: "Deck imported."
    else
      @form.errors.add(:decklist, result.error_messages.first || "Could not import decklist.")
      result.error_messages.drop(1).each { |message| @form.errors.add(:decklist, message) }
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @deck.destroy
    record_audit("deck.removed", deck: @deck, parsed: nil)
    redirect_to decks_path, notice: "Deck removed."
  end

  private
    def current_user
      Current.session.user
    end

    def load_deck
      @deck = current_user.decks.find(params[:id])
    end

    def import_params
      params.require(:deck_import_form).permit(:decklist, :name, :commander_hint, :decklist_file, :archidekt_url, :moxfield_url)
    end

    def record_audit(name, deck:, parsed:)
      metadata = {}
      if deck
        metadata[:deck_name] = deck.name
        metadata[:source_type] = deck.source_type
        metadata[:card_count] = deck.deck_cards.sum(&:quantity) if deck.respond_to?(:deck_cards)
      end
      if parsed
        metadata[:unparsed_line_count] = parsed.unparsed_lines.size
      end
      AuditEvent.create!(
        user: current_user,
        auditable: deck,
        event_name: name,
        occurred_at: Time.current,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: metadata.compact
      )
    end
end

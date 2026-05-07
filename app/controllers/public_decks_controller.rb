class PublicDecksController < ApplicationController
  allow_unauthenticated_access only: %i[show export analysis]

  before_action :load_deck

  def show
    @analysis_run = @deck.latest_deterministic_run
    @scorecard = @analysis_run&.scorecard
    @legality = @analysis_run&.deterministic_snapshot&.dig("legality")
    @ai_run = @deck.latest_ai_run
    @ai_evaluation = Decks::AiEvaluationPresenter.for(@ai_run)
    @recommendations = (@ai_evaluation&.recommendations.presence || Array(@scorecard&.improvement_suggestions))
  end

  def export
    exporter = Decks::Exporter.new(@deck)

    respond_to do |format|
      format.text { send_data exporter.to_text, type: "text/plain", disposition: "attachment", filename: exporter.filename("txt") }
      format.csv { send_data exporter.to_csv, type: "text/csv", disposition: "attachment", filename: exporter.filename("csv") }
      format.json { send_data exporter.to_json, type: "application/json", disposition: "attachment", filename: exporter.filename("json") }
    end
  end

  def analysis
    exporter = Decks::AnalysisExporter.new(@deck, ai_run: @deck.latest_ai_run)

    respond_to do |format|
      format.markdown { send_data exporter.to_markdown, type: "text/markdown", disposition: "attachment", filename: exporter.filename("md") }
      format.json { send_data exporter.to_json, type: "application/json", disposition: "attachment", filename: exporter.filename("json") }
    end
  end

  private
    def load_deck
      @deck = Deck.shared.find_by(share_token: params[:token])
      render plain: "Not found", status: :not_found unless @deck
    end
end

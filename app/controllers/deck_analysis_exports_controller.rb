class DeckAnalysisExportsController < ApplicationController
  before_action :load_deck

  def show
    exporter = Decks::AnalysisExporter.new(@deck)

    respond_to do |format|
      format.markdown { send_data exporter.to_markdown, type: "text/markdown", disposition: "attachment", filename: exporter.filename("md") }
      format.json { send_data exporter.to_json, type: "application/json", disposition: "attachment", filename: exporter.filename("json") }
    end
  end

  private
    def load_deck
      @deck = Current.session.user.decks.find(params[:deck_id])
    end
end

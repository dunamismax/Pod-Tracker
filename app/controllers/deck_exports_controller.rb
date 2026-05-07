class DeckExportsController < ApplicationController
  before_action :load_deck

  def show
    exporter = Decks::Exporter.new(@deck)

    respond_to do |format|
      format.text { send_data exporter.to_text, type: "text/plain", disposition: "attachment", filename: exporter.filename("txt") }
      format.csv { send_data exporter.to_csv, type: "text/csv", disposition: "attachment", filename: exporter.filename("csv") }
      format.json { send_data exporter.to_json, type: "application/json", disposition: "attachment", filename: exporter.filename("json") }
    end
  end

  private
    def load_deck
      @deck = Current.session.user.decks.find(params[:deck_id])
    end
end

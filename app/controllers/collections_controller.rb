class CollectionsController < ApplicationController
  def show
    @import_form = CollectionImportForm.new
    @collection_cards = current_user.collection_cards.order(:name).limit(250)
    @recent_imports = current_user.collection_imports.order(created_at: :desc).limit(10)
    @open_unresolved_entries = current_user.unresolved_entries.where(status: "open").order(created_at: :desc).limit(50)
  end

  private

    def current_user
      Current.session.user
    end
end

class CollectionImportsController < ApplicationController
  def show
    @collection_import = current_user.collection_imports.find(params[:id])
    @unresolved_entries = @collection_import.unresolved_entries.order(:id)
  end

  def create
    @form = CollectionImportForm.new(collection_import_params)

    unless @form.valid?
      load_collection_state
      render "collections/show", status: :unprocessable_entity
      return
    end

    result =
      if @form.upload_provided?
        Collections::Importer.import_file(user: current_user, file: @form.collection_file)
      else
        Collections::Importer.import_text(user: current_user, payload: @form.collection_list)
      end

    if result.success?
      record_audit(result.collection_import)
      redirect_to collection_import_path(result.collection_import), notice: "Collection imported."
    else
      @form.errors.add(:collection_list, result.error_messages.first || "Could not import collection.")
      load_collection_state
      render "collections/show", status: :unprocessable_entity
    end
  end

  private

    def current_user
      Current.session.user
    end

    def collection_import_params
      params.require(:collection_import_form).permit(:collection_list, :collection_file)
    end

    def load_collection_state
      @import_form = @form
      @collection_cards = current_user.collection_cards.order(:name).limit(250)
      @recent_imports = current_user.collection_imports.order(created_at: :desc).limit(10)
      @open_unresolved_entries = current_user.unresolved_entries.where(status: "open").order(created_at: :desc).limit(50)
    end

    def record_audit(collection_import)
      AuditEvent.create!(
        user: current_user,
        auditable: collection_import,
        event_name: "collection.imported",
        occurred_at: Time.current,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          imported_count: collection_import.imported_count,
          unresolved_count: collection_import.unresolved_count,
          source_type: collection_import.source_type
        }
      )
    end
end

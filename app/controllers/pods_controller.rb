class PodsController < ApplicationController
  before_action :load_pod, only: %i[show destroy]

  def index
    @pods = current_user.pods
                        .includes(:pod_slots, :pod_analysis_runs)
                        .order(updated_at: :desc)
                        .limit(50)
  end

  def show
    @latest_run = @pod.latest_analysis_run
    @snapshot = @latest_run&.snapshot || {}
    @brief = @latest_run&.rule_zero_brief || {}
    @warnings = Array(@latest_run&.warnings)
    @suggestions = Array(@latest_run&.suggestions)
    @ai_run = @pod.latest_ai_run
  end

  def new
    @form = PodForm.new
    @form.user = current_user
    @decks = current_user.decks.order(updated_at: :desc).limit(100)
  end

  def create
    @form = PodForm.new(pod_params)
    @form.user = current_user
    @decks = current_user.decks.order(updated_at: :desc).limit(100)

    unless @form.valid?
      render :new, status: :unprocessable_entity
      return
    end

    pod = build_pod_from_form(@form)
    guest_deck = nil

    begin
      Pod.transaction do
        pod.save!
        @form.deck_id_array.each_with_index do |deck_id, idx|
          pod.pod_slots.create!(
            deck_id: deck_id,
            position: idx + 1,
            label: @form.slot_label_for(deck_id).presence
          )
        end

        if @form.guest_deck_provided?
          guest_deck = import_guest_deck(@form)
          guest_deck.update!(guest_for_pod_id: pod.id, visibility: "private")
          pod.pod_slots.create!(
            deck: guest_deck,
            position: pod.pod_slots.size + 1,
            label: @form.guest_label.presence || "Guest"
          )
        end
      end
      Pods::Analyzer.run(pod, user: current_user)
      record_audit("pod.analyzed", pod: pod, guest_deck: guest_deck)
      redirect_to pod_path(pod), notice: "Pod analyzed."
    rescue GuestImportFailed => e
      pod.destroy if pod.persisted?
      e.messages.each { |message| @form.errors.add(:guest_deck, message) }
      render :new, status: :unprocessable_entity
    rescue ActiveRecord::RecordInvalid => e
      pod.destroy if pod.persisted?
      @form.errors.add(:base, e.message)
      render :new, status: :unprocessable_entity
    rescue ArgumentError => e
      pod.destroy if pod.persisted?
      @form.errors.add(:base, e.message)
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @pod.destroy
    record_audit("pod.removed", pod: @pod)
    redirect_to pods_path, notice: "Pod removed."
  end

  private
    GuestImportFailed = Class.new(StandardError) do
      attr_reader :messages

      def initialize(messages)
        @messages = Array(messages).presence || [ "Could not import guest deck." ]
        super(@messages.first)
      end
    end

    def current_user
      Current.session.user
    end

    def load_pod
      @pod = current_user.pods.includes(pod_slots: { deck: :commanders }).find(params[:id])
    end

    def pod_params
      params.require(:pod_form).permit(
        :name,
        deck_ids: [],
        slot_labels: {},
        guest_deck: %i[name label decklist archidekt_url moxfield_url]
      )
    end

    def build_pod_from_form(form)
      Pod.new(
        user: current_user,
        name: form.name.to_s.strip,
        format: "commander",
        status: "draft"
      )
    end

    def import_guest_deck(form)
      result =
        case form.guest_source
        when :archidekt
          Decks::Importer.import_archidekt_url(
            user: nil,
            url: form.guest_archidekt_url,
            name: form.guest_name.presence
          )
        when :moxfield
          Decks::Importer.import_moxfield_url(
            user: nil,
            url: form.guest_moxfield_url,
            name: form.guest_name.presence
          )
        else
          Decks::Importer.import_pasted_text(
            user: nil,
            payload: form.guest_decklist,
            name: form.guest_name.presence
          )
        end

      raise GuestImportFailed.new(result.error_messages) unless result.success?

      result.deck
    end

    def record_audit(event_name, pod:, guest_deck: nil)
      metadata = {
        pod_name: pod.name,
        deck_count: pod.pod_slots.size
      }
      metadata[:guest_deck_source] = guest_deck.source_type if guest_deck

      AuditEvent.create!(
        user: current_user,
        auditable: pod,
        event_name: event_name,
        occurred_at: Time.current,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: metadata
      )
    end
end

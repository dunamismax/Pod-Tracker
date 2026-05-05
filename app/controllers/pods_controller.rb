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
      end
      Pods::Analyzer.run(pod, user: current_user)
      record_audit("pod.analyzed", pod: pod)
      redirect_to pod_path(pod), notice: "Pod analyzed."
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
    def current_user
      Current.session.user
    end

    def load_pod
      @pod = current_user.pods.includes(pod_slots: { deck: :commanders }).find(params[:id])
    end

    def pod_params
      params.require(:pod_form).permit(:name, deck_ids: [], slot_labels: {})
    end

    def build_pod_from_form(form)
      Pod.new(
        user: current_user,
        name: form.name.to_s.strip,
        format: "commander",
        status: "draft"
      )
    end

    def record_audit(event_name, pod:)
      AuditEvent.create!(
        user: current_user,
        auditable: pod,
        event_name: event_name,
        occurred_at: Time.current,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          pod_name: pod.name,
          deck_count: pod.pod_slots.count
        }
      )
    end
end

class AccountExportsController < ApplicationController
  before_action :load_user
  rate_limit to: 6, within: 1.hour, only: :create, with: -> { redirect_to account_path, alert: "Try again later." }

  def create
    exporter = Accounts::Exporter.new(@user)
    record_export(exporter)
    send_data exporter.to_json,
      type: "application/json",
      disposition: "attachment",
      filename: exporter.filename
  end

  private
    def load_user
      @user = Current.session.user
    end

    def record_export(exporter)
      AuditEvent.create!(
        user: @user,
        event_name: "account.exported",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: {
          schema_version: Accounts::Exporter::SCHEMA_VERSION,
          deck_count: @user.decks.count,
          analysis_run_count: @user.analysis_runs.count,
          pod_count: @user.pods.count,
          audit_event_count: @user.audit_events.count
        }
      )
    end
end

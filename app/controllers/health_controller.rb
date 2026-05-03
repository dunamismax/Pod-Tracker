class HealthController < ApplicationController
  allow_unauthenticated_access

  def readiness
    ActiveRecord::Base.connection.execute("SELECT 1")
    render json: { status: "ready" }
  rescue ActiveRecord::ActiveRecordError, PG::Error => error
    Rails.logger.warn("Readiness check failed: #{error.class}: #{error.message}")
    render json: { status: "unready" }, status: :service_unavailable
  end
end

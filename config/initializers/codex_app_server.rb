Rails.application.config.x.codex_app_server = ActiveSupport::OrderedOptions.new.merge!(
  enabled: ActiveModel::Type::Boolean.new.cast(ENV["CODEX_APP_SERVER_ENABLED"]),
  command: ENV["CODEX_APP_SERVER_COMMAND"].presence || "codex app-server",
  request_timeout_seconds: ENV.fetch("CODEX_APP_SERVER_REQUEST_TIMEOUT_SECONDS", 20).to_i,
  stream_timeout_seconds: ENV.fetch("CODEX_APP_SERVER_STREAM_TIMEOUT_SECONDS", 600).to_i,
  stream_idle_timeout_seconds: ENV.fetch("CODEX_APP_SERVER_STREAM_IDLE_TIMEOUT_SECONDS", 60).to_i
)

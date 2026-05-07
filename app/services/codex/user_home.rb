require "fileutils"
require "pathname"

module Codex
  # Per-user Codex state directory ($CODEX_HOME). Each Ideal Magic user gets
  # their own isolated CODEX_HOME under CODEX_HOME_ROOT so the codex CLI
  # signs JSON-RPC calls with that user's ChatGPT account, never another
  # user's. The web service must not have read or write access to Stephen's
  # personal /home/sawyer/.codex.
  module UserHome
    DEFAULT_DEV_ROOT = "tmp/codex_home".freeze

    class Error < StandardError; end

    class << self
      attr_writer :root_path_override

      def root_path(env: ENV)
        return @root_path_override if @root_path_override

        configured = env["CODEX_HOME_ROOT"].to_s.strip
        return Pathname.new(configured) if configured.present?

        if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          Rails.root.join(DEFAULT_DEV_ROOT)
        else
          Pathname.new(DEFAULT_DEV_ROOT)
        end
      end

      def path_for(user)
        raise Error, "user is required" if user.nil?
        raise Error, "user is not persisted" if user.respond_to?(:id) && user.id.nil?

        root_path.join(user.id.to_s)
      end

      def ensure!(user)
        path = path_for(user)
        FileUtils.mkdir_p(path)
        FileUtils.chmod(0o700, path)
        ensure_file_credentials_config!(path)
        path
      end

      def has_auth?(user)
        path_for(user).join("auth.json").exist?
      end

      def purge!(user)
        path = path_for(user)
        FileUtils.rm_rf(path)
        path
      end

      def reset_root_override!
        @root_path_override = nil
      end

      private
        def ensure_file_credentials_config!(path)
          config_path = path.join("config.toml")
          setting = 'cli_auth_credentials_store = "file"'
          contents = config_path.exist? ? config_path.read : +""
          return if contents.match?(/^\s*cli_auth_credentials_store\s*=/)

          contents << "\n" if contents.present? && !contents.end_with?("\n")
          contents << "#{setting}\n"
          config_path.write(contents)
          FileUtils.chmod(0o600, config_path)
        end
    end
  end
end

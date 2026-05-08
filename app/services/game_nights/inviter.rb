module GameNights
  class Inviter
    Result = Struct.new(:success, :invitations, :errors, keyword_init: true) do
      alias_method :success?, :success
    end

    EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

    def self.call(game_night, rows:, host:, deliver: true)
      new(game_night, rows: rows, host: host, deliver: deliver).call
    end

    def initialize(game_night, rows:, host:, deliver: true)
      @game_night = game_night
      @host = host
      @rows = normalize_rows(rows)
      @deliver = deliver
      @errors = []
    end

    def call
      return Result.new(success: true, invitations: [], errors: []) if rows.empty?

      validate
      return Result.new(success: false, invitations: [], errors: errors) if errors.any?

      invitations = []
      GameNight.transaction do
        next_position = (game_night.game_night_invitations.maximum(:position) || 0) + 1

        rows.each_with_index do |row, index|
          email = row[:email_address]
          next if email.blank?
          next if invitee_email_already_in_use?(email, ignore_invitation_id: nil)

          invitation = game_night.game_night_invitations.create!(
            email_address: email,
            display_name: row[:display_name].presence,
            message: row[:message].presence,
            position: next_position + index,
            status: "pending"
          )
          invitations << invitation
        end
      end

      deliver_emails(invitations) if deliver

      Result.new(success: true, invitations: invitations, errors: [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, invitations: [], errors: [ e.message ])
    end

    private

    attr_reader :game_night, :rows, :host, :deliver, :errors

    def normalize_rows(value)
      list =
        case value
        when ActionController::Parameters
          value.to_unsafe_h.values
        when Hash
          value.values
        when Array
          value
        else
          []
        end

      list.filter_map do |row|
        row = row.to_h.transform_keys(&:to_s)
        email = row["email_address"].to_s.strip.downcase
        next if email.blank? && row["display_name"].to_s.strip.blank?

        {
          email_address: email,
          display_name: row["display_name"].to_s.strip,
          message: row["message"].to_s.strip
        }
      end
    end

    def validate
      seen = Set.new
      rows.each_with_index do |row, index|
        row_label = "Invite row #{index + 1}"
        email = row[:email_address]

        if email.blank?
          errors << "#{row_label} needs an email address."
          next
        end

        unless email.match?(EMAIL_FORMAT)
          errors << "#{row_label} email looks invalid."
          next
        end

        if email == host.email_address.to_s.downcase
          errors << "#{row_label} can't invite the host."
          next
        end

        if seen.include?(email)
          errors << "#{row_label} duplicates another invite."
          next
        end
        seen << email

        if invitee_email_already_in_use?(email, ignore_invitation_id: nil)
          errors << "#{row_label}: #{email} is already invited."
        end
      end
    end

    def invitee_email_already_in_use?(email, ignore_invitation_id:)
      scope = game_night.game_night_invitations.where("LOWER(email_address) = ?", email)
      scope = scope.where.not(id: ignore_invitation_id) if ignore_invitation_id
      scope.exists?
    end

    def deliver_emails(invitations)
      invitations.each { |invitation| GameNightMailer.invitation(invitation).deliver_later }
    end
  end
end

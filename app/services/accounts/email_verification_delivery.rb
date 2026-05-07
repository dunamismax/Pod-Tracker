module Accounts
  class EmailVerificationDelivery
    def self.call(user, now: Time.current)
      UserMailer.verify_email(user).deliver_later
      user.update_columns(email_verification_sent_at: now)
    end
  end
end

class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "Ideal Magic <no-reply@ideal-magic.com>") }
  layout "mailer"
end

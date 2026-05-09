class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "Pod Tracker <no-reply@pod-tracker.app>") }
  layout "mailer"
end

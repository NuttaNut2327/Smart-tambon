class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "SMART TAMBON <no-reply@smart-tambon.local>") }
  layout "mailer"
end

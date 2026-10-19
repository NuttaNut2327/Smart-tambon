# Outgoing email (registration OTP and review results). SMTP is used when SMTP_ADDRESS is set; otherwise mail is
# not delivered and development logs the OTP instead (see Registrations::Otp).
ActiveSupport.on_load(:action_mailer) do
  self.default_url_options = { host: ENV.fetch("APP_HOST", "localhost:3000") } if default_url_options.blank?
  next if ENV["SMTP_ADDRESS"].blank?

  self.delivery_method = :smtp
  self.smtp_settings = {
    address: ENV["SMTP_ADDRESS"], port: Integer(ENV.fetch("SMTP_PORT", "587")), user_name: ENV["SMTP_USERNAME"].presence,
    password: ENV["SMTP_PASSWORD"].presence, authentication: (ENV["SMTP_USERNAME"].present? ? :login : nil),
    enable_starttls_auto: ENV.fetch("SMTP_STARTTLS", "true") == "true", open_timeout: 10, read_timeout: 15
  }.compact
end

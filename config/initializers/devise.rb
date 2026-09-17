Devise.setup do |config|
  config.mailer_sender = "noreply@smart-tambon.local"
  require "devise/orm/active_record"
  config.authentication_keys = [:username]
  config.case_insensitive_keys = [:username]
  config.strip_whitespace_keys = [:username]
  config.skip_session_storage = [:http_auth]
  config.stretches = Rails.env.test? ? 1 : 12
  config.reconfirmable = true
  config.expire_all_remember_me_on_sign_out = true
end

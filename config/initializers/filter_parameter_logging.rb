# Prevent credentials and authentication tokens from being written to Rails logs.
Rails.application.config.filter_parameters += [
  :password,
  :password_confirmation,
  :current_password,
  :token,
  :authenticity_token,
  :reset_password_token
]

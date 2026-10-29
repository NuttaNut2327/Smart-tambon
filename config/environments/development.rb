require "active_support/core_ext/integer/time"
Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true
  config.active_storage.service = :local
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
  # Local development uses temporary tunnel hostnames (for example Cloudflare Quick Tunnel) to receive
  # third-party webhooks. Disable Host Authorization here only; production keeps its normal protection.
  config.hosts.clear
  config.active_support.deprecation = :log
end


require_relative "boot"
require "rails/all"
Bundler.require(*Rails.groups)

module SmartCity
  class Application < Rails::Application
    config.load_defaults 7.2
    config.autoload_lib(ignore: %w[assets tasks])
    config.time_zone = "Asia/Bangkok"
    config.active_record.default_timezone = :utc
    config.i18n.default_locale = :th
    config.i18n.available_locales = %i[th en]
  end
end

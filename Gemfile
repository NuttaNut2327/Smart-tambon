source "https://rubygems.org"

ruby "3.3.6"
gem "rails", "~> 7.2.2"
gem "pg", "~> 1.5"
gem "activerecord-postgis-adapter", "~> 10.0"
gem "rgeo-geojson", "~> 2.2"
gem "rgeo-shapefile", "~> 3.0"
gem "mongoid", "~> 9.0"
gem "devise", "~> 4.9"
gem "puma", ">= 6.0"
gem "propshaft"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "roo", "~> 2.10"
gem "roo-xls", "~> 1.2"
gem "pdf-reader", "~> 2.13"
gem "rexml", "~> 3.3"
gem "rubyzip", "~> 2.3"
gem "chunky_png", "~> 1.4"
# Image library: converts uploads to WebP and builds thumbnails (needs libvips from the Dockerfile).
gem "ruby-vips", "~> 2.2", require: false
gem "aws-sdk-s3", require: false
gem "mqtt", "~> 0.6"
gem "bootsnap", require: false
gem "tzinfo-data", platforms: %i[windows jruby]

group :development, :test do
  gem "minitest", "< 6"
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
end

gem "anthropic", "~> 1.78"

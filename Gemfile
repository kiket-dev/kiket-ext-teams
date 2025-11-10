# frozen_string_literal: true

source "https://rubygems.org"

ruby "~> 3.3"

# Web framework
gem "sinatra", "~> 4.0"
gem "puma", "~> 6.4"

# JSON handling
gem "json", "~> 2.7"

# Development and testing
group :development, :test do
  gem "rspec", "~> 3.13"
  gem "rack-test", "~> 2.1"
  gem "webmock", "~> 3.23"
  gem "rubocop", "~> 1.69"
  gem "dotenv", "~> 3.1"
end

# Production
group :production do
  gem "rack", "~> 3.1"
end

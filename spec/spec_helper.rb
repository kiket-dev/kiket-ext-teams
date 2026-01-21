# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'bundler/setup'
Bundler.require(:default, :test)

require 'rspec'
require 'webmock/rspec'

require_relative '../app'

# Mock context for SDK handler testing
def build_context(overrides = {})
  events_logged = []

  default_secrets = {
    'TEAMS_TENANT_ID' => 'test-tenant-id',
    'TEAMS_CLIENT_ID' => 'test-client-id',
    'TEAMS_CLIENT_SECRET' => 'test-client-secret'
  }

  {
    auth: { org_id: 'test-org-123', user_id: 'test-user-456' },
    secret: ->(key) { default_secrets[key] || ENV.fetch(key, nil) },
    endpoints: double('endpoints', log_event: ->(event, data) { events_logged << { event: event, data: data } }),
    events_logged: events_logged
  }.merge(overrides)
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  WebMock.disable_net_connect!(allow_localhost: true)
end

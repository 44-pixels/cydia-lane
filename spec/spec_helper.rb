# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  # Enforced at 100% once implementation specs exist (Task 2+)
  minimum_coverage line: 0
end

require "fastlane"
require "fastlane/plugin/cydia_lane"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.order = :random
  Kernel.srand config.seed
end

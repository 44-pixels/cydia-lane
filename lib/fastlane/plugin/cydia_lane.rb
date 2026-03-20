# frozen_string_literal: true

require "fastlane/plugin/cydia_lane/version"

module Fastlane
  module CydiaLane
    def self.all_classes
      Dir[File.expand_path("cydia_lane/helper/*.rb", __dir__)].each { |f| require f }
      Dir[File.expand_path("cydia_lane/actions/*.rb", __dir__)].each { |f| require f }
    end
  end
end

Fastlane::CydiaLane.all_classes

# frozen_string_literal: true

module Fastlane
  module CydiaLane
    class CydiaClient
      def initialize(base_url:, api_token:)
        @base_url = base_url
        @api_token = api_token
      end
    end
  end
end

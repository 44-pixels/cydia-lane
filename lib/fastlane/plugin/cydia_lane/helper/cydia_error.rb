# frozen_string_literal: true

module Fastlane
  module CydiaLane
    class CydiaError < StandardError
      attr_reader :status_code, :response_body

      def initialize(message, status_code: nil, response_body: nil)
        @status_code = status_code
        @response_body = response_body
        super(message)
      end
    end
  end
end

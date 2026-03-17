# frozen_string_literal: true

module Fastlane
  module Actions
    class FetchCydiaBuildAction < Action
      def self.run(params)
        UI.message("fetch_cydia_build action is not yet implemented")
      end

      def self.description
        "Fetch build information from the Cydia backend"
      end

      def self.authors
        [ "Cydia Team" ]
      end

      def self.available_options
        []
      end

      def self.is_supported?(platform)
        %i[ios android].include?(platform)
      end
    end
  end
end

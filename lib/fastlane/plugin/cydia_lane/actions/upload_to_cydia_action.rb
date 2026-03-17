# frozen_string_literal: true

module Fastlane
  module Actions
    class UploadToCydiaAction < Action
      def self.run(params)
        UI.message("upload_to_cydia action is not yet implemented")
      end

      def self.description
        "Upload a build to the Cydia backend"
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

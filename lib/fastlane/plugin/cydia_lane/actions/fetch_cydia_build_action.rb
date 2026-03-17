# frozen_string_literal: true

module Fastlane
  module Actions
    class FetchCydiaBuildAction < Action
      def self.run(params)
        client = CydiaLane::CydiaClient.new(
          base_url: params[:base_url],
          api_token: params[:api_token]
        )

        platform = params[:platform].to_s.downcase
        UI.user_error!("Platform must be 'ios' or 'android', got '#{platform}'") unless %w[ios android].include?(platform)

        UI.message("Fetching build from Cydia (#{params[:app_slug]}, #{platform}, #{params[:target]}, #{params[:version]})...")

        result = client.fetch_build(
          app_slug: params[:app_slug],
          platform: platform,
          target: params[:target],
          version: params[:version]
        )

        build = result["build"]
        UI.user_error!("Unexpected API response: missing 'build' key") unless build

        Actions.lane_context[SharedValues::CYDIA_BUILD_GUID] = build["guid"]
        Actions.lane_context[SharedValues::CYDIA_BUILD_ARTIFACTS] = build["artefact"]

        UI.success("Successfully fetched build from Cydia! Build GUID: #{build['guid']}")
        result
      rescue CydiaLane::CydiaError => e
        UI.user_error!(e.message)
      end

      def self.description
        "Fetch build information from the Cydia backend"
      end

      def self.authors
        [ "Cydia Team" ]
      end

      def self.return_value
        "Hash containing the build response from Cydia API"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(
            key: :api_token,
            env_name: "CYDIA_API_TOKEN",
            description: "API token for Cydia authentication",
            sensitive: true,
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :app_slug,
            env_name: "CYDIA_APP_SLUG",
            description: "The app slug identifier in Cydia",
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :base_url,
            env_name: "CYDIA_BASE_URL",
            description: "Base URL of the Cydia API",
            type: String,
            default_value: "https://cydia.example.com"
          ),
          FastlaneCore::ConfigItem.new(
            key: :platform,
            description: "Platform (ios or android)",
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :target,
            description: "Build target (e.g., release, debug)",
            type: String
          ),
          FastlaneCore::ConfigItem.new(
            key: :version,
            description: "Build version to fetch",
            type: String
          )
        ]
      end

      def self.output
        [
          [ "CYDIA_BUILD_GUID", "The GUID of the fetched build" ],
          [ "CYDIA_BUILD_ARTIFACTS", "The artifacts hash from the build response" ]
        ]
      end

      def self.is_supported?(platform)
        %i[ios android].include?(platform)
      end
    end
  end
end

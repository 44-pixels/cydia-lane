# frozen_string_literal: true

module Fastlane
  module Actions
    module SharedValues
      CYDIA_BUILD_GUID = :CYDIA_BUILD_GUID
      CYDIA_BUILD_ARTIFACTS = :CYDIA_BUILD_ARTIFACTS
    end

    class UploadToCydiaAction < Action
      def self.run(params)
        client = CydiaLane::CydiaClient.new(
          base_url: params[:base_url],
          api_token: params[:api_token]
        )

        platform = params[:platform] || Actions.lane_context[Actions::SharedValues::PLATFORM_NAME]&.to_s
        UI.user_error!("Could not determine platform. Provide :platform or run within a platform block.") unless platform

        file_path = params[:file] || detect_file(platform)
        UI.user_error!("No build file found. Provide :file or run build_app/gradle first.") unless file_path

        UI.message("Uploading #{file_path} to Cydia (#{params[:app_slug]}, #{platform})...")

        result = client.upload_build(
          app_slug: params[:app_slug],
          platform: platform,
          bundle_path: file_path,
          symbol_path: params[:symbol_file],
          source_map_path: params[:source_map_file]
        )

        build = result["build"]
        UI.user_error!("Unexpected API response: missing 'build' key") unless build

        Actions.lane_context[SharedValues::CYDIA_BUILD_GUID] = build["guid"]
        Actions.lane_context[SharedValues::CYDIA_BUILD_ARTIFACTS] = build["artefact"]

        UI.success("Successfully uploaded build to Cydia! Build GUID: #{build['guid']}")
        result
      rescue CydiaLane::CydiaError => e
        UI.user_error!(e.message)
      end

      def self.detect_file(platform)
        case platform.to_s
        when "ios"
          Actions.lane_context[:IPA_OUTPUT_PATH]
        when "android"
          Actions.lane_context[:GRADLE_APK_OUTPUT_PATH] ||
            Actions.lane_context[:GRADLE_AAB_OUTPUT_PATH]
        end
      end

      def self.description
        "Upload a build to the Cydia backend"
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
            type: String,
            default_value: nil,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :file,
            description: "Path to the build file (IPA/APK/AAB). Auto-detected from lane context if not provided",
            type: String,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :symbol_file,
            description: "Path to the symbol/dSYM file",
            type: String,
            optional: true
          ),
          FastlaneCore::ConfigItem.new(
            key: :source_map_file,
            description: "Path to the React Native source map file",
            type: String,
            optional: true
          )
        ]
      end

      def self.output
        [
          [ "CYDIA_BUILD_GUID", "The GUID of the uploaded build" ],
          [ "CYDIA_BUILD_ARTIFACTS", "The artifacts hash from the build response" ]
        ]
      end

      def self.is_supported?(platform)
        %i[ios android].include?(platform)
      end
    end
  end
end

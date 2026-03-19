# frozen_string_literal: true

require "faraday"
require "json"
require "uri"

module Fastlane
  module CydiaLane
    class CydiaClient
      def initialize(base_url:, api_token:)
        @base_url = base_url.chomp("/")
        @api_token = api_token
      end

      def upload_build(app_slug:, platform:, bundle_path:, symbol_path: nil, source_map_path: nil, backdoors_path: nil)
        payload = {
          platform: platform,
          bundle: Faraday::FilePart.new(bundle_path, "application/octet-stream")
        }
        payload[:symbol] = Faraday::FilePart.new(symbol_path, "application/octet-stream") if symbol_path
        payload[:reactSourceMap] = Faraday::FilePart.new(source_map_path, "application/octet-stream") if source_map_path
        payload[:backdoors] = Faraday::FilePart.new(backdoors_path, "application/octet-stream") if backdoors_path

        response = connection.post(builds_path(app_slug), payload)
        handle_response(response)
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        raise CydiaError, "Network error: #{e.message}"
      end

      def fetch_build(app_slug:, platform:, target:, version:)
        response = connection.get(builds_path(app_slug), platform: platform, target: target, version: version)
        handle_response(response)
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
        raise CydiaError, "Network error: #{e.message}"
      end

      private

      def connection
        @connection ||= Faraday.new(
          url: @base_url,
          request: { open_timeout: 30, read_timeout: 300, write_timeout: 300 }
        ) do |f|
          f.request :multipart
          f.request :url_encoded
          f.headers["Authorization"] = %(Token token="#{@api_token}")
          f.adapter Faraday.default_adapter
        end
      end

      def builds_path(app_slug)
        "/api/public/v1/apps/#{URI.encode_www_form_component(app_slug)}/builds"
      end

      def handle_response(response)
        status = response.status
        body = JSON.parse(response.body.to_s)

        unless (200..299).cover?(status)
          error_message = body["error"] || "HTTP #{status}"
          raise CydiaError.new(
            "Cydia API error (#{status}): #{error_message}",
            status_code: status,
            response_body: body
          )
        end

        body
      rescue JSON::ParserError
        raise CydiaError.new(
          "Invalid JSON response (#{status})",
          status_code: status
        )
      end
    end
  end
end

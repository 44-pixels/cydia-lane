# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "securerandom"

module Fastlane
  module CydiaLane
    class CydiaClient
      def initialize(base_url:, api_token:)
        @base_url = base_url.chomp("/")
        @api_token = api_token
      end

      def upload_build(app_slug:, platform:, bundle_path:, symbol_path: nil, source_map_path: nil)
        uri = build_uri(app_slug)
        boundary = "----FastlanePluginCydiaLane#{SecureRandom.hex(16)}"

        body = build_multipart_body(boundary, platform, bundle_path, symbol_path, source_map_path)

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Authorization"] = auth_header
        request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        request.body = body

        execute_request(uri, request)
      end

      def fetch_build(app_slug:, platform:, target:, version:)
        uri = build_uri(app_slug)
        params = URI.encode_www_form(platform: platform, target: target, version: version)
        uri.query = params

        request = Net::HTTP::Get.new(uri.request_uri)
        request["Authorization"] = auth_header

        execute_request(uri, request)
      end

      private

      def build_uri(app_slug)
        encoded_slug = URI.encode_www_form_component(app_slug)
        URI.parse("#{@base_url}/api/public/v1/apps/#{encoded_slug}/builds")
      end

      def auth_header
        "Token token=\"#{@api_token}\""
      end

      def execute_request(uri, request)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = 30
        http.read_timeout = 300
        http.write_timeout = 300

        response = http.request(request)
        handle_response(response)
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT,
             SocketError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout => e
        raise CydiaError, "Network error: #{e.message}"
      end

      def handle_response(response)
        status = response.code.to_i
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
          "Invalid JSON response (#{response.code})",
          status_code: status
        )
      end

      def build_multipart_body(boundary, platform, bundle_path, symbol_path, source_map_path)
        parts = []

        parts << text_part(boundary, "platform", platform)
        parts << file_part(boundary, "bundle", bundle_path)
        parts << file_part(boundary, "symbol", symbol_path) if symbol_path
        parts << file_part(boundary, "reactSourceMap", source_map_path) if source_map_path

        (parts.join + "--#{boundary}--\r\n").force_encoding(Encoding::BINARY)
      end

      def text_part(boundary, name, value)
        ("--#{boundary}\r\n" \
          "Content-Disposition: form-data; name=\"#{name}\"\r\n" \
          "\r\n" \
          "#{value}\r\n").b
      end

      def file_part(boundary, name, path)
        filename = File.basename(path).gsub(/["\r\n]/, "_")
        content = File.binread(path)

        header = "--#{boundary}\r\n" \
          "Content-Disposition: form-data; name=\"#{name}\"; filename=\"#{filename}\"\r\n" \
          "Content-Type: application/octet-stream\r\n" \
          "\r\n"
        header.force_encoding(Encoding::BINARY) + content + "\r\n".b
      end
    end
  end
end

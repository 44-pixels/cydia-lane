# frozen_string_literal: true

require "spec_helper"
require "net/http"
require "json"
require "tempfile"

RSpec.describe Fastlane::CydiaLane::CydiaClient do
  let(:base_url) { "https://cydia.example.com" }
  let(:api_token) { "test-token-abc123" }
  let(:client) { described_class.new(base_url: base_url, api_token: api_token) }
  let(:app_slug) { "my-app" }

  let(:build_response_body) do
    {
      "build" => {
        "guid" => "build-guid-001",
        "bundleId" => "com.example.app",
        "platform" => "ios",
        "version" => "1.2.3",
        "artefact" => {
          "guid" => "artefact-guid-001",
          "target" => "release",
          "buildFileURL" => "https://cydia.example.com/builds/build-guid-001/app.ipa",
          "symbolURL" => "https://cydia.example.com/builds/build-guid-001/app.dSYM.zip",
          "reactSourceMapURL" => nil
        }
      }
    }
  end

  def stub_upload_request(status:, body:)
    http_response = instance_double(Net::HTTPResponse, code: status.to_s, body: JSON.generate(body))
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:request).and_return(http_response)
    [ http, http_response ]
  end

  def stub_get_request(status:, body:)
    http_response = instance_double(Net::HTTPResponse, code: status.to_s, body: JSON.generate(body))
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:request).and_return(http_response)
    [ http, http_response ]
  end

  describe "#upload_build" do
    let(:bundle_file) { Tempfile.new([ "app", ".ipa" ]) }

    before do
      bundle_file.write("fake-ipa-content")
      bundle_file.rewind
    end

    after do
      bundle_file.close
      bundle_file.unlink
    end

    context "with a successful iOS upload" do
      it "returns the parsed build response" do
        stub_upload_request(status: 200, body: build_response_body)

        result = client.upload_build(
          app_slug: app_slug,
          platform: "ios",
          bundle_path: bundle_file.path
        )

        expect(result).to eq(build_response_body)
        expect(result.dig("build", "guid")).to eq("build-guid-001")
        expect(result.dig("build", "platform")).to eq("ios")
      end
    end

    context "with a successful Android upload" do
      let(:android_response) do
        body = build_response_body.dup
        body["build"] = body["build"].merge("platform" => "android")
        body
      end
      let(:bundle_file) { Tempfile.new([ "app", ".apk" ]) }

      it "returns the parsed build response" do
        stub_upload_request(status: 200, body: android_response)

        result = client.upload_build(
          app_slug: app_slug,
          platform: "android",
          bundle_path: bundle_file.path
        )

        expect(result.dig("build", "platform")).to eq("android")
      end
    end

    context "with optional symbol and source map files" do
      let(:symbol_file) { Tempfile.new([ "app", ".dSYM.zip" ]) }
      let(:source_map_file) { Tempfile.new([ "app", ".map" ]) }

      before do
        symbol_file.write("fake-dsym-content")
        symbol_file.rewind
        source_map_file.write("fake-source-map")
        source_map_file.rewind
      end

      after do
        symbol_file.close
        symbol_file.unlink
        source_map_file.close
        source_map_file.unlink
      end

      it "includes symbol and source map in the upload" do
        http, = stub_upload_request(status: 200, body: build_response_body)

        expect(http).to receive(:request) do |request|
          body = request.body
          expect(body).to include("symbol")
          expect(body).to include("reactSourceMap")
          instance_double(Net::HTTPResponse, code: "200", body: JSON.generate(build_response_body))
        end

        client.upload_build(
          app_slug: app_slug,
          platform: "ios",
          bundle_path: bundle_file.path,
          symbol_path: symbol_file.path,
          source_map_path: source_map_file.path
        )
      end
    end

    context "when the server returns 401 (auth failure)" do
      it "raises CydiaError with status code" do
        stub_upload_request(status: 401, body: { "error" => "unauthorized" })

        expect {
          client.upload_build(app_slug: app_slug, platform: "ios", bundle_path: bundle_file.path)
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.message).to include("401")
          expect(error.status_code).to eq(401)
        }
      end
    end

    context "when the server returns 404 (app not found)" do
      it "raises CydiaError with status code" do
        stub_upload_request(status: 404, body: { "error" => "not found" })

        expect {
          client.upload_build(app_slug: app_slug, platform: "ios", bundle_path: bundle_file.path)
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.message).to include("404")
          expect(error.status_code).to eq(404)
        }
      end
    end

    context "when the server returns 422 (validation error)" do
      it "raises CydiaError with the error message" do
        stub_upload_request(status: 422, body: { "error" => "platform is invalid" })

        expect {
          client.upload_build(app_slug: app_slug, platform: "ios", bundle_path: bundle_file.path)
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.message).to include("platform is invalid")
          expect(error.status_code).to eq(422)
        }
      end
    end

    context "when a network error occurs" do
      it "raises CydiaError wrapping the original error" do
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:request).and_raise(Errno::ECONNREFUSED, "Connection refused")

        expect {
          client.upload_build(app_slug: app_slug, platform: "ios", bundle_path: bundle_file.path)
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.message).to include("Connection refused")
        }
      end
    end

    context "when the server returns invalid JSON" do
      it "raises CydiaError with an invalid JSON message" do
        http_response = instance_double(Net::HTTPResponse, code: "200", body: "not valid json{{{")
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:request).and_return(http_response)

        expect {
          client.upload_build(app_slug: app_slug, platform: "ios", bundle_path: bundle_file.path)
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.message).to include("Invalid JSON response")
        }
      end
    end

    context "multipart form body" do
      it "includes correct boundary, content-disposition, and file content" do
        http, = stub_upload_request(status: 200, body: build_response_body)

        expect(http).to receive(:request) do |request|
          content_type = request["Content-Type"]
          expect(content_type).to match(%r{multipart/form-data; boundary=})

          boundary = content_type.match(/boundary=(.+)/)[1]
          body = request.body

          expect(body).to include("--#{boundary}")
          expect(body).to include('Content-Disposition: form-data; name="platform"')
          expect(body).to include("ios")
          expect(body).to include('Content-Disposition: form-data; name="bundle"')
          expect(body).to include("fake-ipa-content")
          expect(body).to include("--#{boundary}--")

          instance_double(Net::HTTPResponse, code: "200", body: JSON.generate(build_response_body))
        end

        client.upload_build(
          app_slug: app_slug,
          platform: "ios",
          bundle_path: bundle_file.path
        )
      end
    end

    it "sends the correct authorization header" do
      http, = stub_upload_request(status: 200, body: build_response_body)

      expect(http).to receive(:request) do |request|
        expect(request["Authorization"]).to eq('Token token="test-token-abc123"')
        instance_double(Net::HTTPResponse, code: "200", body: JSON.generate(build_response_body))
      end

      client.upload_build(app_slug: app_slug, platform: "ios", bundle_path: bundle_file.path)
    end

    it "posts to the correct endpoint path" do
      http, = stub_upload_request(status: 200, body: build_response_body)

      expect(http).to receive(:request) do |request|
        expect(request.path).to eq("/api/public/v1/apps/my-app/builds")
        instance_double(Net::HTTPResponse, code: "200", body: JSON.generate(build_response_body))
      end

      client.upload_build(app_slug: app_slug, platform: "ios", bundle_path: bundle_file.path)
    end

    it "uses SSL for https URLs" do
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:new).with("cydia.example.com", 443).and_return(http)
      expect(http).to receive(:use_ssl=).with(true)
      allow(http).to receive(:request).and_return(
        instance_double(Net::HTTPResponse, code: "200", body: JSON.generate(build_response_body))
      )

      client.upload_build(app_slug: app_slug, platform: "ios", bundle_path: bundle_file.path)
    end
  end

  describe "#fetch_build" do
    context "with a successful fetch" do
      it "returns the parsed build response" do
        stub_get_request(status: 200, body: build_response_body)

        result = client.fetch_build(
          app_slug: app_slug,
          platform: "ios",
          target: "release",
          version: "1.2.3"
        )

        expect(result).to eq(build_response_body)
        expect(result.dig("build", "guid")).to eq("build-guid-001")
      end
    end

    it "sends query parameters in the request" do
      http, = stub_get_request(status: 200, body: build_response_body)

      expect(http).to receive(:request) do |request|
        uri = URI.parse("https://cydia.example.com#{request.path}")
        params = URI.decode_www_form(uri.query).to_h
        expect(params["platform"]).to eq("ios")
        expect(params["target"]).to eq("release")
        expect(params["version"]).to eq("1.2.3")
        instance_double(Net::HTTPResponse, code: "200", body: JSON.generate(build_response_body))
      end

      client.fetch_build(app_slug: app_slug, platform: "ios", target: "release", version: "1.2.3")
    end

    it "sends the correct authorization header" do
      http, = stub_get_request(status: 200, body: build_response_body)

      expect(http).to receive(:request) do |request|
        expect(request["Authorization"]).to eq('Token token="test-token-abc123"')
        instance_double(Net::HTTPResponse, code: "200", body: JSON.generate(build_response_body))
      end

      client.fetch_build(app_slug: app_slug, platform: "ios", target: "release", version: "1.2.3")
    end

    it "uses GET to the correct endpoint" do
      http, = stub_get_request(status: 200, body: build_response_body)

      expect(http).to receive(:request) do |request|
        expect(request).to be_a(Net::HTTP::Get)
        expect(request.path).to start_with("/api/public/v1/apps/my-app/builds")
        instance_double(Net::HTTPResponse, code: "200", body: JSON.generate(build_response_body))
      end

      client.fetch_build(app_slug: app_slug, platform: "ios", target: "release", version: "1.2.3")
    end

    context "when the server returns 401" do
      it "raises CydiaError" do
        stub_get_request(status: 401, body: { "error" => "unauthorized" })

        expect {
          client.fetch_build(app_slug: app_slug, platform: "ios", target: "release", version: "1.2.3")
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.status_code).to eq(401)
        }
      end
    end

    context "when the server returns 404" do
      it "raises CydiaError" do
        stub_get_request(status: 404, body: { "error" => "not found" })

        expect {
          client.fetch_build(app_slug: app_slug, platform: "ios", target: "release", version: "1.2.3")
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.status_code).to eq(404)
        }
      end
    end

    context "when the server returns 422" do
      it "raises CydiaError with the error message" do
        stub_get_request(status: 422, body: { "error" => "version is required" })

        expect {
          client.fetch_build(app_slug: app_slug, platform: "ios", target: "release", version: "1.2.3")
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.message).to include("version is required")
          expect(error.status_code).to eq(422)
        }
      end
    end

    context "when a network error occurs" do
      it "raises CydiaError" do
        http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:request).and_raise(SocketError, "getaddrinfo: Name or service not known")

        expect {
          client.fetch_build(app_slug: app_slug, platform: "ios", target: "release", version: "1.2.3")
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.message).to include("Name or service not known")
        }
      end
    end
  end
end

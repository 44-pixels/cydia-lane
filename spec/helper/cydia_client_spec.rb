# frozen_string_literal: true

require "spec_helper"
require "json"
require "tempfile"

RSpec.describe Fastlane::CydiaLane::CydiaClient do
  let(:base_url) { "https://cydia.example.com" }
  let(:api_token) { "test-token-abc123" }
  let(:client) { described_class.new(base_url: base_url, api_token: api_token) }
  let(:app_slug) { "my-app" }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }

  let(:build_response_body) do
    {
      "build" => {
        "guid" => "build-guid-001",
        "bundleId" => "com.example.app",
        "platform" => "ios",
        "target" => "release",
        "version" => "1.2.3",
        "artifacts" => [
          {
            "guid" => "artifact-guid-001",
            "slug" => "bundle",
            "fileUrl" => "https://cydia.example.com/builds/build-guid-001/app.ipa"
          },
          {
            "guid" => "artifact-guid-002",
            "slug" => "symbol",
            "fileUrl" => "https://cydia.example.com/builds/build-guid-001/app.dSYM.zip"
          }
        ]
      }
    }
  end

  def json_response(status, body)
    [ status, { "Content-Type" => "application/json" }, JSON.generate(body) ]
  end

  def use_test_adapter
    test_stubs = stubs
    test_conn = Faraday.new(url: base_url) do |f|
      f.request :multipart
      f.request :url_encoded
      f.headers["Authorization"] = %(Token token="#{api_token}")
      f.adapter :test, test_stubs
    end
    allow(client).to receive(:connection).and_return(test_conn)
  end

  describe "connection setup" do
    it "configures the authorization header" do
      conn = client.send(:connection)
      expect(conn.headers["Authorization"]).to eq('Token token="test-token-abc123"')
    end

    it "uses the correct base URL" do
      conn = client.send(:connection)
      expect(conn.url_prefix.to_s).to eq("https://cydia.example.com/")
    end
  end

  describe "#upload_build" do
    let(:bundle_file) { Tempfile.new([ "app", ".ipa" ]) }

    before do
      bundle_file.write("fake-ipa-content")
      bundle_file.rewind
      use_test_adapter
    end

    after do
      bundle_file.close
      bundle_file.unlink
    end

    context "with a successful iOS upload" do
      it "returns the parsed build response" do
        stubs.post("/api/public/v1/apps/my-app/builds") do
          json_response(200, build_response_body)
        end

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
        stubs.post("/api/public/v1/apps/my-app/builds") do
          json_response(200, android_response)
        end

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
        stubs.post("/api/public/v1/apps/my-app/builds") do |env|
          body = env.body.respond_to?(:read) ? env.body.read : env.body.to_s
          expect(body).to include("symbol")
          expect(body).to include("reactSourceMap")
          json_response(200, build_response_body)
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

    context "with optional backdoors file" do
      let(:backdoors_file) { Tempfile.new([ "backdoors", ".json" ]) }

      before do
        backdoors_file.write('{"backdoors": []}')
        backdoors_file.rewind
      end

      after do
        backdoors_file.close
        backdoors_file.unlink
      end

      it "includes backdoors in the upload" do
        stubs.post("/api/public/v1/apps/my-app/builds") do |env|
          body = env.body.respond_to?(:read) ? env.body.read : env.body.to_s
          expect(body).to include("backdoors")
          json_response(200, build_response_body)
        end

        client.upload_build(
          app_slug: app_slug,
          platform: "ios",
          bundle_path: bundle_file.path,
          backdoors_path: backdoors_file.path
        )
      end
    end

    context "when the server returns 401 (auth failure)" do
      it "raises CydiaError with status code and response body" do
        error_body = { "error" => "unauthorized" }
        stubs.post("/api/public/v1/apps/my-app/builds") do
          json_response(401, error_body)
        end

        expect {
          client.upload_build(app_slug: app_slug, platform: "ios", bundle_path: bundle_file.path)
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.message).to include("401")
          expect(error.status_code).to eq(401)
          expect(error.response_body).to eq(error_body)
        }
      end
    end

    context "when the server returns 404 (app not found)" do
      it "raises CydiaError with status code" do
        stubs.post("/api/public/v1/apps/my-app/builds") do
          json_response(404, { "error" => "not found" })
        end

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
        stubs.post("/api/public/v1/apps/my-app/builds") do
          json_response(422, { "error" => "platform is invalid" })
        end

        expect {
          client.upload_build(app_slug: app_slug, platform: "ios", bundle_path: bundle_file.path)
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.message).to include("platform is invalid")
          expect(error.status_code).to eq(422)
        }
      end
    end

    context "when the server returns an error without 'error' key" do
      it "falls back to HTTP status in the error message" do
        stubs.post("/api/public/v1/apps/my-app/builds") do
          json_response(500, { "message" => "internal server error" })
        end

        expect {
          client.upload_build(app_slug: app_slug, platform: "ios", bundle_path: bundle_file.path)
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.message).to include("HTTP 500")
          expect(error.status_code).to eq(500)
        }
      end
    end

    context "when a network error occurs" do
      it "raises CydiaError wrapping the original error" do
        stubs.post("/api/public/v1/apps/my-app/builds") do
          raise Faraday::ConnectionFailed, "Connection refused"
        end

        expect {
          client.upload_build(app_slug: app_slug, platform: "ios", bundle_path: bundle_file.path)
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.message).to include("Connection refused")
        }
      end

      it "handles timeout errors" do
        stubs.post("/api/public/v1/apps/my-app/builds") do
          raise Faraday::TimeoutError, "Net::ReadTimeout"
        end

        expect {
          client.upload_build(app_slug: app_slug, platform: "ios", bundle_path: bundle_file.path)
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.message).to include("Network error")
        }
      end
    end

    context "when the server returns invalid JSON" do
      it "raises CydiaError with an invalid JSON message" do
        stubs.post("/api/public/v1/apps/my-app/builds") do
          [ 200, { "Content-Type" => "text/plain" }, "not valid json{{{" ]
        end

        expect {
          client.upload_build(app_slug: app_slug, platform: "ios", bundle_path: bundle_file.path)
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.message).to include("Invalid JSON response")
        }
      end
    end

    it "posts to the correct endpoint path" do
      stubs.post("/api/public/v1/apps/my-app/builds") do
        json_response(200, build_response_body)
      end

      client.upload_build(app_slug: app_slug, platform: "ios", bundle_path: bundle_file.path)
      stubs.verify_stubbed_calls
    end
  end

  describe "#fetch_build" do
    before { use_test_adapter }

    context "with a successful fetch" do
      it "returns the parsed build response" do
        stubs.get("/api/public/v1/apps/my-app/builds") do
          json_response(200, build_response_body)
        end

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
      stubs.get("/api/public/v1/apps/my-app/builds") do |env|
        params = URI.decode_www_form(env.url.query).to_h
        expect(params["platform"]).to eq("ios")
        expect(params["target"]).to eq("release")
        expect(params["version"]).to eq("1.2.3")
        json_response(200, build_response_body)
      end

      client.fetch_build(app_slug: app_slug, platform: "ios", target: "release", version: "1.2.3")
    end

    context "when the server returns 401" do
      it "raises CydiaError" do
        stubs.get("/api/public/v1/apps/my-app/builds") do
          json_response(401, { "error" => "unauthorized" })
        end

        expect {
          client.fetch_build(app_slug: app_slug, platform: "ios", target: "release", version: "1.2.3")
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.status_code).to eq(401)
        }
      end
    end

    context "when the server returns 404" do
      it "raises CydiaError" do
        stubs.get("/api/public/v1/apps/my-app/builds") do
          json_response(404, { "error" => "not found" })
        end

        expect {
          client.fetch_build(app_slug: app_slug, platform: "ios", target: "release", version: "1.2.3")
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.status_code).to eq(404)
        }
      end
    end

    context "when the server returns 422" do
      it "raises CydiaError with the error message" do
        stubs.get("/api/public/v1/apps/my-app/builds") do
          json_response(422, { "error" => "version is required" })
        end

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
        stubs.get("/api/public/v1/apps/my-app/builds") do
          raise Faraday::ConnectionFailed, "getaddrinfo: Name or service not known"
        end

        expect {
          client.fetch_build(app_slug: app_slug, platform: "ios", target: "release", version: "1.2.3")
        }.to raise_error(Fastlane::CydiaLane::CydiaError) { |error|
          expect(error.message).to include("Name or service not known")
        }
      end
    end
  end
end

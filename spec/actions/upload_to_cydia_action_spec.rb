# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Fastlane::Actions::UploadToCydiaAction do
  let(:api_token) { "test-token-abc123" }
  let(:app_slug) { "my-app" }
  let(:base_url) { "https://cydia.example.com" }
  let(:ipa_file) { Tempfile.new([ "app", ".ipa" ]) }

  let(:build_response) do
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

  before do
    ipa_file.write("fake-ipa-content")
    ipa_file.rewind
    # Reset shared values and lane context keys used for auto-detection
    Fastlane::Actions.lane_context.delete(Fastlane::Actions::SharedValues::CYDIA_BUILD_GUID)
    Fastlane::Actions.lane_context.delete(Fastlane::Actions::SharedValues::CYDIA_BUILD_ARTIFACTS)
    Fastlane::Actions.lane_context.delete(:IPA_OUTPUT_PATH)
    Fastlane::Actions.lane_context.delete(:GRADLE_APK_OUTPUT_PATH)
    Fastlane::Actions.lane_context.delete(:GRADLE_AAB_OUTPUT_PATH)
    Fastlane::Actions.lane_context.delete(Fastlane::Actions::SharedValues::PLATFORM_NAME)
  end

  after do
    ipa_file.close
    ipa_file.unlink
  end

  def stub_client_upload(response)
    client = instance_double(Fastlane::CydiaLane::CydiaClient)
    allow(Fastlane::CydiaLane::CydiaClient).to receive(:new).and_return(client)
    allow(client).to receive(:upload_build).and_return(response)
    client
  end

  def run_action(params)
    Fastlane::FastFile.new.parse("lane :test do
      upload_to_cydia(#{params})
    end").runner.execute(:test)
  end

  describe "successful iOS upload using auto-detected IPA from lane context" do
    it "uploads the IPA from lane context :IPA_OUTPUT_PATH" do
      Fastlane::Actions.lane_context[:IPA_OUTPUT_PATH] = ipa_file.path

      client = stub_client_upload(build_response)

      expect(client).to receive(:upload_build).with(
        app_slug: app_slug,
        platform: "ios",
        bundle_path: ipa_file.path,
        symbol_path: nil,
        source_map_path: nil,
        backdoors_path: nil
      ).and_return(build_response)

      run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios'")

      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::CYDIA_BUILD_GUID]).to eq("build-guid-001")
      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::CYDIA_BUILD_ARTIFACTS]).to eq(build_response.dig("build", "artifacts"))
    end
  end

  describe "successful Android upload" do
    it "uploads an APK file" do
      client = stub_client_upload(build_response)

      expect(client).to receive(:upload_build).with(
        app_slug: app_slug,
        platform: "android",
        bundle_path: ipa_file.path,
        symbol_path: nil,
        source_map_path: nil,
        backdoors_path: nil
      ).and_return(build_response)

      run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'android', file: '#{ipa_file.path}'")
    end
  end

  describe "explicit file path parameter overrides auto-detection" do
    it "uses the explicit file parameter instead of lane context" do
      # Set lane context to a different file
      Fastlane::Actions.lane_context[:IPA_OUTPUT_PATH] = "/some/other/path.ipa"

      client = stub_client_upload(build_response)

      expect(client).to receive(:upload_build).with(
        app_slug: app_slug,
        platform: "ios",
        bundle_path: ipa_file.path,
        symbol_path: nil,
        source_map_path: nil,
        backdoors_path: nil
      ).and_return(build_response)

      run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', file: '#{ipa_file.path}'")
    end
  end

  describe "missing api_token or app_slug raises error" do
    it "raises an error when api_token is missing" do
      expect {
        run_action("app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', file: '#{ipa_file.path}'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError)
    end

    it "raises an error when app_slug is missing" do
      expect {
        run_action("api_token: '#{api_token}', base_url: '#{base_url}', platform: 'ios', file: '#{ipa_file.path}'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError)
    end
  end

  describe "platform auto-detection from lane context" do
    it "auto-detects platform from PLATFORM_NAME when :platform is not provided" do
      Fastlane::Actions.lane_context[:IPA_OUTPUT_PATH] = ipa_file.path

      client = stub_client_upload(build_response)

      expect(client).to receive(:upload_build).with(
        app_slug: app_slug,
        platform: "ios",
        bundle_path: ipa_file.path,
        symbol_path: nil,
        source_map_path: nil,
        backdoors_path: nil
      ).and_return(build_response)

      Fastlane::FastFile.new.parse("platform :ios do
        lane :test do
          upload_to_cydia(api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}')
        end
      end").runner.execute(:test, :ios)
    end

    it "raises an error when platform cannot be determined" do
      stub_client_upload(build_response)

      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', file: '#{ipa_file.path}'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError, /Could not determine platform/)
    end
  end

  describe "missing build key in API response" do
    it "raises an error when response has no 'build' key" do
      client = instance_double(Fastlane::CydiaLane::CydiaClient)
      allow(Fastlane::CydiaLane::CydiaClient).to receive(:new).and_return(client)
      allow(client).to receive(:upload_build).and_return({ "status" => "ok" })

      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', file: '#{ipa_file.path}'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError, /missing 'build' key/)
    end
  end

  describe "missing file raises error" do
    it "raises an error when no file is available from lane context or explicit path" do
      stub_client_upload(build_response)

      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError, /No build file found/)
    end

    it "raises an error when the specified file does not exist on disk" do
      stub_client_upload(build_response)

      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', file: '/nonexistent/path/app.ipa'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError, /Build file not found/)
    end
  end

  describe "invalid optional file paths raise errors" do
    it "raises an error when symbol_file does not exist" do
      stub_client_upload(build_response)

      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', file: '#{ipa_file.path}', symbol_file: '/nonexistent/path/app.dSYM.zip'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError, /Symbol file not found/)
    end

    it "raises an error when source_map_file does not exist" do
      stub_client_upload(build_response)

      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', file: '#{ipa_file.path}', source_map_file: '/nonexistent/path/source.map'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError, /Source map file not found/)
    end

    it "raises an error when backdoors_file does not exist" do
      stub_client_upload(build_response)

      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', file: '#{ipa_file.path}', backdoors_file: '/nonexistent/path/backdoors.json'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError, /Backdoors file not found/)
    end
  end

  describe "directory paths are rejected" do
    it "raises an error when file is a directory" do
      stub_client_upload(build_response)

      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', file: '#{Dir.tmpdir}'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError, /Build file is not a file/)
    end

    it "raises an error when symbol_file is a directory" do
      stub_client_upload(build_response)

      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', file: '#{ipa_file.path}', symbol_file: '#{Dir.tmpdir}'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError, /Symbol file is not a file/)
    end

    it "raises an error when source_map_file is a directory" do
      stub_client_upload(build_response)

      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', file: '#{ipa_file.path}', source_map_file: '#{Dir.tmpdir}'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError, /Source map file is not a file/)
    end

    it "raises an error when backdoors_file is a directory" do
      stub_client_upload(build_response)

      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', file: '#{ipa_file.path}', backdoors_file: '#{Dir.tmpdir}'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError, /Backdoors file is not a file/)
    end
  end

  describe "CydiaError from client is surfaced with UI.user_error!" do
    it "surfaces CydiaError as a fastlane user error" do
      client = instance_double(Fastlane::CydiaLane::CydiaClient)
      allow(Fastlane::CydiaLane::CydiaClient).to receive(:new).and_return(client)
      allow(client).to receive(:upload_build).and_raise(
        Fastlane::CydiaLane::CydiaError.new("Cydia API error (401): unauthorized", status_code: 401)
      )

      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', file: '#{ipa_file.path}'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError, /Cydia API error/)
    end
  end

  describe "shared values CYDIA_BUILD_GUID is set after upload" do
    it "sets CYDIA_BUILD_GUID and CYDIA_BUILD_ARTIFACTS in lane context" do
      stub_client_upload(build_response)

      run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', file: '#{ipa_file.path}'")

      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::CYDIA_BUILD_GUID]).to eq("build-guid-001")
      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::CYDIA_BUILD_ARTIFACTS]).to eq(build_response.dig("build", "artifacts"))
    end
  end

  describe "action metadata" do
    it "has a description" do
      expect(described_class.description).to be_a(String)
      expect(described_class.description.length).to be > 0
    end

    it "has available_options" do
      expect(described_class.available_options).to be_an(Array)
      expect(described_class.available_options.length).to be >= 5
    end

    it "has output definitions" do
      expect(described_class.output).to be_an(Array)
      expect(described_class.output.length).to be >= 2
    end

    it "has return_value" do
      expect(described_class.return_value).to be_a(String)
    end

    it "has authors" do
      expect(described_class.authors).to be_an(Array)
    end

    it "supports ios and android" do
      expect(described_class.is_supported?(:ios)).to be true
      expect(described_class.is_supported?(:android)).to be true
      expect(described_class.is_supported?(:mac)).to be false
    end
  end

  describe ".detect_file" do
    it "returns GRADLE_APK_OUTPUT_PATH for android platform" do
      Fastlane::Actions.lane_context[:GRADLE_APK_OUTPUT_PATH] = "/path/to/app.apk"
      expect(described_class.detect_file("android")).to eq("/path/to/app.apk")
    end

    it "falls back to GRADLE_AAB_OUTPUT_PATH for android when no APK" do
      Fastlane::Actions.lane_context[:GRADLE_AAB_OUTPUT_PATH] = "/path/to/app.aab"
      expect(described_class.detect_file("android")).to eq("/path/to/app.aab")
    end
  end
end

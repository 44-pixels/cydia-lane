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
        source_map_path: nil
      ).and_return(build_response)

      run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios'")

      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::CYDIA_BUILD_GUID]).to eq("build-guid-001")
      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::CYDIA_BUILD_ARTIFACTS]).to eq(build_response.dig("build", "artefact"))
    end
  end

  describe "successful Android upload using auto-detected artifact from lane context" do
    let(:apk_file) { Tempfile.new([ "app", ".apk" ]) }

    before do
      apk_file.write("fake-apk-content")
      apk_file.rewind
    end

    after do
      apk_file.close
      apk_file.unlink
    end

    it "uploads the APK from lane context :GRADLE_APK_OUTPUT_PATH" do
      Fastlane::Actions.lane_context[:GRADLE_APK_OUTPUT_PATH] = apk_file.path

      android_response = build_response.dup
      android_response["build"] = android_response["build"].merge("platform" => "android")

      client = stub_client_upload(android_response)

      expect(client).to receive(:upload_build).with(
        app_slug: app_slug,
        platform: "android",
        bundle_path: apk_file.path,
        symbol_path: nil,
        source_map_path: nil
      ).and_return(android_response)

      run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'android'")

      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::CYDIA_BUILD_GUID]).to eq("build-guid-001")
    end

    it "falls back to GRADLE_AAB_OUTPUT_PATH when no APK is available" do
      aab_file = Tempfile.new([ "app", ".aab" ])
      aab_file.write("fake-aab-content")
      aab_file.rewind

      Fastlane::Actions.lane_context[:GRADLE_AAB_OUTPUT_PATH] = aab_file.path

      android_response = build_response.dup
      android_response["build"] = android_response["build"].merge("platform" => "android")

      client = stub_client_upload(android_response)

      expect(client).to receive(:upload_build).with(
        app_slug: app_slug,
        platform: "android",
        bundle_path: aab_file.path,
        symbol_path: nil,
        source_map_path: nil
      ).and_return(android_response)

      run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'android'")

      aab_file.close
      aab_file.unlink
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
        source_map_path: nil
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
      Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::PLATFORM_NAME] = :ios
      Fastlane::Actions.lane_context[:IPA_OUTPUT_PATH] = ipa_file.path

      client = stub_client_upload(build_response)

      expect(client).to receive(:upload_build).with(
        app_slug: app_slug,
        platform: "ios",
        bundle_path: ipa_file.path,
        symbol_path: nil,
        source_map_path: nil
      ).and_return(build_response)

      run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}'")
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
      expect(Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::CYDIA_BUILD_ARTIFACTS]).to eq(build_response.dig("build", "artefact"))
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
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Fastlane::Actions::FetchCydiaBuildAction do
  let(:api_token) { "test-token-abc123" }
  let(:app_slug) { "my-app" }
  let(:base_url) { "https://cydia.example.com" }

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
    Fastlane::Actions.lane_context.delete(Fastlane::Actions::SharedValues::CYDIA_BUILD_GUID)
    Fastlane::Actions.lane_context.delete(Fastlane::Actions::SharedValues::CYDIA_BUILD_ARTIFACTS)
  end

  def stub_client_fetch(response)
    client = instance_double(Fastlane::CydiaLane::CydiaClient)
    allow(Fastlane::CydiaLane::CydiaClient).to receive(:new).and_return(client)
    allow(client).to receive(:fetch_build).and_return(response)
    client
  end

  def run_action(params)
    Fastlane::FastFile.new.parse("lane :test do
      fetch_cydia_build(#{params})
    end").runner.execute(:test)
  end

  describe "successful build fetch" do
    it "returns the build hash" do
      client = stub_client_fetch(build_response)

      expect(client).to receive(:fetch_build).with(
        app_slug: app_slug,
        platform: "ios",
        target: "release",
        version: "1.2.3"
      ).and_return(build_response)

      result = run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', target: 'release', version: '1.2.3'")

      expect(result).to eq(build_response)
    end
  end

  describe "build not found (404) raises UI.user_error!" do
    it "surfaces CydiaError as a fastlane user error" do
      client = instance_double(Fastlane::CydiaLane::CydiaClient)
      allow(Fastlane::CydiaLane::CydiaClient).to receive(:new).and_return(client)
      allow(client).to receive(:fetch_build).and_raise(
        Fastlane::CydiaLane::CydiaError.new("Cydia API error (404): not found", status_code: 404)
      )

      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', target: 'release', version: '9.9.9'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError, /Cydia API error.*404/)
    end
  end

  describe "missing build key in API response" do
    it "raises an error when response has no 'build' key" do
      client = instance_double(Fastlane::CydiaLane::CydiaClient)
      allow(Fastlane::CydiaLane::CydiaClient).to receive(:new).and_return(client)
      allow(client).to receive(:fetch_build).and_return({ "status" => "ok" })

      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', target: 'release', version: '1.2.3'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError, /missing 'build' key/)
    end
  end

  describe "missing required parameters raises error" do
    it "raises an error when api_token is missing" do
      expect {
        run_action("app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', target: 'release', version: '1.2.3'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError)
    end

    it "raises an error when app_slug is missing" do
      expect {
        run_action("api_token: '#{api_token}', base_url: '#{base_url}', platform: 'ios', target: 'release', version: '1.2.3'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError)
    end

    it "raises an error when platform is missing" do
      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', target: 'release', version: '1.2.3'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError)
    end

    it "raises an error when target is missing" do
      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', version: '1.2.3'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError)
    end

    it "raises an error when version is missing" do
      expect {
        run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', target: 'release'")
      }.to raise_error(FastlaneCore::Interface::FastlaneError)
    end
  end

  describe "shared values set on success" do
    it "sets CYDIA_BUILD_GUID and CYDIA_BUILD_ARTIFACTS in lane context" do
      stub_client_fetch(build_response)

      run_action("api_token: '#{api_token}', app_slug: '#{app_slug}', base_url: '#{base_url}', platform: 'ios', target: 'release', version: '1.2.3'")

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

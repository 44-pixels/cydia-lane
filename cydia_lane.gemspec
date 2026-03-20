# frozen_string_literal: true

require_relative "lib/fastlane/plugin/cydia_lane/version"

Gem::Specification.new do |spec|
  spec.name          = "fastlane-plugin-cydia_lane"
  spec.version       = Fastlane::CydiaLane::VERSION
  spec.authors       = [ "Cydia Team" ]
  spec.email         = [ "team@cydia.dev" ]

  spec.summary       = "Fastlane plugin for uploading builds to the Cydia backend"
  spec.description   = "Provides the upload_to_cydia action for the Cydia build distribution platform."
  spec.homepage      = "https://github.com/cydia/fastlane-plugin-cydia_lane"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.3"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*", "LICENSE.txt"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "fastlane", ">= 2.225.0"
  spec.add_dependency "faraday", "~> 1.0"
end

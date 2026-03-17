# Fastlane Plugin: cydia_lane

## Overview

Create a Ruby gem (fastlane-plugin-cydia_lane) that provides two fastlane actions -- upload_to_cydia and fetch_cydia_build -- for uploading iOS/Android builds to the Cydia backend and querying build info. The gem follows fastlane plugin conventions with 2026 Ruby gem best practices: 100% RSpec coverage, bin/console with reload, rubocop omakase linting, and GitHub Actions CI with Ruby 3.x/4.x matrix.

## Context

- Files involved:
  - /mnt/Karen/fastlane/Fastfile - Example integration (iOS deploy calls upload_to_testflight, Android calls upload_to_play_store)
  - /mnt/Voices/fastlane/Fastfile - Same pattern with upload control parameter
  - /mnt/cydia/app/controllers/api/public/v1/apps/builds_controller.rb - Upload endpoint
  - /mnt/cydia/swagger/v1/swagger.yaml - API spec
- Related patterns:
  - Karen/Voices call upload actions after build_app (iOS) or gradle (Android)
  - upload_to_cydia follows same pattern, called alongside existing upload actions
  - Cydia API: token auth (Authorization: Token token="..."), multipart form upload, returns build guid and artifact URLs
- Dependencies:
  - fastlane (runtime, >= 2.225.0)
  - No extra HTTP gems -- uses Net::HTTP from stdlib for multipart uploads
  - rspec, simplecov, rubocop, rubocop-omakase (development)

## Development Approach

- **Testing approach**: TDD (write specs first, then implementation)
- Complete each task fully before moving to the next
- **CRITICAL: every task MUST include new/updated tests**
- **CRITICAL: all tests must pass before starting next task**

## Implementation Steps

### Task 1: Initialize gem scaffold and development tooling

**Files:**
- Create: `cydia_lane.gemspec`
- Create: `Gemfile`
- Create: `Rakefile`
- Create: `lib/fastlane/plugin/cydia_lane.rb` (plugin entry point with action list)
- Create: `lib/fastlane/plugin/cydia_lane/version.rb`
- Create: `lib/fastlane/plugin/cydia_lane/actions/upload_to_cydia_action.rb` (stub)
- Create: `lib/fastlane/plugin/cydia_lane/actions/fetch_cydia_build_action.rb` (stub)
- Create: `lib/fastlane/plugin/cydia_lane/helper/cydia_client.rb` (stub)
- Create: `bin/console`
- Create: `bin/setup`
- Create: `.rubocop.yml`
- Create: `spec/spec_helper.rb`
- Create: `LICENSE.txt`

- [x] Create gemspec with metadata (name: fastlane-plugin-cydia_lane, required_ruby_version: >= 3.3, fastlane dependency)
- [x] Create Gemfile referencing gemspec
- [x] Create Rakefile with default task running specs then rubocop
- [x] Create plugin entry point that returns the list of actions
- [x] Create version module (0.1.0)
- [x] Create stub action and helper files so require chain works
- [x] Create bin/console with IRB, gem auto-loading, and a reload! method that uses Kernel#load to re-source all lib files
- [x] Create bin/setup script (bundle install)
- [x] Set up .rubocop.yml inheriting from rubocop-omakase
- [x] Create spec_helper.rb with SimpleCov (minimum_coverage 100), require fastlane, and shared test helpers
- [x] Create LICENSE.txt (MIT)
- [x] Run rubocop -- fix any offenses
- [x] Run rspec -- verify setup works (green with 0 examples)

### Task 2: Implement Cydia API client

**Files:**
- Modify: `lib/fastlane/plugin/cydia_lane/helper/cydia_client.rb`
- Create: `lib/fastlane/plugin/cydia_lane/helper/cydia_error.rb`
- Create: `spec/helper/cydia_client_spec.rb`

- [ ] Write RSpec tests for CydiaClient:
  - Successful iOS build upload (mock HTTP 200 with build JSON response)
  - Successful Android build upload
  - Successful build fetch via GET
  - Auth failure (401) raises CydiaError
  - App not found (404) raises CydiaError
  - Validation error (422) raises CydiaError
  - Network/connection errors raise CydiaError
  - Multipart form body includes correct boundary, content-disposition, and file content
- [ ] Implement CydiaClient class:
  - initialize(base_url:, api_token:)
  - upload_build(app_slug:, platform:, bundle_path:, symbol_path: nil, source_map_path: nil) -- POST multipart form
  - fetch_build(app_slug:, platform:, target:, version:) -- GET with query params
  - Token auth header: Authorization: Token token="..."
  - Multipart form data built with Net::HTTP (no external deps)
  - Custom CydiaError class for API and network errors
  - JSON response parsing
- [ ] Run rspec -- all tests must pass
- [ ] Run rubocop -- no offenses

### Task 3: Implement upload_to_cydia fastlane action

**Files:**
- Modify: `lib/fastlane/plugin/cydia_lane/actions/upload_to_cydia_action.rb`
- Create: `spec/actions/upload_to_cydia_action_spec.rb`

- [ ] Write RSpec tests:
  - Successful iOS upload using auto-detected IPA from lane context (SharedValues::IPA_OUTPUT_PATH)
  - Successful Android upload using auto-detected artifact from lane context (SharedValues::GRADLE_APK_OUTPUT_PATH / GRADLE_AAB_OUTPUT_PATH)
  - Explicit file path parameter overrides auto-detection
  - Missing api_token or app_slug raises error
  - Missing file (no lane context, no explicit path) raises error
  - CydiaError from client is surfaced with UI.user_error!
  - Shared values CYDIA_BUILD_GUID is set after upload
- [ ] Implement UploadToCydiaAction:
  - Parameters: api_token (env: CYDIA_API_TOKEN), app_slug (env: CYDIA_APP_SLUG), base_url (env: CYDIA_BASE_URL), platform (auto-detect from fastlane platform context), file (auto-detect from lane context), symbol_file, source_map_file
  - Auto-detect platform: use fastlane's current platform block (:ios / :android)
  - Auto-detect file: IPA_OUTPUT_PATH for iOS, GRADLE_APK_OUTPUT_PATH or GRADLE_AAB_OUTPUT_PATH for Android
  - Call CydiaClient#upload_build
  - Set SharedValues::CYDIA_BUILD_GUID and CYDIA_BUILD_ARTIFACTS
  - Log upload result via UI.success
  - Full action metadata: description, available_options, output, return_value, authors, is_supported?
- [ ] Run rspec -- all tests must pass
- [ ] Run rubocop -- no offenses

### Task 4: Implement fetch_cydia_build fastlane action

**Files:**
- Modify: `lib/fastlane/plugin/cydia_lane/actions/fetch_cydia_build_action.rb`
- Modify: `lib/fastlane/plugin/cydia_lane.rb` (register new action)
- Create: `spec/actions/fetch_cydia_build_action_spec.rb`

- [ ] Write RSpec tests:
  - Successful build fetch returns build hash
  - Build not found (404) raises UI.user_error!
  - Missing required parameters raises error
  - Shared values CYDIA_BUILD_GUID and CYDIA_BUILD_ARTIFACTS set on success
- [ ] Implement FetchCydiaBuildAction:
  - Parameters: api_token, app_slug, base_url, platform, target, version
  - Call CydiaClient#fetch_build
  - Set shared values on success
  - Full action metadata
- [ ] Run rspec -- all tests must pass
- [ ] Run rubocop -- no offenses

### Task 5: Set up CI and final verification

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] Create GitHub Actions workflow:
  - Trigger: push and pull_request
  - Matrix: ruby: ['3.4', '4.0']
  - Steps: checkout, setup ruby with bundler cache, bundle install, bundle exec rake (runs specs + rubocop)
- [ ] Run full test suite (bundle exec rake spec)
- [ ] Run linter (bundle exec rubocop)
- [ ] Verify 100% test coverage from SimpleCov output

### Task 6: Verify acceptance criteria

- [ ] manual test: run bin/console, verify require loads correctly, verify reload! reloads lib files
- [ ] run full test suite (bundle exec rake spec)
- [ ] run linter (bundle exec rubocop)
- [ ] verify test coverage meets 100%

### Task 7: Update documentation

- [ ] Update README.md with: gem description, installation instructions (Pluginfile or Gemfile), usage examples for upload_to_cydia and fetch_cydia_build, integration examples showing where to add the action in Karen/Voices-style Fastfiles
- [ ] Move this plan to `docs/plans/completed/`

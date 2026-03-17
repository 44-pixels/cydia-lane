# fastlane-plugin-cydia_lane

Fastlane plugin for uploading builds to and fetching build info from the Cydia backend. Provides two actions: `upload_to_cydia` and `fetch_cydia_build`.

## Installation

### Using Pluginfile (recommended)

Add the plugin to your project's `fastlane/Pluginfile`:

```ruby
gem "fastlane-plugin-cydia_lane", git: "https://github.com/cydia/fastlane-plugin-cydia_lane"
```

Then run:

```bash
bundle install
```

### Using Gemfile

Add directly to your `Gemfile`:

```ruby
gem "fastlane-plugin-cydia_lane"
```

## Configuration

Set these environment variables or pass them as parameters:

| Variable | Description | Required |
|---|---|---|
| `CYDIA_API_TOKEN` | API token for Cydia authentication | Yes |
| `CYDIA_APP_SLUG` | App slug identifier in Cydia | Yes |
| `CYDIA_BASE_URL` | Base URL of the Cydia API | No (defaults to `https://cydia.example.com`) |

## Actions

### upload_to_cydia

Uploads an iOS or Android build to the Cydia backend.

```ruby
upload_to_cydia(
  api_token: "your-api-token",
  app_slug: "my-app",
  base_url: "https://cydia.example.com",
  platform: "ios",              # "ios" or "android"
  file: "path/to/build.ipa",   # optional, auto-detected from lane context
  symbol_file: "path/to/dSYM", # optional
  source_map_file: "path/to/source-map.js.map" # optional
)
```

The `file` parameter is optional -- if omitted, the action auto-detects the build artifact from fastlane's lane context:

- iOS: uses `IPA_OUTPUT_PATH` (set by `build_app` / `gym`)
- Android: uses `GRADLE_APK_OUTPUT_PATH` or `GRADLE_AAB_OUTPUT_PATH` (set by `gradle`)

After a successful upload, the action sets these shared values:

- `CYDIA_BUILD_GUID` -- the GUID of the uploaded build
- `CYDIA_BUILD_ARTIFACTS` -- the artifacts hash from the build response

### fetch_cydia_build

Fetches build information from the Cydia backend.

```ruby
fetch_cydia_build(
  api_token: "your-api-token",
  app_slug: "my-app",
  base_url: "https://cydia.example.com",
  platform: "ios",
  target: "device",
  version: "1.2.3"
)
```

For iOS builds, the backend derives the target from the IPA: `device` or `simulator`. Pass the appropriate value when fetching.

Sets the same shared values as `upload_to_cydia` on success.

## Integration Examples

These examples show where to add `upload_to_cydia` alongside existing upload actions in your Fastfile.

### iOS deploy lane

```ruby
platform :ios do
  lane :deploy do |options|
    app_identifier = options[:bundle_identifier]

    setup_ci if ENV["CI"]
    sync_code_signing(app_identifier: [app_identifier], type: "appstore")
    build_app(scheme: "MyApp", workspace: "ios/MyApp.xcworkspace")

    # Upload to TestFlight
    upload_to_testflight(api_key_path: "/tmp/fastlane-api-key.json")

    # Upload to Cydia alongside TestFlight
    upload_to_cydia(
      app_slug: "my-app",
      platform: "ios",
      symbol_file: lane_context[:DSYM_OUTPUT_PATH]
    )
  end
end
```

### Android deploy lane

> **Note:** Android build processing is not yet supported by the Cydia backend.
> The plugin will reject Android uploads locally with a clear error message
> until backend support is added.

```ruby
platform :android do
  lane :deploy do |options|
    application_id = options[:application_id]

    gradle(task: "bundleRelease", project_dir: "./android")

    # Upload to Google Play
    upload_to_play_store(
      track: "internal",
      package_name: application_id,
      skip_upload_apk: true,
      release_status: "draft"
    )

    # Upload to Cydia alongside Play Store (pending backend support)
    upload_to_cydia(
      app_slug: "my-app",
      platform: "android"
    )
  end
end
```

### Fetching a build after deploy

```ruby
lane :check_build do
  result = fetch_cydia_build(
    app_slug: "my-app",
    platform: "ios",
    target: "device",
    version: "1.2.3"
  )

  UI.message("Build GUID: #{lane_context[:CYDIA_BUILD_GUID]}")
end
```

## Development

```bash
bin/setup          # install dependencies
bundle exec rake   # run specs + rubocop
bin/console        # interactive console with reload!
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).

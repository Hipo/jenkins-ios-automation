Jenkins Release Automation Tools
================================

This repo contains scripts for automating the iOS release preparation process, we use them for our Jenkins recipes, but they could be repurposed to fit other iOS build automation tools.

* `sign-and-upload.sh`: Bash script that handles all clean, build and archive setup, it expects the following environment variables:

    * `APP_NAME`
    * `APP_BUNDLE_IDENTIFIER`
    * `PROJECT_DIRECTORY`
    * `DEVELOPER_NAME`
    * `PROFILE_NAME`
    * `TRYOUTS_APP_ID`
    * `TRYOUTS_APP_TOKEN`
    * `ITUNES_TOKEN`
    * `TEAM_ID`
    * `RELEASE_BRANCH`
    * `XCODE_WORKSPACE_PATH`
    * `XCODE_SCHEME`
    * `XCODE_CONFIG`
    * `SAUCELABS_USERNAME`
    * `SAUCELABS_TOKEN`
    * `ROBOT_TESTS_PATH`
    * `KEYCHAIN_NAME`
    * `KEYCHAIN_PASSWORD`

* `resign_with_device.rb`: Fastlane-based Ruby script for updating provisioning profiles using [Tryouts](http://tryouts.io) integration

* `export_options.plist`: Export options passed on to `xcodebuild`, update this with your team identifier

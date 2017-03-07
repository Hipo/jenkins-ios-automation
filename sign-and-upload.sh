#!/bin/bash --login

die() {
    echo "$*" >&2
    exit 1
}

OUTPUT_PATH="$PWD/build/Release-iphoneos"
APP_PATH="$OUTPUT_PATH/$APP_NAME.app"
IPA_PATH="$OUTPUT_PATH/$APP_NAME.ipa"
APP_ARCHIVE_PATH="$OUTPUT_PATH/$APP_NAME.xcarchive"
PROVISION_PATH="$PWD/build/$PROFILE_NAME.mobileprovision"

rm -rf "$OUTPUT_PATH"
mkdir -p "$OUTPUT_PATH"


if [ $ENFORCE_RELEASE == true ] ; then
  echo "***************************"
  echo "*    ENFORCE RELEASE      *"
  echo "***************************"

  git checkout -f $RELEASE_BRANCH
  
  RELEASE_TAG=`git describe --exact-match --abbrev=0 --tags`

  if [[ $RELEASE_TAG == "" ]]; then
    RELEASE_TAG=`git describe HEAD^1 --abbrev=0 --tags`
  fi

  if [[ $RELEASE_TAG == "" ]]; then
    echo "No tags found, cannot enforce release"
    exit 0
  fi

  git checkout -f $RELEASE_TAG
fi

RELEASE_MODE=true

if [[ "$GIT_BRANCH" != "$RELEASE_BRANCH" ]]; then
  RELEASE_MODE=false
else
  CURRENT_TAG=`git describe --exact-match --abbrev=0 --tags`

  if [[ $CURRENT_TAG == "" ]]; then
    RELEASE_MODE=false
  fi
fi


echo "***************************"
echo "*  Updating Dependencies  *"
echo "***************************"

/usr/local/bin/pod repo update
/usr/local/bin/pod install --project-directory="$PROJECT_DIRECTORY"


echo "***************************"
echo "*         Cleaning        *"
echo "***************************"

if [ ! -z "$XCODE_WORKSPACE_PATH" ] ; then
  /usr/bin/xcodebuild \
    -workspace "$XCODE_WORKSPACE_PATH" \
    -scheme "$XCODE_SCHEME" \
    -configuration "$XCODE_CONFIG" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    clean || die "Clean failed"
else
  /usr/bin/xcodebuild \
    -project "$XCODE_PROJECT_PATH" \
    -scheme "$XCODE_SCHEME" \
    -configuration "$XCODE_CONFIG" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    clean || die "Clean failed"
fi


if [ $RELEASE_MODE == false ] ; then
  echo "***************************"
  echo "*        Compiling        *"
  echo "***************************"

  if [ ! -z "$XCODE_WORKSPACE_PATH" ] ; then
    /usr/bin/xcodebuild \
      -workspace "$XCODE_WORKSPACE_PATH" \
      -scheme "$XCODE_SCHEME" \
      -configuration "$XCODE_CONFIG" \
      -sdk iphoneos \
      OBJROOT="$PWD/build" \
      SYMROOT="$PWD/build" \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO || die "Compiler failed"
  else
    /usr/bin/xcodebuild \
      -project "$XCODE_PROJECT_PATH" \
      -scheme "$XCODE_SCHEME" \
      -configuration "$XCODE_CONFIG" \
      -sdk iphoneos \
      OBJROOT="$PWD/build" \
      SYMROOT="$PWD/build" \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO || die "Compiler failed"
  fi

else
  
  echo "***************************"
  echo "*    Generating Profile   *"
  echo "***************************"

  ./deploy/resign_with_device.rb \
    tryouts-app-id="$TRYOUTS_APP_ID" \
    tryouts-token="$TRYOUTS_APP_TOKEN" \
    itunes-token="$ITUNES_TOKEN" \
    team-id="$TEAM_ID" \
    app-name="$APP_NAME" \
    bundle-identifier="$APP_BUNDLE_IDENTIFIER" \
    provision-output-path="$PROVISION_PATH"

  PROVISIONING_UUID=`cat "$PROVISION_PATH"_uuid`

  cp $PROVISION_PATH ~/Library/MobileDevice/Provisioning\ Profiles/$PROVISIONING_UUID.mobileprovision

  [[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm"
  rvm use system

  if [ ! -z "$KEYCHAIN_NAME" ] ; then
    echo "***************************"
    echo "*    Switching Keychain    *"
    echo "***************************"
    
    KEYCHAIN_PATH="/usr/local/keychains/$KEYCHAIN_NAME.keychain"
    
    /usr/bin/security list-keychains -s "$KEYCHAIN_PATH"
    /usr/bin/security default-keychain -s "$KEYCHAIN_PATH"
    /usr/bin/security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    
    echo "Loaded keychain at $KEYCHAIN_PATH"
  fi


  echo "***************************"
  echo "*        Compiling        *"
  echo "***************************"

  if [ ! -z "$XCODE_WORKSPACE_PATH" ] ; then
    /usr/bin/xcodebuild \
      -workspace "$XCODE_WORKSPACE_PATH" \
      -scheme "$XCODE_SCHEME" \
      -configuration "$XCODE_CONFIG" \
      -sdk iphoneos \
      ONLY_ACTIVE_ARCH=NO \
      CODE_SIGN_IDENTITY="$DEVELOPER_NAME" \
      PROVISIONING_PROFILE="$PROVISIONING_UUID" \
      archive -archivePath "$APP_ARCHIVE_PATH" || die "Compiler failed"
  else
    /usr/bin/xcodebuild \
      -project "$XCODE_PROJECT_PATH" \
      -scheme "$XCODE_SCHEME" \
      -configuration "$XCODE_CONFIG" \
      -sdk iphoneos \
      ONLY_ACTIVE_ARCH=NO \
      CODE_SIGN_IDENTITY="$DEVELOPER_NAME" \
      PROVISIONING_PROFILE="$PROVISIONING_UUID" \
      archive -archivePath "$APP_ARCHIVE_PATH" || die "Compiler failed"
  fi


  echo "***************************"
  echo "*        Signing          *"
  echo "***************************"

  /usr/bin/xcodebuild -exportArchive \
    -archivePath "$APP_ARCHIVE_PATH" \
    -exportPath "$OUTPUT_PATH" \
    -exportOptionsPlist "$PWD/deploy/export_options.plist" || die "Codesign failed"

  rm -f ~/Library/MobileDevice/Provisioning\ Profiles/$PROVISIONING_UUID.mobileprovision

  if [ ! -z "$KEYCHAIN_NAME" ] ; then
    HIPO_KEYCHAIN_PATH="/Users/hipo/Library/Keychains/hipo.keychain"
    
    /usr/bin/security list-keychains -s "$HIPO_KEYCHAIN_PATH"
    /usr/bin/security default-keychain -s "$HIPO_KEYCHAIN_PATH"
  fi


  echo "***************************"
  echo "*    Generating Notes     *"
  echo "***************************"

  PREVIOUS_TAG=`git describe HEAD^1 --abbrev=0 --tags`
  GIT_HISTORY=`git log --no-merges --format="- %s" $PREVIOUS_TAG..HEAD`

  if [[ $PREVIOUS_TAG == "" ]]; then
    GIT_HISTORY=`git log --no-merges --format="- %s"`
  fi

  echo "Current Tag: $CURRENT_TAG"
  echo "Previous Tag: $PREVIOUS_TAG"
  echo "Release Notes:

  $GIT_HISTORY"

  RELEASE_DATE=`date '+%Y-%m-%d %H:%M:%S'`
  RELEASE_NOTES="Build: $CURRENT_TAG
  Uploaded: $RELEASE_DATE

  $GIT_HISTORY"


  if [ ! -z "$TRYOUTS_APP_ID" ] && [ ! -z "$TRYOUTS_APP_TOKEN" ]; then
    echo ""
    echo "***************************"
    echo "*   Uploading to Tryouts  *"
    echo "***************************"

    curl https://tryouts.io/applications/$TRYOUTS_APP_ID/upload/ \
      -F status="2" \
      -F notify="0" \
      -F notes="$RELEASE_NOTES" \
      -F build="@$IPA_PATH" \
      -H "Authorization: $TRYOUTS_APP_TOKEN"
  fi
  
fi


if [ ! -z "$SAUCELABS_USERNAME" ] && [ ! -z "$SAUCELABS_TOKEN" ] && [ ! -z "$ROBOT_TESTS_PATH" ]; then
  echo ""
  echo "***************************"
  echo "* Uploading to Saucelabs  *"
  echo "***************************"
  
  SIM_OUTPUT_PATH="$PWD/build/Release-iphonesimulator"
  SIM_APP_PATH="$SIM_OUTPUT_PATH/$APP_NAME.app"
  SIM_ZIP_PATH="$SIM_OUTPUT_PATH/$APP_NAME.zip"

  rm -rf "$SIM_OUTPUT_PATH"
  mkdir -p "$SIM_OUTPUT_PATH"
  
  if [ ! -z "$XCODE_WORKSPACE_PATH" ] ; then
    /usr/bin/xcodebuild \
      -workspace "$XCODE_WORKSPACE_PATH" \
      -scheme "$XCODE_SCHEME" \
      -configuration "$XCODE_CONFIG" \
      -sdk iphonesimulator \
      OBJROOT="$PWD/build" \
      SYMROOT="$PWD/build" \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO
  else
    /usr/bin/xcodebuild \
      -project "$XCODE_PROJECT_PATH" \
      -scheme "$XCODE_SCHEME" \
      -configuration "$XCODE_CONFIG" \
      -sdk iphonesimulator \
      OBJROOT="$PWD/build" \
      SYMROOT="$PWD/build" \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO
  fi

  zip -r "$SIM_ZIP_PATH" "$SIM_APP_PATH"
  
  curl -u $SAUCELABS_USERNAME:$SAUCELABS_TOKEN \
    -X POST "http://saucelabs.com/rest/v1/storage/$SAUCELABS_USERNAME/$APP_NAME.zip?overwrite=true" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$SIM_ZIP_PATH"
  
  echo ""
  echo "***************************"
  echo "*   Running Robot Tests   *"
  echo "***************************"

  cd "$ROBOT_TESTS_PATH"
  
  git pull origin master
  
  /usr/local/bin/pybot -- $APP_NAME.robot
  
  REPORT_PATH="$JENKINS_HOME/userContent/$JOB_NAME/$BUILD_NUMBER"
  
  mkdir -p $REPORT_PATH
  mv report.html "$REPORT_PATH/"
  mv log.html "$REPORT_PATH/"
  mv output.xml "$REPORT_PATH/"

fi

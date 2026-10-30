#!/bin/bash
# release.sh - archive, export (Developer ID), notarize, staple, DMG, Sparkle snippet.
#
# Prerequisites:
#   1. Xcode + matching Command Line Tools
#   2. "Developer ID Application" certificate in the login keychain
#   3. A notarytool keychain profile:  xcrun notarytool store-credentials Bough-notary
#   4. Sparkle EdDSA key:              run generate_keys once, put the public key
#                                      into Info.plist SUPublicEDKey
#
# Usage:
#   TEAM_ID=XXXXXXXXXX ./Scripts/release.sh            # full pipeline
#   TEAM_ID=... NOTARIZE=0 ./Scripts/release.sh        # skip notarization (local test)
#
set -euo pipefail

APP_NAME="Bough"
SCHEME="Bough"
PROJECT="Bough.xcodeproj"
TEAM_ID="${TEAM_ID:?Set TEAM_ID (find it in Xcode > Settings > Accounts)}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-Bough-notary}"
NOTARIZE="${NOTARIZE:-1}"
BUILD_DIR="${BUILD_DIR:-build}"
VERSION=$(grep -m1 MARKETING_VERSION Configs/Base.xcconfig | awk '{print $3}')

echo "==> [1/7] Regenerating project (project.yml is the source of truth)"
xcodegen generate

echo "==> [2/7] Archiving ($SCHEME, team $TEAM_ID)"
xcodebuild archive \
  -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  | tail -n 3

echo "==> [3/7] Exporting Developer ID app"
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
  -exportOptionsPlist Scripts/ExportOptions.plist \
  -exportPath "$BUILD_DIR/export" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  | tail -n 3
APP_PATH="$BUILD_DIR/export/Bough.app"
[ -d "$APP_PATH" ] || { echo "export failed: $APP_PATH missing"; exit 1; }

if [ "$NOTARIZE" = "1" ]; then
  echo "==> [4/7] Zipping + notarizing (profile: $KEYCHAIN_PROFILE)"
  ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/Bough.zip"
  xcrun notarytool submit "$BUILD_DIR/Bough.zip" \
    --keychain-profile "$KEYCHAIN_PROFILE" --wait
  echo "==> [5/7] Stapling"
  xcrun stapler staple "$APP_PATH"
else
  echo "==> [4/7] Skipping notarization (NOTARIZE=0)"
  echo "==> [5/7] Skipping staple"
fi

echo "==> [6/7] Verifying + building DMG"
spctl -a -vv "$APP_PATH"
hdiutil create -volname "$APP_NAME $VERSION" \
  -srcfolder "$APP_PATH" -ov -format UDZO \
  "$BUILD_DIR/$APP_NAME-$VERSION.dmg" | tail -n 1

echo "==> [7/7] Sparkle signature snippet"
if command -v sign_update >/dev/null 2>&1; then
  sign_update "$BUILD_DIR/$APP_NAME-$VERSION.dmg" || true
  echo "Paste the signature above into Scripts/appcast-sample.xml (sparkle:edSignature)"
else
  echo "sign_update not found. Install Sparkle tools, then:"
  echo "  sign_update build/Bough-$VERSION.dmg"
fi

echo "==> Done: $BUILD_DIR/$APP_NAME-$VERSION.dmg"

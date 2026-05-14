#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/StatusBarIP.xcodeproj}"
SCHEME="${SCHEME:-StatusBarIP}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-Status Bar IP}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/build/release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_ROOT/DerivedData}"
STAGING_DIR="$BUILD_ROOT/dmg-staging"
RELEASE_DIR="${RELEASE_DIR:-$ROOT_DIR/releases}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-auto}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"
APPLE_ID_FOR_NOTARY="${APPLE_ID:-${APPPLE_ID:-}}"
APP_SPECIFIC_PASSWORD="${APP_SPECIFIC_PASSWORD:-}"

if [[ "$SIGNING_IDENTITY" == "auto" ]]; then
  IDENTITY_LINE="$(security find-identity -v -p codesigning | grep '"Developer ID Application:' | head -n 1 || true)"
  SIGNING_IDENTITY="$(printf '%s\n' "$IDENTITY_LINE" | awk '{ print $2 }')"

  if [[ -z "$DEVELOPMENT_TEAM" && "$IDENTITY_LINE" =~ \(([A-Z0-9]{10})\) ]]; then
    DEVELOPMENT_TEAM="${BASH_REMATCH[1]}"
  fi

  if [[ -z "$SIGNING_IDENTITY" ]]; then
    if [[ "$REQUIRE_NOTARIZATION" == "1" ]]; then
      echo "No Developer ID Application certificate was found in the keychain." >&2
      echo "Install the certificate or pass SIGNING_IDENTITY explicitly." >&2
      exit 1
    fi

    SIGNING_IDENTITY="-"
  fi
fi

if [[ "$REQUIRE_NOTARIZATION" == "1" && -z "$NOTARY_PROFILE" ]]; then
  echo "REQUIRE_NOTARIZATION=1 requires NOTARY_PROFILE." >&2
  exit 1
fi

if [[ -z "$DEVELOPMENT_TEAM" && "$SIGNING_IDENTITY" =~ \(([A-Z0-9]{10})\)$ ]]; then
  DEVELOPMENT_TEAM="${BASH_REMATCH[1]}"
fi

if [[ -n "$NOTARY_PROFILE" && -n "$APP_SPECIFIC_PASSWORD" ]]; then
  if [[ -z "$APPLE_ID_FOR_NOTARY" ]]; then
    echo "APP_SPECIFIC_PASSWORD requires APPLE_ID or APPPLE_ID." >&2
    exit 1
  fi

  if [[ -z "$DEVELOPMENT_TEAM" ]]; then
    echo "APP_SPECIFIC_PASSWORD requires DEVELOPMENT_TEAM or a Developer ID identity with a team id." >&2
    exit 1
  fi

  xcrun notarytool store-credentials "$NOTARY_PROFILE" \
    --apple-id "$APPLE_ID_FOR_NOTARY" \
    --team-id "$DEVELOPMENT_TEAM" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --validate
fi

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "Building with ad-hoc signing. Gatekeeper will warn users after download."
  SIGNING_ARGS=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY=-
    DEVELOPMENT_TEAM=
  )
else
  echo "Building with signing identity: $SIGNING_IDENTITY"
  SIGNING_ARGS=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
    ENABLE_HARDENED_RUNTIME=YES
    OTHER_CODE_SIGN_FLAGS=--timestamp
  )
fi

mkdir -p "$BUILD_ROOT" "$RELEASE_DIR"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  ONLY_ACTIVE_ARCH=NO \
  "${SIGNING_ARGS[@]}" \
  clean build

APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Expected app bundle was not found: $APP_BUNDLE" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_BUNDLE/Contents/Info.plist")"
ARTIFACT_BASENAME="StatusBarIP-${VERSION}-${BUILD_NUMBER}-macOS"
ZIP_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.zip"
DMG_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.dmg"
CHECKSUM_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME-SHA256SUMS.txt"
NOTARY_ZIP_PATH="$BUILD_ROOT/$ARTIFACT_BASENAME-notary.zip"

codesign --verify --deep --strict "$APP_BUNDLE"

rm -rf "$STAGING_DIR" "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH" "$NOTARY_ZIP_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "NOTARY_PROFILE requires a Developer ID signing identity." >&2
    exit 1
  fi

  ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP_PATH"
  xcrun notarytool submit "$NOTARY_ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
fi

mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

shasum -a 256 "$ZIP_PATH" "$DMG_PATH" > "$CHECKSUM_PATH"

echo
echo "Release artifacts:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo "  $CHECKSUM_PATH"
echo
echo "Verify Gatekeeper status with:"
echo "  spctl --assess --type open --context context:primary-signature -vv \"$DMG_PATH\""

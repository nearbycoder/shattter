#!/bin/zsh
# Archives the Release build and uploads it to App Store Connect for TestFlight.
# Signing is automatic via the Apple ID signed into Xcode (Settings → Accounts).
# Optional: set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH to authenticate with
# an App Store Connect API key instead.
set -euo pipefail

cd "$(dirname "$0")/.."
ARCHIVE=build/TestFlight/Shattter.xcarchive
EXPORT=build/TestFlight/export

auth=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  auth=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -authenticationKeyPath "$ASC_KEY_PATH")
fi

rm -rf build/TestFlight
xcodebuild archive \
  -project Shattter.xcodeproj \
  -scheme Shattter \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates "${auth[@]}"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist scripts/ExportOptions-TestFlight.plist \
  -allowProvisioningUpdates "${auth[@]}"

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
command -v xcodebuild >/dev/null || { echo 'Building an iOS IPA requires macOS and Xcode.' >&2; exit 1; }
python3 generate_project.py
xcodebuild -project Reader.xcodeproj -scheme Reader -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath .build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build
app_path=.build/Build/Products/Release-iphoneos/Reader.app
test -x "$app_path/Reader"
mkdir -p build/Payload
ditto "$app_path" build/Payload/Reader.app
rm -rf build/Payload/Reader.app/_CodeSignature
cd build
rm -f Reader-unsigned.ipa
zip -q -r Reader-unsigned.ipa Payload
unzip -t Reader-unsigned.ipa
echo 'Created ios/build/Reader-unsigned.ipa — sign with your own Apple ID/certificate before installing.'

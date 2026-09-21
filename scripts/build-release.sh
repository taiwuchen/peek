#!/bin/sh
# Builds the signed Release app and a signed DMG in dist/. Prints the DMG path and its SHA-256.
set -eu
cd "$(dirname "$0")/.."
version=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
app=build/release/Build/Products/Release/Peek.app
stage=build/dmg-$version
dmg=dist/Peek-$version.dmg
xcodegen generate --quiet
xcodebuild -scheme Peek -configuration Release -destination "generic/platform=macOS" -derivedDataPath build/release \
  OTHER_CODE_SIGN_FLAGS="--timestamp" build -quiet
codesign --verify --deep --strict "$app"
rm -rf "$stage" "$dmg" && mkdir -p "$stage" dist
cp -R "$app" "$stage/" && ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "Peek $version" -srcfolder "$stage" -ov -format UDZO "$dmg"
codesign --sign "Apple Development" --timestamp "$dmg"
echo "$dmg"
shasum -a 256 "$dmg" | cut -d' ' -f1

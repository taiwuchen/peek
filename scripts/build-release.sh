#!/bin/sh
# Builds the signed Release app, a signed DMG, and the Sparkle appcast in dist/. Prints the DMG path and its SHA-256.
# Upload both to GitHub release v<version>, not marked pre-release, so the in-app updater finds it.
set -eu
cd "$(dirname "$0")/.."
version=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
# Sparkle compares build numbers, so each release needs a higher one.
build=$(git rev-list --count HEAD)
app=build/release/Build/Products/Release/Peek.app
stage=build/dmg-$version
dmg=dist/Peek-$version.dmg
xcodegen generate --quiet
xcodebuild -scheme Peek -configuration Release -destination "generic/platform=macOS" -derivedDataPath build/release \
  CURRENT_PROJECT_VERSION="$build" OTHER_CODE_SIGN_FLAGS="--timestamp" build -quiet
codesign --verify --deep --strict "$app"
rm -rf "$stage" "$dmg" && mkdir -p "$stage" dist
cp -R "$app" "$stage/" && ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "Peek $version" -srcfolder "$stage" -ov -format UDZO "$dmg"
codesign --sign "Apple Development" --timestamp "$dmg"
signature=$(build/release/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update --account peek "$dmg")
cat > dist/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Peek</title>
    <item>
      <title>Peek $version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/taiwuchen/peek/releases/tag/v$version</sparkle:fullReleaseNotesLink>
      <enclosure url="https://github.com/taiwuchen/peek/releases/download/v$version/Peek-$version.dmg"
                 type="application/octet-stream" $signature/>
    </item>
  </channel>
</rss>
EOF
echo "$dmg"
shasum -a 256 "$dmg" | cut -d' ' -f1

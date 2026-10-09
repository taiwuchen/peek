#!/bin/sh
# Builds a signed app, signed DMG, and Sparkle appcast for prod (default) or dev. Prints the DMG path and its SHA-256.
# prod: dist/, upload both to GitHub release v<version>, not pre-release. dev: dist/dev/, upload both to the `dev` pre-release.
set -eu
cd "$(dirname "$0")/.."
channel=${1:-prod}
version=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
releases=https://github.com/taiwuchen/peek/releases
case $channel in
  prod)
    # Sparkle compares build numbers, so each release needs a higher one.
    build=$(git rev-list --count HEAD)
    config=Release name=Peek derived=build/release out=dist tag=v$version
    dmg_name=Peek-$version.dmg title="Peek $version"
    # project.yml already sets prod's feed.
    feed=""
    notes="<sparkle:fullReleaseNotesLink>$releases/tag/v$version</sparkle:fullReleaseNotesLink>"
    ;;
  dev)
    # A dev release can repeat a commit, so a timestamp keeps build numbers rising.
    build=$(date -u +%Y%m%d%H%M)
    config=Debug name="Peek Dev" derived=build/dev out=dist/dev tag=dev
    commit=$(git rev-parse --short HEAD)$(git diff --quiet HEAD || echo "-dirty")
    dmg_name=Peek-Dev.dmg title="Peek Dev $version ($commit)"
    # Only released dev builds get a feed; local Debug builds never update themselves.
    feed=SPARKLE_FEED_URL=$releases/download/dev/appcast.xml
    notes=""
    ;;
  *)
    echo "usage: $0 [prod|dev]" >&2
    exit 64
    ;;
esac
app="$derived/Build/Products/$config/$name.app"
stage=build/dmg-$channel
dmg=$out/$dmg_name
xcodegen generate --quiet
xcodebuild -scheme Peek -configuration "$config" -destination "generic/platform=macOS" -derivedDataPath "$derived" \
  CURRENT_PROJECT_VERSION="$build" OTHER_CODE_SIGN_FLAGS="--timestamp" ${feed:+"$feed"} build -quiet
codesign --verify --deep --strict "$app"
rm -rf "$stage" "$dmg" && mkdir -p "$stage" "$out"
cp -R "$app" "$stage/" && ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "$name $version" -srcfolder "$stage" -ov -format UDZO "$dmg"
codesign --sign "Apple Development" --timestamp "$dmg"
signature=$("$derived"/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update --account peek "$dmg")
cat > "$out/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$name</title>
    <item>
      <title>$title</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      $notes
      <enclosure url="$releases/download/$tag/$dmg_name"
                 type="application/octet-stream" $signature/>
    </item>
  </channel>
</rss>
EOF
echo "$dmg"
shasum -a 256 "$dmg" | cut -d' ' -f1

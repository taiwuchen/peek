#!/bin/sh
# Generates the Xcode project and builds the Debug app. Prints the built .app path.
set -eu
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -scheme Peek -configuration Debug -derivedDataPath build build -quiet
echo "build/Build/Products/Debug/Peek.app"

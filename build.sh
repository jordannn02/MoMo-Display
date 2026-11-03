#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
DEST="${1:-build}"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"
APP="$DEST/MoMo Display.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 -sdk "$SDK" \
  -import-objc-header Sources/Bridging-Header.h \
  -F /System/Library/PrivateFrameworks \
  -framework AppKit -framework SwiftUI -framework ServiceManagement -framework IOKit -framework CoreDisplay \
  -framework DisplayServices -framework Metal -framework MetalKit -framework QuartzCore \
  Sources/*.swift -o "$APP/Contents/MacOS/momo-display"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Licenses "$APP/Contents/Resources/"
cp THIRD_PARTY.md "$APP/Contents/Resources/"
if [ -f AppIcon.icns ]; then cp AppIcon.icns "$APP/Contents/Resources/"; fi
# File Provider may attach FinderInfo to newly created bundles in Documents.
# Remove that metadata only from our own new app before ad-hoc signing.
/usr/bin/xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
/usr/bin/codesign --force --sign - "$APP"
echo "$APP"

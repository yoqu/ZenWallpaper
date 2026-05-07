#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="ZenWallpaper.app"
NAME="ZenWallpaper"
DIST_DIR="dist"
DMG_STAGE=".dmg-stage"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo "1.0.0")"
DMG_NAME="${NAME}-${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"

echo "==> swift build (release)..."
swift build -c release

echo "==> Building $APP bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Resources/Branding"
mkdir -p "$APP/Contents/Resources/StylePresets"

cp ".build/release/$NAME" "$APP/Contents/MacOS/$NAME"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Branding/*.png "$APP/Contents/Resources/Branding/"
cp Resources/StylePresets/*.png "$APP/Contents/Resources/StylePresets/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# Make sure the binary is executable
chmod +x "$APP/Contents/MacOS/$NAME"

# Ad-hoc sign so macOS will run it
echo "==> Codesign (ad-hoc)..."
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "==> Building DMG..."
rm -rf "$DIST_DIR" "$DMG_STAGE"
mkdir -p "$DIST_DIR" "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create \
  -volname "$NAME" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$DMG_STAGE"

echo "==> Done. App bundle at: $(pwd)/$APP"
echo "==> DMG installer at: $(pwd)/$DMG_PATH"

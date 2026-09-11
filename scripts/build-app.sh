#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="$ROOT_DIR/build/CodexQuota.app"
MODULE_CACHE_DIR="$ROOT_DIR/.build/module-cache"
CONTENTS_DIR="$APP_DIR/Contents"
# Never follow output symlinks when rebuilding.
for target in "$ROOT_DIR/build" "$ROOT_DIR/.build" "$APP_DIR"; do
  if [[ -L "$target" ]]; then
    echo "Refusing symbolic-link output: $target" >&2
    exit 1
  fi
done

cd "$ROOT_DIR"
if [[ -e "$APP_DIR" ]]; then /usr/bin/find "$APP_DIR" -depth -delete; fi
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
mkdir -p "$MODULE_CACHE_DIR"

clang -fobjc-arc -fmodules \
  -fmodules-cache-path="$MODULE_CACHE_DIR" \
  -mmacosx-version-min=14.0 \
  "$ROOT_DIR/native/main.m" \
  -o "$CONTENTS_DIR/MacOS/CodexQuota" \
  -framework Cocoa -framework QuartzCore


plutil -create xml1 "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleName -string "Codex Quota" "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleDisplayName -string "Codex Quota" "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleIdentifier -string "io.github.a262668008-prog.codexquota" "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleExecutable -string "CodexQuota" "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundlePackageType -string "APPL" "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleShortVersionString -string "0.3.2" "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleVersion -string "6" "$CONTENTS_DIR/Info.plist"
plutil -insert LSMinimumSystemVersion -string "14.0" "$CONTENTS_DIR/Info.plist"
plutil -insert LSUIElement -bool true "$CONTENTS_DIR/Info.plist"
plutil -insert NSHighResolutionCapable -bool true "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"

#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
zsh -n "$ROOT_DIR/scripts/build-app.sh"
zsh "$ROOT_DIR/scripts/build-app.sh"
APP_DIR="$ROOT_DIR/build/CodexQuota.app"
codesign --verify --deep --strict "$APP_DIR"
plutil -lint "$APP_DIR/Contents/Info.plist"
result=$(CODEXQUOTA_SELF_TEST=incremental-parser "$APP_DIR/Contents/MacOS/CodexQuota" 2>&1)
print -r -- "$result"
[[ "$result" == *"CODEXQUOTA_SELF_TEST_PASS incremental-parser"* ]]
[[ "$result" != *"CODEXQUOTA_SELF_TEST_FAIL"* ]]

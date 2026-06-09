#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TIMEOUT_BIN="${TIMEOUT_BIN:-timeout}"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-180s}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/build}"
PRODUCT_DIR="$BUILD_ROOT/${CONFIGURATION}-iphoneos"
APP_NAME="iSH ARM64.app"
APP_PRODUCT="$PRODUCT_DIR/$APP_NAME"
APPEX_PRODUCT="$PRODUCT_DIR/iSHFileProvider.appex"
STAGE_DIR="${STAGE_DIR:-$BUILD_ROOT/ipa-stage-arm64-jit}"
OUTPUT_IPA="${OUTPUT_IPA:-$BUILD_ROOT/iSH-ARM64-JIT-TrollStore.tipa}"

APP_BUNDLE_ID="${APP_BUNDLE_ID:-app.ish.iSH.arm64}"
APP_GROUP_ID="${APP_GROUP_ID:-group.app.ish.iSH.arm64}"
APPEX_BUNDLE_ID="${APPEX_BUNDLE_ID:-${APP_BUNDLE_ID}.FileProvider}"

APP_ENTITLEMENTS="$ROOT/app/iSH-ARM64-ad-hoc.entitlements"
APPEX_ENTITLEMENTS="$ROOT/app/iSH-ARM64-FileProvider-ad-hoc.entitlements"

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required tool '$1' was not found" >&2
        exit 1
    fi
}

run_bounded() {
    "$TIMEOUT_BIN" "$BUILD_TIMEOUT" "$@"
}

require_tool "$TIMEOUT_BIN"
require_tool xcodebuild
require_tool ldid
require_tool zip
require_tool plutil

if [[ ! -f "$APP_ENTITLEMENTS" ]]; then
    echo "error: missing app entitlements: $APP_ENTITLEMENTS" >&2
    exit 1
fi
if [[ ! -f "$APPEX_ENTITLEMENTS" ]]; then
    echo "error: missing file-provider entitlements: $APPEX_ENTITLEMENTS" >&2
    exit 1
fi

echo "building iSH-ARM64 app into $PRODUCT_DIR"
run_bounded xcodebuild \
    -project iSH.xcodeproj \
    -scheme "iSH-ARM64" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=iOS" \
    build \
    SYMROOT="$BUILD_ROOT" \
    PRODUCT_BUNDLE_IDENTIFIER="$APP_BUNDLE_ID" \
    PRODUCT_APP_GROUP_IDENTIFIER="$APP_GROUP_ID" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY='' \
    EXPANDED_CODE_SIGN_IDENTITY=''

echo "building iSHFileProvider extension into $PRODUCT_DIR"
run_bounded xcodebuild \
    -project iSH.xcodeproj \
    -target "iSHFileProvider" \
    -configuration "$CONFIGURATION" \
    build \
    SYMROOT="$BUILD_ROOT" \
    PRODUCT_BUNDLE_IDENTIFIER="$APPEX_BUNDLE_ID" \
    PRODUCT_APP_GROUP_IDENTIFIER="$APP_GROUP_ID" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY='' \
    EXPANDED_CODE_SIGN_IDENTITY=''

if [[ ! -d "$APP_PRODUCT" ]]; then
    echo "error: app product was not produced: $APP_PRODUCT" >&2
    exit 1
fi
if [[ ! -d "$APPEX_PRODUCT" ]]; then
    echo "error: file-provider product was not produced: $APPEX_PRODUCT" >&2
    exit 1
fi

echo "staging Payload"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/Payload"
/usr/bin/ditto "$APP_PRODUCT" "$STAGE_DIR/Payload/$APP_NAME"
mkdir -p "$STAGE_DIR/Payload/$APP_NAME/PlugIns"
/usr/bin/ditto "$APPEX_PRODUCT" "$STAGE_DIR/Payload/$APP_NAME/PlugIns/iSHFileProvider.appex"
rm -rf \
    "$STAGE_DIR/Payload/$APP_NAME/_CodeSignature" \
    "$STAGE_DIR/Payload/$APP_NAME/PlugIns/iSHFileProvider.appex/_CodeSignature"

echo "signing file provider"
ldid -S"$APPEX_ENTITLEMENTS" \
    "$STAGE_DIR/Payload/$APP_NAME/PlugIns/iSHFileProvider.appex/iSHFileProvider"

echo "signing app"
ldid -S"$APP_ENTITLEMENTS" \
    "$STAGE_DIR/Payload/$APP_NAME/iSH ARM64"

echo "writing $OUTPUT_IPA"
mkdir -p "$(dirname "$OUTPUT_IPA")"
(
    cd "$STAGE_DIR"
    rm -f "$OUTPUT_IPA"
    zip -qry "$OUTPUT_IPA" Payload
)

echo "created:"
ls -lh "$OUTPUT_IPA"

echo "app bundle id: $(plutil -extract CFBundleIdentifier raw "$STAGE_DIR/Payload/$APP_NAME/Info.plist")"
echo "file provider bundle id: $(plutil -extract CFBundleIdentifier raw "$STAGE_DIR/Payload/$APP_NAME/PlugIns/iSHFileProvider.appex/Info.plist")"
echo "archive contains:"
unzip -l "$OUTPUT_IPA" | grep -E 'Payload/$|Payload/iSH ARM64.app/$|PlugIns/|iSHFileProvider.appex/iSHFileProvider|Payload/iSH ARM64.app/iSH ARM64$'

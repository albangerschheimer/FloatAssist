#!/bin/bash

# Build a distributable Float Assist disk image using macOS system tools.
# Usage: ./scripts/create-dmg.sh <path/to/Float Assist.app> [output-directory]

set -euo pipefail

readonly APP_NAME="Float Assist"
readonly VOLUME_NAME="Float Assist"
readonly DMG_NAME="FloatAssist.dmg"

usage() {
    echo "Usage: $0 <path/to/${APP_NAME}.app> [output-directory]" >&2
}

fail() {
    echo "Error: $*" >&2
    exit 1
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 1
fi

APP_INPUT="$1"
OUTPUT_INPUT="${2:-$PWD/build}"

[[ -d "$APP_INPUT" ]] || fail "App bundle not found: $APP_INPUT"
[[ -f "$APP_INPUT/Contents/Info.plist" ]] || fail "Not a valid macOS app bundle: $APP_INPUT"

APP_PATH="$(cd "$APP_INPUT" && pwd -P)"

if [[ -e "$OUTPUT_INPUT" && ! -d "$OUTPUT_INPUT" ]]; then
    fail "Output path is not a directory: $OUTPUT_INPUT"
fi

mkdir -p "$OUTPUT_INPUT"
OUTPUT_DIR="$(cd "$OUTPUT_INPUT" && pwd -P)"

[[ "$OUTPUT_DIR" != "/" ]] || fail "Refusing to write a disk image to the filesystem root"

case "$OUTPUT_DIR" in
    "$APP_PATH"|"$APP_PATH"/*)
        fail "Output directory must not be inside the app bundle"
        ;;
esac

DMG_FINAL="$OUTPUT_DIR/$DMG_NAME"
[[ ! -d "$DMG_FINAL" ]] || fail "Output path is a directory: $DMG_FINAL"

TEMP_PREFIX="$OUTPUT_DIR/.float-assist-dmg."
TEMP_DIR=""

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        case "$TEMP_DIR" in
            "$TEMP_PREFIX"*) rm -rf "$TEMP_DIR" || true ;;
        esac
    fi
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

TEMP_DIR="$(mktemp -d "${TEMP_PREFIX}XXXXXX")" || fail "Could not create a temporary staging directory"
STAGING_DIR="$TEMP_DIR/staging"
DMG_TEMP="$TEMP_DIR/$DMG_NAME"

mkdir "$STAGING_DIR"

echo "Copying ${APP_NAME}..."
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating disk image..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    "$DMG_TEMP"

# Move the completed image into place only after hdiutil succeeds.
mv -f "$DMG_TEMP" "$DMG_FINAL"

echo "DMG created: $DMG_FINAL"

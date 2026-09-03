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
MOUNT_POINT=""

cleanup() {
    if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
        hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || \
            hdiutil detach "$MOUNT_POINT" -force -quiet 2>/dev/null || true
    fi
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
MOUNT_POINT="$TEMP_DIR/mount"
DMG_WRITABLE="$TEMP_DIR/writable.dmg"
DMG_TEMP="$TEMP_DIR/$DMG_NAME"

mkdir "$STAGING_DIR"

echo "Copying ${APP_NAME}..."
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

# Give the mounted volume the application's own icon when the bundle carries
# one. This is decoration: a missing icon or a missing SetFile never fails the
# build.
VOLUME_ICON="$APP_PATH/Contents/Resources/AppIcon.icns"
HAS_VOLUME_ICON=0
if [[ -f "$VOLUME_ICON" ]]; then
    cp "$VOLUME_ICON" "$STAGING_DIR/.VolumeIcon.icns"
    HAS_VOLUME_ICON=1
fi

echo "Creating disk image..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -format UDRW \
    -quiet \
    "$DMG_WRITABLE"

if [[ "$HAS_VOLUME_ICON" -eq 1 ]]; then
    mkdir -p "$MOUNT_POINT"
    hdiutil attach "$DMG_WRITABLE" -mountpoint "$MOUNT_POINT" -nobrowse -quiet

    # The custom-icon flag on the volume root is what makes Finder show
    # .VolumeIcon.icns instead of the generic disk image icon.
    if command -v SetFile >/dev/null 2>&1; then
        SetFile -a C "$MOUNT_POINT" || echo "Warning: could not set the volume icon flag." >&2
    else
        echo "Warning: SetFile is unavailable; the volume keeps the default icon." >&2
    fi

    hdiutil detach "$MOUNT_POINT" -quiet
    MOUNT_POINT=""
fi

echo "Compressing disk image..."
hdiutil convert "$DMG_WRITABLE" -format UDZO -quiet -o "$DMG_TEMP"

# Move the completed image into place only after every step has succeeded.
mv -f "$DMG_TEMP" "$DMG_FINAL"

echo "DMG created: $DMG_FINAL"

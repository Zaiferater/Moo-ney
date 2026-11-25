#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="牛马打气机"
EXECUTABLE_NAME="Moo-ney"
BUNDLE_ID="com.zaiferater.mooney"
VERSION="1.0.0"
MIN_MACOS="12.0"

OUTPUT_PATH="$REPO_ROOT/$APP_NAME.app"
UNIVERSAL=0
RUN_TESTS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --universal)
            UNIVERSAL=1
            shift
            ;;
        --test)
            RUN_TESTS=1
            shift
            ;;
        -h|--help)
            cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -o, --output <path>  Output .app bundle path (default: $REPO_ROOT/$APP_NAME.app)
  --universal          Build a universal binary (arm64 + x86_64)
  --test               Run unit tests for payroll and settings persistence
  -h, --help           Show this help message
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/moo-ney-build.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ "$RUN_TESTS" -eq 1 ]]; then
    echo "Running macOS unit tests..."
    swiftc -O -parse-as-library \
        "$SCRIPT_DIR/Sources/Payroll.swift" \
        "$SCRIPT_DIR/Tests/PayrollTests.swift" \
        -o "$WORK_DIR/payroll-tests"
    "$WORK_DIR/payroll-tests"
fi

SOURCES=(
    "$SCRIPT_DIR/Sources/Payroll.swift"
    "$SCRIPT_DIR/Sources/Appearance.swift"
    "$SCRIPT_DIR/Sources/TypingCow.swift"
    "$SCRIPT_DIR/Sources/RollingAmount.swift"
    "$SCRIPT_DIR/Sources/WorkdayCalendar.swift"
    "$SCRIPT_DIR/Sources/SetupWindow.swift"
    "$SCRIPT_DIR/Sources/TimerWindow.swift"
    "$SCRIPT_DIR/Sources/main.swift"
)

SDK_PATH="$(xcrun --show-sdk-path)"
BIN_PATH="$WORK_DIR/$EXECUTABLE_NAME"

compile_arch() {
    local arch="$1"
    local out="$2"
    swiftc -O \
        -target "${arch}-apple-macos${MIN_MACOS}" \
        -sdk "$SDK_PATH" \
        -framework AppKit \
        -framework QuartzCore \
        -framework Foundation \
        "${SOURCES[@]}" \
        -o "$out"
}

if [[ "$UNIVERSAL" -eq 1 ]]; then
    echo "Compiling universal binary (arm64 + x86_64)..."
    compile_arch "arm64" "$WORK_DIR/${EXECUTABLE_NAME}-arm64"
    compile_arch "x86_64" "$WORK_DIR/${EXECUTABLE_NAME}-x86_64"
    lipo -create -output "$BIN_PATH" \
        "$WORK_DIR/${EXECUTABLE_NAME}-arm64" \
        "$WORK_DIR/${EXECUTABLE_NAME}-x86_64"
else
    HOST_ARCH="$(uname -m)"
    echo "Compiling native binary ($HOST_ARCH)..."
    compile_arch "$HOST_ARCH" "$BIN_PATH"
fi

# Generate AppIcon.icns from root app.ico
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
BASE_PNG="$WORK_DIR/icon_base.png"
mkdir -p "$ICONSET_DIR"
sips -s format png "$REPO_ROOT/app.ico" --out "$BASE_PNG" >/dev/null
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$BASE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$BASE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$WORK_DIR/AppIcon.icns"

# Assemble .app bundle
mkdir -p "$(dirname "$OUTPUT_PATH")"
rm -rf "$OUTPUT_PATH"
mkdir -p "$OUTPUT_PATH/Contents/MacOS" "$OUTPUT_PATH/Contents/Resources/Mascots"

cp "$BIN_PATH" "$OUTPUT_PATH/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$OUTPUT_PATH/Contents/MacOS/$EXECUTABLE_NAME"
cp "$WORK_DIR/AppIcon.icns" "$OUTPUT_PATH/Contents/Resources/AppIcon.icns"
cp "$REPO_ROOT/Mascots/panda.png" "$REPO_ROOT/Mascots/cat.png" "$REPO_ROOT/Mascots/penguin.png" \
    "$OUTPUT_PATH/Contents/Resources/Mascots/"

cat > "$OUTPUT_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc sign locally for smooth launch on Apple Silicon / Gatekeeper
if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$OUTPUT_PATH" >/dev/null 2>&1 || true
fi

echo "$OUTPUT_PATH"

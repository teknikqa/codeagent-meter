#!/usr/bin/env bash
set -euo pipefail

# Builds CodeAgentMeterApp and wraps it in a minimal, unsigned "CodeAgent
# Meter.app" bundle before launching it via `open`. A bare `swift run`
# executable has no Info.plist, so macOS shows Dock/Cmd+Tab text derived
# from the binary's filename ("CodeAgentMeterApp") instead of a real app
# name — this gives it one for local development. Not a substitute for
# real packaging (code signing, notarization) before any distribution.

cd "$(dirname "$0")/.."

CONFIGURATION="${1:-debug}"
APP_NAME="CodeAgent Meter"
EXECUTABLE_NAME="CodeAgentMeterApp"
BUNDLE=".build/${APP_NAME}.app"
VERSION="$(sed -n 's/.*"\.": "\(.*\)".*/\1/p' .release-please-manifest.json)"

# The macOS 27 SDK turns SwiftUI's @State into a macro backed by the
# SwiftUIMacros compiler plugin, which ships with Xcode but not with the
# Command Line Tools. With CLT only, fall back to the newest installed SDK
# whose SwiftUI doesn't need that macro. Set SDKROOT yourself to override.
CLT_DIR="/Library/Developer/CommandLineTools"
needs_state_macro() {
  grep -qs '"StateMacro"' "$1/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"
}
if [[ -z "${SDKROOT:-}" && "$(xcode-select -p)" == "$CLT_DIR" ]] && needs_state_macro "$CLT_DIR/SDKs/MacOSX.sdk"; then
  for sdk in $(ls -d "$CLT_DIR"/SDKs/MacOSX[0-9]*.sdk | sort -rV); do
    if ! needs_state_macro "$sdk"; then
      export SDKROOT="$sdk"
      break
    fi
  done
  if [[ -z "${SDKROOT:-}" ]]; then
    echo "No installed SDK can build SwiftUI with the Command Line Tools alone. Install Xcode." >&2
    exit 1
  fi
  echo "Using $SDKROOT (default SDK needs Xcode's SwiftUI macros)"
fi

echo "Building ($CONFIGURATION)..."
swift build -c "$CONFIGURATION"

echo "Assembling ${BUNDLE}..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp ".build/${CONFIGURATION}/${EXECUTABLE_NAME}" "$BUNDLE/Contents/MacOS/${EXECUTABLE_NAME}"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>com.nickmathew.codeagent-meter</string>
	<key>CFBundleExecutable</key>
	<string>${EXECUTABLE_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

# Ad-hoc by default. Set CODESIGN_IDENTITY to sign with a real certificate
# (e.g. a Developer ID).
echo "Signing..."
codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" "$BUNDLE"

# NO_LAUNCH=1 stops after signing, for CI packaging.
if [[ -n "${NO_LAUNCH:-}" ]]; then
  exit 0
fi

echo "Launching..."
open "$BUNDLE"

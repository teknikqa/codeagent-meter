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
	<string>1.0</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

# Sign with a stable self-signed identity rather than ad-hoc. An ad-hoc
# signature identifies the app by its binary hash, so every rebuild looks
# like a new app to Keychain and "Always Allow" never sticks. A certificate
# keeps the identity constant across rebuilds. Set CODESIGN_IDENTITY to use
# your own (e.g. a Developer ID), or "-" for ad-hoc.
SIGN_IDENTITY="${CODESIGN_IDENTITY:-CodeAgent Meter Local Signing}"
if [[ "$SIGN_IDENTITY" != "-" ]] && ! security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
  echo "Creating self-signed code signing certificate \"$SIGN_IDENTITY\" in the login keychain (one-time)..."
  CERT_DIR="$(mktemp -d)"
  # /usr/bin/openssl (LibreSSL) writes a PKCS#12 that `security import` can read; Homebrew's OpenSSL 3 doesn't.
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$SIGN_IDENTITY" \
    -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" 2>/dev/null
  /usr/bin/openssl pkcs12 -export -inkey "$CERT_DIR/key.pem" -in "$CERT_DIR/cert.pem" \
    -name "$SIGN_IDENTITY" -passout pass:codeagent -out "$CERT_DIR/identity.p12"
  security import "$CERT_DIR/identity.p12" -P codeagent -T /usr/bin/codesign
  rm -rf "$CERT_DIR"
fi

echo "Signing as \"$SIGN_IDENTITY\"..."
codesign --force --deep --sign "$SIGN_IDENTITY" "$BUNDLE"

echo "Launching..."
open "$BUNDLE"

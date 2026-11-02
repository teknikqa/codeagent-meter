#!/usr/bin/env bash
# Writes Casks/codeagent-meter.rb in teknikqa/homebrew-tap for a release,
# committing through the GitHub contents API. HOMEBREW_TAP_GITHUB_TOKEN must
# have contents:write on the tap. Also usable by hand to seed an existing
# release: HOMEBREW_TAP_GITHUB_TOKEN=$(gh auth token) scripts/update-cask.sh 1.8.1
set -euo pipefail

VERSION="${1:?usage: update-cask.sh <version, e.g. 1.8.1>}"
: "${HOMEBREW_TAP_GITHUB_TOKEN:?HOMEBREW_TAP_GITHUB_TOKEN must be set}"
export GH_TOKEN="$HOMEBREW_TAP_GITHUB_TOKEN"

API="repos/teknikqa/homebrew-tap/contents/Casks/codeagent-meter.rb"
ZIP_URL="https://github.com/teknikqa/codeagent-meter/releases/download/v${VERSION}/CodeAgent-Meter.zip"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

curl -fsSL -o "$workdir/app.zip" "$ZIP_URL"
sha256=$(shasum -a 256 "$workdir/app.zip" | cut -d' ' -f1)

cat >"$workdir/cask.rb" <<CASK
cask "codeagent-meter" do
  version "${VERSION}"
  sha256 "${sha256}"

  url "https://github.com/teknikqa/codeagent-meter/releases/download/v#{version}/CodeAgent-Meter.zip"
  name "CodeAgent Meter"
  desc "Menu bar app for tracking usage and quota across AI coding agents"
  homepage "https://github.com/teknikqa/codeagent-meter"

  livecheck do
    skip "Auto-generated on release."
  end

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "CodeAgent Meter.app"

  # The app isn't notarized, so clear quarantine or Gatekeeper blocks it.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/CodeAgent Meter.app"]
  end
end
CASK

# The blob sha is required to update an existing file, absent on first create.
blob_sha=$(gh api "$API" --jq .sha 2>/dev/null || true)
args=(-X PUT "$API" -f message="codeagent-meter ${VERSION}" -f content="$(base64 <"$workdir/cask.rb" | tr -d '\n')")
[[ -n "$blob_sha" ]] && args+=(-f sha="$blob_sha")
gh api "${args[@]}" --silent
echo "Updated codeagent-meter cask to ${VERSION}"

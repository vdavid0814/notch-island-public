#!/bin/bash
# Builds build/NotchIsland.app from the SwiftPM product and signs it.
#
#   Scripts/build.sh                 debug build
#   CONFIG=release Scripts/build.sh  optimised build
#   SIGN_ID="Apple Development: …"   override the signing identity
#
# The bundle is assembled by hand (SwiftPM has no app-bundle product): binary, Info.plist, PkgInfo
# and, if Scripts/vendor-mediaremote.sh was run, the MediaRemote adapter under Resources/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# xcode-select on this machine points at the Command Line Tools; the macOS 27 SDK ships with Xcode.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
CONFIG="${CONFIG:-debug}"
# A stable identity keeps TCC grants (Accessibility, Automation) across rebuilds: TCC keys them on
# the bundle id plus the signing identity, and an ad-hoc signature changes with every build.
# Default: the first Apple Development certificate in the keychain.
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)}"

APP="$ROOT/build/NotchIsland.app"
ENTITLEMENTS="$ROOT/Support/NotchIsland.entitlements"
VENDOR="$ROOT/Vendor/MediaRemoteAdapter"

case "$CONFIG" in
  debug|release) ;;
  *) echo "error: CONFIG must be 'debug' or 'release' (got '$CONFIG')" >&2; exit 64 ;;
esac

cd "$ROOT"

echo "==> swift build -c $CONFIG"
xcrun swift build -c "$CONFIG" --product NotchIsland
BIN_DIR="$(xcrun swift build -c "$CONFIG" --show-bin-path)"

echo "==> assembling ${APP#"$ROOT"/}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NotchIsland" "$APP/Contents/MacOS/NotchIsland"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# Where diagnostics and bug reports go (About). Support/diagnostics-webhooks.json, written by
# Scripts/discord-setup.py, routes each kind to its channel; otherwise DIAGNOSTICS_WEBHOOK or the
# first line of Support/diagnostics-webhook.txt sends everything to one channel. Both files are
# git-ignored because the repository is public.
CONFIG_JSON="$ROOT/Support/diagnostics-webhooks.json"
WEBHOOK="${DIAGNOSTICS_WEBHOOK:-}"
if [[ -z "$WEBHOOK" && -f "$ROOT/Support/diagnostics-webhook.txt" ]]; then
  WEBHOOK="$(head -n 1 "$ROOT/Support/diagnostics-webhook.txt" | tr -d '[:space:]')"
fi
if [[ -f "$CONFIG_JSON" ]]; then
  plutil -insert NIDiagnosticsConfig -string "$(tr -d '\n' < "$CONFIG_JSON")" "$APP/Contents/Info.plist"
  echo "==> diagnostics: Discord channels from ${CONFIG_JSON#"$ROOT"/}"
elif [[ -n "$WEBHOOK" ]]; then
  /usr/libexec/PlistBuddy -c "Add :NIDiagnosticsWebhookURL string $WEBHOOK" "$APP/Contents/Info.plist"
  echo "==> diagnostics: one webhook (run Scripts/discord-setup.py for separate channels)"
else
  echo "    no diagnostics webhook: sending reports is disabled in this build"
fi
# Sentry and Mixpanel (crashes, errors, the health numbers; EU): Support/telemetry.json, git-ignored
# (Support/telemetry.example.json shows its keys). Without it the build sends no reports.
TELEMETRY_JSON="$ROOT/Support/telemetry.json"
if [[ -f "$TELEMETRY_JSON" ]]; then
  /usr/libexec/PlistBuddy -c "Add :NITelemetry dict" "$APP/Contents/Info.plist"
  for key in sentryDSN mixpanelToken mixpanelHost; do
    value="$(/usr/bin/plutil -extract "$key" raw -o - "$TELEMETRY_JSON" 2>/dev/null || true)"
    [[ -n "$value" ]] && /usr/libexec/PlistBuddy -c "Add :NITelemetry:$key string $value" "$APP/Contents/Info.plist"
  done
  /usr/libexec/PlistBuddy -c "Add :NITelemetry:environment string $CONFIG" "$APP/Contents/Info.plist"
  echo "==> telemetry: Sentry and Mixpanel from ${TELEMETRY_JSON#"$ROOT"/}"
else
  echo "    no Support/telemetry.json: this build sends no diagnostics reports"
fi
# The app's icon (Support/AppIcon.png, rendered to .icns): shown in Finder, the Dock and the DMG.
cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# The energy log and the performance tests behind it: every build and download carries them.
cp "$ROOT/docs/ENERGY-LOG.md" "$ROOT/docs/PERFORMANCE-TESTS.md" "$APP/Contents/Resources/"

if [[ -d "$VENDOR" ]]; then
  REVISION="$(head -n 1 "$VENDOR/REVISION" 2>/dev/null || echo 'unknown revision')"
  echo "==> bundling MediaRemote adapter ($REVISION)"
  cp -R "$VENDOR" "$APP/Contents/Resources/MediaRemoteAdapter"
else
  echo "    no Vendor/MediaRemoteAdapter: Now Playing will use Music and Spotify only"
  echo "    (run Scripts/vendor-mediaremote.sh to add every player)"
fi

echo "==> signing"
if security find-identity -v -p codesigning | grep -qF "\"$SIGN_ID\""; then
  IDENTITY="$SIGN_ID"
else
  IDENTITY="-"
  cat >&2 <<WARN

  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  !!  Signing identity not found:
  !!    $SIGN_ID
  !!  Falling back to AD-HOC signing. macOS treats every ad-hoc build as a new
  !!  app, so Accessibility and Automation grants are LOST on each rebuild.
  !!  Set SIGN_ID to an identity from: security find-identity -v -p codesigning
  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

WARN
fi

# Inside-out: nested frameworks first, then the bundle (whose seal covers them).
while IFS= read -r -d '' framework; do
  codesign --force --sign "$IDENTITY" --timestamp=none "$framework"
done < <(find "$APP/Contents/Resources" -maxdepth 2 -name '*.framework' -type d -print0)
codesign --force --sign "$IDENTITY" --timestamp=none --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict "$APP"

codesign -dv "$APP" 2>&1 | sed 's/^/    /'

# Symbols for Sentry: a release build's dSYM next to the app, uploaded when sentry-cli and a token
# are there (SENTRY_AUTH_TOKEN, or `sentry-cli login --url https://de.sentry.io` once, which keeps it
# in ~/.sentryclirc; org and project from Support/telemetry.json), so crashes read as NotchIsland's
# functions and lines.
if [[ "$CONFIG" == release ]]; then
  DSYM="$ROOT/build/NotchIsland.app.dSYM"
  rm -rf "$DSYM"
  dsymutil "$APP/Contents/MacOS/NotchIsland" -o "$DSYM" 2>/dev/null && echo "==> symbols: ${DSYM#"$ROOT"/}"
  if [[ -d "$DSYM" && ( -n "${SENTRY_AUTH_TOKEN:-}" || -f "$HOME/.sentryclirc" ) && -f "$TELEMETRY_JSON" ]] \
     && command -v sentry-cli >/dev/null; then
    ORG="$(/usr/bin/plutil -extract sentryOrg raw -o - "$TELEMETRY_JSON" 2>/dev/null || true)"
    PROJECT="$(/usr/bin/plutil -extract sentryProject raw -o - "$TELEMETRY_JSON" 2>/dev/null || true)"
    URL="$(/usr/bin/plutil -extract sentryURL raw -o - "$TELEMETRY_JSON" 2>/dev/null || echo https://de.sentry.io)"
    if [[ -n "$ORG" && -n "$PROJECT" ]]; then
      sentry-cli --url "$URL" debug-files upload --org "$ORG" --project "$PROJECT" "$DSYM" \
        && echo "==> symbols uploaded to Sentry ($ORG/$PROJECT)"
    fi
  fi
fi
echo "==> built ${APP#"$ROOT"/}"

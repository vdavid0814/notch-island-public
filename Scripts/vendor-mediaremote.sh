#!/bin/bash
# Optional: fetches and builds ungive/mediaremote-adapter (BSD-3-Clause) into
# Vendor/MediaRemoteAdapter, which Scripts/build.sh bundles into Resources/MediaRemoteAdapter.
#
# With it, Now Playing works for every player that reports to the system (Safari, browsers, VLC,
# IINA, …) without an Automation prompt, and artwork and position arrive with the metadata.
# Without it, NotchIsland reads Music and Spotify directly and ships no third-party code.
#
#   ADAPTER_REF=<tag or commit> Scripts/vendor-mediaremote.sh   reproducible build of that revision
#   Scripts/vendor-mediaremote.sh                               upstream default branch
#
# The resolved commit is written to Vendor/MediaRemoteAdapter/REVISION either way, and build.sh
# prints it, so every bundle says which adapter it contains.
# Builds with cmake when it is installed, otherwise directly with clang (same sources and flags).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${ADAPTER_REPO:-https://github.com/ungive/mediaremote-adapter.git}"
REF="${ADAPTER_REF:-}"
WORK="$ROOT/.build/mediaremote-src"
VENDOR="$ROOT/Vendor/MediaRemoteAdapter"

echo "==> fetching mediaremote-adapter ${REF:-(default branch)}"
rm -rf "$WORK"
mkdir -p "$WORK"
git -C "$WORK" init -q
git -C "$WORK" remote add origin "$REPO"
if [[ -n "$REF" ]]; then
  git -C "$WORK" fetch -q --depth 1 origin "$REF"
else
  git -C "$WORK" fetch -q --depth 1 origin HEAD
fi
git -C "$WORK" checkout -q --detach FETCH_HEAD
COMMIT="$(git -C "$WORK" rev-parse HEAD)"
echo "    commit $COMMIT"
if [[ -z "$REF" ]]; then
  echo "    tip: pin it with ADAPTER_REF=$COMMIT for reproducible builds"
fi

echo "==> building the framework"
if command -v cmake >/dev/null 2>&1; then
  cmake -S "$WORK" -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$WORK/build" --config Release
else
  # No cmake: build what CMakeLists.txt builds (the adapter framework only, not the test client).
  echo "    cmake not found, building with clang"
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
  FRAMEWORK="$WORK/build/MediaRemoteAdapter.framework"
  VERSION_DIR="$FRAMEWORK/Versions/A"
  mkdir -p "$VERSION_DIR/Resources" "$VERSION_DIR/Headers"
  SOURCES=()
  while IFS= read -r source; do SOURCES+=("$WORK/$source"); done < <(
    sed -n '/set(ADAPTER_SOURCES/,/)/p' "$WORK/CMakeLists.txt" | grep -o 'src/[^ )]*\.m'
  )
  # -fvisibility=default: the perl script looks the exported functions up by name.
  xcrun clang -dynamiclib -fobjc-arc -fvisibility=default -O2 -arch arm64 -arch x86_64 \
    -mmacosx-version-min=11.0 -I"$WORK/include" -I"$WORK/src" "${SOURCES[@]}" \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
    -o "$VERSION_DIR/MediaRemoteAdapter"
  cp "$WORK/include/MediaRemoteAdapter.h" "$VERSION_DIR/Headers/"
  cat > "$VERSION_DIR/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
  <key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
  <key>CFBundleName</key><string>MediaRemoteAdapter</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
</dict></plist>
PLIST
  ln -s A "$FRAMEWORK/Versions/Current"
  for item in MediaRemoteAdapter Resources Headers; do
    ln -s "Versions/Current/$item" "$FRAMEWORK/$item"
  done
  codesign --force --sign - "$FRAMEWORK"
fi

echo "==> installing into Vendor/MediaRemoteAdapter"
rm -rf "$VENDOR"
mkdir -p "$VENDOR"
cp -R "$WORK/build/MediaRemoteAdapter.framework" "$VENDOR/"
cp "$WORK/bin/mediaremote-adapter.pl" "$VENDOR/"
cp "$WORK/LICENSE" "$VENDOR/LICENSE"
# Line 1: the commit (machine-readable); line 2: where it came from.
printf '%s\n%s\n' "$COMMIT" "$REPO" > "$VENDOR/REVISION"

echo "==> smoke test"
if /usr/bin/perl "$VENDOR/mediaremote-adapter.pl" "$VENDOR/MediaRemoteAdapter.framework" get >/dev/null 2>&1; then
  echo "    adapter answers"
else
  echo "    adapter did not answer (nothing playing is a normal reason)"
fi

echo "==> done. Rebuild the app to bundle it: Scripts/build.sh"

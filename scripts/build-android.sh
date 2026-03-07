#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GO_DIR="$ROOT/go"
FLUTTER_APP="$ROOT/flutter-app"
DIST_DIR="$ROOT/dist"
APK_SRC="$FLUTTER_APP/build/app/outputs/flutter-apk/app-release.apk"
APK_DST="$DIST_DIR/piper-android.apk"

step() { echo; echo "==> $1"; }

step "Building Android native library (libpiper.so)"
"$GO_DIR/build_android.sh"

step "Building Flutter APK (release)"
(
  cd "$FLUTTER_APP"
  flutter build apk --release
)

step "Copying APK to dist/"
mkdir -p "$DIST_DIR"
cp -f "$APK_SRC" "$APK_DST"
echo "Done: $APK_DST"

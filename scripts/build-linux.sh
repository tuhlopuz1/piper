#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GO_DIR="$ROOT/go"
FLUTTER_APP="$ROOT/flutter-app"
BUNDLE_DIR="$FLUTTER_APP/build/linux/x64/release/bundle"
DIST_DIR="$ROOT/dist"
DIST_TAR="$DIST_DIR/piper-linux.tar.gz"

step() { echo; echo "==> $1"; }

step "Building Flutter Linux app (release)"
(
  cd "$FLUTTER_APP"
  flutter build linux --release
)

step "Building Linux native library (libpiper.so)"
mkdir -p "$BUNDLE_DIR/lib"
(
  cd "$GO_DIR"
  CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -buildmode=c-shared -o "$BUNDLE_DIR/lib/libpiper.so" ./ffi/
)

step "Packaging Linux bundle"
mkdir -p "$DIST_DIR"
tar -C "$BUNDLE_DIR" -czf "$DIST_TAR" .
echo "Done: $DIST_TAR"

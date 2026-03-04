#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "Building libpiper.so for Linux..."

CGO_ENABLED=1 go build -buildmode=c-shared \
  -o ../flutter-app/linux/bundle/lib/libpiper.so ./ffi/

echo "Done: flutter-app/linux/bundle/lib/libpiper.so"

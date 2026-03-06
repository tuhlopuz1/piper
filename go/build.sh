#!/bin/bash
set -e
cd "$(dirname "$0")"

# Default to Linux x64
ARCH="${1:-x64}"

case "$ARCH" in
    x64|amd64)
        echo "Building libpiper.so for Linux x64..."
        export CGO_ENABLED=1
        export GOOS=linux
        export GOARCH=amd64
        OUTPUT="../flutter-app/linux/bundle/lib/libpiper.so"
        ;;
    i686|386)
        echo "Building libpiper.so for Linux i686..."
        export CGO_ENABLED=1
        export GOOS=linux
        export GOARCH=386
        export CC=gcc
        export CGO_CFLAGS="-m32"
        export CGO_LDFLAGS="-m32"
        OUTPUT="../flutter-app/linux/bundle/lib/libpiper.so"
        ;;
    *)
        echo "Unknown architecture: $ARCH"
        echo "Usage: $0 [x64|i686]"
        exit 1
        ;;
esac

mkdir -p "$(dirname "$OUTPUT")"

go build -buildmode=c-shared \
  -o "$OUTPUT" ./ffi/

echo "Done: $OUTPUT"

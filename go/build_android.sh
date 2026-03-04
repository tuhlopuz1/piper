#!/bin/bash
# Cross-compile Go to Android arm64 and x86_64
# Prerequisites:
#   export ANDROID_NDK_HOME=/path/to/ndk  (NDK r25+)
set -e
cd "$(dirname "$0")"

if [ -z "$ANDROID_NDK_HOME" ]; then
  echo "ERROR: set ANDROID_NDK_HOME to your Android NDK path"
  exit 1
fi

TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"

# arm64-v8a
echo "Building arm64-v8a..."
mkdir -p ../flutter-app/android/app/src/main/jniLibs/arm64-v8a
CGO_ENABLED=1 GOOS=android GOARCH=arm64 \
  CC="$TOOLCHAIN/aarch64-linux-android21-clang" \
  go build -buildmode=c-shared \
  -o ../flutter-app/android/app/src/main/jniLibs/arm64-v8a/libpiper.so ./ffi/
echo "Done: jniLibs/arm64-v8a/libpiper.so"

# x86_64 (emulator)
echo "Building x86_64..."
mkdir -p ../flutter-app/android/app/src/main/jniLibs/x86_64
CGO_ENABLED=1 GOOS=android GOARCH=amd64 \
  CC="$TOOLCHAIN/x86_64-linux-android21-clang" \
  go build -buildmode=c-shared \
  -o ../flutter-app/android/app/src/main/jniLibs/x86_64/libpiper.so ./ffi/
echo "Done: jniLibs/x86_64/libpiper.so"

echo "Android build complete."

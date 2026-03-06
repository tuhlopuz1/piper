#!/bin/bash
set -e

# Piper Linux i686 (32-bit) Build Script
# Usage: ./scripts/build-linux-i686.sh [target]
# Targets: all (default), app, tar.gz, clean
#
# Note: Requires 32-bit build tools and libraries
# On Ubuntu/Debian: sudo apt-get install gcc-multilib g++-multilib

TARGET="${1:-all}"
ARCH="i686"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_APP="$ROOT/flutter-app"
GO_DIR="$ROOT/go"
DIST_DIR="$ROOT/dist"
BUILD_DIR="$FLUTTER_APP/build/linux"

function write_step() {
    echo ""
    echo "==> $1"
}

function write_ok() {
    echo "    OK: $1"
}

function write_warn() {
    echo "    WARN: $1"
}

function write_error() {
    echo "    ERROR: $1" >&2
}

# ── Check dependencies ────────────────────────────────────────────────────────
function check_deps() {
    write_step "Checking dependencies..."
    
    if ! command -v go &> /dev/null; then
        write_error "Go is not installed. Install from https://go.dev"
        exit 1
    fi
    
    if ! command -v flutter &> /dev/null; then
        write_error "Flutter is not installed. Install from https://flutter.dev"
        exit 1
    fi
    
    # Check for 32-bit build tools
    if ! command -v gcc &> /dev/null; then
        write_error "gcc is not installed. Install build-essential:"
        write_error "  Ubuntu/Debian: sudo apt-get install build-essential gcc-multilib"
        write_error "  Fedora: sudo dnf install gcc glibc-devel.i686"
        exit 1
    fi
    
    # Check if we can build 32-bit binaries
    if ! gcc -m32 -x c - -o /dev/null 2>/dev/null <<< "int main() { return 0; }"; then
        write_warn "32-bit build tools may not be available"
        write_warn "Install multilib support:"
        write_warn "  Ubuntu/Debian: sudo apt-get install gcc-multilib g++-multilib"
        write_warn "  Fedora: sudo dnf install glibc-devel.i686"
    fi
    
    write_ok "All dependencies found"
}

# ── Build Go FFI library ─────────────────────────────────────────────────────
function build_go_lib() {
    write_step "Building Go FFI library (libpiper.so) for Linux $ARCH..."
    cd "$GO_DIR"
    
    export CGO_ENABLED=1
    export GOOS=linux
    export GOARCH=386
    export CC=gcc
    export CGO_CFLAGS="-m32"
    export CGO_LDFLAGS="-m32"
    
    # Create bundle/lib directory if it doesn't exist
    mkdir -p "$FLUTTER_APP/linux/bundle/lib"
    
    go build -buildmode=c-shared \
        -o "$FLUTTER_APP/linux/bundle/lib/libpiper.so" \
        ./ffi/
    
    if [ $? -ne 0 ]; then
        write_error "Go build failed"
        write_error "Make sure 32-bit build tools are installed:"
        write_error "  Ubuntu/Debian: sudo apt-get install gcc-multilib g++-multilib"
        exit 1
    fi
    
    write_ok "libpiper.so -> flutter-app/linux/bundle/lib/"
}

# ── Build Flutter app ────────────────────────────────────────────────────────
function build_flutter() {
    write_step "Building Flutter Linux release (i686)..."
    cd "$FLUTTER_APP"
    
    # Flutter doesn't directly support 32-bit builds, but we can try
    # Note: Flutter Linux builds are typically 64-bit only
    # This may require manual configuration or cross-compilation setup
    write_warn "Flutter Linux builds are typically 64-bit only"
    write_warn "Building with default settings - verify architecture compatibility"
    
    flutter build linux --release
    
    if [ $? -ne 0 ]; then
        write_error "Flutter build failed"
        exit 1
    fi
    
    write_ok "piper -> flutter-app/build/linux/x64/release/bundle/"
    write_warn "Note: Flutter may have built x64. Verify the binary architecture."
}

# ── Create tar.gz archive ─────────────────────────────────────────────────────
function create_tarball() {
    write_step "Creating tar.gz archive..."
    
    mkdir -p "$DIST_DIR"
    
    BUNDLE_PATH="$BUILD_DIR/x64/release/bundle"
    
    if [ ! -d "$BUNDLE_PATH" ]; then
        write_error "Bundle not found at $BUNDLE_PATH"
        write_error "Run 'make linux-i686 app' first"
        exit 1
    fi
    
    TARBALL_PATH="$DIST_DIR/piper-linux-i686.tar.gz"
    
    # Remove old tarball if exists
    [ -f "$TARBALL_PATH" ] && rm "$TARBALL_PATH"
    
    cd "$BUNDLE_PATH"
    tar -czf "$TARBALL_PATH" .
    
    if [ $? -ne 0 ]; then
        write_error "Tarball creation failed"
        exit 1
    fi
    
    SIZE=$(du -h "$TARBALL_PATH" | cut -f1)
    write_ok "dist/piper-linux-i686.tar.gz ($SIZE)"
}

# ── Clean ─────────────────────────────────────────────────────────────────────
function clean() {
    write_step "Cleaning build artifacts..."
    rm -rf "$FLUTTER_APP/build/linux"
    rm -rf "$FLUTTER_APP/linux/bundle/lib/libpiper.so"
    rm -rf "$DIST_DIR/piper-linux-i686.tar.gz"
    write_ok "Cleaned."
}

# ── Entry point ───────────────────────────────────────────────────────────────
case "$TARGET" in
    all)
        check_deps
        build_go_lib
        build_flutter
        create_tarball
        echo ""
        echo "All done! See dist/"
        echo ""
        echo "NOTE: Flutter Linux builds are typically 64-bit only."
        echo "The Go library is built for i686, but Flutter binary may be x64."
        echo "For true 32-bit builds, you may need to configure Flutter manually."
        ;;
    app)
        check_deps
        build_go_lib
        build_flutter
        echo ""
        echo "App built! See flutter-app/build/linux/x64/release/bundle/"
        ;;
    tar.gz)
        create_tarball
        ;;
    clean)
        clean
        ;;
    *)
        echo "Unknown target: $TARGET"
        echo "Usage: $0 [all|app|tar.gz|clean]"
        exit 1
        ;;
esac

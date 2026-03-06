#!/bin/bash
set -e

# Piper macOS Build Script
# Usage: ./scripts/build-macos.sh [target]
# Targets: all (default), app, dmg, clean

TARGET="${1:-all}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_APP="$ROOT/flutter-app"
GO_DIR="$ROOT/go"
DIST_DIR="$ROOT/dist"
BUILD_DIR="$FLUTTER_APP/build/macos"

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
    
    if ! command -v create-dmg &> /dev/null; then
        write_warn "create-dmg not found. DMG creation will be skipped."
        write_warn "Install with: brew install create-dmg"
    fi
    
    write_ok "All dependencies found"
}

# ── Build Go FFI library ──────────────────────────────────────────────────────
function build_go_lib() {
    write_step "Building Go FFI library (libpiper.dylib)..."
    cd "$GO_DIR"
    
    export CGO_ENABLED=1
    export GOOS=darwin
    export GOARCH=amd64
    
    # Build to temporary location first
    TEMP_LIB="$GO_DIR/libpiper.dylib"
    
    go build -buildmode=c-shared \
        -o "$TEMP_LIB" \
        ./ffi/
    
    if [ $? -ne 0 ]; then
        write_error "Go build failed"
        exit 1
    fi
    
    write_ok "libpiper.dylib built"
}

# ── Build Flutter app ─────────────────────────────────────────────────────────
function build_flutter() {
    write_step "Building Flutter macOS release..."
    cd "$FLUTTER_APP"
    
    flutter build macos --release
    
    if [ $? -ne 0 ]; then
        write_error "Flutter build failed"
        exit 1
    fi
    
    # Copy Go library into app bundle
    APP_BUNDLE="$BUILD_DIR/Build/Products/Release/piper.app"
    if [ -d "$APP_BUNDLE" ]; then
        # Copy to Frameworks directory in app bundle
        mkdir -p "$APP_BUNDLE/Contents/Frameworks"
        cp "$GO_DIR/libpiper.dylib" "$APP_BUNDLE/Contents/Frameworks/libpiper.dylib"
        
        # Also copy to MacOS directory (Flutter may look there)
        mkdir -p "$APP_BUNDLE/Contents/MacOS"
        cp "$GO_DIR/libpiper.dylib" "$APP_BUNDLE/Contents/MacOS/libpiper.dylib"
        
        write_ok "libpiper.dylib copied to app bundle"
    fi
    
    write_ok "piper.app -> flutter-app/build/macos/Build/Products/Release/"
}

# ── Create DMG ────────────────────────────────────────────────────────────────
function create_dmg() {
    write_step "Creating DMG installer..."
    
    if ! command -v create-dmg &> /dev/null; then
        write_warn "create-dmg not available, skipping DMG creation"
        write_warn "Install with: brew install create-dmg"
        return
    fi
    
    mkdir -p "$DIST_DIR"
    
    APP_PATH="$BUILD_DIR/Build/Products/Release/piper.app"
    DMG_PATH="$DIST_DIR/piper-macos.dmg"
    
    if [ ! -d "$APP_PATH" ]; then
        write_error "App bundle not found at $APP_PATH"
        write_error "Run 'make macos app' first"
        exit 1
    fi
    
    # Remove old DMG if exists
    [ -f "$DMG_PATH" ] && rm "$DMG_PATH"
    
    create-dmg \
        --volname "Piper" \
        --volicon "$FLUTTER_APP/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "piper.app" 150 190 \
        --hide-extension "piper.app" \
        --app-drop-link 450 190 \
        "$DMG_PATH" \
        "$APP_PATH"
    
    if [ $? -ne 0 ]; then
        write_error "DMG creation failed"
        exit 1
    fi
    
    SIZE=$(du -h "$DMG_PATH" | cut -f1)
    write_ok "dist/piper-macos.dmg ($SIZE)"
}

# ── Clean ─────────────────────────────────────────────────────────────────────
function clean() {
    write_step "Cleaning build artifacts..."
    rm -rf "$FLUTTER_APP/build"
    rm -f "$GO_DIR/libpiper.dylib"
    rm -rf "$DIST_DIR/piper-macos.dmg"
    write_ok "Cleaned."
}

# ── Entry point ───────────────────────────────────────────────────────────────
case "$TARGET" in
    all)
        check_deps
        build_go_lib
        build_flutter
        create_dmg
        echo ""
        echo "All done! See dist/"
        ;;
    app)
        check_deps
        build_go_lib
        build_flutter
        echo ""
        echo "App built! See flutter-app/build/macos/Build/Products/Release/"
        ;;
    dmg)
        create_dmg
        ;;
    clean)
        clean
        ;;
    *)
        echo "Unknown target: $TARGET"
        echo "Usage: $0 [all|app|dmg|clean]"
        exit 1
        ;;
esac

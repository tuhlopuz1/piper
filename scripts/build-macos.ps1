# Cross-compile Piper for macOS from Windows
# Usage: .\scripts\build-macos.ps1 [target]
# Targets: lib (default), all, clean
#
# Note: Flutter cannot be cross-compiled from Windows to macOS.
# This script only builds the Go FFI library. For full macOS build,
# you need to run Flutter build on a macOS machine or use CI/CD.

param(
    [string]$Target = "lib"
)

$ErrorActionPreference = "Stop"

$Root       = Split-Path $PSScriptRoot -Parent
$GoDir      = Join-Path $Root "go"
$FlutterApp = Join-Path $Root "flutter-app"
$DistDir    = Join-Path $Root "dist"

function Write-Step([string]$msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}
function Write-OK([string]$msg) {
    Write-Host "    OK: $msg" -ForegroundColor Green
}
function Write-Warn([string]$msg) {
    Write-Host "    WARN: $msg" -ForegroundColor Yellow
}
function Write-Error([string]$msg) {
    Write-Host "    ERROR: $msg" -ForegroundColor Red
}

# ── Check dependencies ────────────────────────────────────────────────────────
function Check-Deps {
    Write-Step "Checking dependencies..."
    
    if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
        Write-Error "Go is not installed. Install from https://go.dev"
        exit 1
    }
    
    $goVersion = go version
    Write-OK "Found: $goVersion"
}

# ── Build Go FFI library for macOS ──────────────────────────────────────────
function Build-GoLib {
    Write-Step "Cross-compiling Go FFI library (libpiper.dylib) for macOS..."
    
    Push-Location $GoDir
    try {
        $env:CGO_ENABLED = "1"
        $env:GOOS = "darwin"
        $env:GOARCH = "amd64"
        
        # Note: CGO cross-compilation requires a macOS C compiler
        # For pure Go code, this works. For CGO, you may need:
        # - macOS SDK (not available on Windows)
        # - Or use osxcross toolchain
        # - Or build on macOS/CI
        
        $outputDir = Join-Path $FlutterApp "macos\Frameworks"
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
        $outputFile = Join-Path $outputDir "libpiper.dylib"
        
        Write-Host "    Building for darwin/amd64..."
        & go build -buildmode=c-shared -o $outputFile ".\ffi\"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Go build failed. CGO cross-compilation to macOS requires macOS SDK."
            Write-Warn "Options:"
            Write-Warn "  1. Build on macOS machine"
            Write-Warn "  2. Use osxcross toolchain (https://github.com/tpoechtrager/osxcross)"
            Write-Warn "  3. Use CI/CD (GitHub Actions, etc.)"
            throw "Go build failed (exit $LASTEXITCODE)"
        }
        
        Write-OK "libpiper.dylib -> flutter-app\macos\Frameworks\"
    }
    finally {
        $env:GOOS = ""
        $env:GOARCH = ""
        $env:CGO_ENABLED = ""
        Pop-Location
    }
}

# ── Build Go FFI library for macOS ARM64 (Apple Silicon) ───────────────────
function Build-GoLibARM64 {
    Write-Step "Cross-compiling Go FFI library (libpiper.dylib) for macOS ARM64..."
    
    Push-Location $GoDir
    try {
        $env:CGO_ENABLED = "1"
        $env:GOOS = "darwin"
        $env:GOARCH = "arm64"
        
        $outputDir = Join-Path $FlutterApp "macos\Frameworks"
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
        $outputFile = Join-Path $outputDir "libpiper-arm64.dylib"
        
        Write-Host "    Building for darwin/arm64..."
        & go build -buildmode=c-shared -o $outputFile ".\ffi\"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Go build failed for ARM64. CGO cross-compilation requires macOS SDK."
            return
        }
        
        Write-OK "libpiper-arm64.dylib -> flutter-app\macos\Frameworks\"
    }
    finally {
        $env:GOOS = ""
        $env:GOARCH = ""
        $env:CGO_ENABLED = ""
        Pop-Location
    }
}

# ── Create distribution package info ────────────────────────────────────────
function Create-Info {
    Write-Step "Creating build info..."
    
    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
    
    $infoFile = Join-Path $DistDir "macos-build-info.txt"
    @"
Piper macOS Cross-Compilation Build Info
=========================================
Build Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Build Platform: Windows
Target Platform: macOS

Go Library Status:
- libpiper.dylib (amd64): $(if (Test-Path "$FlutterApp\macos\Frameworks\libpiper.dylib") { "Built" } else { "Not built" })
- libpiper-arm64.dylib: $(if (Test-Path "$FlutterApp\macos\Frameworks\libpiper-arm64.dylib") { "Built" } else { "Not built" })

Next Steps:
1. Copy the Go library to your macOS build machine
2. Run Flutter build on macOS:
   cd flutter-app
   flutter build macos --release
3. Or use CI/CD (GitHub Actions with macos-latest runner)

Note: CGO cross-compilation to macOS from Windows requires macOS SDK,
which is not available on Windows. For full builds, use macOS or CI/CD.
"@ | Out-File -FilePath $infoFile -Encoding UTF8
    
    Write-OK "Build info saved to dist\macos-build-info.txt"
}

# ── Clean ────────────────────────────────────────────────────────────────────
function Clean {
    Write-Step "Cleaning macOS build artifacts..."
    Remove-Item -Recurse -Force (Join-Path $FlutterApp "macos\Frameworks\libpiper*.dylib") -ErrorAction SilentlyContinue
    Remove-Item -Force (Join-Path $DistDir "macos-build-info.txt") -ErrorAction SilentlyContinue
    Write-OK "Cleaned."
}

# ── Entry point ───────────────────────────────────────────────────────────────
switch ($Target.ToLower()) {
    "lib" {
        Check-Deps
        Build-GoLib
        Create-Info
        Write-Host ""
        Write-Host "Go library built! See flutter-app\macos\Frameworks\" -ForegroundColor Green
        Write-Host "For full macOS build, run Flutter on macOS or use CI/CD." -ForegroundColor Yellow
    }
    "lib-arm64" {
        Check-Deps
        Build-GoLibARM64
        Create-Info
    }
    "all" {
        Check-Deps
        Build-GoLib
        Build-GoLibARM64
        Create-Info
        Write-Host ""
        Write-Host "All libraries built! See flutter-app\macos\Frameworks\" -ForegroundColor Green
    }
    "clean" {
        Clean
    }
    default {
        Write-Host "Unknown target: $Target" -ForegroundColor Red
        Write-Host "Usage: .\scripts\build-macos.ps1 [lib|lib-arm64|all|clean]"
        exit 1
    }
}

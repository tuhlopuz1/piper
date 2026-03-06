# Cross-compile Piper for Linux x64 from Windows
# Usage: .\scripts\build-linux.ps1 [target]
# Targets: lib (default), all, clean
#
# Note: Flutter Linux builds require Linux environment.
# This script builds the Go FFI library. For full Linux build,
# use WSL, Docker, or CI/CD.

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
    
    # Check for gcc (for CGO)
    # On Windows, we can use MinGW or WSL
    $gccPath = $null
    if (Get-Command gcc -ErrorAction SilentlyContinue) {
        $gccPath = (Get-Command gcc).Source
        Write-OK "Found GCC: $gccPath"
    } else {
        Write-Warn "GCC not found in PATH. CGO builds may fail."
        Write-Warn "Options:"
        Write-Warn "  1. Install MinGW: choco install mingw"
        Write-Warn "  2. Use WSL for full Linux builds"
        Write-Warn "  3. Use Docker for Linux builds"
    }
}

# ── Build Go FFI library for Linux x64 ───────────────────────────────────────
function Build-GoLib {
    Write-Step "Cross-compiling Go FFI library (libpiper.so) for Linux x64..."
    
    Push-Location $GoDir
    try {
        $env:CGO_ENABLED = "1"
        $env:GOOS = "linux"
        $env:GOARCH = "amd64"
        
        # For CGO cross-compilation, we need a Linux C compiler
        # Options:
        # 1. Use WSL (Windows Subsystem for Linux)
        # 2. Use Docker
        # 3. Use a Linux cross-compiler (like from MinGW-w64 or TDM-GCC)
        
        # Try to detect if we're in WSL
        $isWSL = $false
        if (Test-Path "/proc/version") {
            $procVersion = Get-Content "/proc/version" -Raw
            if ($procVersion -match "Microsoft|WSL") {
                $isWSL = $true
                Write-OK "Detected WSL environment"
            }
        }
        
        $outputDir = Join-Path $FlutterApp "linux\bundle\lib"
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
        $outputFile = Join-Path $outputDir "libpiper.so"
        
        Write-Host "    Building for linux/amd64..."
        
        # Set CC if available
        if ($isWSL -and (Get-Command gcc -ErrorAction SilentlyContinue)) {
            $env:CC = "gcc"
            Write-Host "    Using GCC from WSL"
        }
        
        & go build -buildmode=c-shared -o $outputFile ".\ffi\"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Go build failed. CGO cross-compilation to Linux requires Linux C compiler."
            Write-Warn "Options:"
            Write-Warn "  1. Use WSL: wsl bash scripts/build-linux.sh"
            Write-Warn "  2. Use Docker: docker run -v ${PWD}:/app -w /app golang:latest bash scripts/build-linux.sh"
            Write-Warn "  3. Use CI/CD (GitHub Actions with ubuntu-latest runner)"
            throw "Go build failed (exit $LASTEXITCODE)"
        }
        
        Write-OK "libpiper.so -> flutter-app\linux\bundle\lib\"
    }
    finally {
        $env:GOOS = ""
        $env:GOARCH = ""
        $env:CGO_ENABLED = ""
        $env:CC = ""
        Pop-Location
    }
}

# ── Create distribution package info ────────────────────────────────────────
function Create-Info {
    Write-Step "Creating build info..."
    
    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
    
    $infoFile = Join-Path $DistDir "linux-build-info.txt"
    @"
Piper Linux Cross-Compilation Build Info
=========================================
Build Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Build Platform: Windows
Target Platform: Linux x64

Go Library Status:
- libpiper.so (amd64): $(if (Test-Path "$FlutterApp\linux\bundle\lib\libpiper.so") { "Built" } else { "Not built" })

Next Steps:
1. Copy the Go library to your Linux build machine
2. Run Flutter build on Linux:
   cd flutter-app
   flutter build linux --release
3. Or use WSL:
   wsl bash scripts/build-linux.sh
4. Or use Docker:
   docker run -v `$(pwd):/app -w /app golang:latest bash scripts/build-linux.sh
5. Or use CI/CD (GitHub Actions with ubuntu-latest runner)

Note: CGO cross-compilation to Linux from Windows requires Linux C compiler.
For full builds, use WSL, Docker, or CI/CD.
"@ | Out-File -FilePath $infoFile -Encoding UTF8
    
    Write-OK "Build info saved to dist\linux-build-info.txt"
}

# ── Clean ────────────────────────────────────────────────────────────────────
function Clean {
    Write-Step "Cleaning Linux build artifacts..."
    Remove-Item -Recurse -Force (Join-Path $FlutterApp "linux\bundle\lib\libpiper.so") -ErrorAction SilentlyContinue
    Remove-Item -Force (Join-Path $DistDir "linux-build-info.txt") -ErrorAction SilentlyContinue
    Write-OK "Cleaned."
}

# ── Entry point ───────────────────────────────────────────────────────────────
switch ($Target.ToLower()) {
    "lib" {
        Check-Deps
        Build-GoLib
        Create-Info
        Write-Host ""
        Write-Host "Go library built! See flutter-app\linux\bundle\lib\" -ForegroundColor Green
        Write-Host "For full Linux build, use WSL, Docker, or CI/CD." -ForegroundColor Yellow
    }
    "all" {
        Check-Deps
        Build-GoLib
        Create-Info
        Write-Host ""
        Write-Host "Library built! See flutter-app\linux\bundle\lib\" -ForegroundColor Green
    }
    "clean" {
        Clean
    }
    default {
        Write-Host "Unknown target: $Target" -ForegroundColor Red
        Write-Host "Usage: .\scripts\build-linux.ps1 [lib|all|clean]"
        exit 1
    }
}

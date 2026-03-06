# Cross-compile Piper for Linux i686 (32-bit) from Windows
# Usage: .\scripts\build-linux-i686.ps1 [target]
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
    $gccPath = $null
    if (Get-Command gcc -ErrorAction SilentlyContinue) {
        $gccPath = (Get-Command gcc).Source
        Write-OK "Found GCC: $gccPath"
    } else {
        Write-Warn "GCC not found in PATH. CGO builds may fail."
        Write-Warn "32-bit cross-compilation requires multilib support."
    }
}

# ── Build Go FFI library for Linux i686 ───────────────────────────────────────
function Build-GoLib {
    Write-Step "Cross-compiling Go FFI library (libpiper.so) for Linux i686..."
    
    Push-Location $GoDir
    try {
        $env:CGO_ENABLED = "1"
        $env:GOOS = "linux"
        $env:GOARCH = "386"
        
        # For 32-bit CGO cross-compilation, we need a 32-bit Linux C compiler
        # This is best done in WSL or Docker with multilib support
        
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
        
        Write-Host "    Building for linux/386..."
        
        # Set CC with -m32 flag for 32-bit builds
        if ($isWSL -and (Get-Command gcc -ErrorAction SilentlyContinue)) {
            $env:CC = "gcc"
            $env:CGO_CFLAGS = "-m32"
            $env:CGO_LDFLAGS = "-m32"
            Write-Host "    Using GCC with -m32 flag"
        }
        
        & go build -buildmode=c-shared -o $outputFile ".\ffi\"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Go build failed. 32-bit CGO cross-compilation requires Linux C compiler with multilib."
            Write-Warn "Options:"
            Write-Warn "  1. Use WSL with multilib:"
            Write-Warn "     sudo apt-get install gcc-multilib g++-multilib"
            Write-Warn "     wsl bash scripts/build-linux-i686.sh"
            Write-Warn "  2. Use Docker with multilib support"
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
        $env:CGO_CFLAGS = ""
        $env:CGO_LDFLAGS = ""
        Pop-Location
    }
}

# ── Create distribution package info ────────────────────────────────────────
function Create-Info {
    Write-Step "Creating build info..."
    
    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
    
    $infoFile = Join-Path $DistDir "linux-i686-build-info.txt"
    @"
Piper Linux i686 Cross-Compilation Build Info
==============================================
Build Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Build Platform: Windows
Target Platform: Linux i686 (32-bit)

Go Library Status:
- libpiper.so (i686): $(if (Test-Path "$FlutterApp\linux\bundle\lib\libpiper.so") { "Built" } else { "Not built" })

Next Steps:
1. Copy the Go library to your Linux build machine
2. Run Flutter build on Linux (note: Flutter Linux is typically 64-bit only)
3. Or use WSL with multilib:
   sudo apt-get install gcc-multilib g++-multilib
   wsl bash scripts/build-linux-i686.sh
4. Or use Docker with multilib support
5. Or use CI/CD (GitHub Actions with ubuntu-latest runner)

Note: 
- CGO cross-compilation to Linux i686 requires Linux C compiler with multilib support
- Flutter Linux builds are typically 64-bit only
- For full 32-bit builds, you may need to configure Flutter manually or use native Linux build
"@ | Out-File -FilePath $infoFile -Encoding UTF8
    
    Write-OK "Build info saved to dist\linux-i686-build-info.txt"
}

# ── Clean ────────────────────────────────────────────────────────────────────
function Clean {
    Write-Step "Cleaning Linux i686 build artifacts..."
    Remove-Item -Recurse -Force (Join-Path $FlutterApp "linux\bundle\lib\libpiper.so") -ErrorAction SilentlyContinue
    Remove-Item -Force (Join-Path $DistDir "linux-i686-build-info.txt") -ErrorAction SilentlyContinue
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
        Write-Host "Note: Flutter Linux builds are typically 64-bit only." -ForegroundColor Yellow
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
        Write-Host "Usage: .\scripts\build-linux-i686.ps1 [lib|all|clean]"
        exit 1
    }
}

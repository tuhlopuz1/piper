# Build Piper for Android and produce a release APK.
#
# Requirements:
#   1. Android NDK r21+ installed via Android Studio
#      (SDK Manager -> SDK Tools -> NDK (Side by side))
#   2. ANDROID_NDK_HOME set, OR NDK auto-detected from %LOCALAPPDATA%\Android\Sdk\ndk\
#   3. Flutter SDK in PATH
#   4. Go 1.21+ in PATH
#
# Usage:  make android

$ErrorActionPreference = "Stop"

$Root       = Split-Path $PSScriptRoot -Parent
$GoDir      = Join-Path $Root "go"
$FlutterApp = Join-Path $Root "flutter-app"

function Step($msg)  { Write-Host "" ; Write-Host "==> $msg" -ForegroundColor Cyan }
function OK($msg)    { Write-Host "    OK: $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "    WARN: $msg" -ForegroundColor Yellow }
function Fail($msg)  { Write-Host "ERROR: $msg" -ForegroundColor Red ; exit 1 }

# Locate NDK
$NDK = $env:ANDROID_NDK_HOME
if (-not $NDK) {
    if ($env:ANDROID_SDK_ROOT) {
        $sdkRoot = $env:ANDROID_SDK_ROOT
    } else {
        $sdkRoot = "$env:LOCALAPPDATA\Android\Sdk"
    }
    $ndkDir = Join-Path $sdkRoot "ndk"
    if (Test-Path $ndkDir) {
        $NDK = Get-ChildItem $ndkDir -Directory |
               Sort-Object Name -Descending |
               Select-Object -First 1 -ExpandProperty FullName
    }
}

if (-not $NDK) {
    Fail "Android NDK not found. Set ANDROID_NDK_HOME or install NDK via Android Studio."
}
if (-not (Test-Path $NDK)) {
    Fail "NDK path does not exist: $NDK"
}

Step "Using NDK: $NDK"

$ToolchainBin = Join-Path $NDK "toolchains\llvm\prebuilt\windows-x86_64\bin"

# ABI list: goarch, clang prefix, jniLibs folder name
$abiList = @(
    "arm64|aarch64-linux-android21-clang|arm64-v8a",
    "amd64|x86_64-linux-android21-clang|x86_64"
)

Step "Cross-compiling libpiper.so for Android..."

foreach ($entry in $abiList) {
    $parts   = $entry.Split("|")
    $goarch  = $parts[0]
    $clang   = $parts[1]
    $jniDir  = $parts[2]

    $cc      = Join-Path $ToolchainBin "$clang.cmd"
    $cxxName = ($clang -replace "clang$", "clang++") + ".cmd"
    $cxx     = Join-Path $ToolchainBin $cxxName
    $outDir  = Join-Path $FlutterApp "android\app\src\main\jniLibs\$jniDir"
    $outFile = Join-Path $outDir "libpiper.so"

    if (-not (Test-Path $cc)) {
        Warn "Clang not found: $cc -- skipping $jniDir"
        continue
    }

    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    Push-Location $GoDir
    try {
        $env:CGO_ENABLED = "1"
        $env:GOOS        = "android"
        $env:GOARCH      = $goarch
        $env:CC          = $cc
        $env:CXX         = $cxx

        Write-Host "    Building $jniDir (GOARCH=$goarch)..."
        & go build -buildmode=c-shared -o $outFile ".\ffi\"
        if ($LASTEXITCODE -ne 0) {
            throw "Go build failed for $jniDir (exit $LASTEXITCODE)"
        }
        OK "$jniDir\libpiper.so"
    }
    finally {
        $env:GOOS        = ""
        $env:GOARCH      = ""
        $env:CC          = ""
        $env:CXX         = ""
        $env:CGO_ENABLED = "1"
        Pop-Location
    }
}

# Flutter APK
Step "Building Flutter APK (release)..."
Push-Location $FlutterApp
try {
    & flutter build apk --release
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build apk failed (exit $LASTEXITCODE)"
    }
}
finally {
    Pop-Location
}

# Copy to dist/
$apk  = Join-Path $FlutterApp "build\app\outputs\flutter-apk\app-release.apk"
$dist = Join-Path $Root "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$dest = Join-Path $dist "piper-android.apk"
Copy-Item $apk $dest -Force

$sizeMB = [math]::Round((Get-Item $dest).Length / 1MB, 1)
OK "dist\piper-android.apk ($sizeMB MB)"
Write-Host ""
Write-Host "Done! To install on a connected device:" -ForegroundColor Green
Write-Host "  adb install dist\piper-android.apk"

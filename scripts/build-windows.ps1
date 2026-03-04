param(
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"

$Root        = Split-Path $PSScriptRoot -Parent
$FlutterApp  = Join-Path $Root "flutter-app"
$GoDir       = Join-Path $Root "go"
$InstallerDir= Join-Path $Root "installer"
$DistDir     = Join-Path $Root "dist"
$Release     = Join-Path $FlutterApp "build\windows\x64\runner\Release"
$ISCC        = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

function Write-Step([string]$msg) {
    Write-Host "`n==> $msg" -ForegroundColor Cyan
}
function Write-OK([string]$msg) {
    Write-Host "    OK: $msg" -ForegroundColor Green
}
function Write-Warn([string]$msg) {
    Write-Host "    WARN: $msg" -ForegroundColor Yellow
}

# ── Go DLL ────────────────────────────────────────────────────────────────────
function Build-DLL {
    Write-Step "Building Go DLL (libpiper.dll)..."
    Push-Location $GoDir
    try {
        $env:CGO_ENABLED = "1"
        $env:PATH = "C:\ProgramData\mingw64\mingw64\bin;$env:PATH"
        go build -buildmode=c-shared `
            -o "..\flutter-app\windows\runner\libpiper.dll" `
            ".\ffi\"
        if ($LASTEXITCODE -ne 0) { throw "Go build failed (exit $LASTEXITCODE)" }
        Write-OK "libpiper.dll -> flutter-app\windows\runner\"
    } finally {
        Pop-Location
    }
}

# ── Flutter release ───────────────────────────────────────────────────────────
function Build-Flutter {
    Write-Step "Building Flutter release..."
    Push-Location $FlutterApp
    try {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "Flutter build failed (exit $LASTEXITCODE)" }
        Write-OK "piper.exe -> flutter-app\build\windows\x64\runner\Release\"
    } finally {
        Pop-Location
    }
}

# ── Inno Setup installer ──────────────────────────────────────────────────────
function Build-Installer {
    Write-Step "Building installer (piper-setup.exe)..."
    if (-not (Test-Path $ISCC)) {
        Write-Warn "Inno Setup not found at: $ISCC"
        Write-Warn "Install with: choco install innosetup -y"
        Write-Warn "Skipping installer target."
        return
    }
    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
    & $ISCC (Join-Path $InstallerDir "piper.iss")
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed (exit $LASTEXITCODE)" }
    $size = [math]::Round((Get-Item (Join-Path $DistDir "piper-setup.exe")).Length / 1MB, 1)
    Write-OK "dist\piper-setup.exe ($size MB)"
}

# ── ZIP archive ───────────────────────────────────────────────────────────────
function Build-Zip {
    Write-Step "Building ZIP archive (piper-windows.zip)..."
    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
    $ZipPath = Join-Path $DistDir "piper-windows.zip"
    if (Test-Path $ZipPath) { Remove-Item $ZipPath }
    Compress-Archive -Path "$Release\*" -DestinationPath $ZipPath
    $size = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
    Write-OK "dist\piper-windows.zip ($size MB)"
}

# ── Clean ─────────────────────────────────────────────────────────────────────
function Clean {
    Write-Step "Cleaning build artifacts..."
    Remove-Item -Recurse -Force (Join-Path $FlutterApp "build") -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $DistDir -ErrorAction SilentlyContinue
    Write-OK "Cleaned."
}

# ── Entry point ───────────────────────────────────────────────────────────────
switch ($Target.ToLower()) {
    "all" {
        Build-DLL
        Build-Flutter
        Build-Installer
        Build-Zip
        Write-Host "`nAll done! See dist\" -ForegroundColor Green
    }
    "installer" {
        Build-DLL
        Build-Flutter
        Build-Installer
    }
    "zip" {
        Build-DLL
        Build-Flutter
        Build-Zip
    }
    "package" {
        # Only packaging steps — assumes flutter already built
        Build-Installer
        Build-Zip
    }
    "clean" { Clean }
    default  { Write-Host "Unknown target: $Target. Use: all | installer | zip | package | clean" -ForegroundColor Red }
}

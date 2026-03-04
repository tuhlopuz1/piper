@echo off
cd /d "%~dp0"
echo Building libpiper.dll for Windows...

set CGO_ENABLED=1
go build -buildmode=c-shared -o ..\flutter-app\windows\runner\libpiper.dll .\ffi\

if %errorlevel% equ 0 (
    echo Done: flutter-app\windows\runner\libpiper.dll
) else (
    echo FAILED. Make sure MinGW gcc is on PATH.
    echo Run: choco install mingw
    exit /b 1
)

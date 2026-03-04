@echo off
set CGO_ENABLED=1
set PATH=C:\ProgramData\mingw64\mingw64\bin;%PATH%
cd /d "%~dp0"
go build -buildmode=c-shared -o ..\flutter-app\windows\runner\libpiper.dll .\ffi\ 2>&1
echo Exit: %errorlevel%

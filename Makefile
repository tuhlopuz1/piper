# Piper — Build System
# Usage (from project root):
#   make                  → build for current platform
#   make windows          → build Windows (installer + zip)
#   make macos            → cross-compile macOS Go library (Windows) or full build (macOS)
#   make linux            → cross-compile Linux x64 Go library (Windows) or full build (Linux)
#   make linux-i686       → cross-compile Linux i686 Go library (Windows) or full build (Linux)
#   make android          → build Android APK
#   make clean            → delete all build artifacts
#
# Platform-specific targets:
#   Windows: installer, zip, package
#   macOS: dmg, app (on macOS) or lib (cross-compile from Windows)
#   Linux: tar.gz, app (on Linux) or lib (cross-compile from Windows)
#
# Note: On Windows, macOS/Linux targets only build Go FFI libraries.
#       For full Flutter builds, use WSL, Docker, or CI/CD.

UNAME_S := $(shell uname -s 2>/dev/null || echo "Windows")
PS := powershell -NoProfile -ExecutionPolicy Bypass -File

.PHONY: all windows macos linux linux-i686 android clean installer zip package dmg app

# Detect platform and build accordingly
all:
ifeq ($(UNAME_S),Linux)
	@echo "Detected Linux, building for x64..."
	@bash scripts/build-linux.sh
else ifeq ($(UNAME_S),Darwin)
	@echo "Detected macOS, building..."
	@bash scripts/build-macos.sh
else
	@echo "Detected Windows, building..."
	$(PS) scripts\build-windows.ps1 -Target all
	$(PS) scripts\build-android.ps1
endif

# Windows targets
windows:
	$(PS) scripts\build-windows.ps1 -Target all

installer:
ifeq ($(IS_WINDOWS),1)
	$(PS) scripts\build-windows.ps1 -Target installer
else
	@echo "installer target is only supported on Windows."
	@echo "From WSL/Linux use: make linux"
endif

zip:
ifeq ($(IS_WINDOWS),1)
	$(PS) scripts\build-windows.ps1 -Target zip
else
	@echo "zip target is only supported on Windows."
endif

package:
ifeq ($(IS_WINDOWS),1)
	$(PS) scripts\build-windows.ps1 -Target package
else
	@echo "package target is only supported on Windows."
endif

# macOS targets (cross-compile from Windows)
macos:
ifeq ($(UNAME_S),Windows)
	$(PS) scripts\build-macos.ps1
else
	@bash scripts/build-macos.sh
endif

dmg:
ifeq ($(UNAME_S),Windows)
	$(PS) scripts\build-macos.ps1 all
else
	@bash scripts/build-macos.sh dmg
endif

app:
ifeq ($(UNAME_S),Windows)
	$(PS) scripts\build-macos.ps1 lib
else
	@bash scripts/build-macos.sh app
endif

# Linux targets (cross-compile from Windows)
linux:
ifeq ($(UNAME_S),Windows)
	$(PS) scripts\build-linux.ps1
else
	@bash scripts/build-linux.sh
endif

linux-i686:
ifeq ($(UNAME_S),Windows)
	$(PS) scripts\build-linux-i686.ps1
else
	@bash scripts/build-linux-i686.sh
endif

# Android target
android:
ifeq ($(IS_WINDOWS),1)
	$(PS) scripts\build-android.ps1
else
	bash scripts/build-android.sh
endif

linux:
ifeq ($(IS_WINDOWS),1)
	@echo "Run Linux build target from WSL:"
	@echo "  wsl make linux"
else
	bash scripts/build-linux.sh
endif

# Clean all build artifacts
clean:
ifeq ($(UNAME_S),Linux)
	@bash scripts/build-linux.sh clean
	@bash scripts/build-linux-i686.sh clean
else ifeq ($(UNAME_S),Darwin)
	@bash scripts/build-macos.sh clean
else
	$(PS) scripts\build-windows.ps1 -Target clean
	$(PS) scripts\build-macos.ps1 clean
	$(PS) scripts\build-linux.ps1 clean
	$(PS) scripts\build-linux-i686.ps1 clean
endif

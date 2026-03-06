# Piper — Build System
# Usage (from project root):
#   make                  → build installer + android
#   make installer        → installer EXE only (Windows)
#   make zip              → portable ZIP only (Windows)
#   make package          → repackage without rebuilding Flutter (Windows)
#   make android          → Android release APK
#   make linux            → Linux release build (run inside WSL/Linux shell)
#   make clean            → delete build artifacts

PS := powershell -NoProfile -ExecutionPolicy Bypass -File

ifeq ($(OS),Windows_NT)
IS_WINDOWS := 1
else
IS_WINDOWS := 0
endif

all:
	$(PS) scripts\build-windows.ps1 -Target all
	$(PS) scripts\build-android.ps1

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

clean:
ifeq ($(IS_WINDOWS),1)
	$(PS) scripts\build-windows.ps1 -Target clean
else
	rm -rf flutter-app/build dist
endif

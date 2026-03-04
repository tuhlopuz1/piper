# Piper — Build System
# Usage (from project root):
#   make                  → build everything (installer + zip)
#   make installer        → installer EXE only
#   make zip              → portable ZIP only
#   make package          → repackage without rebuilding Flutter
#   make clean            → delete all build artifacts

PS := powershell -NoProfile -ExecutionPolicy Bypass -File

.PHONY: all installer zip package android clean

all:
	$(PS) scripts\build-windows.ps1 -Target all

installer:
	$(PS) scripts\build-windows.ps1 -Target installer

zip:
	$(PS) scripts\build-windows.ps1 -Target zip

package:
	$(PS) scripts\build-windows.ps1 -Target package

android:
	$(PS) scripts\build-android.ps1

clean:
	$(PS) scripts\build-windows.ps1 -Target clean

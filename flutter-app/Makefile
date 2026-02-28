GO_SRC   := ./go
OUT      := assets/daemon

.PHONY: daemon daemon-windows daemon-linux daemon-android flutter-run flutter-apk flutter-windows clean

# ── Go daemon builds ──────────────────────────────────────────────────────────

daemon-windows:
	cd $(GO_SRC) && GOOS=windows GOARCH=amd64 go build -o "$(CURDIR)/$(OUT)/piper-daemon-windows-amd64.exe" .

daemon-linux:
	cd $(GO_SRC) && GOOS=linux GOARCH=amd64 go build -o "$(CURDIR)/$(OUT)/piper-daemon-linux-amd64" .

daemon-android:
	cd $(GO_SRC) && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o "$(CURDIR)/$(OUT)/piper-daemon-android-arm64" .

# Build all platform daemons at once
daemon: daemon-windows daemon-linux daemon-android

# ── Flutter builds (requires daemon binaries) ─────────────────────────────────

flutter-apk: daemon-android
	flutter build apk --release

flutter-windows: daemon-windows
	flutter build windows --release

flutter-linux: daemon-linux
	flutter build linux --release

# ── Dev helpers ───────────────────────────────────────────────────────────────

# Run Go daemon in dev mode (Flutter connects to it automatically)
daemon-run:
	cd go && go run .

# Run Flutter with hot-reload (daemon must be running separately via make daemon-run)
flutter-run:
	flutter run

clean:
	rm -f $(OUT)/piper-daemon-*

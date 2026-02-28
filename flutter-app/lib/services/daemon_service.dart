import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Manages the lifecycle of the Go daemon process.
/// On startup it extracts the platform-specific binary from Flutter assets,
/// launches it, reads the `PORT=<n>` line from stdout, and exposes the port.
class DaemonService {
  static final DaemonService instance = DaemonService._();
  DaemonService._();

  Process? _process;
  int? _port;

  int? get port => _port;
  bool get isRunning => _process != null;

  /// Starts the daemon with the given display [name].
  /// Returns the localhost port the daemon is listening on.
  /// Throws if the binary is missing or the daemon fails to start.
  Future<int> start({required String name}) async {
    if (_process != null) return _port!;

    final binaryName = _binaryName();
    if (binaryName == null) {
      throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
    }

    // Extract binary from Flutter assets to app support directory
    final binaryPath = await _extractBinary(binaryName);

    debugPrint('[daemon] launching $binaryPath');
    _process = await Process.start(binaryPath, ['--name', name]);

    // Read PORT= from stdout
    final completer = Completer<int>();
    _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      debugPrint('[daemon:out] $line');
      if (!completer.isCompleted && line.startsWith('PORT=')) {
        final port = int.tryParse(line.substring(5));
        if (port != null) completer.complete(port);
      }
    });

    _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => debugPrint('[daemon:err] $line'));

    _process!.exitCode.then((code) {
      debugPrint('[daemon] exited with code $code');
      _process = null;
      _port = null;
    });

    _port = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Daemon did not start in time'),
    );

    debugPrint('[daemon] ready on port $_port');
    return _port!;
  }

  void stop() {
    _process?.kill();
    _process = null;
    _port = null;
  }

  // ── private ──────────────────────────────────────────────────────────────

  String? _binaryName() {
    if (Platform.isWindows) return 'piper-daemon-windows-amd64.exe';
    if (Platform.isLinux) return 'piper-daemon-linux-amd64';
    if (Platform.isAndroid) return 'piper-daemon-android-arm64';
    return null;
  }

  Future<String> _extractBinary(String name) async {
    final appDir = await getApplicationSupportDirectory();
    final daemonDir = Directory('${appDir.path}/daemon');
    await daemonDir.create(recursive: true);
    final file = File('${daemonDir.path}/$name');

    // Always overwrite to pick up updates bundled in new app versions
    final data = await rootBundle.load('assets/daemon/$name');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);

    // Set executable bit on non-Windows
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', file.path]);
    }

    return file.path;
  }
}

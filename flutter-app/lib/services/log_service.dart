import 'package:flutter/foundation.dart';

enum LogLevel { info, warning, error }

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String message;
  final String? detail; // stack trace or extra context

  LogEntry({
    required this.time,
    required this.level,
    required this.message,
    this.detail,
  });
}

/// In-memory log collector. Hooks into debugPrint and FlutterError so all
/// framework output is captured automatically.
class LogService extends ChangeNotifier {
  LogService._();
  static final LogService instance = LogService._();

  static const _maxEntries = 1000;
  final List<LogEntry> _entries = [];
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// Install hooks so Flutter's own logging also appears in the log screen.
  void install() {
    // Override debugPrint so all debugPrint() calls are captured.
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message == null) return;
      _add(LogEntry(time: DateTime.now(), level: LogLevel.info, message: message));
      // Still write to native console in debug mode.
      if (kDebugMode) debugPrintSynchronously(message, wrapWidth: wrapWidth);
    };

    // Capture Flutter framework errors.
    FlutterError.onError = (details) {
      _add(LogEntry(
        time: DateTime.now(),
        level: LogLevel.error,
        message: details.exceptionAsString(),
        detail: details.stack?.toString(),
      ));
      if (kDebugMode) FlutterError.dumpErrorToConsole(details);
    };
  }

  void info(String message, {String? detail}) =>
      _add(LogEntry(time: DateTime.now(), level: LogLevel.info, message: message, detail: detail));

  void warning(String message, {String? detail}) =>
      _add(LogEntry(time: DateTime.now(), level: LogLevel.warning, message: message, detail: detail));

  void error(String message, {String? detail}) =>
      _add(LogEntry(time: DateTime.now(), level: LogLevel.error, message: message, detail: detail));

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  void _add(LogEntry entry) {
    if (_entries.length >= _maxEntries) _entries.removeAt(0);
    _entries.add(entry);
    notifyListeners();
  }
}

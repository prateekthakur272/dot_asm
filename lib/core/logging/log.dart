import 'dart:io';

enum LogLevel { debug, info, warning, error }

class Log {
  Log._();

  static const int _maxLogBytes = 1000000; // 1 MB cap
  static LogLevel minimumLevel = LogLevel.info;
  static String? _file;

  static void writeTo(String path) => _file = path;

  static void debug(String tag, String message) =>
      log(LogLevel.debug, tag, message, null);

  static void info(String tag, String message) =>
      log(LogLevel.info, tag, message, null);

  static void warning(
    String tag,
    String message, [
    Object? cause,
    StackTrace? stack,
  ]) => log(LogLevel.warning, tag, message, cause, stack);

  static void error(
    String tag,
    String message, [
    Object? cause,
    StackTrace? stack,
  ]) => log(LogLevel.error, tag, message, cause, stack);

  static T orElse<T>(
    String tag,
    String message,
    T fallback,
    T Function() block,
  ) {
    try {
      return block();
    } catch (e, st) {
      warning(tag, '$message: $e', e, st);
      return fallback;
    }
  }

  static void log(
    LogLevel level,
    String tag,
    String message, [
    Object? cause,
    StackTrace? stack,
  ]) {
    if (level.index < minimumLevel.index) return;
    final now = DateTime.now().toIso8601String();
    final lvl = level.name.toUpperCase().padRight(7);
    final causeStr = cause != null ? ' | Cause: $cause' : '';
    final stackStr = stack != null ? '\n$stack' : '';
    final line = '[$now] $lvl [$tag] $message$causeStr$stackStr';

    // Console output
    if (level == LogLevel.error) {
      stderr.writeln(line);
    } else {
      stdout.writeln(line);
    }

    // Rotating file output
    final f = _file;
    if (f == null) return;
    try {
      final file = File(f);
      if (file.existsSync() && file.lengthSync() > _maxLogBytes) {
        final old = File('$f.old');
        if (old.existsSync()) old.deleteSync();
        file.renameSync(old.path);
      }
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}

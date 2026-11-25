import 'dart:io' as io;

import 'package:dot_asm/utils/app_config.dart';
import 'package:path/path.dart' as p;

final class Paths {
  const Paths._();

  static String get _slug => AppConfig.SLUG;

  /// The user's home folder: USERPROFILE on Windows, HOME on Unix.
  static String get home {
    final env = io.Platform.environment;
    return io.Platform.isWindows
        ? (env['USERPROFILE'] ?? env['HOME'] ?? '')
        : (env['HOME'] ?? env['USERPROFILE'] ?? '');
  }

  /// App data directory: ~/.dotasm
  static String get dataDir => p.join(home, '.$_slug');

  /// Main log file path: ~/.dotasm/dotasm.log
  static String logFile([String? dir]) => p.join(dir ?? dataDir, '$_slug.log');

  /// A uniquely stamped temporary file path
  static String tempFile(String ext) => p.join(
    io.Directory.systemTemp.path,
    '$_slug-${DateTime.now().microsecondsSinceEpoch}$ext',
  );
}

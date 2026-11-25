import 'dart:io' as io;

import 'package:dot_asm/core/logging/log.dart';
import 'package:dot_asm/utils/app_config.dart';
import 'package:dot_asm/platform/platform.dart';
import 'package:flutter/foundation.dart';

/// Cross-platform desktop service for managing "Open at Login" / "Launch at Startup".
///
/// Supports:
/// - macOS: AppleScript Login Items (pointing to the .app bundle or binary)
/// - Windows: HKCU\Software\Microsoft\Windows\CurrentVersion\Run registry entry
/// - Linux: XDG autostart desktop entry (`~/.config/autostart/<slug>.desktop`)
class LaunchAtStartup {
  LaunchAtStartup._();

  static const String appName = AppConfig.NAME;
  static const String _tag = 'launch_at_startup';

  @visibleForTesting
  static bool? mockEnabled;

  @visibleForTesting
  static String? customAppPathForTesting;

  /// Resolves the app bundle (.app on macOS) or executable path.
  static String get appPath {
    if (customAppPathForTesting != null) return customAppPathForTesting!;
    final exec = io.Platform.resolvedExecutable;
    if (Platform.isMac) {
      const marker = '.app/Contents/MacOS/';
      final idx = exec.indexOf(marker);
      if (idx != -1) {
        return exec.substring(0, idx + 4);
      }
    }
    return exec;
  }

  /// Checks if the app is currently configured to launch at login.
  static Future<bool> isEnabled() async {
    if (mockEnabled != null) return mockEnabled!;

    try {
      if (Platform.isMac) {
        final res = await io.Process.run('osascript', [
          '-e',
          'tell application "System Events" to exists login item "$appName"',
        ]);
        if (res.exitCode == 0) {
          return res.stdout.toString().trim() == 'true';
        }
      } else if (Platform.isWindows) {
        final res = await io.Process.run('reg', [
          'query',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          appName,
        ]);
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final file = _linuxDesktopFile();
        return file != null && file.existsSync();
      }
    } catch (e, st) {
      Log.warning(_tag, 'Failed to check launch at startup status', e, st);
    }
    return false;
  }

  /// Enables or disables launch at startup on the host operating system.
  static Future<bool> setEnabled(bool enable) async {
    if (mockEnabled != null) {
      mockEnabled = enable;
      return true;
    }

    try {
      if (Platform.isMac) {
        return await _setMac(enable);
      } else if (Platform.isWindows) {
        return await _setWindows(enable);
      } else if (Platform.isLinux) {
        return await _setLinux(enable);
      }
    } catch (e, st) {
      Log.warning(_tag, 'Failed to set launch at startup: $enable', e, st);
    }
    return false;
  }

  static Future<bool> _setMac(bool enable) async {
    final path = appPath;
    if (enable) {
      final script =
          '''
tell application "System Events"
  if exists login item "$appName" then
    delete login item "$appName"
  end if
  make login item at end with properties {name:"$appName", path:"$path", hidden:false}
end tell
''';
      final res = await io.Process.run('osascript', ['-e', script]);
      if (res.exitCode != 0) {
        Log.warning(_tag, 'macOS login item creation failed: ${res.stderr}');
        return false;
      }
      return true;
    } else {
      final script =
          '''
tell application "System Events"
  if exists login item "$appName" then
    delete login item "$appName"
  end if
end tell
''';
      final res = await io.Process.run('osascript', ['-e', script]);
      return res.exitCode == 0;
    }
  }

  static Future<bool> _setWindows(bool enable) async {
    final exec = appPath;
    if (enable) {
      final res = await io.Process.run('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        '/v',
        appName,
        '/t',
        'REG_SZ',
        '/d',
        '"$exec"',
        '/f',
      ]);
      return res.exitCode == 0;
    } else {
      final res = await io.Process.run('reg', [
        'delete',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
        '/v',
        appName,
        '/f',
      ]);
      return res.exitCode == 0;
    }
  }

  static io.File? _linuxDesktopFile() {
    final home = io.Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return io.File(
      '$home/.config/autostart/${AppConfig.SLUG}.desktop',
    );
  }

  static Future<bool> _setLinux(bool enable) async {
    final file = _linuxDesktopFile();
    if (file == null) return false;

    if (enable) {
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      final exec = appPath;
      final content =
          '''[Desktop Entry]
Type=Application
Version=1.0
Name=$appName
Comment=${AppConfig.TAGLINE}
Exec=$exec
Terminal=false
StartupNotify=false
Categories=Utility;
''';
      await file.writeAsString(content);
      return true;
    } else {
      if (file.existsSync()) {
        await file.delete();
      }
      return true;
    }
  }
}

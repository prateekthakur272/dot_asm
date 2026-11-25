import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:dot_asm/core/logging/log.dart';
import 'package:url_launcher/url_launcher.dart';

class Platform {
  Platform._();

  static final bool isMac = io.Platform.isMacOS;
  static final bool isWindows = io.Platform.isWindows;
  static final bool isLinux = io.Platform.isLinux;

  static Future<void> init() async {
    try {
      await FilePicker.skipEntitlementsChecks();
    } catch (e, st) {
      Log.warning('platform', 'Could not configure file picker', e, st);
    }
  }

  static Future<String?> pickDirectory(String title) async {
    try {
      await FilePicker.skipEntitlementsChecks();
      final res = await FilePicker.getDirectoryPath(dialogTitle: title);
      if (res != null && res.isNotEmpty) return res;
    } catch (e, st) {
      Log.warning(
        'platform',
        'FilePicker folder dialog failed, trying fallback: $e',
        e,
        st,
      );
    }

    if (isMac) {
      return await _macPickDirectoryFallback(title);
    }
    return null;
  }

  /// Opens a native dialog to pick an application executable or bundle.
  static Future<String?> pickApplication(String title) async {
    if (isMac) {
      try {
        final res = await io.Process.run('osascript', [
          '-e',
          'try\n'
              'POSIX path of (choose application with prompt "$title")\n'
              'on error\n'
              'return ""\n'
              'end try',
        ]);
        if (res.exitCode == 0) {
          final path = res.stdout.toString().trim();
          if (path.isNotEmpty) {
            return path.endsWith('/')
                ? path.substring(0, path.length - 1)
                : path;
          }
        }
      } catch (e, st) {
        Log.warning(
          'platform',
          'AppleScript choose application failed, trying FilePicker fallback: $e',
          e,
          st,
        );
      }
    }

    try {
      await FilePicker.skipEntitlementsChecks();
      final res = await FilePicker.pickFiles(
        dialogTitle: title,
        initialDirectory: isMac ? '/Applications' : null,
        type: isLinux ? FileType.any : FileType.custom,
        allowedExtensions: isMac
            ? ['app']
            : (isWindows ? ['exe', 'lnk'] : null),
      );
      if (res.isNotEmpty &&
          res.first.path != null &&
          res.first.path!.isNotEmpty) {
        return res.first.path;
      }
    } catch (e, st) {
      Log.warning(
        'platform',
        'FilePicker application dialog failed: $e',
        e,
        st,
      );
    }
    return null;
  }

  static Future<String?> _macPickDirectoryFallback(String title) async {
    try {
      final res = await io.Process.run('osascript', [
        '-e',
        'try\n'
            'POSIX path of (choose folder with prompt "$title")\n'
            'on error\n'
            'return ""\n'
            'end try',
      ]);
      if (res.exitCode == 0) {
        final path = res.stdout.toString().trim();
        if (path.isNotEmpty) {
          return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
        }
      }
    } catch (e, st) {
      Log.warning('platform', 'AppleScript folder dialog failed', e, st);
    }
    return null;
  }

  static String get revealLabel => isMac
      ? 'Show in Finder'
      : (isWindows ? 'Show in Explorer' : 'Show in File Manager');

  static Future<void> reveal(String path) async {
    try {
      if (isMac) {
        await io.Process.run('open', ['-R', path]);
      } else if (isWindows) {
        await io.Process.run('explorer.exe', ['/select,', path]);
      } else {
        await io.Process.run('xdg-open', [path]);
      }
    } catch (e, st) {
      Log.warning('platform', 'Reveal failed for $path', e, st);
    }
  }

  static Future<void> openInTerminal(String path) async {
    try {
      if (isMac) {
        await io.Process.run('open', ['-a', 'Terminal', path]);
      } else if (isWindows) {
        await io.Process.start('cmd.exe', [
          '/c',
          'start',
          'cmd',
          '/k',
          'cd /d "$path"',
        ], runInShell: true);
      } else {
        try {
          await io.Process.start('gnome-terminal', [
            '--working-directory=$path',
          ]);
        } catch (_) {
          await io.Process.start(
            'x-terminal-emulator',
            [],
            workingDirectory: path,
          );
        }
      }
    } catch (e, st) {
      Log.warning('platform', 'Terminal launch failed for $path', e, st);
    }
  }

  static Future<void> openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  static Future<void> copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {}
  }

  static Future<String> paste() async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    } catch (_) {
      return '';
    }
  }
}

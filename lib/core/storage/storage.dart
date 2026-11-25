import 'dart:io';

import 'package:dot_asm/core/logging/log.dart';
import 'package:dot_asm/core/model/models.dart';
import 'package:dot_asm/utils/json.dart';
import 'package:dot_asm/utils/paths.dart';
import 'package:path/path.dart' as p;

/// Synchronous JSON persistence under the app data directory (`~/.dotasm`).
///
/// No cloud and no `shared_preferences`: every file is plain JSON, read at startup and written atomically
/// enough for a single-user desktop app (`flush: true`).
class AppStore {
  AppStore._();

  static const String _tag = 'storage';

  /// Override of the data directory; set before first use (tests).
  static String? homeOverride;

  static String? _dirCache;
  static String? _dirCacheKey;

  static String get dir {
    final key = homeOverride ?? '';
    if (_dirCache != null && _dirCacheKey == key) return _dirCache!;
    final d = homeOverride ?? Paths.dataDir;
    Directory(d).createSync(recursive: true);
    Log.writeTo(Paths.logFile(d));
    _dirCache = d;
    _dirCacheKey = key;
    return d;
  }

  static String get _settingsFile => p.join(dir, 'settings.json');
  static String get _stateFile => p.join(dir, 'state.json');
  static String get _prefsFile => p.join(dir, 'prefs.json');

  /// True when nothing has been saved yet: a fresh installation.
  static bool isFirstRun() => !File(_settingsFile).existsSync();

  static Map<String, dynamic> _loadFlags() {
    try {
      final f = File(_prefsFile);
      if (!f.existsSync()) return <String, dynamic>{};
      return Json.obj(Json.parse(f.readAsStringSync())) ?? <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// A small named value the app remembers (e.g. dismissed update version).
  static Object? flag(String key) => _loadFlags()[key];

  /// [flag] when it holds a string, else null.
  static String? flagString(String key) {
    final v = flag(key);
    return v is String ? v : null;
  }

  /// Saves a flag; a null [value] removes it.
  static void setFlag(String key, Object? value) {
    final m = _loadFlags();
    if (value == null) {
      if (m.remove(key) == null && !File(_prefsFile).existsSync()) return;
    } else {
      m[key] = value;
    }
    try {
      File(_prefsFile)
          .writeAsStringSync(Json.encode(m, pretty: true), flush: true);
    } catch (e, st) {
      Log.warning(_tag, 'Failed to save flags', e, st);
    }
  }

  // Settings
  static AppSettings loadSettings() {
    try {
      final f = File(_settingsFile);
      if (!f.existsSync()) return const AppSettings();
      return AppSettings.fromJson(Json.obj(Json.parse(f.readAsStringSync())));
    } catch (e, st) {
      Log.warning(_tag, 'Failed to load settings', e, st);
      return const AppSettings();
    }
  }

  static void saveSettings(AppSettings settings) {
    try {
      File(_settingsFile).writeAsStringSync(
        Json.encode(settings.toJson(), pretty: true),
        flush: true,
      );
    } catch (e, st) {
      Log.warning(_tag, 'Failed to save settings', e, st);
    }
  }

  // UI State
  static SavedState loadState() {
    try {
      final f = File(_stateFile);
      if (!f.existsSync()) return const SavedState();
      return SavedState.fromJson(Json.obj(Json.parse(f.readAsStringSync())));
    } catch (e, st) {
      Log.warning(_tag, 'Failed to load UI state', e, st);
      return const SavedState();
    }
  }

  static void saveState(SavedState state) {
    try {
      File(_stateFile).writeAsStringSync(
        Json.encode(state.toJson(), pretty: true),
        flush: true,
      );
    } catch (e, st) {
      Log.warning(_tag, 'Failed to save UI state', e, st);
    }
  }

  // Window geometry convenience
  static WindowGeometry? loadWindow() => loadState().window;

  static void saveWindow(WindowGeometry window) =>
      saveState(loadState().copyWith(window: window));
}

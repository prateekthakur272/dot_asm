import 'dart:io';

import 'package:dot_asm/core/logging/log.dart';
import 'package:dot_asm/core/model/models.dart';
import 'package:dot_asm/core/dsl/dsl.dart';
import 'package:dot_asm/core/model/project.dart';
import 'package:dot_asm/core/sim/dsl/processor_dsl.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';
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
  static String get _windowFile => p.join(dir, 'window.json');

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

  /// True until the welcome tour has been shown once.
  static bool get needsOnboarding => flag('onboarding_completed') != true;

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

  // ---------------------------------------------------------------------------------------------------------------
  // Projects live in folders the user chooses, not in the app data directory. The data directory only keeps this
  // list of where they are.

  static String get _registryFile => p.join(dir, 'projects.json');

  /// Folders of the projects shown in the sidebar, most recently added first.
  static List<String> loadProjectPaths() {
    try {
      final f = File(_registryFile);
      if (!f.existsSync()) return [];
      final obj = Json.obj(Json.parse(f.readAsStringSync()));
      final l = Json.list(obj?['paths']) ?? const [];
      return [
        for (final e in l)
          if (e is String) e,
      ];
    } catch (e, st) {
      Log.warning(_tag, 'Failed to read the project list', e, st);
      return [];
    }
  }

  static void saveProjectPaths(List<String> paths) {
    try {
      File(_registryFile).writeAsStringSync(
        Json.encode({'paths': paths}, pretty: true),
        flush: true,
      );
    } catch (e, st) {
      Log.warning(_tag, 'Failed to save the project list', e, st);
    }
  }

  /// Where the project dialog starts: the folder last used, else the home folder.
  static String get lastProjectParent =>
      flagString('lastProjectParent') ?? Paths.home;
  static set lastProjectParent(String path) =>
      setFlag('lastProjectParent', path);

  /// Name of the folder inside a project that holds its processors.
  static const cpuFolder = 'cpu';

  /// A file-system friendly folder name for a project called [name].
  static String folderNameFor(String name) {
    final s = name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[.\s-]+|[\s.-]+$'), '');
    return s.isEmpty ? 'project' : s;
  }

  /// Creates the folder for a new project under [parent]. Throws a [StateError] with a message the user can act on.
  static String createProjectFolder(String parent, String name) {
    final pd = Directory(parent);
    if (!pd.existsSync()) {
      throw StateError('The folder "$parent" does not exist');
    }
    final path = p.join(parent, folderNameFor(name));
    final d = Directory(path);
    if (d.existsSync() && d.listSync().isNotEmpty) {
      throw StateError(
        '"${p.basename(path)}" already exists in that folder and is not empty. Choose another name or location.',
      );
    }
    try {
      d.createSync(recursive: true);
    } on FileSystemException catch (e) {
      throw StateError(
        'Cannot create the project folder: ${e.osError?.message ?? e.message}',
      );
    }
    return path;
  }

  /// Reads the project in [path], or null when it has no valid `project.dotasm` (the reason is logged).
  static Project? readProject(String path) {
    final f = File(p.join(path, ProjectDsl.fileName));
    if (!f.existsSync()) return null;
    try {
      return Project(
        path: path,
        config: ProjectDsl.parse(f.readAsStringSync()),
      );
    } on DslError catch (e) {
      Log.warning(_tag, 'Cannot read ${f.path}: $e');
    } catch (e, st) {
      Log.warning(_tag, 'Cannot read ${f.path}', e, st);
    }
    return null;
  }

  /// Like [readProject], but explains what is wrong.
  static ({Project? project, String? error}) inspectProject(String path) {
    final f = File(p.join(path, ProjectDsl.fileName));
    if (!f.existsSync()) {
      return (
        project: null,
        error: 'There is no ${ProjectDsl.fileName} in "$path"',
      );
    }
    try {
      return (
        project: Project(
          path: path,
          config: ProjectDsl.parse(f.readAsStringSync()),
        ),
        error: null,
      );
    } on DslError catch (e) {
      return (project: null, error: '${ProjectDsl.fileName}: $e');
    }
  }

  static void writeProjectConfig(String path, ProjectConfig config) {
    try {
      File(p.join(path, ProjectDsl.fileName))
          .writeAsStringSync(ProjectDsl.write(config), flush: true);
    } catch (e, st) {
      Log.warning(_tag, 'Failed to write the project file in $path', e, st);
    }
  }

  static String readSource(Project project) {
    try {
      final f = File(p.join(project.path, project.config.source));
      return f.existsSync() ? f.readAsStringSync() : '';
    } catch (e, st) {
      Log.warning(_tag, 'Failed to read the source of ${project.path}', e, st);
      return '';
    }
  }

  static void writeSource(Project project, String source) {
    try {
      final f = File(p.join(project.path, project.config.source));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(source, flush: true);
    } catch (e, st) {
      Log.warning(_tag, 'Failed to save the source of ${project.path}', e, st);
    }
  }

  static void deleteProjectFolder(String path) {
    try {
      final d = Directory(path);
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (e, st) {
      Log.warning(_tag, 'Failed to delete $path', e, st);
    }
  }

  /// The `.cpu` files in a project's `cpu/` folder: (absolute path, text).
  static List<({String path, String text})> readLocalProcessors(
    String projectPath,
  ) {
    final out = <({String path, String text})>[];
    try {
      final d = Directory(p.join(projectPath, cpuFolder));
      if (!d.existsSync()) return out;
      final files =
          d
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.cpu'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        try {
          out.add((path: f.path, text: f.readAsStringSync()));
        } catch (e, st) {
          Log.warning(_tag, 'Cannot read ${f.path}', e, st);
        }
      }
    } catch (e, st) {
      Log.warning(_tag, 'Failed to list the processors of $projectPath', e, st);
    }
    return out;
  }

  /// Writes `<project>/cpu/<id>.cpu` and returns its path.
  static String writeLocalProcessor(
    String projectPath,
    String id,
    String text,
  ) {
    final safe = id.replaceAll(RegExp(r'[^\w.-]'), '_');
    final f = File(
      p.join(
        projectPath,
        cpuFolder,
        '${safe.isEmpty ? 'processor' : safe}.cpu',
      ),
    );
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(text, flush: true);
    return f.path;
  }

  static void deleteFile(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (e, st) {
      Log.warning(_tag, 'Failed to delete $path', e, st);
    }
  }

  /// Path of a project's processor file as stored in `project.dotasm` (relative, with forward slashes).
  static String relativeCpuPath(String fileName) => '$cpuFolder/$fileName';

  // ---------------------------------------------------------------------------------------------------------------
  // Projects created by earlier versions lived in `<data>/projects/<id>/` with a JSON file, and custom processors in
  // `<data>/processors/*.json`. They are converted in place: a `project.dotasm` is written, the custom processor a
  // project uses is copied into its `cpu/` folder, and the project is added to the list.

  static int migrateLegacyProjects() {
    var migrated = 0;
    try {
      final legacy = Directory(p.join(dir, 'projects'));
      if (!legacy.existsSync()) return 0;
      final paths = loadProjectPaths();
      for (final d in legacy.listSync().whereType<Directory>()) {
        final jf = File(p.join(d.path, 'project.json'));
        if (!jf.existsSync()) continue;
        try {
          final obj = Json.obj(Json.parse(jf.readAsStringSync()));
          if (obj == null) continue;
          final procId = (obj['processorId'] as String?) ?? '';
          var ref = ProcessorRef.builtin(procId);
          final legacyCpu = File(
            p.join(
              dir,
              'processors',
              '${procId.replaceAll(RegExp(r'[^\w.-]'), '_')}.json',
            ),
          );
          if (legacyCpu.existsSync()) {
            final spec = ProcessorSpec.parse(legacyCpu.readAsStringSync());
            final path = writeLocalProcessor(
              d.path,
              spec.id,
              ProcessorDsl.write(spec),
            );
            ref = ProcessorRef.file(relativeCpuPath(p.basename(path)));
          }
          final now = DateTime.now();
          final config = ProjectConfig(
            name: (obj['name'] as String?) ?? p.basename(d.path),
            processor: ref,
            created: DateTime.tryParse('${obj['createdAt']}') ?? now,
            updated: DateTime.tryParse('${obj['updatedAt']}') ?? now,
          );
          writeProjectConfig(d.path, config);
          jf.renameSync('${jf.path}.migrated');
          if (!paths.contains(d.path)) paths.add(d.path);
          migrated++;
        } catch (e, st) {
          Log.warning(_tag, 'Could not migrate ${d.path}', e, st);
        }
      }
      if (migrated > 0) saveProjectPaths(paths);
    } catch (e, st) {
      Log.warning(_tag, 'Legacy project migration failed', e, st);
    }
    return migrated;
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

  // The window's size, position and state live in their own file: `state.json` is rewritten whenever a layout setting
  // changes, and that must never put an old window size back.

  /// The window as it was left, or null the first time. Falls back to the copy older versions kept in `state.json`.
  static WindowGeometry? loadWindow() {
    try {
      final f = File(_windowFile);
      if (f.existsSync()) {
        return WindowGeometry.fromJson(
          Json.obj(Json.parse(f.readAsStringSync())),
        );
      }
    } catch (e, st) {
      Log.warning(_tag, 'Failed to load the window geometry', e, st);
    }
    return loadState().window;
  }

  static void saveWindow(WindowGeometry window) {
    try {
      File(_windowFile).writeAsStringSync(
        Json.encode(window.toJson(), pretty: true),
        flush: true,
      );
    } catch (e, st) {
      Log.warning(_tag, 'Failed to save the window geometry', e, st);
    }
  }
}

import 'dart:async';
import 'dart:io' hide Platform;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:dot_asm/app/modal.dart';
import 'package:dot_asm/app/processor_catalog.dart';
import 'package:dot_asm/app/processor_draft.dart';
import 'package:dot_asm/app/sim_session.dart';
import 'package:dot_asm/core/dsl/dsl.dart';
import 'package:dot_asm/core/logging/log.dart';
import 'package:dot_asm/core/model/models.dart';
import 'package:dot_asm/core/model/project.dart';
import 'package:dot_asm/core/sim/dsl/processor_dsl.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/platform/launch_at_startup.dart';
import 'package:dot_asm/platform/platform.dart';

export 'package:dot_asm/app/modal.dart';

/// Single owner of application state. Widgets receive it explicitly and listen with `ListenableBuilder`.
///
/// Projects are folders the user chooses. Each holds `project.dotasm` (its configuration), the assembly source and a
/// `cpu/` folder with the project's own processors. The app data directory only remembers where the projects are.
class AppState with ChangeNotifier {
  AppState() {
    _init();
  }

  static const String _tag = 'app_state';

  AppSettings _settings = const AppSettings();
  SavedState _uiState = const SavedState();

  List<Project> _projects = [];

  /// Registered folders that could not be read (moved, deleted, unmounted).
  List<String> _missing = [];

  /// Processors found in each project's `cpu/` folder, by project path.
  final Map<String, List<ProcessorSpec>> _local = {};

  /// Problems found while reading `.cpu` files, by project path.
  final Map<String, List<String>> _localErrors = {};
  Project? _activeProject;
  String _source = '';

  /// The text last read from or written to the source file: edits not yet on disk differ from it.
  String _savedSource = '';
  Timer? _sourceTimer;

  /// The processor open in the builder, or null while the processor library is shown.
  ProcessorDraft? builderDraft;

  /// The simulator of the open project.
  final SimSession sim = SimSession();

  /// Incremented whenever the source text is replaced from outside the editor (opening a project).
  int sourceRevision = 0;

  AppModal? _modal;
  bool _paletteOpen = false;
  String? _availableUpdate;
  String? _toast;
  Timer? _toastTimer;
  bool _disposed = false;

  AppSettings get settings => _settings;
  SavedState get uiState => _uiState;

  List<Project> get projects => List.unmodifiable(_projects);

  /// Projects by when they were last opened, newest first (projects never opened follow in list order).
  List<Project> recentProjects({int limit = 5}) {
    final opened = AppStore.flag('recentProjects');
    final order = <String>[if (opened is List) ...opened.whereType<String>()];
    final byPath = {for (final x in _projects) x.path: x};
    final list = <Project>[
      for (final path in order)
        if (byPath[path] != null) byPath[path]!,
    ];
    for (final x in _projects) {
      if (!list.contains(x)) list.add(x);
    }
    return list.take(limit).toList();
  }

  void _markRecent(String path) {
    final opened = AppStore.flag('recentProjects');
    final order = <String>[
      path,
      if (opened is List) ...opened.whereType<String>().where((x) => x != path),
    ];
    AppStore.setFlag('recentProjects', order.take(20).toList());
  }

  List<String> get missingProjectPaths => List.unmodifiable(_missing);
  Project? get activeProject => _activeProject;
  String get source => _source;

  /// The processors in the open project's `cpu/` folder.
  List<ProcessorSpec> get processors =>
      List.unmodifiable(_local[_activeProject?.path] ?? const []);

  /// `.cpu` files of the open project that could not be read.
  List<String> get processorFileProblems =>
      List.unmodifiable(_localErrors[_activeProject?.path] ?? const []);

  ProcessorSpec? processorById(String id) =>
      processors.where((x) => x.id == id).firstOrNull;

  /// The processor a project uses: the `.cpu` file in its `cpu/` folder, or null when it cannot be read.
  ProcessorSpec? processorFor(Project project) {
    final ref = project.processor;
    if (ref.builtin) {
      return null; // converted to a file when the project is loaded
    }
    final file = p.normalize(p.join(project.path, ref.value));
    return (_local[project.path] ?? const [])
        .where(
          (x) => x.sourcePath != null && p.normalize(x.sourcePath!) == file,
        )
        .firstOrNull;
  }

  ProcessorSpec? get activeProcessor =>
      _activeProject == null ? null : processorFor(_activeProject!);

  AppModal? get modal => _modal;
  set modal(AppModal? m) {
    _modal = m;
    notifyListeners();
  }

  bool get paletteOpen => _paletteOpen;
  set paletteOpen(bool open) {
    _paletteOpen = open;
    notifyListeners();
  }

  /// Non-null when a newer GitHub release has been detected.
  String? get availableUpdate => _availableUpdate;
  set availableUpdate(String? v) {
    if (_availableUpdate != v) {
      _availableUpdate = v;
      notifyListeners();
    }
  }

  /// Transient feedback toast.
  String? get toast => _toast;
  set toast(String? v) {
    _toast = v;
    notifyListeners();
  }

  void showToast(String msg) {
    toast = msg;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 3500), () => toast = null);
  }

  void _init() {
    _settings = AppStore.loadSettings();
    _uiState = AppStore.loadState();
    sim.addListener(notifyListeners);
    sim.onPersist = _saveSimConfig;

    // Projects from earlier versions are converted in place, once.
    if (AppStore.flag('legacy_projects_migrated') != true) {
      final n = AppStore.migrateLegacyProjects();
      if (n > 0) Log.info(_tag, 'Converted $n project(s) from the old layout');
      AppStore.setFlag('legacy_projects_migrated', true);
    }

    _loadProjects();
    final last = _uiState.activeProjectId;
    if (last != null && _projects.any((x) => x.path == last)) {
      openProject(last, notify: false);
    } else if (_uiState.activeView != 'home') {
      _uiState = _uiState.copyWith(
        activeView: 'home',
        clearActiveProject: true,
      );
    }
    unawaited(_syncOpenAtLogin());
  }

  // --- Project list ---

  void _loadProjects() {
    final paths = AppStore.loadProjectPaths();
    final ok = <Project>[];
    final missing = <String>[];
    for (final path in paths) {
      final pr = AppStore.readProject(path);
      if (pr == null) {
        missing.add(path);
      } else {
        ok.add(_materializeLegacy(pr));
        _readLocalProcessors(ok.last);
      }
    }
    _projects = ok;
    _missing = missing;
  }

  /// A project written by an earlier version may name a template (`processor builtin x`): copy that template into
  /// the project's `cpu/` folder and point the project at the file, so every project reads a processor file.
  Project _materializeLegacy(Project project) {
    final ref = project.processor;
    if (!ref.builtin) return project;
    final t = TemplateCatalog.byId(ref.value);
    if (t == null) return project;
    final file = AppStore.writeLocalProcessor(project.path, t.id, t.text);
    final config = project.config.copyWith(
      processor: ProcessorRef.file(AppStore.relativeCpuPath(p.basename(file))),
    );
    AppStore.writeProjectConfig(project.path, config);
    return project.withConfig(config);
  }

  void _saveRegistry() => AppStore.saveProjectPaths([
    for (final x in _projects) x.path,
    ..._missing,
  ]);

  void _readLocalProcessors(Project project) {
    final specs = <ProcessorSpec>[];
    final errors = <String>[];
    for (final f in AppStore.readLocalProcessors(project.path)) {
      try {
        final spec = ProcessorDsl.parse(f.text);
        spec.sourcePath = f.path;
        specs.add(spec);
      } on DslError catch (e) {
        errors.add('${p.basename(f.path)}: $e');
      } on SpecFormatError catch (e) {
        errors.add('${p.basename(f.path)}: ${e.errors.first}');
      } catch (e) {
        errors.add('${p.basename(f.path)}: $e');
      }
    }
    _local[project.path] = specs;
    _localErrors[project.path] = errors;
  }

  // --- Processor gallery ---

  void openGallery() {
    flushSource();
    sim.pause();
    builderDraft = null;
    updateUiState((s) => s.copyWith(activeView: 'gallery'));
  }

  void closeGallery() => updateUiState(
    (s) =>
        s.copyWith(activeView: _activeProject != null ? 'workspace' : 'home'),
  );

  // --- Processor builder ---

  /// Opens the editor on the open project's processor.
  void openBuilder() {
    final spec = activeProcessor;
    if (_activeProject == null) {
      showToast('Open or create a project to use the processor builder');
      return;
    }
    if (spec == null) {
      showToast("This project's processor was not found");
      return;
    }
    flushSource();
    sim.pause();
    editProcessor(spec);
  }

  /// Leaves the builder: back to the open project, or home.
  void closeBuilder() {
    builderDraft = null;
    updateUiState(
      (s) =>
          s.copyWith(activeView: _activeProject != null ? 'workspace' : 'home'),
    );
  }

  bool _idTaken(String id) => processors.any((x) => x.id == id);

  String uniqueProcessorId(String base) {
    final slug = base
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_.-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final root = slug.isEmpty ? 'custom' : slug;
    if (!_idTaken(root)) return root;
    var n = 2;
    while (_idTaken('$root-$n')) {
      n++;
    }
    return '$root-$n';
  }

  /// Starts a new processor from the blank template, inside the open project. It is only a draft until it is saved,
  /// which writes `<project>/cpu/<id>.cpu`.
  void newProcessor() {
    if (_activeProject == null) {
      showToast(
        'Open or create a project first: processors live in its cpu/ folder',
      );
      return;
    }
    final base = TemplateCatalog.blank;
    if (base == null) {
      showToast('No template is available');
      return;
    }
    final json = ProcessorDsl.toJsonMap(base.text);
    json['name'] = 'My processor';
    json.remove('description');
    json['id'] = uniqueProcessorId('my-processor');
    builderDraft = ProcessorDraft(json);
    builderDraft!.dirty = true;
    updateUiState((s) => s.copyWith(activeView: 'builder'));
  }

  /// Copies a template's `.cpu` file into the open project (with a fresh id when the id is taken) and optionally opens
  /// it in the builder. Does nothing without an open project.
  ProcessorSpec? addTemplate(ProcessorTemplate t, {bool edit = false}) {
    final project = _activeProject;
    if (project == null) return null;
    var text = t.text;
    var id = t.id;
    if (_idTaken(id)) {
      final json = ProcessorDsl.toJsonMap(t.text);
      id = uniqueProcessorId(id);
      json['id'] = id;
      text = ProcessorDsl.fromJsonMap(json);
    }
    final path = AppStore.writeLocalProcessor(project.path, id, text);
    _readLocalProcessors(project);
    final spec = processors
        .where(
          (x) =>
              x.sourcePath != null &&
              p.normalize(x.sourcePath!) == p.normalize(path),
        )
        .firstOrNull;
    if (spec != null && edit) {
      editProcessor(spec);
    } else {
      notifyListeners();
    }
    return spec;
  }

  /// Edits a processor of the open project.
  void editProcessor(ProcessorSpec spec) {
    builderDraft = ProcessorDraft(spec.toJson(), originalId: spec.id);
    updateUiState((s) => s.copyWith(activeView: 'builder'));
  }

  /// Copies a processor of the open project under a new id and edits the copy.
  void duplicateProcessor(ProcessorSpec spec) {
    if (_activeProject == null) return;
    final json = spec.toJson();
    json['id'] = uniqueProcessorId('${spec.id}-copy');
    json['name'] = '${spec.name} (copy)';
    builderDraft = ProcessorDraft(json);
    builderDraft!.dirty = true;
    updateUiState((s) => s.copyWith(activeView: 'builder'));
  }

  /// "Customise" on a template: a copy in the open project, or (with no project open) a new project built around it.
  void customiseTemplate(ProcessorTemplate t) {
    if (_activeProject == null) {
      modal = ModalNewProject(templateId: t.id, openInBuilder: true);
    } else {
      addTemplate(t, edit: true);
    }
  }

  void closeDraft() => closeBuilder();

  /// Saves the processor in the builder as `<project>/cpu/<id>.cpu`. Returns false (with a toast) when it cannot be
  /// saved yet.
  bool saveDraft() {
    final d = builderDraft;
    final project = _activeProject;
    if (d == null) return false;
    if (project == null) {
      showToast(
        'Open a project first: its processors are saved in its cpu/ folder',
      );
      return false;
    }
    final spec = d.spec;
    if (spec == null || !d.isValid) {
      showToast(
        'Fix the ${d.problems.length} problem${d.problems.length == 1 ? '' : 's'} first',
      );
      return false;
    }
    if (processors.any((x) => x.id == spec.id && x.id != d.originalId)) {
      showToast(
        "Another processor in this project already uses the id '${spec.id}'",
      );
      return false;
    }
    final old = d.originalId == null
        ? null
        : processors.where((x) => x.id == d.originalId).firstOrNull;
    final text = ProcessorDsl.write(spec);
    final path = AppStore.writeLocalProcessor(project.path, spec.id, text);
    var config = project.config;
    if (old?.sourcePath != null &&
        p.normalize(old!.sourcePath!) != p.normalize(path)) {
      AppStore.deleteFile(old.sourcePath!);
      // A project that used the old file follows the rename.
      final oldRel = p
          .relative(old.sourcePath!, from: project.path)
          .replaceAll(r'\', '/');
      if (!config.processor.builtin && config.processor.value == oldRel) {
        config = config.copyWith(
          processor: ProcessorRef.file(
            AppStore.relativeCpuPath(p.basename(path)),
          ),
        );
      }
    }
    _setProjectConfig(project, config);
    _readLocalProcessors(_activeProject!);
    d.markSaved(spec.id);
    if (activeProcessor?.id == spec.id) _reconfigureSim();
    showToast('Saved ${p.join(AppStore.cpuFolder, p.basename(path))}');
    notifyListeners();
    return true;
  }

  /// Makes [spec] (a processor in this project's `cpu/` folder) the processor of the open project.
  void useProcessor(ProcessorSpec spec) {
    final project = _activeProject;
    if (project == null) return;
    if (spec.sourcePath == null) {
      showToast('Save the processor first');
      return;
    }
    final rel = p
        .relative(spec.sourcePath!, from: project.path)
        .replaceAll(r'\', '/');
    _setProjectConfig(
      project,
      project.config.copyWith(
        processor: ProcessorRef.file(rel),
        updated: DateTime.now(),
      ),
    );
    _reconfigureSim();
    showToast('${project.name} now uses ${spec.name}');
    notifyListeners();
  }

  void deleteProcessor(ProcessorSpec spec) {
    if (spec.sourcePath == null) return;
    AppStore.deleteFile(spec.sourcePath!);
    if (builderDraft?.originalId == spec.id) builderDraft = null;
    final project = _activeProject;
    if (project != null) {
      _readLocalProcessors(project);
      if (activeProcessor == null) sim.pause();
    }
    notifyListeners();
  }

  /// Imports a processor (`.cpu` text, or JSON from older versions) into the open project. Returns the problems
  /// found, or an empty list when it was added.
  List<String> importProcessor(String text) {
    final project = _activeProject;
    if (project == null) {
      return const [
        'Open a project first: its processors are saved in its cpu/ folder',
      ];
    }
    ProcessorSpec spec;
    try {
      spec = ProcessorDsl.parse(text);
    } on DslError catch (e) {
      return ['$e'];
    } on SpecFormatError catch (e) {
      return e.errors;
    }
    final problems = spec.validate();
    // An id clash is not a problem: the import simply gets a fresh id.
    final real = problems.where((x) => !x.startsWith('id ')).toList();
    if (real.isNotEmpty) return real;
    final json = spec.toJson();
    if (_idTaken(spec.id)) json['id'] = uniqueProcessorId(spec.id);
    final imported = ProcessorSpec.fromJson(json);
    AppStore.writeLocalProcessor(
      project.path,
      imported.id,
      ProcessorDsl.write(imported),
    );
    _readLocalProcessors(project);
    notifyListeners();
    showToast(
      "Imported '${imported.name}' into ${AppStore.cpuFolder}/${imported.id}.cpu",
    );
    return const [];
  }

  /// Writes [spec] as `<id>.cpu` into a folder the user picks. Returns the file path, or null if cancelled.
  Future<String?> exportProcessor(ProcessorSpec spec) async {
    final dir = await Platform.pickDirectory(
      'Choose where to save ${spec.id}.cpu',
    );
    if (dir == null) return null;
    try {
      final f = File('$dir/${spec.id}.cpu');
      await f.writeAsString(ProcessorDsl.write(spec));
      showToast('Exported to ${f.path}');
      return f.path;
    } catch (e, st) {
      Log.warning(_tag, 'Cannot export ${spec.id}', e, st);
      showToast('Could not write the file: $e');
      return null;
    }
  }

  // --- Projects ---

  String suggestProjectName() {
    var n = _projects.length + 1;
    while (_projects.any((x) => x.name == 'Project $n')) {
      n++;
    }
    return 'Project $n';
  }

  /// Creates a project folder under [parentDir]: the template's `.cpu` file is copied into its `cpu/` folder, the
  /// source starts from the template's sample program, and the project is opened. With [openInBuilder] the new
  /// processor is opened in the builder. Returns an error message, or null on success.
  String? createProject({
    required String name,
    required String parentDir,
    required String templateId,
    bool openInBuilder = false,
  }) {
    final template = TemplateCatalog.byId(templateId);
    if (template == null) return 'Choose a processor first';
    final title = name.trim().isEmpty ? suggestProjectName() : name.trim();
    final String path;
    try {
      path = AppStore.createProjectFolder(parentDir, title);
    } on StateError catch (e) {
      return e.message;
    }
    try {
      final file = AppStore.writeLocalProcessor(
        path,
        template.id,
        template.text,
      );
      final ref = ProcessorRef.file(AppStore.relativeCpuPath(p.basename(file)));
      final now = DateTime.now();
      final config = ProjectConfig(
        name: title,
        processor: ref,
        created: now,
        updated: now,
      );
      AppStore.writeProjectConfig(path, config);
      final project = Project(path: path, config: config);
      final sample = template.spec.sample;
      AppStore.writeSource(
        project,
        sample.isNotEmpty ? sample : '# ${template.spec.name}\n\n',
      );
      AppStore.lastProjectParent = parentDir;
      _projects = [project, ..._projects.where((x) => x.path != path)];
      _readLocalProcessors(project);
      _saveRegistry();
      openProject(path);
      if (openInBuilder) {
        final spec = activeProcessor;
        if (spec != null) editProcessor(spec);
      }
      return null;
    } catch (e, st) {
      Log.warning(_tag, 'Could not create the project in $path', e, st);
      return 'Could not create the project: $e';
    }
  }

  /// Opens an existing project folder (adding it to the list). Returns an error message, or null on success.
  String? openProjectFolder(String path) {
    final r = AppStore.inspectProject(path);
    if (r.project == null) return r.error;
    final project = _materializeLegacy(r.project!);
    _projects = [project, ..._projects.where((x) => x.path != path)];
    _missing = _missing.where((x) => x != path).toList();
    _readLocalProcessors(project);
    _saveRegistry();
    AppStore.lastProjectParent = p.dirname(path);
    openProject(path);
    return null;
  }

  /// Lets the user pick a project folder and opens it.
  Future<void> openProjectFromPicker() async {
    final dir = await Platform.pickDirectory(
      'Open a project folder (it contains project.dotasm)',
    );
    if (dir == null) return;
    final err = openProjectFolder(dir);
    if (err != null) showToast(err);
  }

  void openProject(String path, {bool notify = true}) {
    final project = _projects.where((x) => x.path == path).firstOrNull;
    if (project == null) return;
    flushSource();
    // Re-read from disk so edits made outside the app are picked up.
    final fresh = _materializeLegacy(AppStore.readProject(path) ?? project);
    _projects = [for (final x in _projects) x.path == path ? fresh : x];
    _readLocalProcessors(fresh);
    _activeProject = fresh;
    _source = AppStore.readSource(fresh);
    _savedSource = _source;
    sourceRevision++;
    builderDraft = null;
    _reconfigureSim();
    final cfg = fresh.config;
    sim.speed =
        SimSpeed.values.where((s) => s.name == cfg.speed).firstOrNull ??
        SimSpeed.fast;
    sim.breakpoints
      ..clear()
      ..addAll(cfg.breakpoints);
    if (activeProcessor == null && notify) {
      showToast("This project's processor (${fresh.processor}) was not found");
    }
    _uiState = _uiState.copyWith(
      activeView: 'workspace',
      activeProjectId: path,
      panelTab: cfg.panel,
    );
    AppStore.saveState(_uiState);
    _markRecent(path);
    if (notify) notifyListeners();
  }

  /// (Re)loads the active project's processor into the simulator and assembles the source.
  void _reconfigureSim() {
    final spec = activeProcessor;
    if (spec == null) {
      sim.pause();
      return;
    }
    sim.configure(spec);
    sim.assemble(_source);
  }

  void closeProject() {
    flushSource();
    sim.pause();
    _activeProject = null;
    _source = '';
    _savedSource = '';
    builderDraft = null;
    updateUiState(
      (s) => s.copyWith(activeView: 'home', clearActiveProject: true),
    );
  }

  void renameProject(Project project, String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    _setProjectConfig(
      project,
      project.config.copyWith(name: n, updated: DateTime.now()),
    );
    notifyListeners();
  }

  /// Forgets a project; with [deleteFiles] its folder is deleted from disk as well.
  void removeProject(Project project, {bool deleteFiles = false}) {
    if (_activeProject?.path == project.path) closeProject();
    _projects = _projects.where((x) => x.path != project.path).toList();
    _local.remove(project.path);
    _localErrors.remove(project.path);
    _saveRegistry();
    if (deleteFiles) AppStore.deleteProjectFolder(project.path);
    notifyListeners();
  }

  /// Drops a registered folder that no longer exists.
  void forgetMissing(String path) {
    _missing = _missing.where((x) => x != path).toList();
    _saveRegistry();
    notifyListeners();
  }

  /// Replaces a project's config in memory and writes `project.dotasm`.
  void _setProjectConfig(Project project, ProjectConfig config) {
    final updated = project.withConfig(config);
    _projects = [
      for (final x in _projects) x.path == project.path ? updated : x,
    ];
    if (_activeProject?.path == project.path) _activeProject = updated;
    AppStore.writeProjectConfig(project.path, config);
  }

  void _saveSimConfig() {
    final pr = _activeProject;
    if (pr == null) return;
    _setProjectConfig(
      pr,
      pr.config.copyWith(
        speed: sim.speed.name,
        breakpoints: (sim.breakpoints.toList()..sort()),
      ),
    );
  }

  /// Remembers which panel tab the open project shows.
  void setPanelTab(String id) {
    updateUiState((s) => s.copyWith(panelTab: id));
    final pr = _activeProject;
    if (pr != null && pr.config.panel != id) {
      _setProjectConfig(pr, pr.config.copyWith(panel: id));
    }
  }

  /// Called by the editor on every change. Saves and re-assembles shortly after typing stops.
  void onSourceChanged(String text) {
    if (text == _source) return;
    _source = text;
    _sourceTimer?.cancel();
    _sourceTimer = Timer(const Duration(milliseconds: 350), () {
      flushSource();
      sim.assemble(_source);
    });
  }

  /// Writes the pending source to disk now.
  void flushSource() {
    _sourceTimer?.cancel();
    _sourceTimer = null;
    final pr = _activeProject;
    if (pr == null) return;
    if (_source != _savedSource) {
      AppStore.writeSource(pr, _source);
      _savedSource = _source;
      _setProjectConfig(pr, pr.config.copyWith(updated: DateTime.now()));
      notifyListeners();
    }
  }

  /// Assembles right now (toolbar button / shortcut).
  void assembleNow() {
    flushSource();
    sim.assemble(_source);
  }

  void updateSettings(AppSettings newSettings) {
    _settings = newSettings;
    AppStore.saveSettings(_settings);
    notifyListeners();
  }

  void toggleTheme() => updateSettings(
    _settings.copyWith(
      themeMode: _settings.themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark,
    ),
  );

  /// Toggles whether the app launches automatically at user login / system startup.
  Future<void> setOpenAtLogin(bool enable) async {
    _settings = _settings.copyWith(openAtLogin: enable);
    AppStore.saveSettings(_settings);
    await LaunchAtStartup.setEnabled(enable);
    notifyListeners();
  }

  /// Re-registers the login item when the setting is on but the OS entry went missing (e.g. the app moved).
  Future<void> _syncOpenAtLogin() async {
    try {
      if (_settings.openAtLogin && !await LaunchAtStartup.isEnabled()) {
        await LaunchAtStartup.setEnabled(true);
      }
    } catch (e, st) {
      Log.warning(_tag, 'Could not sync open-at-login', e, st);
    }
  }

  void updateUiState(SavedState Function(SavedState current) update) {
    _uiState = update(_uiState);
    AppStore.saveState(_uiState);
    notifyListeners();
  }

  void toggleSidebar() =>
      updateUiState((s) => s.copyWith(sidebarVisible: !s.sidebarVisible));

  /// Flushes everything to disk (called before the window is destroyed).
  void persist() {
    flushSource();
    AppStore.saveSettings(_settings);
    AppStore.saveState(_uiState);
    Log.info(_tag, 'State flushed to disk successfully');
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    flushSource();
    _toastTimer?.cancel();
    sim.removeListener(notifyListeners);
    sim.dispose();
    super.dispose();
  }
}

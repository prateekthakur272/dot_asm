import 'package:flutter/material.dart' show ThemeMode;

/// User preferences persisted to `settings.json`.
/// Preferences stored in `settings.json`.
class AppSettings {
  final ThemeMode themeMode;

  /// The editor's font size in points (see `EditorMetrics.sizes`).
  final int editorFontSize;

  /// Spaces per indent level in the assembly editor (2, 4 or 8).
  final int editorTabSize;

  /// Close brackets and quotes as they are typed, and type over the closing one.
  final bool autoClosePairs;

  /// Open the suggestion list while typing (Ctrl+Space always opens it).
  final bool autoSuggest;

  /// Faint vertical lines at every indent step.
  final bool indentGuides;

  /// The run speed a new project starts with: `slow`, `medium` or `fast`.
  final String defaultSpeed;

  /// How registers and memory values are shown at first: `hex`, `dec`, `udec` or `bin`.
  final String valueFormat;

  /// How many executed instructions are kept so that **Step back** can undo them.
  final int historyLimit;

  /// Open the project that was open when the app was closed.
  final bool reopenLastProject;

  /// Look for a newer release when the app starts.
  final bool checkUpdates;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.editorFontSize = 13,
    this.editorTabSize = 4,
    this.autoClosePairs = true,
    this.autoSuggest = true,
    this.indentGuides = true,
    this.defaultSpeed = 'fast',
    this.valueFormat = 'hex',
    this.historyLimit = 20000,
    this.reopenLastProject = true,
    this.checkUpdates = true,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? editorFontSize,
    int? editorTabSize,
    bool? autoClosePairs,
    bool? autoSuggest,
    bool? indentGuides,
    String? defaultSpeed,
    String? valueFormat,
    int? historyLimit,
    bool? reopenLastProject,
    bool? checkUpdates,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    editorFontSize: editorFontSize ?? this.editorFontSize,
    editorTabSize: editorTabSize ?? this.editorTabSize,
    autoClosePairs: autoClosePairs ?? this.autoClosePairs,
    autoSuggest: autoSuggest ?? this.autoSuggest,
    indentGuides: indentGuides ?? this.indentGuides,
    defaultSpeed: defaultSpeed ?? this.defaultSpeed,
    valueFormat: valueFormat ?? this.valueFormat,
    historyLimit: historyLimit ?? this.historyLimit,
    reopenLastProject: reopenLastProject ?? this.reopenLastProject,
    checkUpdates: checkUpdates ?? this.checkUpdates,
  );

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'editorFontSize': editorFontSize,
    'editorTabSize': editorTabSize,
    'autoClosePairs': autoClosePairs,
    'autoSuggest': autoSuggest,
    'indentGuides': indentGuides,
    'defaultSpeed': defaultSpeed,
    'valueFormat': valueFormat,
    'historyLimit': historyLimit,
    'reopenLastProject': reopenLastProject,
    'checkUpdates': checkUpdates,
  };

  /// Reads settings, ignoring keys it does not know (such as one written by an older version) and replacing any value
  /// that is out of range with the default.
  factory AppSettings.fromJson(Map<String, dynamic>? m) {
    if (m == null) return const AppSettings();
    const d = AppSettings();
    T pick<T>(Object? v, List<T> allowed, T fallback) =>
        allowed.contains(v) ? v as T : fallback;
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (e) => e.name == m['themeMode'],
        orElse: () => ThemeMode.system,
      ),
      editorFontSize: pick(m['editorFontSize'], const [
        11,
        12,
        13,
        14,
        15,
        16,
        18,
      ], d.editorFontSize),
      editorTabSize: pick(m['editorTabSize'], const [2, 4, 8], d.editorTabSize),
      autoClosePairs: m['autoClosePairs'] as bool? ?? d.autoClosePairs,
      autoSuggest: m['autoSuggest'] as bool? ?? d.autoSuggest,
      indentGuides: m['indentGuides'] as bool? ?? d.indentGuides,
      defaultSpeed: pick(m['defaultSpeed'], const [
        'slow',
        'medium',
        'fast',
      ], d.defaultSpeed),
      valueFormat: pick(m['valueFormat'], const [
        'hex',
        'dec',
        'udec',
        'bin',
      ], d.valueFormat),
      historyLimit: pick(m['historyLimit'], const [
        1000,
        5000,
        20000,
        50000,
      ], d.historyLimit),
      reopenLastProject: m['reopenLastProject'] as bool? ?? d.reopenLastProject,
      checkUpdates: m['checkUpdates'] as bool? ?? d.checkUpdates,
    );
  }
}

/// Window position and dimension persistence.
class WindowGeometry {
  final double width;
  final double height;
  final double? x;
  final double? y;
  final bool maximized;
  final bool fullscreen;

  const WindowGeometry(
    this.width,
    this.height, [
    this.x,
    this.y,
    this.maximized = false,
    this.fullscreen = false,
  ]);

  /// The same size and position with a different state.
  WindowGeometry copyWith({bool? maximized, bool? fullscreen}) =>
      WindowGeometry(
        width,
        height,
        x,
        y,
        maximized ?? this.maximized,
        fullscreen ?? this.fullscreen,
      );

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    'maximized': maximized,
    'fullscreen': fullscreen,
  };

  factory WindowGeometry.fromJson(Map<String, dynamic>? m) {
    if (m == null) return const WindowGeometry(1360, 860);
    return WindowGeometry(
      (m['width'] as num?)?.toDouble() ?? 1360,
      (m['height'] as num?)?.toDouble() ?? 860,
      (m['x'] as num?)?.toDouble(),
      (m['y'] as num?)?.toDouble(),
      m['maximized'] as bool? ?? false,
      m['fullscreen'] as bool? ?? false,
    );
  }
}

/// Session state persisted to `state.json`: layout, open project and window geometry.
class SavedState {
  final double sidebarWidth;
  final bool sidebarVisible;

  /// `home` or `workspace` (and later `builder`).
  final String activeView;
  final String? activeProjectId;

  /// Width of the live processor panel in the workspace.
  final double panelWidth;
  final String panelTab;
  final WindowGeometry? window;

  const SavedState({
    this.sidebarWidth = 270,
    this.sidebarVisible = true,
    this.activeView = 'home',
    this.activeProjectId,
    this.panelWidth = 460,
    this.panelTab = 'overview',
    this.window,
  });

  SavedState copyWith({
    double? sidebarWidth,
    bool? sidebarVisible,
    String? activeView,
    String? activeProjectId,
    bool clearActiveProject = false,
    double? panelWidth,
    String? panelTab,
    WindowGeometry? window,
  }) => SavedState(
    sidebarWidth: sidebarWidth ?? this.sidebarWidth,
    sidebarVisible: sidebarVisible ?? this.sidebarVisible,
    activeView: activeView ?? this.activeView,
    activeProjectId: clearActiveProject
        ? null
        : (activeProjectId ?? this.activeProjectId),
    panelWidth: panelWidth ?? this.panelWidth,
    panelTab: panelTab ?? this.panelTab,
    window: window ?? this.window,
  );

  Map<String, dynamic> toJson() => {
    'sidebarWidth': sidebarWidth,
    'sidebarVisible': sidebarVisible,
    'activeView': activeView,
    if (activeProjectId != null) 'activeProjectId': activeProjectId,
    'panelWidth': panelWidth,
    'panelTab': panelTab,
    if (window != null) 'window': window!.toJson(),
  };

  factory SavedState.fromJson(Map<String, dynamic>? m) {
    if (m == null) return const SavedState();
    final w = m['window'];
    return SavedState(
      sidebarWidth: (m['sidebarWidth'] as num?)?.toDouble() ?? 270,
      sidebarVisible: m['sidebarVisible'] as bool? ?? true,
      activeView: (m['activeView'] as String?) ?? 'home',
      activeProjectId: m['activeProjectId'] as String?,
      panelWidth: (m['panelWidth'] as num?)?.toDouble() ?? 460,
      panelTab: (m['panelTab'] as String?) ?? 'overview',
      window: w is Map<String, dynamic> ? WindowGeometry.fromJson(w) : null,
    );
  }
}

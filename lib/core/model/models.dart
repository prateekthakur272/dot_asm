import 'package:flutter/material.dart' show ThemeMode;

/// User preferences persisted to `settings.json`.
class AppSettings {
  final ThemeMode themeMode;
  final bool openAtLogin;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.openAtLogin = false,
  });

  AppSettings copyWith({ThemeMode? themeMode, bool? openAtLogin}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        openAtLogin: openAtLogin ?? this.openAtLogin,
      );

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'openAtLogin': openAtLogin,
  };

  factory AppSettings.fromJson(Map<String, dynamic>? m) {
    if (m == null) return const AppSettings();
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (e) => e.name == m['themeMode'],
        orElse: () => ThemeMode.system,
      ),
      openAtLogin: m['openAtLogin'] as bool? ?? false,
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

  const WindowGeometry(
    this.width,
    this.height, [
    this.x,
    this.y,
    this.maximized = false,
  ]);

  WindowGeometry copyWith({bool? maximized}) =>
      WindowGeometry(width, height, x, y, maximized ?? this.maximized);

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    'maximized': maximized,
  };

  factory WindowGeometry.fromJson(Map<String, dynamic>? m) {
    if (m == null) return const WindowGeometry(1360, 860);
    return WindowGeometry(
      (m['width'] as num?)?.toDouble() ?? 1360,
      (m['height'] as num?)?.toDouble() ?? 860,
      (m['x'] as num?)?.toDouble(),
      (m['y'] as num?)?.toDouble(),
      m['maximized'] as bool? ?? false,
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

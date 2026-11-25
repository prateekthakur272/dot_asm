import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:dot_asm/app/modal.dart';
import 'package:dot_asm/core/logging/log.dart';
import 'package:dot_asm/core/model/models.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/platform/launch_at_startup.dart';

export 'package:dot_asm/app/modal.dart';

/// Single owner of application state. Widgets receive it explicitly and listen with `ListenableBuilder`.
///
/// Feature state belongs in topic-specific extensions (`app_state_<topic>.dart`) so this class stays small.
class AppState with ChangeNotifier {
  AppState() {
    _init();
  }

  static const String _tag = 'app_state';

  AppSettings _settings = const AppSettings();
  SavedState _uiState = const SavedState();

  AppModal? _modal;
  bool _paletteOpen = false;
  String? _availableUpdate;
  String? _toast;
  Timer? _toastTimer;
  bool _disposed = false;

  AppSettings get settings => _settings;
  SavedState get uiState => _uiState;

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
    unawaited(_syncOpenAtLogin());
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
    _toastTimer?.cancel();
    super.dispose();
  }
}

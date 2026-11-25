import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/app/processor_catalog.dart';
import 'package:dot_asm/core/logging/log.dart';
import 'package:dot_asm/core/model/models.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/features/shell/app_shell.dart';
import 'package:dot_asm/features/shell/menus.dart';
import 'package:dot_asm/features/shell/window_chrome.dart';
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/theme.dart';
import 'package:dot_asm/utils/app_config.dart';
import 'package:dot_asm/utils/app_metadata.dart';
import 'package:dot_asm/utils/update_checker.dart';
import 'package:window_manager/legacy.dart' as wm;

bool _onScreen(double x, double y, double w, double h) {
  try {
    final probe = Offset(x + 40, y + 20);
    for (final d in PlatformDispatcher.instance.displays) {
      final dw = d.size.width / d.devicePixelRatio;
      final dh = d.size.height / d.devicePixelRatio;
      if (probe.dx > -dw &&
          probe.dx < 2 * dw &&
          probe.dy >= -dh &&
          probe.dy < 2 * dh) {
        return true;
      }
    }
  } catch (_) {}
  return false;
}

bool _positionVisible(WindowGeometry? g) =>
    g != null &&
    g.x != null &&
    g.y != null &&
    _onScreen(g.x!, g.y!, g.width, g.height);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppMetadata.load();
  await TemplateCatalog.load(rootBundle);
  await PlannedCatalog.load(rootBundle);
  await Platform.init();
  await wm.windowManager.ensureInitialized();

  final isMac = Platform.isMac;
  final saved = AppStore.loadWindow();
  final placed = _positionVisible(saved);

  await wm.windowManager.waitUntilReadyToShow(
    wm.WindowOptions(
      // Never smaller than the window may be (a screen that changed could have left a tiny size behind).
      size: saved != null
          ? Size(
              saved.width < 840 ? 840 : saved.width,
              saved.height < 520 ? 520 : saved.height,
            )
          : const Size(1360, 860),
      minimumSize: const Size(840, 520),
      center: !placed,
      title: AppConfig.NAME,
      titleBarStyle: wm.TitleBarStyle.hidden,
      windowButtonVisibility: isMac,
    ),
    () async {
      if (saved != null && placed) {
        await wm.windowManager.setPosition(Offset(saved.x!, saved.y!));
      }
      if (saved != null && saved.fullscreen) {
        await wm.windowManager.setFullScreen(true);
      } else if (saved != null && saved.maximized) {
        await wm.windowManager.maximize();
      }
    },
  );

  await wm.windowManager.setPreventClose(true);
  runApp(const DotAsmApp());

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await wm.windowManager.setOpacity(1);
    await wm.windowManager.show();
    await wm.windowManager.focus();
  });
}

class _DesktopScrollBehavior extends MaterialScrollBehavior {
  const _DesktopScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

class DotAsmApp extends StatefulWidget {
  const DotAsmApp({super.key});

  @override
  State<DotAsmApp> createState() => _DotAsmAppState();
}

class _DotAsmAppState extends State<DotAsmApp>
    with WidgetsBindingObserver, wm.WindowListener {
  late final AppState state;
  bool maximized = false;
  late bool dark;
  Timer? _boundsTimer;
  WindowGeometry? _floating = AppStore.loadWindow();

  bool get isMac => Platform.isMac;

  bool _computeDark() {
    final mode = state.settings.themeMode;
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  @override
  void initState() {
    super.initState();
    state = AppState();
    dark = _computeDark();
    state.addListener(_onState);
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    wm.windowManager.addListener(this);
    // Check for a newer GitHub release after the first frame so it never delays startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncMaximized());
      _showOnboardingOnce();
      _checkForUpdateOnce();
    });
  }

  /// The window may have been restored maximized: make the title bar's maximize button agree.
  Future<void> _syncMaximized() async {
    final max = await wm.windowManager.isMaximized();
    if (mounted && max != maximized) setState(() => maximized = max);
  }

  /// The first time the app runs, open the welcome tour. It is marked as seen right away, so closing it any way at all
  /// (even by clicking outside) means it does not come back.
  void _showOnboardingOnce() {
    if (!AppStore.needsOnboarding) return;
    AppStore.setFlag('onboarding_completed', true);
    state.modal = const ModalOnboarding();
  }

  Future<void> _checkForUpdateOnce() async {
    if (!state.settings.checkUpdates) return;
    final result = await UpdateChecker.check(AppMetadata.version);
    if (!mounted) return;
    if (result.hasUpdate) {
      state.availableUpdate = result.version;
      if (result.shouldShowDialog && state.modal == null) {
        state.modal = ModalUpdateAvailable(result.version!);
      }
    }
  }

  @override
  void dispose() {
    _boundsTimer?.cancel();
    wm.windowManager.removeListener(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    state.removeListener(_onState);
    state.dispose();
    super.dispose();
  }

  void _onState() {
    final d = _computeDark();
    setState(() => dark = d);
  }

  @override
  void didChangePlatformBrightness() => _onState();

  void _saveBoundsSoon() {
    _boundsTimer?.cancel();
    _boundsTimer = Timer(const Duration(milliseconds: 400), _saveBounds);
  }

  Future<void> _saveBounds() async {
    try {
      final max = await wm.windowManager.isMaximized();
      final full = await wm.windowManager.isFullScreen();
      // Only a normal window tells us its own size; a maximized or full-screen one keeps the size it will return to.
      if (!max && !full && !await wm.windowManager.isMinimized()) {
        final r = await wm.windowManager.getBounds();
        _floating = WindowGeometry(r.width, r.height, r.left, r.top);
      }
      // Nothing to return to yet (it was never a normal window this session): use whatever size it has.
      if (_floating == null) {
        final r = await wm.windowManager.getBounds();
        _floating = WindowGeometry(r.width, r.height, r.left, r.top);
      }
      AppStore.saveWindow(
        _floating!.copyWith(maximized: max, fullscreen: full),
      );
    } catch (e, st) {
      Log.warning('window', 'Cannot save window geometry', e, st);
    }
  }

  @override
  void onWindowResized() => _saveBoundsSoon();

  @override
  void onWindowMoved() => _saveBoundsSoon();

  @override
  void onWindowMaximize() {
    setState(() => maximized = true);
    _saveBoundsSoon();
  }

  @override
  void onWindowUnmaximize() {
    setState(() => maximized = false);
    _saveBoundsSoon();
  }

  @override
  void onWindowEnterFullScreen() => _saveBoundsSoon();

  @override
  void onWindowLeaveFullScreen() => _saveBoundsSoon();

  @override
  void onWindowClose() => quit();

  void quit() {
    _boundsTimer?.cancel();
    state.persist();
    unawaited(_saveBounds().whenComplete(wm.windowManager.destroy));
  }

  void minimize() => unawaited(wm.windowManager.minimize());

  Future<void> toggleMaximize() async {
    if (await wm.windowManager.isMaximized()) {
      await wm.windowManager.unmaximize();
    } else {
      await wm.windowManager.maximize();
    }
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;

    // Debugger keys (only while a project is open): F5 run/pause, F10 step, Shift+F10 step back.
    if (state.activeProject != null &&
        state.modal == null &&
        !state.paletteOpen) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (e.logicalKey == LogicalKeyboardKey.f5) {
        state.sim.running ? state.sim.pause() : unawaited(state.sim.run());
        return true;
      }
      if (e.logicalKey == LogicalKeyboardKey.f10) {
        shift ? state.sim.stepBack() : state.sim.stepOnce();
        return true;
      }
    }

    final isCmdOrCtrl = isMac
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;

    if (isCmdOrCtrl) {
      if (e.logicalKey == LogicalKeyboardKey.keyK) {
        state.paletteOpen = !state.paletteOpen;
        return true;
      }
      if (e.logicalKey == LogicalKeyboardKey.keyN) {
        state.modal = const ModalNewProject();
        return true;
      }
      if (e.logicalKey == LogicalKeyboardKey.keyB) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          if (state.activeProject != null) state.assembleNow();
        } else {
          state.toggleSidebar();
        }
        return true;
      }
      if (e.logicalKey == LogicalKeyboardKey.keyT) {
        state.toggleTheme();
        return true;
      }
      if (e.logicalKey == LogicalKeyboardKey.comma) {
        state.modal = const ModalSettings();
        return true;
      }
      if (!isMac && e.logicalKey == LogicalKeyboardKey.keyQ) {
        quit();
        return true;
      }
    }
    return false;
  }

  WindowChrome get chrome => WindowChrome.desktop(
    isMac: isMac,
    maximized: maximized,
    onMinimize: minimize,
    onToggleMaximize: () => unawaited(toggleMaximize()),
    onClose: quit,
    onDragStart: () => unawaited(wm.windowManager.startDragging()),
    onContextMenu: () => unawaited(wm.windowManager.popUpWindowMenu()),
    menuBar: WindowMenuBar(
      state: state,
      onQuit: quit,
      onMinimize: minimize,
      onToggleMaximize: () => unawaited(toggleMaximize()),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pal = DotAsmTheme.palFor(dark);

    final app = PalScope(
      pal: pal,
      child: MaterialApp(
        title: AppConfig.NAME,
        debugShowCheckedModeBanner: false,
        theme: DotAsmTheme.makeTheme(false),
        darkTheme: DotAsmTheme.makeTheme(true),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        scrollBehavior: const _DesktopScrollBehavior(),
        home: Scaffold(
          body: AppShell(state: state, chrome: chrome),
        ),
      ),
    );

    if (isMac) {
      return PlatformMenuBar(menus: buildMacMenus(state, quit), child: app);
    }

    return app;
  }
}

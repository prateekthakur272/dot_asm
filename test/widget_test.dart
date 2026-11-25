import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/templates.dart';

import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/features/projects/sidebar.dart';
import 'package:dot_asm/features/shell/app_shell.dart';
import 'package:dot_asm/features/shell/window_chrome.dart';
import 'package:dot_asm/theme/theme.dart';
import 'package:dot_asm/utils/app_config.dart';

Widget _host(AppState state, {bool dark = true}) => PalScope(
  pal: DotAsmTheme.palFor(dark),
  child: MaterialApp(
    theme: DotAsmTheme.makeTheme(dark),
    home: Scaffold(
      body: AppShell(state: state, chrome: const WindowChrome()),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    loadTemplates();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dotasm_shell_test_');
    AppStore.homeOverride = tempDir.path;
  });

  tearDown(() {
    AppStore.homeOverride = null;
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('shell renders brand, sidebar and status bar', (tester) async {
    tester.view.physicalSize = const Size(1360, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState();
    await tester.pumpWidget(_host(state));
    expect(find.text(AppConfig.NAME), findsWidgets);
    expect(find.text('PROJECTS'), findsOneWidget);
    expect(find.text('New project'), findsWidgets);
    expect(find.text('commands'), findsOneWidget);
  });

  testWidgets('settings, about and developer dialogs open and close', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1360, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState();
    await tester.pumpWidget(_host(state));

    state.modal = const ModalSettings();
    await tester.pump();
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Open at Login'), findsOneWidget);

    state.modal = const ModalAbout();
    await tester.pump();
    expect(find.text('About ${AppConfig.NAME}'), findsOneWidget);

    state.modal = const ModalDeveloper();
    await tester.pump();
    expect(find.text('Developer'), findsOneWidget);

    state.modal = const ModalUpdateAvailable('9.9.9');
    await tester.pump();
    expect(find.text('Update Available'), findsOneWidget);

    state.modal = null;
    await tester.pump();
    expect(find.text('Update Available'), findsNothing);
  });

  testWidgets('theme toggle and sidebar toggle persist', (tester) async {
    final state = AppState();
    state.toggleTheme();
    expect(AppStore.loadSettings().themeMode, ThemeMode.dark);
    state.toggleSidebar();
    expect(AppStore.loadState().sidebarVisible, isFalse);
  });

  testWidgets('command palette lists core commands', (tester) async {
    tester.view.physicalSize = const Size(1360, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState();
    await tester.pumpWidget(_host(state));
    state.paletteOpen = true;
    await tester.pump();
    expect(find.text('Open Preferences'), findsOneWidget);
    expect(find.text('Check for Updates'), findsOneWidget);
  });

  testWidgets('create a project, step, and see registers change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState();
    await tester.pumpWidget(_host(state));
    state.modal = const ModalNewProject();
    await tester.pump();
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);

    state.modal = null;
    final err = state.createProject(
      name: 'Demo',
      parentDir: tempDir.path,
      templateId: 'rv32i',
    );
    expect(err, isNull);
    final project = state.activeProject!;
    await tester.pump(const Duration(milliseconds: 600));
    expect(state.activeProject!.id, project.id);
    expect(state.sim.errors, isEmpty);
    expect(find.text('Demo'), findsWidgets);
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Registers'), findsWidgets);

    state.sim.stepOnce(); // li t0, 0 -> addi t0, zero, 0 (no visible change)
    state.sim.stepOnce(); // li t1, 1
    await tester.pump();
    expect(state.sim.machine!.register(6), 1);
    expect(find.text('0x00000001'), findsWidgets);

    state.updateUiState((s) => s.copyWith(panelTab: 'decode'));
    await tester.pump();
    expect(find.text('SEMANTICS'), findsOneWidget);

    state.updateUiState((s) => s.copyWith(panelTab: 'memory'));
    await tester.pump();
    expect(find.textContaining('KiB'), findsWidgets);

    state.updateUiState((s) => s.copyWith(panelTab: 'disassembly'));
    await tester.pump();
    expect(find.textContaining('addi'), findsWidgets);

    await tester.runAsync(() async {
      await state.sim.run();
    });
    await tester.pump();
    expect(state.sim.machine!.console.toString(), 'sum = 55');
    expect(find.text('Finished'), findsOneWidget);
    state.sim.stepBack();
    await tester.pump();
    state.closeProject();
    await tester.pump();
    // The home screen is a small set of actions plus the recent projects (no processor grid).
    expect(find.text('New project'), findsWidgets);
    expect(find.text('Open project…'), findsWidgets);
    expect(find.text('Processor gallery'), findsWidgets);
    expect(find.text('RECENT PROJECTS'), findsOneWidget);
    expect(find.text('START WITH A PROCESSOR'), findsNothing);
    // Reopening restores the source from disk.
    state.openProject(project.id);
    await tester.pump(const Duration(milliseconds: 600));
    expect(state.source, contains('Sum the numbers'));
  });

  testWidgets(
    'the title bar stays and the app header sits at the top of the sidebar',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppState();
      await tester.pumpWidget(
        PalScope(
          pal: DotAsmTheme.palFor(true),
          child: MaterialApp(
            theme: DotAsmTheme.makeTheme(true),
            home: Scaffold(
              body: AppShell(state: state, chrome: const WindowChrome()),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      // The name appears in the title bar and in the sidebar's header, which belongs to the sidebar.
      expect(find.text('dot ASM'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(ProjectsSidebar),
          matching: find.byType(AppHeader),
        ),
        findsOneWidget,
      );
      // Hiding the sidebar takes its header with it and leaves nothing else at the top.
      state.toggleSidebar();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppHeader), findsNothing);
      state.toggleSidebar();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppHeader), findsOneWidget);
    },
  );
}

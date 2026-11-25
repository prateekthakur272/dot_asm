import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/core/storage/storage.dart';
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
    expect(find.text('Sidebar'), findsOneWidget);
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
}

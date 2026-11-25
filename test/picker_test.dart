import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/features/dialogs/project_dialogs.dart';
import 'package:dot_asm/features/shell/app_shell.dart';
import 'package:dot_asm/features/shell/window_chrome.dart';
import 'package:dot_asm/theme/theme.dart';

import 'support/templates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dotasm_picker_');
    AppStore.homeOverride = '${tmp.path}/data';
    Directory('${tmp.path}/data').createSync();
    Directory('${tmp.path}/work').createSync();
    AppStore.lastProjectParent = '${tmp.path}/work';
    loadTemplates();
  });

  tearDown(() {
    AppStore.homeOverride = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget host(AppState s) => PalScope(
    pal: DotAsmTheme.palFor(true),
    child: MaterialApp(
      theme: DotAsmTheme.makeTheme(true),
      home: Scaffold(
        body: AppShell(state: s, chrome: const WindowChrome()),
      ),
    ),
  );

  Future<AppState> open(
    WidgetTester tester, {
    Size size = const Size(1500, 950),
    String? template,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppState();
    await tester.pumpWidget(host(s));
    s.modal = ModalNewProject(templateId: template);
    await tester.pump();
    return s;
  }

  // The home screen behind the dialog also shows processor names, so look inside the picker only.
  Finder inPicker(String text) => find.descendant(
    of: find.byType(TemplatePicker),
    matching: find.text(text),
  );

  // The picker's search box is the second text field in the dialog (the first is the project name).
  Future<void> search(WidgetTester tester, String q) async {
    await tester.enterText(find.byType(TextField).at(1), q);
    await tester.pump();
  }

  testWidgets(
    'the picker groups processors by family and shows details of the selected one',
    (tester) async {
      await open(tester, template: 'mos6502');
      expect(find.text('RISC'), findsWidgets); // first group, on screen
      expect(find.text('Starter program'), findsOneWidget);
      expect(find.text('Word size'), findsOneWidget);
      expect(find.text('16-bit, little endian'), findsOneWidget);
      expect(
        find.textContaining('variable length (1/2/3 bytes)'),
        findsOneWidget,
      );
      expect(find.text('Legacy'), findsWidgets);
      expect(find.textContaining('MOS Technology'), findsWidgets);
      // Other groups appear as the list is narrowed.
      await search(tester, 'x86');
      expect(find.text('X86 / X64'), findsOneWidget);
      await search(tester, 'blank');
      expect(find.text('CUSTOM'), findsOneWidget);
      await search(tester, 'educational');
      expect(find.text('EDUCATIONAL'), findsOneWidget);
    },
  );

  testWidgets('selecting another processor changes the details', (
    tester,
  ) async {
    await open(tester, template: 'mos6502');
    await search(tester, 'arm');
    await tester.tap(find.text('ARM (ARMv7-A, A32 subset)').last);
    await tester.pump();
    expect(find.text('32-bit, little endian'), findsOneWidget);
    expect(find.textContaining('fixed 32-bit'), findsOneWidget);
    expect(find.text('Modern'), findsWidgets);
  });

  testWidgets('search narrows the list by name, vendor, tag or year', (
    tester,
  ) async {
    await open(tester);
    await search(tester, 'intel');
    expect(inPicker('Intel x86 (IA-32 subset)'), findsWidgets);
    expect(inPicker('MIPS32'), findsNothing);
    await search(tester, '8-bit');
    expect(inPicker('MOS Technology 6502'), findsWidgets);
    expect(inPicker('Atmel AVR (ATmega subset)'), findsWidgets);
    expect(inPicker('MIPS32'), findsNothing);
    await search(tester, '1985');
    expect(inPicker('MIPS32'), findsWidgets);
    await search(tester, 'zzzz');
    expect(find.textContaining('No processor matches'), findsOneWidget);
  });

  testWidgets('creating uses the processor that is selected in the picker', (
    tester,
  ) async {
    final s = await open(tester);
    await search(tester, 'mips');
    await tester.tap(find.text('MIPS32').last);
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(s.activeProject!.processor.value, 'cpu/mips32.cpu');
    expect(s.activeProcessor!.name, 'MIPS32');
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('the dialog scrolls instead of overflowing in a small window', (
    tester,
  ) async {
    await open(tester, size: const Size(1000, 640), template: 'x86_64');
    expect(tester.takeException(), isNull);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Starter program'), findsOneWidget);
  });
}

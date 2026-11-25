import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/features/shell/app_shell.dart';
import 'package:dot_asm/features/shell/window_chrome.dart';
import 'package:dot_asm/features/workspace/code_editor.dart';
import 'package:dot_asm/features/workspace/editor_parts.dart';
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/theme.dart';

import 'support/templates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late AppState s;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dotasm_editor_');
    AppStore.homeOverride = '${tmp.path}/data';
    Directory('${tmp.path}/data').createSync();
    Directory('${tmp.path}/work').createSync();
    loadTemplates();
  });
  tearDown(() {
    AppStore.homeOverride = null;
    tmp.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    s = AppState();
    expect(
      s.createProject(
        name: 'Ed',
        parentDir: '${tmp.path}/work',
        templateId: 'rv32i',
      ),
      isNull,
    );
    await tester.pumpWidget(
      PalScope(
        pal: DotAsmTheme.palFor(true),
        child: MaterialApp(
          theme: DotAsmTheme.makeTheme(true),
          home: Scaffold(
            body: AppShell(state: s, chrome: const WindowChrome()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  Finder editorField() => find.descendant(
    of: find.byType(CodeEditor),
    matching: find.byWidgetPredicate(
      (w) => w is EditableText && w.maxLines == null,
    ),
  );

  String text(WidgetTester tester) =>
      tester.widget<EditableText>(editorField()).controller.text;

  Future<void> typeText(WidgetTester tester, String t) async {
    await tester.tap(editorField());
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: t,
        selection: TextSelection.collapsed(offset: t.length),
      ),
    );
    await tester.pump();
  }

  testWidgets('typing opens suggestions and Tab accepts one', (tester) async {
    await open(tester);
    await typeText(tester, 'ad');
    expect(find.byType(CompletionPopup), findsOneWidget);
    expect(find.text('add'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(text(tester), startsWith('add '));
    expect(find.byType(CompletionPopup), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Escape closes the list; arrows move; Enter accepts', (
    tester,
  ) async {
    await open(tester);
    await typeText(tester, 'ad');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(CompletionPopup), findsNothing);
    await typeText(tester, 'a');
    expect(find.byType(CompletionPopup), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final second = tester
        .widget<CompletionPopup>(find.byType(CompletionPopup))
        .items[1]
        .label;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(text(tester), startsWith('$second '));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Tab indents when there is no list', (tester) async {
    await open(tester);
    await typeText(tester, '');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(text(tester), '    ');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('find highlights matches and replace all rewrites them', (
    tester,
  ) async {
    await open(tester);
    await typeText(tester, 'addi x1, x0, 1\naddi x2, x0, 2\n');
    final mod = Platform.isMac
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(mod);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(mod);
    await tester.pump();
    expect(find.byType(FindBar), findsOneWidget);
    final fields = find.descendant(
      of: find.byType(FindBar),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'addi');
    await tester.pump();
    expect(find.text('1 of 2'), findsOneWidget);
    await tester.enterText(fields.at(1), 'subi');
    await tester.tap(find.text('All'));
    await tester.pump();
    expect(text(tester), 'subi x1, x0, 1\nsubi x2, x0, 2\n');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(FindBar), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the status strip shows the line and the instruction help', (
    tester,
  ) async {
    await open(tester);
    await typeText(tester, 'add x1, x2, x3');
    expect(find.textContaining('Ln 1, Col 15'), findsOneWidget);
    expect(find.byType(EditorStatus), findsOneWidget);
    final status = tester.widget<EditorStatus>(find.byType(EditorStatus));
    expect(status.hint?.label, 'add');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'the header shows the file and the problems, and marks the bad line',
    (tester) async {
      await open(tester);
      expect(find.text('main.s'), findsOneWidget);
      expect(find.text('No problems'), findsOneWidget);
      await typeText(tester, 'bogus x1, x2\n');
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('1 problem'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets); // the wavy underline
      expect(
        find.textContaining('bogus'),
        findsWidgets,
      ); // the message after the code
      await tester.tap(find.text('1 problem'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    },
  );
}

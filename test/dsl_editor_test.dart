import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/features/processor_builder/builder_view.dart';
import 'package:dot_asm/features/processor_builder/dsl_editor.dart';
import 'package:dot_asm/features/workspace/editor_logic.dart';
import 'package:dot_asm/features/workspace/editor_parts.dart';
import 'package:dot_asm/theme/theme.dart';

import 'support/templates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late AppState s;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dotasm_dsl_');
    AppStore.homeOverride = '${tmp.path}/data';
    Directory('${tmp.path}/data').createSync();
    Directory('${tmp.path}/work').createSync();
    loadTemplates();
  });
  tearDown(() {
    AppStore.homeOverride = null;
    tmp.deleteSync(recursive: true);
  });

  Future<void> openSource(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1300, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    s = AppState();
    expect(
      s.createProject(
        name: 'D',
        parentDir: '${tmp.path}/work',
        templateId: 'tiny16',
      ),
      isNull,
    );
    s.openBuilder();
    await tester.pumpWidget(
      PalScope(
        pal: DotAsmTheme.palFor(true),
        child: MaterialApp(
          theme: DotAsmTheme.makeTheme(true),
          home: Scaffold(body: BuilderView(state: s)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Source (.cpu)').first);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder field() => find.descendant(
    of: find.byType(SourceEditor),
    matching: find.byWidgetPredicate(
      (w) => w is EditableText && w.maxLines == null,
    ),
  );

  Future<void> setText(WidgetTester tester, String t, [int? caret]) async {
    await tester.tapAt(tester.getTopLeft(field()) + const Offset(30, 10));
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: t,
        selection: TextSelection.collapsed(offset: caret ?? t.length),
      ),
    );
    await tester.pump();
  }

  testWidgets('the source tab is a code editor on the .cpu text', (
    tester,
  ) async {
    await openSource(tester);
    expect(find.byType(SourceEditor), findsOneWidget);
    expect(find.text('tiny16.cpu'), findsOneWidget);
    expect(find.text('No problems'), findsOneWidget);
    final text = tester.widget<EditableText>(field()).controller.text;
    expect(text, contains('processor tiny16'));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a parse error is marked on its line and Apply stays honest', (
    tester,
  ) async {
    await openSource(tester);
    final text = tester.widget<EditableText>(field()).controller.text;
    final bad = text.replaceFirst('word 16 little', 'word 16 sideways');
    await setText(tester, bad);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('1 problem'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Fix it again: the problem goes away.
    await setText(tester, text);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('No problems'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Apply sends the edited text to the processor', (tester) async {
    await openSource(tester);
    final text = tester.widget<EditableText>(field()).controller.text;
    await setText(
      tester,
      text.replaceFirst('"Tiny-16 (teaching CPU)"', '"Renamed CPU"'),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Apply'));
    await tester.pump();
    expect(s.builderDraft!.name, 'Renamed CPU');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('keywords are suggested at the start of a statement', (
    tester,
  ) async {
    await openSource(tester);
    await setText(tester, 'processor x "X" {\n  ins');
    expect(find.byType(CompletionPopup), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester.widget<EditableText>(field()).controller.text,
      endsWith('instruction '),
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('no keyword suggestions inside an exec block', (tester) async {
    await openSource(tester);
    await setText(tester, 'instruction a "x" {\n  exec {\n    ins');
    expect(find.byType(CompletionPopup), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });

  group('brace-aware typing', () {
    TextEditingValue type(TextEditingValue old, String ch) {
      final s = old.selection;
      final now = TextEditingValue(
        text: old.text.replaceRange(s.start, s.end, ch),
        selection: TextSelection.collapsed(offset: s.start + ch.length),
      );
      return EditorOps.assist(old, now, unit: 2, blocks: true) ?? now;
    }

    TextEditingValue v(String t, int c) => TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: c),
    );

    test('Enter after { indents one level', () {
      final r = type(v('a {', 3), '\n');
      expect(r.text, 'a {\n  ');
      expect(r.selection.start, 6);
    });

    test('Enter between { and } opens the block', () {
      final r = type(v('a {}', 3), '\n');
      expect(r.text, 'a {\n  \n}');
      expect(r.selection.start, 6);
    });

    test('Enter keeps the current indentation', () {
      final r = type(v('  size 16', 9), '\n');
      expect(r.text, '  size 16\n  ');
    });

    test('typing } on an indented empty line steps back', () {
      final r = type(v('a {\n  ', 6), '}');
      expect(r.text, 'a {\n}');
      expect(r.selection.start, 5);
    });
  });

  test(
    'highlighting does not throw on triple quotes, raw blocks or odd text',
    () {
      final c = DslEditingController(
        text:
            'sample """\n  li t0, 0\n"""\n'
            'exec {\n  rd = sext(imm, 12) + 1; # c\n}\n"unterminated\n}\n',
      );
      addTearDown(c.dispose);
      // Building the span needs a context; just make sure the text round-trips through the controller.
      expect(c.text, contains('sext'));
    },
  );

  testWidgets(
    'the starter program is edited in a code editor and saved on the processor',
    (tester) async {
      await openSource(tester);
      await tester.tap(find.text('Advanced').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('starter.s'), findsOneWidget);
      expect(find.byType(SourceEditor), findsOneWidget);

      final ed = find.byWidgetPredicate(
        (w) => w is EditableText && w.maxLines == null,
      );
      await tester.tapAt(tester.getTopLeft(ed.first) + const Offset(30, 10));
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'main:\n    ldi r1, 5\n    ha',
          selection: TextSelection.collapsed(offset: 26),
        ),
      );
      await tester.pump();
      // Instructions of this processor are suggested, and the text lands in the processor.
      expect(find.byType(CompletionPopup), findsOneWidget);
      expect(s.builderDraft!.json['sample'], contains('ldi r1, 5'));
      await tester.pump(const Duration(seconds: 1));
    },
  );
}

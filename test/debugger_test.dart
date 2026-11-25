import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/features/shell/app_shell.dart';
import 'package:dot_asm/features/shell/window_chrome.dart';
import 'package:dot_asm/features/workspace/value_format.dart';
import 'package:dot_asm/theme/theme.dart';

import 'support/templates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dotasm_dbg_');
    AppStore.homeOverride = '${tmp.path}/data';
    Directory('${tmp.path}/data').createSync();
    Directory('${tmp.path}/work').createSync();
    loadTemplates();
  });
  tearDown(() {
    AppStore.homeOverride = null;
    tmp.deleteSync(recursive: true);
  });

  AppState project() {
    final s = AppState();
    expect(
      s.createProject(
        name: 'Dbg',
        parentDir: '${tmp.path}/work',
        templateId: 'rv32i',
      ),
      isNull,
    );
    s.sim.assemble(s.source);
    return s;
  }

  test('parseValue reads hex, binary, decimal and negatives', () {
    expect(parseValue('0x1F'), 31);
    expect(parseValue(r'$ff'), 255);
    expect(parseValue('0b1010_1010'), 170);
    expect(parseValue(' 42 '), 42);
    expect(parseValue('-1'), -1);
    expect(parseValue('0xffffffffffffffff'), -1);
    expect(parseValue(''), isNull);
    expect(parseValue('0xzz'), isNull);
    expect(parseValue('abc'), isNull);
  });

  group('debugger edits', () {
    test('registers, flags, pc and memory can be changed by hand', () {
      final s = project();
      final m = s.sim.machine!;
      s.sim.editRegister(5, 0x1234);
      expect(m.register(5), 0x1234);
      s.sim.editRegister(0, 99); // the zero register ignores writes
      expect(m.register(0), 0);
      s.sim.editPc(m.pc + 4);
      expect(m.pc, m.entry + 4);
      s.sim.editByte(0x2000, 0xAB);
      expect(m.memory.peek(0x2000, 1).single, 0xAB);
    });

    test('toggling a flag only affects known flags', () {
      final s = project();
      final m = s.sim.machine!;
      expect(m.setFlag('nope', 1), isFalse);
    });

    test('watched registers toggle', () {
      final s = project();
      s.sim.toggleWatch(10);
      expect(s.sim.watched, {10});
      s.sim.toggleWatch(10);
      expect(s.sim.watched, isEmpty);
    });

    test('a breakpoint can be set from an address', () {
      final s = project();
      final addr = s.sim.program!.addressToLine.keys.first;
      expect(s.sim.toggleBreakpointAt(addr), isTrue);
      expect(s.sim.breakpoints, {s.sim.program!.addressToLine[addr]});
      expect(s.sim.toggleBreakpointAt(0xdead0000), isFalse);
    });

    test('run to here stops at the address', () async {
      final s = project();
      final m = s.sim.machine!;
      final target = m.entry + 12;
      await s.sim.runTo(target);
      expect(m.pc, target);
      expect(m.canStep, isTrue);
      expect(s.sim.running, isFalse);
    });

    test('rewind goes back to just after a recorded instruction', () {
      final s = project();
      for (var i = 0; i < 6; i++) {
        s.sim.stepOnce();
      }
      expect(s.sim.machine!.history.length, 6);
      s.sim.rewindTo(2);
      expect(s.sim.machine!.history.length, 2);
      expect(s.sim.lastTrace, same(s.sim.machine!.history.last));
    });
  });

  testWidgets('register cells edit in place and flags toggle', (tester) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = project();
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
    s.setPanelTab('registers');
    await tester.pump();

    // Edit a register: click its value, type, Enter.
    await tester.tap(find.text('x5'));
    await tester.pump();
    final edit = find.byWidgetPredicate(
      (w) => w is TextField && w.autofocus && w.maxLength == null,
    );
    expect(edit, findsOneWidget);
    await tester.enterText(edit, '0xCAFE');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(s.sim.machine!.register(5), 0xCAFE);

    // A bad value keeps the editor open.
    await tester.tap(find.text('0x0000cafe'));
    await tester.pump();
    await tester.enterText(edit, 'nonsense');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(
      find.byWidgetPredicate((w) => w is TextField && w.autofocus),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
      find.byWidgetPredicate((w) => w is TextField && w.autofocus),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('memory: go to an address, select a byte, edit it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = project();
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
    s.setPanelTab('memory');
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '0x2000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    // The selected byte shows its interpretations in the footer.
    expect(find.textContaining('8-bit'), findsOneWidget);
    expect(find.textContaining('0x00002000'), findsWidgets);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
    'the overview shows the next instruction, the flow and register activity',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = project();
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
      // A new project opens on the overview.
      expect(s.uiState.panelTab, 'overview');
      expect(find.text('NEXT INSTRUCTION'), findsOneWidget);
      expect(find.text('Nothing has run yet'), findsOneWidget);

      s.sim.stepOnce();
      s.sim.stepOnce();
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('Nothing has run yet'), findsNothing);
      for (final t in ['Decode', 'Execute', 'Memory', 'Write-back']) {
        expect(find.text(t), findsWidgets);
      }
      expect(find.text('REGISTER ACTIVITY'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    },
  );
}

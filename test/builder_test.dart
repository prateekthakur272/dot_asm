import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/templates.dart';

import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/app/processor_catalog.dart';
import 'package:dot_asm/app/processor_draft.dart';
import 'package:dot_asm/core/sim/asm/assembler.dart';
import 'package:dot_asm/core/sim/dsl/processor_dsl.dart';
import 'package:dot_asm/core/sim/machine/machine.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/features/shell/app_shell.dart';
import 'package:dot_asm/features/shell/window_chrome.dart';
import 'package:dot_asm/theme/theme.dart';

ProcessorSpec load(String id) => template(id);

Widget host(AppState s) => PalScope(
  pal: DotAsmTheme.palFor(true),
  child: MaterialApp(
    theme: DotAsmTheme.makeTheme(true),
    home: Scaffold(
      body: AppShell(state: s, chrome: const WindowChrome()),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late Directory data; // the app data directory
  late Directory work; // where projects are created

  setUpAll(() {
    loadTemplates();
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dotasm_builder_');
    data = Directory('${tmp.path}/data')..createSync();
    work = Directory('${tmp.path}/work')..createSync();
    AppStore.homeOverride = data.path;
  });

  tearDown(() {
    AppStore.homeOverride = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('ProcessorDraft', () {
    test('validates as it is edited', () {
      final d = ProcessorDraft(load('tiny16').toJson());
      expect(d.isValid, isTrue);
      d.edit(
        (j) =>
            (j['instructions'] as List).first['exec'] = 'rd = rs1 + nothing;',
      );
      expect(d.isValid, isFalse);
      expect(d.problems.join(), contains("'nothing'"));
      d.edit(
        (j) => (j['instructions'] as List).first['exec'] = 'rd = rs1 + rs2;',
      );
      expect(d.isValid, isTrue);
      d.edit((j) => j['wordBits'] = 12);
      expect(d.problems.join(), contains('wordBits'));
    });

    test('structural errors leave no spec but a message', () {
      final d = ProcessorDraft(load('tiny16').toJson());
      d.edit((j) => (j['memory'] as List).first['size'] = 'lots');
      expect(d.spec, isNull);
      expect(d.problems.join(), contains('size'));
    });

    test('replace swaps the whole definition', () {
      final d = ProcessorDraft(load('tiny16').toJson());
      d.replace(load('rv32i').toJson());
      expect(d.spec!.id, 'rv32i');
      expect(d.revision, 1);
    });
  });

  group('AppState processors (files in the project folder)', () {
    AppState withProject({String template = 'tiny16'}) {
      final s = AppState();
      expect(
        s.createProject(name: 'P', parentDir: work.path, templateId: template),
        isNull,
      );
      return s;
    }

    File cpuFile(AppState s, String id) =>
        File('${s.activeProject!.path}/cpu/$id.cpu');
    List<String> cpuFiles(AppState s) =>
        Directory('${s.activeProject!.path}/cpu')
            .listSync()
            .map((f) => f.path.split('/').last)
            .toList()
          ..sort();

    test('a new processor starts from the blank template and is saved as a .cpu file', () {
      final s = withProject(template: 'my-cpu');
      s.newProcessor();
      final d = s.builderDraft!;
      expect(d.isValid, isTrue);
      expect(d.name, 'My processor');
      d.set('name', 'Neo-8');
      d.set('id', 'neo-8');
      expect(s.saveDraft(), isTrue);
      expect(s.processors.map((p) => p.id), containsAll(['my-cpu', 'neo-8']));
      final f = cpuFile(s, 'neo-8');
      expect(f.existsSync(), isTrue);
      expect(
        f.readAsStringSync(),
        startsWith('# dot ASM processor definition'),
      );
      expect(f.readAsStringSync(), contains('processor neo-8 "Neo-8" {'));
      // Nothing about it lives in the app data directory.
      expect(Directory('${data.path}/processors').existsSync(), isFalse);

      s.useProcessor(s.processorById('neo-8')!);
      expect(s.activeProject!.processor.value, 'cpu/neo-8.cpu');
      expect(
        File('${s.activeProject!.path}/project.dotasm').readAsStringSync(),
        contains('processor "cpu/neo-8.cpu"'),
      );
      final m = s.sim.machine!;
      while (m.canStep) {
        m.step();
      }
      expect(m.console.toString(), '42');

      // Reopening from disk (a fresh app) finds the processor in the project.
      final s2 = AppState();
      expect(s2.activeProject!.path, s.activeProject!.path);
      expect(s2.activeProcessor!.id, 'neo-8');
      expect(s2.sim.errors, isEmpty);
    });

    test('ids must be unique inside the project', () {
      final s = withProject();
      s.newProcessor();
      s.builderDraft!.set('id', 'tiny16'); // the project already has this one
      expect(s.saveDraft(), isFalse);
      s.builderDraft!.set('id', 'one');
      expect(s.saveDraft(), isTrue);
      s.newProcessor();
      s.builderDraft!.set('id', 'one');
      expect(s.saveDraft(), isFalse);
    });

    test('invalid processors cannot be saved', () {
      final s = withProject();
      final before = cpuFiles(s);
      s.newProcessor();
      s.builderDraft!.edit((j) => j['memory'] = <dynamic>[]);
      expect(s.saveDraft(), isFalse);
      expect(cpuFiles(s), before);
    });

    test('renaming the id moves the file and the project follows', () {
      final s = withProject();
      s.newProcessor();
      s.builderDraft!.set('id', 'first');
      s.saveDraft();
      s.useProcessor(s.processorById('first')!);
      s.editProcessor(s.processorById('first')!);
      s.builderDraft!.set('id', 'second');
      expect(s.saveDraft(), isTrue);
      expect(s.processorById('first'), isNull);
      expect(cpuFile(s, 'first').existsSync(), isFalse);
      expect(cpuFile(s, 'second').existsSync(), isTrue);
      expect(s.activeProject!.processor.value, 'cpu/second.cpu');
      expect(s.activeProcessor!.id, 'second');
    });

    test('a template is copied into the project as its own file', () {
      final s = withProject();
      final t = TemplateCatalog.byId('rv32i')!;
      final spec = s.addTemplate(t)!;
      expect(cpuFile(s, 'rv32i').readAsStringSync(), t.text);
      expect(spec.sourcePath, cpuFile(s, 'rv32i').path);
      // Adding it again gets a fresh id instead of overwriting.
      final again = s.addTemplate(t)!;
      expect(again.id, 'rv32i-2');
      expect(cpuFile(s, 'rv32i-2').existsSync(), isTrue);
      expect(cpuFile(s, 'rv32i').readAsStringSync(), t.text);
    });

    test('duplicating a project processor edits a copy', () {
      final s = withProject();
      s.duplicateProcessor(s.processorById('tiny16')!);
      final d = s.builderDraft!;
      expect(d.originalId, isNull);
      expect(d.id, 'tiny16-copy');
      expect(d.name, contains('(copy)'));
      expect(s.saveDraft(), isTrue);
      expect(cpuFile(s, 'tiny16-copy').existsSync(), isTrue);
      expect(cpuFile(s, 'tiny16').existsSync(), isTrue);
    });

    test('the builder is for projects: without one it does not open', () {
      final s = AppState(); // no project
      s.openBuilder();
      expect(s.uiState.activeView, isNot('builder'));
      expect(s.builderDraft, isNull);
      s.newProcessor();
      expect(s.builderDraft, isNull);
      expect(s.saveDraft(), isFalse);
      expect(s.importProcessor(ProcessorDsl.write(load('tiny16'))), isNotEmpty);
      expect(s.processors, isEmpty);
    });

    test('customising a template with no project asks for a project (and opens the builder after)', () {
      final s = AppState();
      s.customiseTemplate(TemplateCatalog.byId('rv32i')!);
      expect(s.builderDraft, isNull);
      expect(s.modal, isA<ModalNewProject>());
      expect((s.modal! as ModalNewProject).templateId, 'rv32i');
      expect((s.modal! as ModalNewProject).openInBuilder, isTrue);
    });

    test('with a project open, new processors still go into the project', () {
      final s = withProject();
      s.newProcessor();
      s.builderDraft!.set('id', 'in-project');
      expect(s.saveDraft(), isTrue);
      expect(cpuFile(s, 'in-project').existsSync(), isTrue);
    });

    test('processors belong to their project only', () {
      final a = withProject();
      a.newProcessor();
      a.builderDraft!.set('id', 'only-in-a');
      a.saveDraft();
      final pathA = a.activeProject!.path;
      expect(
        a.createProject(name: 'B', parentDir: work.path, templateId: 'rv32i'),
        isNull,
      );
      expect(a.activeProject!.path, isNot(pathA));
      expect(a.processors.map((p) => p.id), ['rv32i']);
      expect(a.processorById('only-in-a'), isNull);
      a.openProject(pathA);
      expect(a.processorById('only-in-a'), isNotNull);
    });

    test('import accepts .cpu text and old JSON, renames clashes, explains bad files', () {
      final s = withProject();
      final spec = load('tiny16');
      final dsl = ProcessorDsl.write(spec).replaceFirst(
        'processor tiny16 "Tiny-16 (teaching CPU)"',
        'processor shared "Shared"',
      );
      expect(s.importProcessor(dsl), isEmpty);
      expect(s.processorById('shared'), isNotNull);
      expect(cpuFile(s, 'shared').existsSync(), isTrue);
      expect(s.importProcessor(dsl), isEmpty);
      expect(
        s.processors.map((p) => p.id),
        containsAll(['tiny16', 'shared', 'shared-2']),
      );

      final asJson = load('tiny16').toJson()..['id'] = 'from-json';
      expect(s.importProcessor(jsonEncode(asJson)), isEmpty);
      expect(s.processorById('from-json'), isNotNull);

      expect(s.importProcessor('not a processor'), isNotEmpty);
      expect(
        s.importProcessor('processor x "X" {\n  regsters r count 4\n}').join(),
        contains("did you mean 'registers'"),
      );
      final bad = ProcessorDsl.write(spec)
          .replaceFirst('rd = rs1 + rs2;', 'rd = ghost;')
          .replaceFirst('processor tiny16', 'processor bad');
      final before = s.processors.length;
      final problems = s.importProcessor(bad);
      expect(problems.join(), contains('ghost'));
      expect(s.processors.length, before);
    });

    test('delete removes the file', () {
      final s = withProject();
      s.newProcessor();
      s.builderDraft!.set('id', 'gone');
      s.saveDraft();
      s.deleteProcessor(s.processorById('gone')!);
      expect(s.processorById('gone'), isNull);
      expect(cpuFile(s, 'gone').existsSync(), isFalse);
    });

    test('a broken .cpu file is reported, not fatal', () {
      final s = withProject();
      File('${s.activeProject!.path}/cpu/broken.cpu')
          .writeAsStringSync('processor broken "B" {\n  wibble 1\n}\n');
      s.openProject(s.activeProject!.path);
      expect(s.processorById('tiny16'), isNotNull);
      expect(s.processorFileProblems.single, contains('broken.cpu'));
      expect(s.processorFileProblems.single, contains('line 2'));
    });
  });

  testWidgets(
    'builder UI: editor on the project processor → tabs → add an instruction → save',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final s = AppState();
      expect(
        s.createProject(name: 'UI', parentDir: work.path, templateId: 'tiny16'),
        isNull,
      );
      await tester.pumpWidget(host(s));
      s.openBuilder();
      await tester.pump();
      // The editor opens straight on the project's processor, no library in between.
      expect(s.uiState.activeView, 'builder');
      expect(s.builderDraft!.originalId, 'tiny16');
      expect(find.text('Identity'), findsOneWidget);
      expect(find.text('Add to this project'), findsNothing);

      s.newProcessor();
      await tester.pump();
      expect(find.text('Identity'), findsOneWidget);
      expect(find.text('Ready to use'), findsOneWidget);

      for (final tab in [
        'Registers & flags',
        'Memory map',
        'Instructions',
        'Advanced',
        'Source (.cpu)',
        'General',
      ]) {
        await tester.tap(find.text(tab).first);
        await tester.pump();
      }

      await tester.tap(find.text('Instructions').first);
      await tester.pump();
      expect(find.text('Add instruction'), findsOneWidget);
      await tester.tap(find.text('Add instruction'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('problem'),
        findsWidgets,
      ); // the blank instruction is incomplete
      expect(find.text('Semantics'), findsOneWidget);
      expect(s.builderDraft!.isValid, isFalse);

      // The open instruction shows its bit layout.
      expect(find.text('opcode bits'), findsWidgets);

      // Make the new instruction valid through the draft, then save through the UI state.
      s.builderDraft!.edit((j) {
        final l = j['instructions'] as List;
        final m = l.last as Map<String, dynamic>;
        m['mnemonic'] = 'swap';
        m['syntax'] = 'rd';
        m['mask'] = '0xfe3f';
        m['value'] = '0xe000';
        m['bits'] = 16;
        m['operands'] = {'rd': 'reg'};
        m['fields'] = {'rd': '[8:6]'};
        m['exec'] = 'rd = ((rd & 255) << 8) | (rd >> 8);';
      });
      await tester.pump();
      expect(
        s.builderDraft!.problems,
        isEmpty,
        reason: s.builderDraft!.problems.join('\n'),
      );
      final newId = s.builderDraft!.id;
      expect(s.saveDraft(), isTrue);
      await tester.pump();

      // The saved CPU runs a program that uses the new instruction.
      final spec = s.processorById(newId)!;
      final prog = Assembler(spec).assemble('ldi r1, 1\nswap r1\nout r1\nhalt');
      expect(prog.errors, isEmpty, reason: prog.errors.join('\n'));
      final m = Machine(spec)..loadProgram(prog);
      while (m.canStep) {
        m.step();
      }
      expect(m.console.toString(), '256');
      await tester.pump(
        const Duration(seconds: 4),
      ); // let the toast timer finish
    },
  );

  testWidgets('the builder button exists only while a project is open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = AppState(); // no project
    await tester.pumpWidget(host(s));
    // Home and sidebar offer the gallery but not the builder.
    expect(find.text('Processor gallery'), findsWidgets);
    expect(find.text('Processor builder'), findsNothing);

    expect(
      s.createProject(name: 'UI3', parentDir: work.path, templateId: 'tiny16'),
      isNull,
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Processor builder'), findsOneWidget); // workspace toolbar
    await tester.tap(find.text('Processor builder'));
    await tester.pump();
    expect(s.uiState.activeView, 'builder');
    expect(s.builderDraft!.originalId, 'tiny16');
    expect(find.text('Identity'), findsOneWidget);
    s.closeDraft();
    await tester.pump();
    expect(s.uiState.activeView, 'workspace');

    s.closeProject();
    await tester.pump();
    expect(find.text('Processor builder'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });
}

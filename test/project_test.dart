import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/templates.dart';

import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/app/processor_catalog.dart';
import 'package:dot_asm/app/sim_session.dart';
import 'package:dot_asm/core/dsl/dsl.dart';
import 'package:dot_asm/core/model/project.dart';
import 'package:dot_asm/core/storage/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late Directory data;
  late Directory work;

  setUpAll(loadTemplates);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dotasm_project_');
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

  AppState app() => AppState();
  String? create(
    AppState s, {
    String name = 'Demo',
    String proc = 'rv32i',
    bool edit = false,
    Directory? parent,
  }) => s.createProject(
    name: name,
    parentDir: (parent ?? work).path,
    templateId: proc,
    openInBuilder: edit,
  );

  group('project folders', () {
    test(
      'a project is created in the chosen folder, never in the data directory',
      () {
        final s = app();
        expect(create(s, name: 'My Demo'), isNull);
        final path = s.activeProject!.path;
        expect(path, '${work.path}/My Demo');
        expect(File('$path/project.dotasm').existsSync(), isTrue);
        expect(
          File('$path/main.s').readAsStringSync(),
          contains('Sum the numbers'),
        );
        expect(
          File('$path/project.dotasm').readAsStringSync(),
          contains('processor "cpu/rv32i.cpu"'),
        );
        // The processor is a file copied from the template: the app only reads it.
        expect(
          File('$path/cpu/rv32i.cpu').readAsStringSync(),
          TemplateCatalog.byId('rv32i')!.text,
        );
        // The data directory only holds app files and the list of project locations.
        expect(Directory('${data.path}/projects').existsSync(), isFalse);
        expect(Directory('${data.path}/processors').existsSync(), isFalse);
        final registry = jsonDecode(
          File('${data.path}/projects.json').readAsStringSync(),
        ) as Map;
        expect(registry['paths'], [path]);
        expect(Directory(path).parent.path, work.path);
      },
    );

    test('the chosen location is remembered as the next default', () {
      final s = app();
      create(s);
      expect(AppStore.lastProjectParent, work.path);
    });

    test('problems with the location are explained and nothing is created', () {
      final s = app();
      expect(
        create(s, parent: Directory('${tmp.path}/nope')),
        contains('does not exist'),
      );
      Directory('${work.path}/Taken').createSync();
      File('${work.path}/Taken/file.txt').writeAsStringSync('x');
      expect(create(s, name: 'Taken'), contains('already exists'));
      expect(s.projects, isEmpty);
      expect(create(s, proc: 'no-such-cpu'), contains('processor'));
      // An empty existing folder is fine.
      Directory('${work.path}/Empty').createSync();
      expect(create(s, name: 'Empty'), isNull);
    });

    test('names are made safe for the file system', () {
      expect(AppStore.folderNameFor('a/b:c*d'), 'a-b-c-d');
      expect(AppStore.folderNameFor('   '), 'project');
      expect(
        AppStore.folderNameFor('  My  cool   project '),
        'My cool project',
      );
      final s = app();
      expect(create(s, name: 'x/y'), isNull);
      expect(s.activeProject!.name, 'x/y');
      expect(s.activeProject!.path, '${work.path}/x-y');
    });

    test('the project list and the open project survive a restart', () {
      final s = app();
      create(s, name: 'One');
      create(s, name: 'Two', proc: 'tiny16');
      s.openProject('${work.path}/One');
      final s2 = app();
      expect(s2.projects.map((p) => p.name).toSet(), {'One', 'Two'});
      expect(s2.activeProject!.name, 'One');
      expect(s2.activeProcessor!.id, 'rv32i');
      expect(s2.sim.errors, isEmpty);
    });

    test('an existing folder can be opened (and a wrong one is explained)', () {
      final a = app();
      create(a, name: 'Shared');
      // Another machine / another data directory: only the folder is needed.
      AppStore.homeOverride = (Directory(
        '${tmp.path}/data2',
      )..createSync()).path;
      final b = app();
      expect(b.projects, isEmpty);
      expect(b.openProjectFolder('${work.path}/Shared'), isNull);
      expect(b.activeProject!.name, 'Shared');
      expect(b.projects.length, 1);
      Directory('${tmp.path}/plain').createSync();
      expect(
        b.openProjectFolder('${tmp.path}/plain'),
        contains('project.dotasm'),
      );
      File('${tmp.path}/plain/project.dotasm')
          .writeAsStringSync('project "x" {\n  speed warp\n}\n');
      expect(b.openProjectFolder('${tmp.path}/plain'), contains('line 2'));
    });

    test(
      'a folder that disappeared is shown as missing and can be forgotten',
      () {
        final s = app();
        create(s, name: 'Gone');
        create(s, name: 'Kept');
        Directory('${work.path}/Gone').deleteSync(recursive: true);
        final s2 = app();
        expect(s2.projects.map((p) => p.name), ['Kept']);
        expect(s2.missingProjectPaths, ['${work.path}/Gone']);
        s2.forgetMissing('${work.path}/Gone');
        expect(app().missingProjectPaths, isEmpty);
      },
    );

    test('removing keeps the files unless asked to delete them', () {
      final s = app();
      create(s, name: 'A');
      create(s, name: 'B');
      final a = s.projects.firstWhere((p) => p.name == 'A');
      final b = s.projects.firstWhere((p) => p.name == 'B');
      s.removeProject(a);
      expect(Directory(a.path).existsSync(), isTrue);
      s.removeProject(b, deleteFiles: true);
      expect(Directory(b.path).existsSync(), isFalse);
      expect(s.projects, isEmpty);
      expect(app().projects, isEmpty);
    });

    test('renaming changes the project file, not the folder', () {
      final s = app();
      create(s, name: 'Old');
      s.renameProject(s.activeProject!, 'New name');
      expect(
        File('${work.path}/Old/project.dotasm').readAsStringSync(),
        contains('project "New name"'),
      );
      expect(app().activeProject!.name, 'New name');
    });
  });

  group('project configuration lives in project.dotasm', () {
    test('source edits go to the project folder; outside edits are picked up on open', () async {
      final s = app();
      create(s);
      final path = s.activeProject!.path;
      s.onSourceChanged('main:\n  nop\n');
      s.flushSource();
      expect(File('$path/main.s').readAsStringSync(), 'main:\n  nop\n');
      File('$path/main.s').writeAsStringSync('main:\n  li a0, 7\n  ebreak\n');
      s.openProject(path);
      expect(s.source, contains('li a0, 7'));
      expect(s.sim.errors, isEmpty);
    });

    test('speed, breakpoints and the panel tab are saved in the project and restored', () {
      final s = app();
      create(s);
      final path = s.activeProject!.path;
      s.sim.setSpeed(SimSpeed.slow);
      s.sim.toggleBreakpoint(12);
      s.sim.toggleBreakpoint(5);
      s.setPanelTab('memory');
      final text = File('$path/project.dotasm').readAsStringSync();
      expect(text, contains('speed slow'));
      expect(text, contains('breakpoints 5 12'));
      expect(text, contains('panel memory'));
      s.sim.toggleBreakpoint(12);
      expect(
        File('$path/project.dotasm').readAsStringSync(),
        contains('breakpoints 5\n'),
      );

      final s2 = app();
      expect(s2.sim.speed, SimSpeed.slow);
      expect(s2.sim.breakpoints, {5});
      expect(s2.uiState.panelTab, 'memory');
    });

    test('creating a project copies the template file into cpu/ and can open it in the builder', () {
      final s = app();
      expect(create(s, name: 'Mine', proc: 'arm32', edit: true), isNull);
      final path = s.activeProject!.path;
      expect(File('$path/cpu/arm32.cpu').existsSync(), isTrue);
      expect(
        File('$path/project.dotasm').readAsStringSync(),
        contains('processor "cpu/arm32.cpu"'),
      );
      expect(s.activeProcessor!.sourcePath, '$path/cpu/arm32.cpu');
      expect(s.activeProcessor!.name, 'ARM (ARMv7-A, A32 subset)');
      expect(s.builderDraft, isNotNull);
      expect(s.builderDraft!.originalId, 'arm32');
      expect(s.uiState.activeView, 'builder');
      // The environment is set up from the file: it runs.
      final m = s.sim.machine!;
      while (m.canStep) {
        m.step();
      }
      expect(m.console.toString(), 'result = 110');
    });

    test(
      'the project processor is exactly the template text, plain and readable',
      () {
        final s = app();
        create(s, proc: 'tiny16');
        final text = File('${s.activeProject!.path}/cpu/tiny16.cpu')
            .readAsStringSync();
        expect(text, TemplateCatalog.byId('tiny16')!.text);
        expect(text, contains('processor tiny16 "Tiny-16 (teaching CPU)" {'));
        expect(text, contains('  registers r count 8 width 16 {'));
        expect(text, contains('  instruction add "rd, rs1, rs2" {'));
        expect(text, contains('    match 0xf007 0x0'));
        expect(text, isNot(contains('"instructions"'))); // no JSON
      },
    );

    test('a processor can be written from scratch as a .cpu file: the app just reads it', () {
      final s = app();
      create(s, proc: 'my-cpu');
      final path = s.activeProject!.path;
      File('$path/cpu/my-cpu.cpu').writeAsStringSync(
        File('$path/cpu/my-cpu.cpu')
            .readAsStringSync()
            .replaceFirst('ldi r1, 40', 'ldi r1, 41')
            .replaceFirst(
              '"Blank processor (design your own)"',
              '"Hand edited"',
            ),
      );
      File('$path/main.s').writeAsStringSync('ldi r1, 7\nout r1\nhalt\n');
      s.openProject(path);
      expect(s.activeProcessor!.name, 'Hand edited');
      final m = s.sim.machine!;
      while (m.canStep) {
        m.step();
      }
      expect(m.console.toString(), '7');
    });

    test(
      'editing a project processor by hand in the .cpu file is picked up',
      () {
        final s = app();
        create(s, proc: 'tiny16');
        final f = File('${s.activeProject!.path}/cpu/tiny16.cpu');
        f.writeAsStringSync(
          f.readAsStringSync().replaceFirst(
            'rd = rs1 + rs2;',
            'rd = rs1 + rs2 + 1;',
          ),
        );
        s.openProject(s.activeProject!.path);
        expect(s.activeProcessor!.instructions.first.exec, contains('rs2 + 1'));
      },
    );
  });

  group('project file language', () {
    test('round trip', () {
      final c = ProjectConfig(
        name: 'Round "trip"',
        processor: const ProcessorRef.file('cpu/my chip.cpu'),
        source: 'src/main.s',
        created: DateTime.utc(2026, 11, 25, 10),
        updated: DateTime.utc(2026, 11, 25, 11),
        speed: 'medium',
        breakpoints: [9, 3],
        panel: 'decode',
      );
      final text = ProjectDsl.write(c);
      final back = ProjectDsl.parse(text);
      expect(back.name, c.name);
      expect(back.processor, c.processor);
      expect(back.source, 'src/main.s');
      expect(back.created, c.created);
      expect(back.breakpoints, [3, 9]);
      expect(back.speed, 'medium');
      expect(back.panel, 'decode');
      expect(ProjectDsl.write(back), text);
    });

    test('the processor is a path; older files wrote file/builtin forms', () {
      ProcessorRef ref(String line) =>
          ProjectDsl.parse('project "X" {\n  $line\n}\n').processor;
      expect(
        ref('processor "cpu/a.cpu"'),
        const ProcessorRef.file('cpu/a.cpu'),
      );
      expect(
        ref('processor file "cpu/b.cpu"'),
        const ProcessorRef.file('cpu/b.cpu'),
      );
      expect(ref('processor builtin rv32i').builtin, isTrue);
      expect(
        ProjectDsl.write(
          ProjectDsl.parse('project "X" {\n  processor builtin rv32i\n}\n'),
        ),
        contains('processor builtin rv32i'),
      );
    });

    test('comments, defaults and clear errors', () {
      final c = ProjectDsl.parse(
        '# hello\nproject "X" {\n  processor builtin rv32i   # the CPU\n}\n',
      );
      expect(c.source, 'main.s');
      expect(c.speed, 'fast');
      DslError err(String t) {
        try {
          ProjectDsl.parse(t);
        } on DslError catch (e) {
          return e;
        }
        fail('expected an error');
      }

      expect(err('project "X" {\n}\n').message, contains('processor'));
      expect(
        err('project "X" {\n  processor builtin a\n  wibble 1\n}\n').line,
        3,
      );
      expect(
        err('project "X" {\n  processor magic a\n}\n').message,
        contains('Write the processor as'),
      );
      expect(
        err('project "X" {\n  processor builtin a\n  breakpoints 0\n}\n')
            .message,
        contains('line number'),
      );
      expect(err('nothing').message, contains('project'));
    });
  });

  group('projects from earlier versions', () {
    test('are converted in place, with their custom processor copied into the project', () {
      // Old layout: <data>/projects/<id>/{project.json,main.s} and <data>/processors/<id>.json
      final legacy = Directory('${data.path}/projects/1700000000')
        ..createSync(recursive: true);
      File('${legacy.path}/project.json').writeAsStringSync(
        jsonEncode({
          'id': '1700000000',
          'name': 'Old project',
          'processorId': 'oldcpu',
          'createdAt': '2026-01-02T03:04:05.000',
          'updatedAt': '2026-01-03T03:04:05.000',
        }),
      );
      File('${legacy.path}/main.s')
          .writeAsStringSync('main:\n  li r1, 5\n  out r1\n  halt\n');
      final plain = Directory('${data.path}/projects/1700000001')
        ..createSync(recursive: true);
      File('${plain.path}/project.json').writeAsStringSync(
        jsonEncode({
          'id': '1700000001',
          'name': 'Builtin one',
          'processorId': 'rv32i',
        }),
      );
      File('${plain.path}/main.s').writeAsStringSync('main:\n  nop\n');
      Directory('${data.path}/processors').createSync();
      final custom = template('tiny16').toJson()
        ..['id'] = 'oldcpu'
        ..['name'] = 'Old CPU';
      File('${data.path}/processors/oldcpu.json')
          .writeAsStringSync(jsonEncode(custom));

      final s = app();
      expect(s.projects.map((p) => p.name).toSet(), {
        'Old project',
        'Builtin one',
      });
      final old = s.projects.firstWhere((p) => p.name == 'Old project');
      expect(old.processor.builtin, isFalse);
      expect(File('${legacy.path}/project.dotasm').existsSync(), isTrue);
      expect(
        File('${legacy.path}/cpu/oldcpu.cpu').readAsStringSync(),
        contains('processor oldcpu "Old CPU" {'),
      );
      expect(File('${legacy.path}/project.json').existsSync(), isFalse);
      expect(File('${legacy.path}/project.json.migrated').existsSync(), isTrue);
      s.openProject(old.path);
      expect(s.activeProcessor!.name, 'Old CPU');
      final m = s.sim.machine!;
      while (m.canStep) {
        m.step();
      }
      expect(m.console.toString(), '5');
      // A project that named a template now has the template's file in its own cpu/ folder.
      final other = s.projects.firstWhere((p) => p.name == 'Builtin one');
      expect(other.processor.builtin, isFalse);
      expect(other.processor.value, 'cpu/rv32i.cpu');
      expect(
        File('${plain.path}/cpu/rv32i.cpu').readAsStringSync(),
        TemplateCatalog.byId('rv32i')!.text,
      );
      expect(
        File('${plain.path}/project.dotasm').readAsStringSync(),
        contains('processor "cpu/rv32i.cpu"'),
      );
      // The conversion happens once.
      expect(AppStore.flag('legacy_projects_migrated'), isTrue);
      expect(app().projects.length, 2);
    });
  });

  test('recent projects are ordered by when they were last opened', () {
    final s = app();
    create(s, name: 'A');
    create(s, name: 'B');
    create(s, name: 'C');
    final a = s.projects.firstWhere((p) => p.name == 'A');
    s.openProject(a.path);
    s.closeProject();
    expect(s.recentProjects().first.name, 'A');
    expect(app().recentProjects().first.name, 'A');
    expect(s.recentProjects(limit: 2).length, 2);
  });
}

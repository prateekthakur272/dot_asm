import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'support/templates.dart';

import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/app/gallery.dart';
import 'package:dot_asm/app/processor_catalog.dart';
import 'package:dot_asm/core/sim/asm/assembler.dart';
import 'package:dot_asm/core/sim/machine/machine.dart';
import 'package:dot_asm/core/sim/dsl/processor_dsl.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/features/shell/app_shell.dart';
import 'package:dot_asm/features/shell/window_chrome.dart';
import 'package:dot_asm/theme/theme.dart';

List<ProcessorSpec> loadAll() => [
  for (final f in templateFiles())
    ProcessorDsl.parse(f.readAsStringSync(), builtin: true),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final specs = loadAll();

  group('bundled processors', () {
    test('every template is valid, categorised and unique', () {
      expect(specs, isNotEmpty);
      expect(
        specs.map((s) => s.id).toSet().length,
        specs.length,
        reason: 'ids must be unique',
      );
      loadTemplates();
      expect(
        TemplateCatalog.templates.length,
        specs.length,
        reason: 'every .cpu file in assets/templates is picked up',
      );
      for (final s in specs) {
        expect(
          s.validate(),
          isEmpty,
          reason: '${s.id}: ${s.validate().take(5).join('; ')}',
        );
        expect(s.vendor, isNotEmpty, reason: '${s.id} needs a vendor');
        expect(s.year, greaterThan(1960), reason: '${s.id} needs a year');
        expect(s.tags, isNotEmpty, reason: '${s.id} needs tags');
        expect(s.sample, isNotEmpty, reason: '${s.id} needs a sample program');
        expect(s.description, isNotEmpty);
      }
    });

    testWidgets(
      'startup discovers the templates and planned list from the asset bundle',
      (tester) async {
        TemplateCatalog.templates = const [];
        PlannedCatalog.entries = const [];
        await tester.runAsync(() async {
          await TemplateCatalog.load(rootBundle);
          await PlannedCatalog.load(rootBundle);
        });
        // Exactly the .cpu files in assets/templates, found without any list in the code.
        expect(
          TemplateCatalog.templates.map((t) => t.id).toSet(),
          templateFiles()
              .map((f) => ProcessorDsl.parse(f.readAsStringSync()).id)
              .toSet(),
        );
        expect(TemplateCatalog.templates.length, templateFiles().length);
        expect(TemplateCatalog.blank!.id, 'my-cpu');
        expect(PlannedCatalog.entries, isNotEmpty);
      },
    );

    test('the app contains no processor-specific code: processors are only read from files', () {
      // Template ids that are distinctive; arch/tag labels like x86 or avr are data, not processors.
      final ids = specs.map((s) => s.id).where((id) => id.length > 4).toList();
      expect(ids, isNotEmpty);
      for (final f
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final text = f.readAsStringSync();
        for (final id in ids) {
          expect(
            text.contains("'$id'") || text.contains('"$id"'),
            isFalse,
            reason: '${f.path} mentions the processor "$id"',
          );
        }
      }
    });

    for (final s in specs) {
      test(
        '${s.name}: the sample assembles, runs to completion and prints something',
        () {
          final p = Assembler(s).assemble(s.sample);
          expect(p.errors, isEmpty, reason: p.errors.join('\n'));
          final m = Machine(s)..loadProgram(p);
          var n = 0;
          while (m.canStep && n++ < 200000) {
            m.step();
          }
          expect(m.fault, isNull, reason: '${s.id}: ${m.fault}');
          expect(
            m.status,
            MachineStatus.halted,
            reason: '${s.id} did not halt',
          );
          expect(m.console.toString().trim(), isNotEmpty);
        },
      );

      test(
        '${s.name}: disassembly of the assembled program decodes every instruction',
        () {
          final p = Assembler(s).assemble(s.sample);
          final m = Machine(s)..loadProgram(p);
          for (final r in p.codeRanges) {
            final lines = m.decoder.disassemble(m.memory, r.start, r.end);
            expect(lines, isNotEmpty);
            // Only the instruction stream we assembled: no unknown bytes.
            for (final l in lines.where(
              (l) =>
                  l.address <
                  p.addressToLine.keys.reduce((a, b) => a > b ? a : b) + 1,
            )) {
              expect(
                l.decoded,
                isNotNull,
                reason:
                    '${s.id}: undecodable at ${l.address.toRadixString(16)}',
              );
            }
          }
        },
      );
    }

    test('families cover the categories the gallery promises', () {
      final tags = {for (final s in specs) ...s.tags};
      for (final t in [
        'RISC',
        'CISC',
        'ARM',
        'x86',
        'x64',
        'RISC-V',
        'MIPS',
        'AVR',
        '8-bit',
        '16-bit',
        '32-bit',
        '64-bit',
      ]) {
        expect(tags, contains(t));
      }
      final eras = {
        for (final s in specs)
          GalleryEntry.fromTemplate(TemplateCatalog.byId(s.id)!).era,
      };
      expect(eras, {'legacy', 'modern'});
    });
  });

  group('gallery model', () {
    test('groups follow the tags', () {
      GalleryGroup g(String id) =>
          GalleryEntry.fromTemplate(TemplateCatalog.byId(id)!).group;
      expect(g('arm32'), GalleryGroup.arm);
      expect(g('x86'), GalleryGroup.x86);
      expect(g('x86_64'), GalleryGroup.x86);
      expect(g('mips32'), GalleryGroup.risc);
      expect(g('avr'), GalleryGroup.risc);
      expect(g('rv32i'), GalleryGroup.risc);
      expect(g('mos6502'), GalleryGroup.cisc);
      expect(g('tiny16'), GalleryGroup.educational);
      expect(g('my-cpu'), GalleryGroup.custom);
    });

    test('planned entries come from a data file and are not runnable', () {
      final planned = PlannedProcessor.parse(
        File('assets/gallery/planned.dotasm').readAsStringSync(),
      );
      expect(planned.length, greaterThanOrEqualTo(5));
      final entries = planned.map(GalleryEntry.fromPlanned).toList();
      expect(entries.every((e) => !e.ready), isTrue);
      expect(entries.map((e) => e.name), contains('Zilog Z80'));
      final z80 = entries.firstWhere((e) => e.name == 'Zilog Z80');
      expect(z80.year, 1976);
      expect(z80.legacy, isTrue);
      expect(z80.bits, 8);
      expect(z80.group, GalleryGroup.cisc);
    });
  });

  group('gallery UI', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('dotasm_gallery_');
      AppStore.homeOverride = '${tmp.path}/data';
      Directory('${tmp.path}/data').createSync();
      Directory('${tmp.path}/work').createSync();
      loadTemplates();
      PlannedCatalog.entries = PlannedProcessor.parse(
        File('assets/gallery/planned.dotasm').readAsStringSync(),
      );
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

    testWidgets(
      'browse, filter by era and category, search, and start a project',
      (tester) async {
        tester.view.physicalSize = const Size(1700, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final s = AppState();
        await tester.pumpWidget(host(s));
        s.openGallery();
        await tester.pump();

        expect(find.text('Processor gallery'), findsWidgets);
        expect(find.text('MOS Technology 6502'), findsOneWidget);
        expect(find.text('ARM (ARMv7-A, A32 subset)'), findsOneWidget);
        expect(find.text('ARM AArch64 (ARMv8-A)'), findsOneWidget); // planned
        expect(find.text('Planned'), findsWidgets);

        // Legacy era hides modern processors.
        await tester.tap(
          find.text('Legacy').first,
        ); // the filter pill (cards also carry a Legacy badge)
        await tester.pump();
        expect(find.text('MOS Technology 6502'), findsOneWidget);
        expect(find.text('MIPS32'), findsOneWidget);
        expect(find.text('RISC-V RV32I'), findsNothing);
        expect(find.text('x86-64 (AMD64 subset)'), findsNothing);

        // Category filter.
        await tester.tap(find.text('CISC').first);
        await tester.pump();
        expect(find.text('MOS Technology 6502'), findsOneWidget);
        expect(find.text('MIPS32'), findsNothing);
        expect(find.text('Zilog Z80'), findsOneWidget); // planned CISC

        // Back to everything, then search.
        await tester.tap(find.text('All').first);
        await tester.pump();
        await tester.tap(find.text('All').last);
        await tester.pump();
        await tester.enterText(find.byType(TextField).first, 'arduino');
        await tester.pump();
        expect(find.text('Atmel AVR (ATmega subset)'), findsOneWidget);
        expect(find.text('MIPS32'), findsNothing);
        await tester.enterText(find.byType(TextField).first, '');
        await tester.pump();

        // Use a template -> new project dialog preselects it -> create -> workspace with its sample.
        AppStore.lastProjectParent =
            '${tmp.path}/work'; // where the dialog starts
        s.modal = const ModalNewProject(templateId: 'arm32');
        await tester.pump();
        // One dialog: name, location and the (preselected) template.
        expect(find.text('Location'), findsOneWidget);
        expect(find.text('Create'), findsOneWidget);
        await tester.tap(find.text('Create'));
        await tester.pump(const Duration(milliseconds: 600));
        expect(s.activeProject!.processor.value, 'cpu/arm32.cpu');
        expect(
          File('${s.activeProject!.path}/cpu/arm32.cpu').existsSync(),
          isTrue,
        );
        expect(s.activeProject!.path, startsWith('${tmp.path}/work/'));
        expect(
          File('${s.activeProject!.path}/project.dotasm').existsSync(),
          isTrue,
        );
        expect(s.uiState.activeView, 'workspace');
        expect(s.sim.errors, isEmpty);
        await tester.runAsync(() async => s.sim.run());
        await tester.pump();
        expect(s.sim.machine!.console.toString(), 'result = 110');
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'customise copies a template file into the project and opens it',
      (tester) async {
        tester.view.physicalSize = const Size(1700, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final s = AppState();
        await tester.pumpWidget(host(s));

        // Without a project, "Customise" first asks for one (and opens the builder afterwards).
        s.customiseTemplate(TemplateCatalog.byId('mos6502')!);
        await tester.pump();
        expect(s.modal, isA<ModalNewProject>());
        expect((s.modal! as ModalNewProject).templateId, 'mos6502');
        expect((s.modal! as ModalNewProject).openInBuilder, isTrue);
        s.modal = null;

        expect(
          s.createProject(
            name: 'Custom',
            parentDir: '${tmp.path}/work',
            templateId: 'tiny16',
          ),
          isNull,
        );
        s.openGallery();
        await tester.pump();
        // The gallery lists templates, the blank starting point and the planned processors.
        // Narrow the list so the (last) Custom group is on screen.
        await tester.enterText(find.byType(TextField).first, 'blank');
        await tester.pump();
        expect(find.text('CUSTOM'), findsOneWidget);
        expect(find.text('Blank processor (design your own)'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, '');
        await tester.pump();

        s.customiseTemplate(TemplateCatalog.byId('mos6502')!);
        await tester.pump();
        expect(s.builderDraft!.id, 'mos6502');
        expect(s.builderDraft!.isValid, isTrue);
        expect(find.text('Identity'), findsOneWidget);
        expect(
          File('${s.activeProject!.path}/cpu/mos6502.cpu').existsSync(),
          isTrue,
        );
        expect(
          s.processors.map((p) => p.id),
          containsAll(['tiny16', 'mos6502']),
        );
        expect(s.saveDraft(), isTrue);
        expect(s.processorById('mos6502')!.tags, contains('MOS'));
        await tester.pump(const Duration(seconds: 4));
      },
    );
  });
}

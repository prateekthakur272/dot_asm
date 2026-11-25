import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/core/model/models.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/features/dialogs/settings_widgets.dart';
import 'package:dot_asm/features/shell/app_shell.dart';
import 'package:dot_asm/features/shell/window_chrome.dart';
import 'package:dot_asm/features/workspace/editor_logic.dart';
import 'package:dot_asm/features/workspace/editor_parts.dart';
import 'package:dot_asm/theme/theme.dart';

import 'support/templates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dotasm_settings_');
    AppStore.homeOverride = '${tmp.path}/data';
    Directory('${tmp.path}/data').createSync();
    Directory('${tmp.path}/work').createSync();
    loadTemplates();
  });
  tearDown(() {
    AppStore.homeOverride = null;
    tmp.deleteSync(recursive: true);
  });

  group('the settings model', () {
    test('every setting survives a round trip', () {
      const s = AppSettings(
        themeMode: ThemeMode.dark,
        editorFontSize: 16,
        editorTabSize: 8,
        autoClosePairs: false,
        autoSuggest: false,
        indentGuides: false,
        defaultSpeed: 'slow',
        valueFormat: 'bin',
        historyLimit: 5000,
        reopenLastProject: false,
        checkUpdates: false,
      );
      final b = AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(b.toJson(), s.toJson());
    });

    test(
      'missing, unknown and out-of-range values fall back to the defaults',
      () {
        final s = AppSettings.fromJson({
          'editorTabSize': 3,
          'editorFontSize': 99,
          'defaultSpeed': 'warp',
          'valueFormat': 'octal',
          'historyLimit': 7,
          'openAtLogin': true, // written by an older version: ignored
        });
        const d = AppSettings();
        expect(s.editorTabSize, d.editorTabSize);
        expect(s.editorFontSize, d.editorFontSize);
        expect(s.defaultSpeed, d.defaultSpeed);
        expect(s.valueFormat, d.valueFormat);
        expect(s.historyLimit, d.historyLimit);
        expect(s.toJson().containsKey('openAtLogin'), isFalse);
      },
    );

    test('the settings file no longer holds open at login after a save', () {
      File('${tmp.path}/data/settings.json').writeAsStringSync(
        jsonEncode({'themeMode': 'dark', 'openAtLogin': true}),
      );
      final loaded = AppStore.loadSettings();
      expect(loaded.themeMode, ThemeMode.dark);
      AppStore.saveSettings(loaded);
      expect(
        File('${tmp.path}/data/settings.json').readAsStringSync(),
        isNot(contains('openAtLogin')),
      );
    });
  });

  group('settings change behaviour', () {
    test('a new project starts at the default run speed', () {
      final s = AppState();
      s.updateSettings(s.settings.copyWith(defaultSpeed: 'slow'));
      expect(
        s.createProject(
          name: 'Slow',
          parentDir: '${tmp.path}/work',
          templateId: 'tiny16',
        ),
        isNull,
      );
      expect(s.activeProject!.config.speed, 'slow');
    });

    test('the undo history is limited, now and for the next machine', () {
      final s = AppState();
      s.createProject(
        name: 'H',
        parentDir: '${tmp.path}/work',
        templateId: 'rv32i',
      );
      s.sim.assemble(s.source);
      for (var i = 0; i < 30; i++) {
        s.sim.stepOnce();
      }
      expect(s.sim.machine!.history.length, 30);
      s.updateSettings(s.settings.copyWith(historyLimit: 1000));
      expect(s.sim.machine!.maxHistory, 1000);
      // A smaller limit than what is stored trims it.
      s.sim.historyLimit = 10;
      expect(s.sim.machine!.history.length, 10);
      s.sim.stepOnce();
      expect(s.sim.machine!.history.length, 10);
    });

    test('the last project is reopened only when asked', () {
      var s = AppState();
      s.createProject(
        name: 'R',
        parentDir: '${tmp.path}/work',
        templateId: 'tiny16',
      );
      s.persist();
      expect(AppState().activeProject?.name, 'R');

      s.updateSettings(s.settings.copyWith(reopenLastProject: false));
      s.persist();
      final fresh = AppState();
      expect(fresh.activeProject, isNull);
      expect(fresh.uiState.activeView, 'home');
    });
  });

  group('editor assistance follows the settings', () {
    TextEditingValue type(String before, String ch, {bool pairs = true}) {
      final old = TextEditingValue(
        text: before,
        selection: TextSelection.collapsed(offset: before.length),
      );
      final now = TextEditingValue(
        text: before + ch,
        selection: TextSelection.collapsed(offset: before.length + 1),
      );
      return EditorOps.assist(old, now, pairs: pairs) ?? now;
    }

    test('brackets close themselves unless that is off', () {
      expect(type('lw x1, 4', '(').text, 'lw x1, 4()');
      expect(type('lw x1, 4', '(', pairs: false).text, 'lw x1, 4(');
    });

    test('the indent size is used by Tab', () {
      const v = TextEditingValue(
        text: 'add',
        selection: TextSelection.collapsed(offset: 0),
      );
      expect(EditorOps.indent(v, size: 2).text, '  add');
      expect(EditorOps.indent(v, size: 8).text, '        add');
    });
  });

  testWidgets(
    'the preferences dialog has the new groups and applies a change',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = AppState();
      s.modal = const ModalSettings();
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
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Startup'), findsOneWidget);
      expect(find.text('Open at Login'), findsNothing);

      await tester.tap(find.text('Editor').last);
      await tester.pump();
      expect(find.text('Indentation'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(Segmented<int>),
          matching: find.text('8'),
        ),
      );
      await tester.pump();
      expect(s.settings.editorTabSize, 8);
      await tester.ensureVisible(find.text('Indent guides'));
      await tester.pump();
      await tester.tap(find.text('Indent guides'));
      await tester.pump();
      expect(s.settings.indentGuides, isFalse);

      await tester.tap(find.text('Simulator').last);
      await tester.pump();
      await tester.tap(find.text('Binary'));
      await tester.pump();
      expect(s.settings.valueFormat, 'bin');

      await tester.tap(find.text('Reset to defaults'));
      await tester.pump();
      expect(s.settings.toJson(), const AppSettings().toJson());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  group('the editor font size', () {
    tearDown(() => EditorMetrics.fontSize = EditorMetrics.defaultSize);

    test(
      'the line height follows the size, and 13 keeps the original layout',
      () {
        EditorMetrics.fontSize = 13;
        expect(EditorMetrics.lineHeight, 20);
        EditorMetrics.fontSize = 16;
        expect(EditorMetrics.lineHeight, 25);
        EditorMetrics.fontSize = 11;
        expect(EditorMetrics.lineHeight, 17);
        for (final n in EditorMetrics.sizes) {
          EditorMetrics.fontSize = n.toDouble();
          // Text always fits its line.
          expect(EditorMetrics.lineHeight, greaterThan(n));
        }
      },
    );

    test('a bigger font is a wider character and a wider gutter', () {
      EditorMetrics.fontSize = 12;
      final small = EditorMetrics.charWidth;
      final gutter12 = EditorGutter.width;
      EditorMetrics.fontSize = 18;
      expect(EditorMetrics.charWidth, greaterThan(small));
      expect(EditorGutter.width, greaterThan(gutter12));
    });

    test('every size in the settings is one the editor offers', () {
      for (final n in EditorMetrics.sizes) {
        expect(AppSettings.fromJson({'editorFontSize': n}).editorFontSize, n);
      }
    });

    testWidgets('changing it in preferences resizes the open editor', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1500, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = AppState();
      s.createProject(
        name: 'F',
        parentDir: '${tmp.path}/work',
        templateId: 'rv32i',
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
      Finder field() => find.byWidgetPredicate(
        (w) =>
            w is EditableText &&
            w.maxLines == null &&
            w.controller.text.contains('main'),
      );
      expect(tester.widget<EditableText>(field()).style.fontSize, 13);
      final lineBefore = tester.getSize(field()).height;

      s.updateSettings(s.settings.copyWith(editorFontSize: 18));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<EditableText>(field()).style.fontSize, 18);
      expect(tester.getSize(field()).height, greaterThan(lineBefore));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}

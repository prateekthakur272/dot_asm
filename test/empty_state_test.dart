import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/empty_state.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/features/shell/app_shell.dart';
import 'package:dot_asm/features/shell/window_chrome.dart';
import 'package:dot_asm/theme/theme.dart';

import 'support/templates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every illustration paints in both themes without errors', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      final pal = DotAsmTheme.palFor(dark);
      await tester.pumpWidget(
        PalScope(
          pal: pal,
          child: MaterialApp(
            home: Material(
              color: pal.bg,
              child: Wrap(
                children: [
                  for (final a in EmptyArt.values)
                    EmptyState(
                      art: a,
                      title: a.name,
                      subtitle: 'sub',
                      action: const SizedBox(height: 4),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
      for (final a in EmptyArt.values) {
        expect(find.text(a.name), findsOneWidget);
      }
    }
  });

  testWidgets(
    'empty messages in the app use the illustrations and fit their panels',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tmp = Directory.systemTemp.createTempSync('dotasm_empty_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      AppStore.homeOverride = '${tmp.path}/data';
      Directory('${tmp.path}/data').createSync();
      Directory('${tmp.path}/work').createSync();
      addTearDown(() => AppStore.homeOverride = null);
      loadTemplates();

      final s = AppState();
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
      // Sidebar with no projects.
      expect(find.text('No projects yet'), findsOneWidget);
      expect(find.byType(EmptyArtView), findsWidgets);
      expect(tester.takeException(), isNull);

      // A fresh project: output, trace and disassembly start empty.
      expect(
        s.createProject(
          name: 'E',
          parentDir: '${tmp.path}/work',
          templateId: 'my-cpu',
        ),
        isNull,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('The program output appears here.'), findsOneWidget);
      s.setPanelTab('trace');
      await tester.pump();
      expect(find.text('No trace yet'), findsOneWidget);
      s.setPanelTab('disassembly');
      s.onSourceChanged('');
      s.flushSource();
      s.sim.assemble('');
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    },
  );
}

// Renders the screenshots used by the README, docs and the marketplace listing into
// `.marketplace/screenshots/` and `docs/screenshots/`.
//
// It draws the real widgets of the app (not a mock-up) at 1440x900, so the images match the app. It needs macOS system
// fonts (SF Pro / SF Mono) and the Flutter SDK's Material Icons font, and is not part of `flutter test`:
//
//     flutter test tool/screenshots.dart
//
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/features/shell/app_shell.dart';
import 'package:dot_asm/features/shell/window_chrome.dart';
import 'package:dot_asm/theme/theme.dart';
import 'package:dot_asm/utils/app_metadata.dart';

import '../test/support/templates.dart';

Future<void> font(String family, String path) async {
  final l = FontLoader(family)
    ..addFont(Future.value(ByteData.view(File(path).readAsBytesSync().buffer)));
  await l.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('screenshots', (tester) async {
    await font('Menlo', '/System/Library/Fonts/SFNSMono.ttf');
    await font('Sans', '/System/Library/Fonts/SFNS.ttf');
    await font(
      'MaterialIcons',
      '${Platform.environment['FLUTTER_ROOT'] ?? Directory(Platform.resolvedExecutable).parent.parent.parent.parent.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    final tmp = Directory.systemTemp.createTempSync('dotasm_shots_');
    AppStore.homeOverride = '${tmp.path}/data';
    Directory('${tmp.path}/data').createSync();
    Directory('${tmp.path}/work').createSync();
    loadTemplates();
    // ignore: invalid_use_of_visible_for_testing_member
    AppMetadata.debugSetVersion('1.0.0');
    final s = AppState();
    s.createProject(
      name: 'Sum of numbers',
      parentDir: '${tmp.path}/work',
      templateId: 'rv32i',
    );
    s.createProject(
      name: 'Tiny CPU demo',
      parentDir: '${tmp.path}/work',
      templateId: 'tiny16',
    );
    s.createProject(
      name: 'ARM blink',
      parentDir: '${tmp.path}/work',
      templateId: 'arm32',
    );
    s.openProject(
      s.projects.firstWhere((p) => p.name == 'Sum of numbers').path,
    );
    s.sim.assemble(s.source);
    while (s.sim.machine!.canStep &&
        !s.sim.machine!.console.toString().contains('55')) {
      s.sim.stepOnce();
    }

    Future<void> shot(
      String name,
      bool dark, {
      void Function()? prep,
      Future<void> Function()? after,
      Duration settle = const Duration(milliseconds: 1600),
    }) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();
      prep?.call();
      final pal = DotAsmTheme.palFor(dark);
      await tester.pumpWidget(
        PalScope(
          pal: pal,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            builder: (c, w) => DefaultTextStyle.merge(
              style: const TextStyle(fontFamily: 'Sans'),
              child: w!,
            ),
            theme: (() {
              final t = DotAsmTheme.makeTheme(dark);
              return t.copyWith(
                textTheme: t.textTheme.apply(fontFamily: 'Sans'),
              );
            })(),
            home: Scaffold(
              backgroundColor: pal.bg,
              body: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: pal.bg,
                  child: AppShell(
                    state: s,
                    chrome: const WindowChrome(leftInset: 76),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(settle);
      if (after != null) {
        await after();
        await tester.pump(settle);
      }
      await tester.runAsync(() async {
        final b =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1.5);
        final bd = await img.toByteData(format: ui.ImageByteFormat.png);
        for (final d in ['.marketplace/screenshots', 'docs/screenshots']) {
          File('$d/$name.png').writeAsBytesSync(bd!.buffer.asUint8List());
        }
      });
    }

    await shot(
      'workspace',
      true,
      prep: () {
        s.modal = null;
        s.paletteOpen = false;
        s.setPanelTab('overview');
      },
    );
    await shot(
      'registers',
      true,
      prep: () {
        s.setPanelTab('registers');
      },
    );
    await shot(
      'memory',
      true,
      prep: () {
        s.setPanelTab('memory');
      },
    );
    await shot(
      'gallery',
      true,
      prep: () {
        s.openGallery();
      },
    );
    await shot(
      'new-project',
      true,
      prep: () {
        s.closeProject();
        AppStore.lastProjectParent = '/Users/you/asm-projects';
        s.modal = const ModalNewProject();
      },
    );
    await shot(
      'command-palette',
      true,
      prep: () {
        s.modal = null;
        s.paletteOpen = true;
      },
    );
    s.paletteOpen = false;
    s.openProject(s.projects.firstWhere((p) => p.name == 'Tiny CPU demo').path);
    s.sim.assemble(s.source);
    for (var i = 0; i < 9; i++) {
      s.sim.stepOnce();
    }
    await shot(
      'builder-source',
      true,
      prep: () {
        s.openBuilder();
      },
      after: () async {
        await tester.tap(find.text('Source (.cpu)').first);
      },
    );
    await shot(
      'light-theme',
      false,
      prep: () {
        s.closeBuilder();
        s.setPanelTab('overview');
      },
    );
    await tester.pump(const Duration(seconds: 4));
  });
}

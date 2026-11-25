import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/features/dialogs/onboarding_dialog.dart';
import 'package:dot_asm/features/shell/app_shell.dart';
import 'package:dot_asm/features/shell/window_chrome.dart';
import 'package:dot_asm/theme/theme.dart';

import 'support/templates.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dotasm_onb_');
    AppStore.homeOverride = '${tmp.path}/data';
    Directory('${tmp.path}/data').createSync();
    loadTemplates();
  });
  tearDown(() {
    AppStore.homeOverride = null;
    tmp.deleteSync(recursive: true);
  });

  test('the tour is needed until it has been marked as seen', () {
    expect(AppStore.needsOnboarding, isTrue);
    AppStore.setFlag('onboarding_completed', true);
    expect(AppStore.needsOnboarding, isFalse);
  });

  testWidgets(
    'the tour walks through its steps and ends with the ways to start',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = AppState();
      s.modal = const ModalOnboarding();
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
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(OnboardingDialog), findsOneWidget);
      expect(find.text('Welcome to dot ASM'), findsOneWidget);
      expect(find.text('Back'), findsNothing);

      for (final title in [
        'Projects are folders',
        'Run it and watch',
        'Real processors, or your own',
        'You are ready',
      ]) {
        await tester.tap(find.text('Continue'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(title), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      // The last step offers the first actions and a Done button instead of Continue.
      expect(find.text('New project'), findsWidgets);
      expect(find.text('Continue'), findsNothing);

      await tester.tap(find.text('Back'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Real processors, or your own'), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(s.modal, isNull);
      expect(find.byType(OnboardingDialog), findsNothing);
    },
  );

  testWidgets('New project on the last step opens the new project dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppState();
    s.modal = const ModalOnboarding();
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
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.tap(find.widgetWithText(Btn, 'New project').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(s.modal, isA<ModalNewProject>());
  });
}

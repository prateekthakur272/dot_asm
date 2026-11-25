import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/core/model/models.dart';
import 'package:dot_asm/core/storage/storage.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dotasm_window_');
    AppStore.homeOverride = tmp.path;
  });
  tearDown(() {
    AppStore.homeOverride = null;
    tmp.deleteSync(recursive: true);
  });

  test('size, position, maximized and full screen survive a round trip', () {
    const g = WindowGeometry(1200, 800, 40, 60, true, false);
    final back = WindowGeometry.fromJson(g.toJson());
    expect(
      [
        back.width,
        back.height,
        back.x,
        back.y,
        back.maximized,
        back.fullscreen,
      ],
      [1200, 800, 40, 60, true, false],
    );
    final full = WindowGeometry.fromJson(
      const WindowGeometry(900, 600, 1, 2, false, true).toJson(),
    );
    expect(full.fullscreen, isTrue);
  });

  test('the state keeps the size while the window returns from maximized', () {
    const g = WindowGeometry(1200, 800, 40, 60);
    final m = g.copyWith(maximized: true);
    expect(
      [m.width, m.height, m.x, m.y, m.maximized],
      [1200, 800, 40, 60, true],
    );
    expect(m.copyWith(maximized: false).maximized, isFalse);
  });

  test('nothing is saved the first time', () {
    expect(AppStore.loadWindow(), isNull);
  });

  test('the window is saved and loaded from its own file', () {
    AppStore.saveWindow(const WindowGeometry(1111, 777, 10, 20, true, true));
    final w = AppStore.loadWindow()!;
    expect(
      [w.width, w.height, w.x, w.y, w.maximized, w.fullscreen],
      [1111, 777, 10, 20, true, true],
    );
    expect(File('${tmp.path}/window.json').existsSync(), isTrue);
  });

  test('saving the UI state never puts an old window size back', () {
    AppStore.saveState(const SavedState());
    AppStore.saveWindow(const WindowGeometry(1500, 900, 5, 5));
    // Toggling the sidebar (or anything else) rewrites state.json many times while the app runs.
    AppStore.saveState(AppStore.loadState().copyWith(sidebarVisible: false));
    AppStore.saveState(const SavedState(sidebarVisible: true));
    final w = AppStore.loadWindow()!;
    expect([w.width, w.height], [1500, 900]);
  });

  test('a window saved by an older version in state.json is still read', () {
    AppStore.saveState(
      const SavedState().copyWith(
        window: const WindowGeometry(1000, 700, 1, 2),
      ),
    );
    expect(AppStore.loadWindow()!.width, 1000);
    // Once the new file exists it wins.
    AppStore.saveWindow(const WindowGeometry(1300, 850));
    expect(AppStore.loadWindow()!.width, 1300);
  });
}

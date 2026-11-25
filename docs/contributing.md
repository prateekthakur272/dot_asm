# Contributing to dot ASM

Thank you for contributing to dot ASM! This guide covers the local setup, the code rules and how to submit changes.

## Ways to help

- **Report a bug**: use **Help ▸ Report an Issue…** or open a GitHub issue with the steps to reproduce, what you expected,
  and your platform. For a processor problem attach the `.cpu` file.
- **Add a processor**: a new template is one file. See [Adding a template](PROCESSORS.md#adding-a-template).
- **Improve the docs**: fix or extend anything in `docs/`.
- **Fix something or add a feature**: open an issue first for anything large, so the approach can be agreed.

## Local setup

1. Install [Flutter](https://docs.flutter.dev/get-started/install) (stable channel). dot ASM uses Flutter 3.50.0
   (Dart SDK `^3.14.0`).
2. Clone and run:
   ```bash
   git clone https://github.com/prateekthakur272/dot_asm.git
   cd dot_asm
   flutter pub get
   flutter run -d macos    # or -d windows, -d linux
   ```
3. Check your work:
   ```bash
   dart format lib test
   flutter analyze
   flutter test
   ```

## Rules of the code

Read [ARCHITECTURE.md](ARCHITECTURE.md), [project-structure.md](project-structure.md) and [AGENTS.md](../AGENTS.md). The
invariants that matter most:

1. **Layers.** `core/` is pure Dart and never imports `app/`, `features/`, `components/`, `theme/` or `platform/`. New
   screens go in `features/<name>/`; reusable widgets in `components/`.
2. **No processor in code.** A processor is a `.cpu` file; nothing in `lib/` may mention one by name (a test enforces
   it). Behaviour that differs between processors belongs in the file's format and the engine, not in an `if`.
3. **State.** One `AppState`. Feature state goes in `app_state_<topic>.dart` extensions or the session objects; widgets
   get the state passed in and listen with `ListenableBuilder`.
4. **Projects live where the user chooses**, never in `~/.dotasm`. App data is read and written through `AppStore`.
5. **Desktop behaviour.** Drag handles and splitters pass `supportedDevices: kDragDevices`; scrolling uses
   `ClampingScrollPhysics`; shortcuts are platform-aware (`⌘` on macOS, `Ctrl` elsewhere).
6. **Errors are logged, never swallowed.** Use `Log` with a tag.

## Tests

```bash
flutter test
```

- **Engine tests** (`test/sim/`) check real machine words for each processor, step traces, faults and undo.
- **Logic tests** (`test/editor_logic_test.dart`, `test/dsl_test.dart`) are pure Dart.
- **Widget tests** build the real screens. Tests that touch storage set `AppStore.homeOverride` to a temporary
  directory, and create projects in a temporary folder.
- A new processor needs a `test/sim/<id>_test.dart` with known encodings and a program that runs to a result.

## Screenshots

The images in `docs/screenshots/` and `.marketplace/screenshots/` are rendered from the real widgets:

```bash
flutter test tool/screenshots.dart
```

It needs the macOS system fonts, so run it on a Mac. Update them when the interface changes noticeably.

## Pull requests

1. `dart format lib test` and `flutter analyze` report nothing.
2. `flutter test` passes.
3. The docs and `README.md` match what you changed (features, shortcuts, file formats).
4. The description says what changed and why, and how you tested it.

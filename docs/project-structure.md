# Project structure

```
dot_asm/
  assets/
    icons/                 app icon and header logo
    templates/*.cpu        the processors offered in the gallery (plain text, no code)
    gallery/planned.dotasm processors that are listed but not simulated yet
  docs/                    this documentation (and docs/screenshots)
  .marketplace/            the marketplace listing: app-info.yaml, icon, screenshots
  tool/screenshots.dart    renders the screenshots
  lib/
    main.dart              startup, window, global shortcuts
    app/                   AppState and the session/draft/catalog objects
    components/            reusable widgets (buttons, inputs, selectable rows, context menu, empty states)
    core/                  pure Dart: models, the block language (dsl), the simulator (sim), storage, logging
    features/              screens: shell, projects, workspace, processor_builder, dialogs
    platform/              OS bridges (window helpers, open at login)
    theme/                 palette (Pal), theme, icons
    utils/                 AppConfig, AppMetadata, paths, issue report, update checker
  test/                    unit, engine and widget tests (test/sim: one file per processor)
  macos/ windows/ linux/   platform runners and installer packaging (fastforge)
  .github/workflows/       CI and the release build
```

## `lib/core`

| Folder | What it holds |
|---|---|
| `dsl/` | The block language parser used by both file types (`#` / `//` comments, `{ }` blocks, `"""` strings) |
| `model/` | `Project`, `ProjectConfig`, `ProjectDsl` (the `project.dotasm` format) and the app-state models |
| `sim/spec/` | `ProcessorSpec`: registers, flags, memory, instruction encodings and semantics |
| `sim/dsl/` | `ProcessorDsl`: reads and writes `.cpu` files |
| `sim/expr.dart` | The semantics language: parsed once, evaluated per instruction, no loops or I/O |
| `sim/asm/` | The two-pass assembler: labels, directives, pseudo-instructions, errors with line numbers |
| `sim/machine/` | `Machine` (step, undo, faults), `Memory` with permissions, the instruction `Decoder` |
| `storage/` | `AppStore`: app data under `~/.dotasm`, project folders, processor files |

## `lib/app`

`AppState` owns everything the UI shows: the project list and the open project, the open view, modals, the command
palette and the toast. `SimSession` drives the machine of the open project (assemble, run, step, step back, breakpoints,
debugger edits). `ProcessorDraft` is the processor being edited in the builder. `TemplateCatalog` and the gallery
types read the templates from the asset bundle.

## `lib/features`

| Folder | Screens |
|---|---|
| `shell/` | Window, title bar, menus, command palette, status bar |
| `projects/` | Sidebar (with the app header), start screen, processor gallery |
| `workspace/` | Toolbar, assembly editor, bottom panel, the processor panel (overview, registers, memory, disassembly, decode, trace) |
| `processor_builder/` | The builder: forms, instruction editor, the `.cpu` source editor and the starter-program editor |
| `dialogs/` | Settings, About, Developer, Update, New project, project and processor dialogs |

The two code editors share their logic (`workspace/editor_logic.dart`: indentation, comments, line commands, brackets,
find, suggestions) and pieces (`workspace/editor_parts.dart`: gutter, suggestion popup, find bar, header, status strip).

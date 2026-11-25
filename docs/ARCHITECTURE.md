# dot ASM architecture

`lib/main.dart` initialises metadata, platform and the window, then runs `dot ASMApp`, which owns the `AppState`, the
palette (`Pal` via `PalScope`), global shortcuts, window-bounds persistence and the update check. `AppShell` composes
the title bar, the sidebar (which carries the app header), the main view, the status bar, the command palette, the modal
overlay and the toast. The main view is one of: start screen, processor gallery, workspace or processor builder.

See `AGENTS.md` for the layer rules. Startup order:

1. `AppMetadata.load()` reads version/build from the platform.
2. `Platform.init()` and `windowManager.ensureInitialized()`.
3. Saved window geometry is restored (only when still on a visible display).
4. `runApp`; after the first frame the window is shown, so there is no flicker.
5. After the first frame an update check runs against GitHub releases (`UpdateChecker`); a newer, not-dismissed
   release opens the *Update Available* dialog, and a badge stays in the status bar.

## Data on disk

App data (`~/.dotasm`):

| File | Contents |
|---|---|
| `settings.json` | `AppSettings`: theme mode, open at login |
| `state.json` | `SavedState`: sidebar, window geometry, open view |
| `prefs.json` | Small flags: dismissed update version, last project location |
| `projects.json` | The folders of the known projects (the projects themselves are not stored here) |
| `dotasm.log` | Rotating log, 1 MB with `.old` backup |

A project is a folder the user chooses:

| File | Contents |
|---|---|
| `project.dotasm` | Project configuration in the block language: name, processor, source file, speed, breakpoints, panel tab |
| `main.s` | The assembly source |
| `cpu/*.cpu` | The project's own processors in the block language |

See [PROCESSORS.md](PROCESSORS.md) for the file formats.

## The simulator

Nothing about a particular processor is written in code. A `.cpu` file is read by `ProcessorDsl` into a `ProcessorSpec`,
and one generic engine builds everything from it:

```
.cpu text ──▶ ProcessorSpec ──▶ Assembler   (two passes: labels, directives, pseudo-instructions)
                    │
                    ├─────────▶ Decoder     (mask/value match, operand fields, disassembly)
                    └─────────▶ Machine     (registers, flags, memory with permissions, step, undo)
                                   └── semantics: the `exec` expressions, parsed once, no loops or I/O
```

`SimSession` (in `lib/app/`) owns the machine of the open project and drives it: assembling the source, running in
time-sliced batches so the UI stays responsive, stepping, stepping back, breakpoints, "run to here", and the debugger
edits. Every step returns a `StepTrace` (registers, flags and memory touched, output, cycles, fault); the same trace
feeds the Overview, the Trace tab and the undo log.

## The editors

The assembly editor (`features/workspace/code_editor.dart`) and the processor source editor
(`features/processor_builder/dsl_editor.dart`, the `SourceEditor`) are built on Flutter's text field. What a text field
does not provide is in `workspace/editor_logic.dart` (pure functions on a `TextEditingValue`: indentation, comments, line
commands, brackets, find, and `CompletionIndex` for suggestions) and `workspace/editor_parts.dart` (gutter, suggestion
popup, find bar, header and status strip). Highlighting comes from the text controller's `buildTextSpan`. Because the
font is monospaced, positions of overlays (matches, brackets, error underlines, the popup) are computed from line and
column instead of measuring text.

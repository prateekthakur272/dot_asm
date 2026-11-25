# dot ASM Development Instructions

dot ASM mirrors the architecture and desktop patterns of the sibling `devspace` app. Keep new code consistent with them.

## Layers (`lib/`, imports are `package:dot_asm/...`)

| Layer | Owns | May depend on |
|---|---|---|
| `core/` | Models, storage (`AppStore`), logging (`Log`) | `utils/` |
| `utils/` | `AppConfig`, `AppMetadata`, `Paths`, `Json`, `IssueReport`, `UpdateChecker` | `core/logging`, `core/storage` |
| `theme/`, `platform/` | `Pal` palette + icons; OS bridges (`Platform`, `LaunchAtStartup`) | `core/logging`, `utils/` |
| `components/` | Reusable widgets: `Btn`, `IconBtn`, `T`, `ModalScaffold`, `SplitPane`, `ContextMenu`, `HoverBuilder` | `theme/` |
| `app/` | `AppState` (`ChangeNotifier`), sealed `AppModal` | `core/`, `platform/` |
| `features/*` | `shell/` (window, menus, palette, status bar), `dialogs/` (settings, about, developer, update) | everything above |

**Invariant:** `core/` never imports `app/`, `features/`, `components/`, `theme/` or `platform/`.

## Rules

- Single source of truth: `AppState`; add feature state in `app_state_<topic>.dart` extensions. Widgets get the state passed in and listen with `ListenableBuilder`.
- Modals: add a case to `AppModal` (`app/modal.dart`) and resolve it in `buildActiveModal` (`features/dialogs/modals.dart`).
- Identity (name, links, repo URL) lives only in `AppConfig`. The version lives only in `pubspec.yaml` and is read back by `AppMetadata`.
- Data lives under `~/.dotasm` (`settings.json`, `state.json`, `prefs.json`, `dotasm.log`), resolved through `Paths` and read/written through `AppStore`. Tests set `AppStore.homeOverride`.
- Window: hidden title bar via `window_manager`, custom chrome in `window_chrome.dart`, persisted bounds with an on-screen check, `setPreventClose(true)` then `persist()` before `destroy()`, show the window only after the first frame.
- Drag handles and splitters pass `supportedDevices: kDragDevices` so trackpad scrolling never resizes panes.
- Scrolling uses `ClampingScrollPhysics`; no overscroll glow, no scrollbars.
- Shortcuts are platform-aware (`⌘` on macOS, `Ctrl` elsewhere). `Cmd/Ctrl+K` opens the command palette.
- Never swallow errors silently: log through `Log` with a tag.

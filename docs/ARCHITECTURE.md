# dot ASM architecture

`lib/main.dart` initialises metadata, platform and the window, then runs `dot ASMApp`, which owns the `AppState`, the
palette (`Pal` via `PalScope`), global shortcuts, window-bounds persistence and the update check. `AppShell` composes
the title bar, top bar, sidebar, main view, status bar, command palette, modal overlay and toast.

See `AGENTS.md` for the layer rules. Startup order:

1. `AppMetadata.load()` reads version/build from the platform.
2. `Platform.init()` and `windowManager.ensureInitialized()`.
3. Saved window geometry is restored (only when still on a visible display).
4. `runApp`; after the first frame the window is shown, so there is no flicker.
5. After the first frame an update check runs against GitHub releases (`UpdateChecker`); a newer, not-dismissed
   release opens the *Update Available* dialog, and a badge stays in the status bar.

## Data on disk (`~/.dotasm`)

| File | Contents |
|---|---|
| `settings.json` | `AppSettings`: theme mode, open at login |
| `state.json` | `SavedState`: sidebar, window geometry |
| `prefs.json` | Small flags, e.g. the dismissed update version |
| `dotasm.log` | Rotating log, 1 MB with `.old` backup |

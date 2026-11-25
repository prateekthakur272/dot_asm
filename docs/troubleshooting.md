# Troubleshooting

## Where dot ASM keeps its files

App data lives in `~/.dotasm` (on Windows: `%USERPROFILE%\.dotasm`). Choose **Help ▸ Show Data Folder** (or **File ▸ Show
Data Folder** on macOS) to open it.

| File | Purpose |
|---|---|
| `settings.json` | Preferences: theme, open at login |
| `state.json` | Window position, sidebar, the open project and view |
| `prefs.json` | Small flags: the dismissed update, the last project location, recent projects |
| `projects.json` | Where your projects are (the projects themselves are not stored here) |
| `dotasm.log` | Rotating log of warnings and errors (**Help ▸ Show Log File**) |

Your projects are ordinary folders in the places you chose; they are never moved into `~/.dotasm`.

To reset the app to a clean state, quit it, move or rename `~/.dotasm`, and start it again. Your projects are untouched;
add them back with **Open project…**.

## Projects

- **A project shows "missing" in the sidebar.** Its folder was moved, renamed or deleted. If you moved it, remove the
  entry and open the new location with **Open project…**.
- **"There is no project.dotasm in …".** Choose the folder that contains `project.dotasm`, not a parent or a subfolder.
  If the message starts with `project.dotasm:` the file itself has a mistake; it names the line.
- **"This project's processor was not found".** The project names a processor file that is not in its `cpu/` folder. Put
  the file back, or open `project.dotasm` and point `processor` at a file that exists.
- **Edits I made outside the app are gone.** The app re-reads the source when a project is opened. If you edit
  `main.s` elsewhere while the project is open, close it in the app and reopen it afterwards, and avoid editing both
  places at once.

## Assembling and running

- **"Unknown instruction".** The instruction is not defined by this processor. Every processor has its own set: check
  the starter program, the Disassembly tab, or the processor's Instructions list in the builder.
- **An instruction assembles but the operand is rejected.** Look at the instruction's **syntax** in the builder (or in
  the suggestions popup) and at which operands are registers, numbers or branch targets. Immediates have a limited range
  that depends on the encoding.
- **The program stops with a fault.** The Overview says why: typically a load or store outside any memory region, a
  store to read-only memory, a misaligned access on a processor that requires alignment, or an instruction that does not
  decode (for example, running past the end of the code).
- **Run does nothing.** The processor has not been assembled because of an error (see **Problems**), or the program has
  already finished: press **Reset**.
- **A long loop seems stuck.** Press **Pause**, or switch the speed to *Fast*. Breakpoints are the quickest way to look
  inside a loop.

## Processor files

- **"line N: …" when applying or opening a `.cpu` file.** The message names the line and, for a misspelled statement,
  suggests the right one. The Source tab marks the line in red.
- **The builder says "N problems".** Click the status card at the bottom of its navigation to list them. Common ones are
  a mask and value that do not overlap correctly, an operand that is not in the semantics, and two instructions with the
  same encoding.
- **My changes to a processor do not take effect in the running program.** Save it, and make sure the project uses it
  (**Use in project**).

See [PROCESSORS.md](PROCESSORS.md) for the file format.

## Windows and Linux

- **Windows SmartScreen warns about the installer.** The installers are not signed yet. Choose **More info ▸ Run anyway**.
- **macOS says the app is from an unidentified developer.** Right-click the app and choose **Open** the first time.
- **Linux AppImage does not start.** Make it executable (`chmod +x`) and install FUSE if your distribution does not ship
  it (`sudo apt install libfuse2`).

## Reporting a problem

Use **Help ▸ Report an Issue…** (or the bug icon in the status bar). It opens a GitHub issue with your version and
platform filled in. Attach the relevant part of `dotasm.log` and, if it is about a processor, the `.cpu` file.

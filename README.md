# dot ASM

An assembly learning and processor design toolkit (Flutter: macOS, Windows, Linux).

* **Projects**: a project is a folder you choose, holding `project.dotasm`, your source and a `cpu/` folder. Pick a processor, write assembly, step through it and watch registers, flags, memory, the decoded
  instruction bits and a trace update live. Run, pause, step back, breakpoints.
* **Processor gallery**: templates by family and era (RISC-V, MIPS, ARM, x86, x86-64, MOS 6502, AVR, a teaching CPU and a
  blank one). They are plain `.cpu` files: creating a project copies one into the project, and the app just reads it.
* **Processor builder**: design your own processor (word size, registers, flags, memory map, instruction encodings and
  semantics), validate it live, and keep it as a readable `.cpu` file in the project. See [docs/PROCESSORS.md](docs/PROCESSORS.md).

```
flutter pub get
flutter run -d macos
flutter analyze && flutter test
```

Architecture and rules: [AGENTS.md](AGENTS.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
Name, links and repo URL are set in `lib/utils/app_config.dart`.

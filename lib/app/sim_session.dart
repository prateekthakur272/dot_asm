import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:dot_asm/core/sim/asm/assembler.dart';
import 'package:dot_asm/core/sim/asm/program.dart';
import 'package:dot_asm/core/sim/machine/machine.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';

enum SimSpeed {
  slow('Slow', 1, Duration(milliseconds: 600)),
  medium('Medium', 1, Duration(milliseconds: 120)),
  fast('Fast', 4000, Duration(milliseconds: 16));

  const SimSpeed(this.label, this.stepsPerTick, this.tickDelay);
  final String label;
  final int stepsPerTick;
  final Duration tickDelay;
}

/// Owns the machine of the open project and drives it: assemble, step, back-step, run, pause, breakpoints.
///
/// Running is time-sliced on the UI isolate (a batch of instructions per tick), so it stays responsive and can be
/// paused at any moment.
class SimSession extends ChangeNotifier {
  ProcessorSpec? spec;
  Assembler? _assembler;
  Machine? machine;
  AssembledProgram? program;
  List<AsmDiagnostic> errors = const [];
  StepTrace? lastTrace;

  /// 1-based source lines with a breakpoint.
  final Set<int> breakpoints = {};
  SimSpeed speed = SimSpeed.fast;

  /// Called when the speed or the breakpoints change, so the project file can be updated.
  VoidCallback? onPersist;
  bool running = false;
  int _token = 0;

  bool get hasProgram => program != null && errors.isEmpty;
  bool get canStep =>
      hasProgram && machine != null && machine!.canStep && !running;
  bool get canRun =>
      hasProgram && machine != null && machine!.canStep && !running;
  bool get canUndo => machine != null && machine!.canUndo && !running;

  Set<int> get changedRegisters => {
    for (final c in lastTrace?.regWrites ?? const <RegChange>[]) c.index,
  };
  Set<String> get changedFlags => {
    for (final c in lastTrace?.flagWrites ?? const <FlagChange>[]) c.name,
  };

  /// Source line of the next instruction, if known.
  int? get currentLine {
    final m = machine;
    if (m == null || program == null || errors.isNotEmpty) return null;
    return program!.addressToLine[m.pc];
  }

  int _historyLimit = 20000;

  /// How many steps can be undone. Applies to the running machine at once.
  set historyLimit(int n) {
    _historyLimit = n;
    final m = machine;
    if (m == null) return;
    m.maxHistory = n;
    if (m.history.length > n) m.history.removeRange(0, m.history.length - n);
  }

  /// Switches to another processor; clears the program.
  void configure(ProcessorSpec s) {
    pause();
    spec = s;
    _assembler = Assembler(s);
    machine = Machine(s, maxHistory: _historyLimit);
    program = null;
    errors = const [];
    lastTrace = null;
    notifyListeners();
  }

  /// Assembles [source]; on success the machine restarts with the new program.
  void assemble(String source) {
    final a = _assembler;
    if (a == null) return;
    pause();
    final p = a.assemble(source);
    errors = p.errors;
    lastTrace = null;
    if (p.ok) {
      program = p;
      machine!.loadProgram(p);
    }
    notifyListeners();
  }

  void reset() {
    pause();
    _runTo = null;
    machine?.reset();
    lastTrace = null;
    notifyListeners();
  }

  void stepOnce() {
    if (!canStep) return;
    lastTrace = machine!.step();
    notifyListeners();
  }

  void stepBack() {
    if (!canUndo) return;
    machine!.undo();
    final h = machine!.history;
    lastTrace = h.isEmpty ? null : h.last;
    notifyListeners();
  }

  // --- Debugger edits ---

  /// Registers pinned to the top of the register view.
  final Set<int> watched = {};

  void toggleWatch(int register) {
    if (!watched.remove(register)) watched.add(register);
    notifyListeners();
  }

  /// Edits made by hand do not enter the step history, so they cannot be stepped back.
  void editRegister(int index, int value) {
    machine?.setRegister(index, value);
    notifyListeners();
  }

  void editFlag(String name, int value) {
    machine?.setFlag(name, value);
    notifyListeners();
  }

  void editPc(int address) {
    machine?.setPc(address);
    notifyListeners();
  }

  void editByte(int address, int value) {
    machine?.memory.poke(address, [value & 0xFF]);
    notifyListeners();
  }

  /// Toggles the breakpoint on the source line of the instruction at [address].
  bool toggleBreakpointAt(int address) {
    final line = program?.addressToLine[address];
    if (line == null) return false;
    toggleBreakpoint(line);
    return true;
  }

  int? _runTo;

  /// Runs until the program counter reaches [address] (or a breakpoint, halt or fault comes first).
  Future<void> runTo(int address) {
    _runTo = address;
    return run();
  }

  /// Undoes steps until [count] instructions remain in the history ("rewind to here").
  void rewindTo(int count) {
    final m = machine;
    if (m == null || running) return;
    while (m.history.length > count && m.canUndo) {
      m.undo();
    }
    lastTrace = m.history.isEmpty ? null : m.history.last;
    notifyListeners();
  }

  void toggleBreakpoint(int line) {
    if (!breakpoints.remove(line)) breakpoints.add(line);
    notifyListeners();
    onPersist?.call();
  }

  void setSpeed(SimSpeed s) {
    speed = s;
    notifyListeners();
    onPersist?.call();
  }

  Set<int> get _breakpointAddresses {
    final p = program;
    if (p == null) return const {};
    return {for (final l in breakpoints) ?p.addressOfLine(l)};
  }

  Future<void> run() async {
    if (!canRun) return;
    running = true;
    final token = ++_token;
    notifyListeners();
    final m = machine!;
    var first = true;
    while (running && token == _token && m.canStep) {
      final bps = {..._breakpointAddresses, ?_runTo};
      for (var i = 0; i < speed.stepsPerTick && m.canStep; i++) {
        if (!first && bps.contains(m.pc)) {
          running = false;
          break;
        }
        first = false;
        final t = m.step();
        lastTrace = t;
        if (t == null || t.failed || t.halted) break;
      }
      notifyListeners();
      if (!running) break;
      await Future<void>.delayed(speed.tickDelay);
    }
    if (token == _token) running = false;
    _runTo = null;
    notifyListeners();
  }

  void pause() {
    if (!running) return;
    running = false;
    _token++;
    notifyListeners();
  }

  @override
  void dispose() {
    running = false;
    _token++;
    super.dispose();
  }
}

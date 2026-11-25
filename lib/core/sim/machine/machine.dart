import 'package:dot_asm/core/sim/asm/program.dart';
import 'package:dot_asm/core/sim/expr.dart';
import 'package:dot_asm/core/sim/machine/decoder.dart';
import 'package:dot_asm/core/sim/machine/memory.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';

enum MachineStatus {
  /// No program loaded yet.
  empty,

  /// Ready to execute the next instruction.
  ready,

  /// The program ended (halt instruction).
  halted,

  /// The last instruction failed; see [Machine.fault].
  faulted,
}

class RegChange {
  const RegChange(this.index, this.oldValue, this.newValue);
  final int index;
  final int oldValue;
  final int newValue;
}

class FlagChange {
  const FlagChange(this.name, this.oldValue, this.newValue);
  final String name;
  final int oldValue;
  final int newValue;
}

class MemAccess {
  const MemAccess({
    required this.address,
    required this.size,
    required this.value,
    required this.write,
    this.oldBytes = const [],
  });

  final int address;
  final int size;
  final int value;
  final bool write;

  /// The bytes that were overwritten (for undo).
  final List<int> oldBytes;
}

/// Everything one instruction did. This is the feed for the live view and also the undo record.
class StepTrace {
  StepTrace({
    required this.pcBefore,
    required this.pcAfter,
    required this.raw,
    required this.length,
    required this.text,
    required this.decoded,
    this.regWrites = const [],
    this.flagWrites = const [],
    this.memAccesses = const [],
    this.output = '',
    this.cycles = 1,
    this.halted = false,
    this.fault,
  });

  final int pcBefore;
  final int pcAfter;

  /// Instruction word (0 when the fetch failed).
  final int raw;
  final int length;

  /// Disassembly of the executed instruction.
  final String text;

  /// How the instruction was decoded (matched encoding and operand values), or null on fetch failure.
  final Decoded? decoded;
  final List<RegChange> regWrites;
  final List<FlagChange> flagWrites;
  final List<MemAccess> memAccesses;
  final String output;
  final int cycles;
  final bool halted;
  final String? fault;

  bool get failed => fault != null;
}

class _Halt implements Exception {}

/// A processor built from a [ProcessorSpec]: registers, flags, pc, memory and the instruction interpreter.
class Machine implements ExprEnv {
  Machine(this.spec, {this.maxHistory = 20000})
    : memory = Memory(spec),
      decoder = Decoder(spec),
      _regs = List.filled(spec.registerCount, 0),
      _flags = {for (final f in spec.flags) f: 0},
      bits = spec.wordBits,
      _addrMask = spec.wordBits >= 64 ? -1 : (1 << spec.wordBits) - 1 {
    reset();
  }

  final ProcessorSpec spec;
  final Memory memory;
  final Decoder decoder;
  final int bits;
  final int _addrMask;

  final List<int> _regs;
  final Map<String, int> _flags;
  int pc = 0;
  MachineStatus status = MachineStatus.empty;
  String? fault;
  int instructionCount = 0;
  int cycleCount = 0;
  final StringBuffer console = StringBuffer();

  AssembledProgram? program;

  /// Executed instructions, newest last, for [undo].
  final List<StepTrace> history = [];

  /// How many executed instructions are kept for [undo]; the oldest are dropped beyond it.
  int maxHistory;

  int get entry => program?.entry ?? spec.resetPc;

  int register(int index) => _regs[index];
  int flag(String name) => _flags[name] ?? 0;
  Map<String, int> get flags => Map.unmodifiable(_flags);
  List<int> get registers => List.unmodifiable(_regs);

  int _regMask(int idx) {
    final w = spec.registerWidth(idx);
    return w >= 64 ? -1 : (1 << w) - 1;
  }

  /// Sets a register directly (debugger edit). Respects the zero register.
  void setRegister(int index, int value) {
    if (index == spec.zeroRegister) return;
    _regs[index] = value & _regMask(index);
  }

  /// Sets a flag directly (debugger edit). Returns false for an unknown flag.
  bool setFlag(String name, int value) {
    if (!_flags.containsKey(name)) return false;
    _flags[name] = value & 1;
    return true;
  }

  /// Moves the program counter directly (debugger edit). A stopped (halted) machine becomes ready again.
  void setPc(int value) {
    pc = value & _addrMask;
    if (status == MachineStatus.halted) status = MachineStatus.ready;
  }

  /// Clears registers, flags, memory, history and output, then reloads the current program.
  void reset() {
    _regs.fillRange(0, _regs.length, 0);
    for (final k in _flags.keys.toList()) {
      _flags[k] = 0;
    }
    memory.clear();
    history.clear();
    console.clear();
    instructionCount = 0;
    cycleCount = 0;
    fault = null;
    pc = spec.resetPc;
    spec.init.forEach((name, v) {
      final i = spec.registerIndexExact(name);
      if (i != null) setRegister(i, v);
    });
    final p = program;
    if (p != null) {
      for (final s in p.segments) {
        memory.poke(s.address, s.bytes);
      }
      pc = p.entry;
      status = MachineStatus.ready;
    } else {
      status = MachineStatus.empty;
    }
  }

  /// Loads an assembled program and resets the machine to its entry point.
  void loadProgram(AssembledProgram p) {
    program = p;
    reset();
  }

  // -------------------------------------------------------------------------------------------------------------
  // Execution

  late List<RegChange> _regLog;
  late List<FlagChange> _flagLog;
  late List<MemAccess> _memLog;
  late Map<String, int> _locals;
  late Map<String, int> _ops;
  late InstructionSpec _cur;
  late int _curPc;
  late int _nextPc;
  int? _newPc;
  final StringBuffer _out = StringBuffer();

  bool get canStep => status == MachineStatus.ready;

  /// Executes one instruction. Returns null when the machine cannot run (see [status]).
  StepTrace? step() {
    if (!canStep) return null;
    final startPc = pc;

    List<int> bytes;
    try {
      bytes = memory.fetch(pc, spec.maxInstrBits ~/ 8);
    } on MemFault catch (e) {
      return _fail(startPc, 0, '', null, e.message);
    }
    final d = decoder.decode(bytes);
    if (d == null) {
      final w = bytes.take(spec.minInstrBits ~/ 8).toList();
      var word = 0;
      for (var i = w.length - 1; i >= 0; i--) {
        word = (word << 8) | w[i];
      }
      return _fail(
        startPc,
        word,
        '',
        null,
        'Illegal instruction ${hex(word, w.length * 2)} at ${hex(startPc)}',
      );
    }

    _cur = d.instruction;
    _curPc = startPc;
    _nextPc = (startPc + d.length) & _addrMask;
    _newPc = null;
    _regLog = [];
    _flagLog = [];
    _memLog = [];
    _locals = {};
    _ops = d.operands;
    _out.clear();
    final text = decoder.format(d, startPc);

    var halted = false;
    try {
      final interp = Interp(this, bits);
      // A conditional instruction whose condition is false does nothing (but still takes its slot).
      final cond = d.condition;
      if (cond == null || interp.eval(cond.expr) != 0) {
        interp.exec(_cur.program);
      }
    } on _Halt {
      halted = true;
    } on MemFault catch (e) {
      _revertLogs();
      return _fail(startPc, d.raw, text, d, e.message);
    } on ExprError catch (e) {
      _revertLogs();
      return _fail(
        startPc,
        d.raw,
        text,
        d,
        '${e.message} (in "${d.instruction.mnemonic}")',
      );
    }

    pc = halted ? _nextPc : ((_newPc ?? _nextPc) & _addrMask);
    final out = _out.toString();
    console.write(out);
    instructionCount++;
    cycleCount += _cur.cycles;
    if (halted) status = MachineStatus.halted;

    final trace = StepTrace(
      pcBefore: startPc,
      pcAfter: pc,
      raw: d.raw,
      length: d.length,
      text: text,
      decoded: d,
      regWrites: _regLog,
      flagWrites: _flagLog,
      memAccesses: _memLog,
      output: out,
      cycles: _cur.cycles,
      halted: halted,
    );
    history.add(trace);
    if (history.length > maxHistory) history.removeAt(0);
    return trace;
  }

  StepTrace _fail(
    int pcBefore,
    int raw,
    String text,
    Decoded? d,
    String message,
  ) {
    status = MachineStatus.faulted;
    fault = message;
    return StepTrace(
      pcBefore: pcBefore,
      pcAfter: pcBefore,
      raw: raw,
      length: 0,
      text: text,
      decoded: d,
      fault: message,
    );
  }

  void _revertLogs() {
    for (final c in _regLog.reversed) {
      _regs[c.index] = c.oldValue;
    }
    for (final c in _flagLog.reversed) {
      _flags[c.name] = c.oldValue;
    }
    for (final m in _memLog.reversed) {
      if (m.write) memory.poke(m.address, m.oldBytes);
    }
    _out.clear();
  }

  bool get canUndo => history.isNotEmpty;

  /// Reverts the last executed instruction exactly. Returns false when there is nothing to undo.
  bool undo() {
    if (history.isEmpty) return false;
    final t = history.removeLast();
    for (final c in t.regWrites.reversed) {
      _regs[c.index] = c.oldValue;
    }
    for (final c in t.flagWrites.reversed) {
      _flags[c.name] = c.oldValue;
    }
    for (final m in t.memAccesses.reversed) {
      if (m.write) memory.poke(m.address, m.oldBytes);
    }
    pc = t.pcBefore;
    instructionCount--;
    cycleCount -= t.cycles;
    if (t.output.isNotEmpty) {
      final s = console.toString();
      console.clear();
      console.write(s.substring(0, s.length - t.output.length));
    }
    status = MachineStatus.ready;
    fault = null;
    return true;
  }

  // -------------------------------------------------------------------------------------------------------------
  // ExprEnv

  @override
  int read(String name) {
    final op = _cur.operands[name];
    if (op != null) {
      final v = _ops[name] ?? 0;
      return op == OperandKind.reg ? _regs[v] : v;
    }
    if (name == 'pc') return _curPc;
    if (name == 'next') return _nextPc;
    if (_flags.containsKey(name)) return _flags[name]!;
    final r = spec.registerIndexExact(name);
    if (r != null) return _regs[r];
    final l = _locals[name];
    if (l != null) return l;
    throw ExprError("'$name' has no value yet");
  }

  void _writeReg(int idx, int value) {
    if (idx == spec.zeroRegister) return;
    final v = value & _regMask(idx);
    final old = _regs[idx];
    if (v == old) return;
    _regs[idx] = v;
    _regLog.add(RegChange(idx, old, v));
  }

  @override
  void write(String name, int value) {
    final op = _cur.operands[name];
    if (op != null) {
      if (op != OperandKind.reg) {
        throw ExprError("'$name' is an immediate and cannot be assigned");
      }
      _writeReg(_ops[name] ?? 0, value);
      return;
    }
    if (name == 'pc') {
      _newPc = value;
      return;
    }
    if (name == 'next') throw ExprError("'next' is read-only");
    if (_flags.containsKey(name)) {
      final v = value & 1;
      final old = _flags[name]!;
      if (v != old) {
        _flags[name] = v;
        _flagLog.add(FlagChange(name, old, v));
      }
      return;
    }
    final r = spec.registerIndexExact(name);
    if (r != null) {
      _writeReg(r, value);
      return;
    }
    _locals[name] = value;
  }

  @override
  int load(int size, int addr) {
    final v = memory.read(addr, size);
    _memLog.add(
      MemAccess(address: addr & _addrMask, size: size, value: v, write: false),
    );
    return v;
  }

  @override
  void store(int size, int addr, int value) {
    final old = memory.write(addr, size, value);
    final mask = size >= 8 ? -1 : (1 << (size * 8)) - 1;
    _memLog.add(
      MemAccess(
        address: addr & _addrMask,
        size: size,
        value: value & mask,
        write: true,
        oldBytes: old,
      ),
    );
  }

  @override
  void call(String fn, List<Object> args) {
    switch (fn) {
      case 'halt':
        throw _Halt();
      case 'trap':
        throw ExprError(args.isNotEmpty ? '${args.first}' : 'trap');
      case 'out':
        if (args.length != 2 || args[0] is! String || args[1] is! int) {
          throw ExprError('out(kind, value) expects a kind name and a value');
        }
        final v = args[1] as int;
        final w = bits >= 64 ? v : v & ((1 << bits) - 1);
        final signed = bits >= 64
            ? v
            : (w >= (1 << (bits - 1)) ? w - (1 << bits) : w);
        switch (args[0]) {
          case 'int':
            _out.write(signed);
          case 'uint':
            _out.write(w);
          case 'hex':
            _out.write(hex(w, bits ~/ 4));
          case 'char':
            _out.writeCharCode(v & 0xFF);
          case 'str':
            for (var a = w, n = 0; n < 4096; a++, n++) {
              final c = memory.read(a, 1);
              if (c == 0) break;
              _out.writeCharCode(c);
            }
          default:
            throw ExprError(
              "Unknown out kind '${args[0]}' (int, uint, hex, char, str)",
            );
        }
      default:
        throw ExprError("Unknown statement '$fn()'");
    }
  }
}

import 'package:dot_asm/core/sim/asm/program.dart';
import 'package:dot_asm/core/sim/expr.dart';
import 'package:dot_asm/core/sim/machine/memory.dart' show hex;
import 'package:dot_asm/core/sim/spec/processor_spec.dart';

class _AsmError implements Exception {
  _AsmError(this.message);
  final String message;
}

/// A resolved instruction: its spec, operand texts and (for conditional instructions) the condition value.
typedef _Resolved = ({InstructionSpec ins, List<String> operands, int? cond});

class _Candidate {
  _Candidate(this.ins, this.regex);
  final InstructionSpec ins;
  final RegExp regex;
}

/// One thing to emit: an instruction (possibly from a pseudo expansion) or data.
class _Item {
  _Item(this.line, this.address, this.segment);
  final int line;
  final int address;
  final Segment segment;

  /// Real instruction text: mnemonic + operands, plus the chosen candidate.
  InstructionSpec? ins;
  List<String>? operandTexts;
  int? cond;

  /// Data emitted by directives (one entry per value, with its size).
  List<({String expr, int size})>? data;
  List<int>? raw;
}

class _Section {
  _Section(this.region);
  final MemoryRegionSpec region;
  late int cursor = region.base;
  Segment? segment;
  int? segEnd;

  void advance(int n) {
    cursor += n;
    segEnd = cursor;
  }
}

/// Assembles source text for a [ProcessorSpec].
///
/// Supports labels, `.text .data .org .align .balign .equ .set .byte .half .word .dword .ascii .asciz .string .space
/// .zero .globl`, the instruction syntaxes and pseudo-instructions of the spec, and the expression language of
/// `expr.dart` (plus `%hi()` / `%lo()`).
class Assembler {
  Assembler(this.spec) {
    final byMn = <String, List<_Candidate>>{};
    for (final ins in spec.instructions) {
      byMn
          .putIfAbsent(ins.mnemonic, () => [])
          .add(_Candidate(ins, _compileSyntax(ins)));
    }
    _byMnemonic = byMn;
    for (final p in spec.pseudos) {
      _pseudos.putIfAbsent(p.mnemonic.toLowerCase(), () => []).add(p);
    }
  }

  final ProcessorSpec spec;
  late final Map<String, List<_Candidate>> _byMnemonic;
  final Map<String, List<PseudoSpec>> _pseudos = {};

  static final _identRe = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');

  RegExp _compileSyntax(InstructionSpec ins) {
    final b = StringBuffer('^');
    final s = ins.syntax.replaceAll(RegExp(r'\s+'), '');
    var i = 0;
    while (i < s.length) {
      final m = _identRe.matchAsPrefix(s, i);
      if (m != null) {
        final w = m.group(0)!;
        b.write(ins.operands.containsKey(w) ? '(.+?)' : RegExp.escape(w));
        i = m.end;
      } else {
        b.write(RegExp.escape(s[i]));
        i++;
      }
    }
    b.write(r'$');
    return RegExp(b.toString(), caseSensitive: false);
  }

  // ---------------------------------------------------------------------------------------------------------------

  late Map<String, int> _symbols;
  late List<AsmDiagnostic> _errors;
  bool _pass2 = false;
  bool _unknownSymbol = false;
  bool _symbolRead = false;
  int _line = 0;

  AssembledProgram assemble(String source) {
    _symbols = {};
    _errors = [];
    final lines = source.split(RegExp(r'\r?\n'));

    final sections = <String, _Section>{};
    final text = spec.regionWithRole('text') ?? spec.memory.first;
    sections['text'] = _Section(text);
    sections['data'] = _Section(spec.regionWithRole('data') ?? text);
    if (identical(sections['data']!.region, text)) {
      // Data shares the code region: continue after code.
      sections['data'] = sections['text']!;
    }
    var current = sections['text']!;
    final segments = <Segment>[];
    final items = <_Item>[];
    final addressToLine = <int, int>{};
    String? entryLabel;

    Segment ensureSegment(_Section s) {
      final seg = s.segment;
      if (seg != null && s.segEnd == s.cursor) return seg;
      final n = Segment(s.cursor);
      s.segment = n;
      segments.add(n);
      return n;
    }

    // Pass 1: sizes, labels, symbols.
    _pass2 = false;
    for (var n = 0; n < lines.length; n++) {
      _line = n + 1;
      var line = _stripComment(lines[n]).trim();
      if (line.isEmpty) continue;

      // Leading labels.
      while (true) {
        final m = RegExp(r'^([A-Za-z_.$][A-Za-z0-9_.$]*)\s*:\s*(.*)$')
            .firstMatch(line);
        if (m == null) break;
        final name = m.group(1)!;
        if (_symbols.containsKey(name)) {
          _err("Label '$name' is already defined");
        } else {
          _symbols[name] = current.cursor;
        }
        line = m.group(2)!.trim();
      }
      if (line.isEmpty) continue;

      try {
        if (line.startsWith('.')) {
          final sp = line.indexOf(RegExp(r'\s'));
          final dir = (sp < 0 ? line : line.substring(0, sp)).toLowerCase();
          final rest = sp < 0 ? '' : line.substring(sp).trim();
          switch (dir) {
            case '.text':
              current = sections['text']!;
            case '.data' || '.bss' || '.rodata':
              current = sections['data']!;
            case '.section':
              current = rest.contains('text')
                  ? sections['text']!
                  : sections['data']!;
            case '.globl' ||
                '.global' ||
                '.type' ||
                '.size' ||
                '.file' ||
                '.option':
              break;
            case '.entry':
              entryLabel = rest;
            case '.org':
              final v = _evalConst(rest);
              current.cursor = v;
            case '.align' || '.balign':
              final v = _evalConst(rest);
              final a = dir == '.align' ? 1 << v : v;
              if (a <= 0) throw _AsmError('Alignment must be positive');
              final pad = (a - current.cursor % a) % a;
              if (pad > 0) {
                final item = _Item(
                  _line,
                  current.cursor,
                  ensureSegment(current),
                )..raw = List.filled(pad, 0);
                items.add(item);
                current.advance(pad);
              }
            case '.equ' || '.set':
              final parts = _splitTop(rest);
              if (parts.length != 2) {
                throw _AsmError('$dir needs a name and a value');
              }
              _symbols[parts[0].trim()] = _evalConst(parts[1]);
            case '.byte' ||
                '.half' ||
                '.short' ||
                '.word' ||
                '.long' ||
                '.dword' ||
                '.quad':
              final size = switch (dir) {
                '.byte' => 1,
                '.half' || '.short' => 2,
                '.word' => spec.wordBytes,
                '.long' => 4,
                _ => 8,
              };
              final exprs = _splitTop(rest);
              if (exprs.isEmpty ||
                  (exprs.length == 1 && exprs[0].trim().isEmpty)) {
                throw _AsmError('$dir needs at least one value');
              }
              final item = _Item(_line, current.cursor, ensureSegment(current))
                ..data = [for (final e in exprs) (expr: e.trim(), size: size)];
              items.add(item);
              current.advance(size * exprs.length);
            case '.ascii' || '.asciz' || '.asciiz' || '.string':
              final bytes = _stringBytes(rest, dir != '.ascii');
              final item = _Item(_line, current.cursor, ensureSegment(current))
                ..raw = bytes;
              items.add(item);
              current.advance(bytes.length);
            case '.space' || '.zero' || '.skip':
              final parts = _splitTop(rest);
              final count = _evalConst(parts[0]);
              final fill = parts.length > 1 ? _evalConst(parts[1]) : 0;
              if (count < 0 || count > 1 << 24) {
                throw _AsmError('Bad size for $dir');
              }
              final item = _Item(_line, current.cursor, ensureSegment(current))
                ..raw = List.filled(count, fill & 0xFF);
              items.add(item);
              current.advance(count);
            default:
              throw _AsmError("Unknown directive '$dir'");
          }
        } else {
          final expanded = _expandStatement(line);
          for (final e in expanded) {
            final item = _Item(_line, current.cursor, ensureSegment(current))
              ..ins = e.ins
              ..operandTexts = e.operands
              ..cond = e.cond;
            items.add(item);
            addressToLine[current.cursor] = _line;
            current.advance(e.ins.bytes);
          }
        }
      } on _AsmError catch (e) {
        _err(e.message);
      } on ExprError catch (e) {
        _err(e.message);
      }
    }

    // Pass 2: encode with all symbols known.
    _pass2 = true;
    for (final it in items) {
      _line = it.line;
      try {
        final seg = it.segment;
        if (it.raw != null) {
          seg.bytes.addAll(it.raw!);
        } else if (it.data != null) {
          for (final d in it.data!) {
            final v = _evalExpr(d.expr);
            seg.bytes.addAll(_bytesOf(v, d.size));
          }
        } else if (it.ins != null) {
          seg.bytes.addAll(
            _encode(it.ins!, it.operandTexts!, it.address, cond: it.cond),
          );
        }
      } on _AsmError catch (e) {
        _err(e.message);
      } on ExprError catch (e) {
        _err(e.message);
      }
    }

    // Everything must land inside a memory region.
    for (final s in segments) {
      if (s.bytes.isEmpty) continue;
      final r = spec.memory
          .where((r) => s.address >= r.base && s.end <= r.end)
          .firstOrNull;
      if (r == null) {
        final line = addressToLine[s.address] ?? 1;
        _errors.add(
          AsmDiagnostic(
            line,
            'Code or data at ${hex(s.address)}..${hex(s.end)} does not fit in any memory region',
          ),
        );
      }
    }

    var entry = text.base;
    final names = entryLabel != null ? [entryLabel] : ['_start', 'main'];
    for (final n in names) {
      if (_symbols.containsKey(n)) {
        entry = _symbols[n]!;
        break;
      }
    }
    if (entryLabel != null && !_symbols.containsKey(entryLabel)) {
      _errors.add(AsmDiagnostic(1, "Entry label '$entryLabel' is not defined"));
    }
    if (entry == text.base &&
        !_symbols.containsKey('_start') &&
        !_symbols.containsKey('main') &&
        addressToLine.isNotEmpty) {
      entry = addressToLine.keys.reduce((a, b) => a < b ? a : b);
    }

    return AssembledProgram(
      segments: segments.where((s) => s.bytes.isNotEmpty).toList(),
      entry: entry,
      symbols: Map.of(_symbols),
      addressToLine: addressToLine,
      errors: _errors..sort((a, b) => a.line.compareTo(b.line)),
    );
  }

  void _err(String message) => _errors.add(AsmDiagnostic(_line, message));

  String _stripComment(String line) {
    var inStr = false;
    String quote = '';
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inStr) {
        if (c == r'\') {
          i++;
        } else if (c == quote) {
          inStr = false;
        }
        continue;
      }
      if (c == '"' ||
          (c == "'" &&
              i + 2 < line.length &&
              (line[i + 2] == "'" || line[i + 1] == r'\'))) {
        inStr = true;
        quote = c;
        continue;
      }
      for (final cm in spec.comments) {
        if (line.startsWith(cm, i)) return line.substring(0, i);
      }
    }
    return line;
  }

  /// Splits on commas that are not inside parentheses or quotes.
  List<String> _splitTop(String s) {
    final out = <String>[];
    var depth = 0;
    var inStr = false;
    var start = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inStr) {
        if (c == r'\') {
          i++;
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') {
        inStr = true;
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      } else if (c == ',' && depth == 0) {
        out.add(s.substring(start, i));
        start = i + 1;
      }
    }
    out.add(s.substring(start));
    return out;
  }

  List<int> _stringBytes(String rest, bool terminate) {
    final out = <int>[];
    for (final part in _splitTop(rest)) {
      final t = part.trim();
      if (!t.startsWith('"') || !t.endsWith('"') || t.length < 2) {
        throw _AsmError('Expected a "quoted string"');
      }
      final e = parseExpression(t);
      if (e is! StrExpr) throw _AsmError('Expected a "quoted string"');
      out.addAll(e.value.codeUnits.map((c) => c & 0xFF));
      if (terminate) out.add(0);
    }
    return out;
  }

  List<int> _bytesOf(int v, int size) {
    final out = <int>[];
    for (var i = 0; i < size; i++) {
      out.add((v >>> (i * 8)) & 0xFF);
    }
    return spec.endian == Endian.little ? out : out.reversed.toList();
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Expressions

  int _evalExpr(String text) {
    var t = text.trim().replaceAll('%hi(', 'hi(').replaceAll('%lo(', 'lo(');
    if (t.isEmpty) throw _AsmError('Missing value');
    if (spec.hexPrefix.isNotEmpty) {
      t = t.replaceAllMapped(
        RegExp(
          '(?<![A-Za-z0-9_])${RegExp.escape(spec.hexPrefix)}([0-9A-Fa-f]+)',
        ),
        (m) => '0x${m[1]}',
      );
    }
    // `<expr` is the low byte and `>expr` the high byte (6502 style, for `lda #<label`).
    if (t.startsWith('<')) {
      t = '((${t.substring(1)}) & 255)';
    } else if (t.startsWith('>')) {
      t = '(((${t.substring(1)}) >> 8) & 255)';
    }
    final e = parseExpression(t);
    final env = _SymbolEnv(this);
    return Interp(env, 64).eval(e);
  }

  int _evalConst(String text) {
    final saved = _pass2;
    _unknownSymbol = false;
    final v = _evalExpr(text);
    _pass2 = saved;
    if (_unknownSymbol) {
      throw _AsmError(
        "Value '${text.trim()}' must be known when this line is read (use only earlier labels and constants)",
      );
    }
    return v;
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Instructions

  /// Splits `mnemonic operands`.
  ({String mnemonic, String operands}) _split(String line) {
    final m = RegExp(r'^(\S+)\s*(.*)$').firstMatch(line)!;
    var operands = m.group(2).toString().replaceAll(RegExp(r'\s+'), '');
    for (final r in spec.operandRewrites) {
      operands = operands.replaceAllMapped(
        RegExp(r[0], caseSensitive: false),
        (g) => r[1].replaceAllMapped(
          RegExp(r'\$(\d)'),
          (x) => g.group(int.parse(x.group(1)!)) ?? '',
        ),
      );
    }
    return (mnemonic: m.group(1)!.toLowerCase(), operands: operands);
  }

  /// A real instruction with its operand texts, resolved at pass 1.
  List<_Resolved> _expandStatement(String line) {
    final s = _split(line);
    final pseudos = _pseudos[s.mnemonic];
    // A real instruction wins when its operands fit. When they do not, a pseudo-instruction of the same name
    // (e.g. `li` with a large value) gets its turn before the real error is reported.
    final real = _resolveReal(
      s.mnemonic,
      s.operands,
      strict: false,
      requireFit: pseudos != null,
    );
    if (real != null) return [real];

    if (pseudos != null) {
      for (final p in pseudos) {
        final params = p.params;
        List<String> texts;
        if (p.syntax.contains('{')) {
          // Register-list pseudo: operands are written {a, b, c}.
          if (!s.operands.startsWith('{') || !s.operands.endsWith('}')) {
            continue;
          }
          texts = _splitTop(s.operands.substring(1, s.operands.length - 1));
        } else {
          texts = s.operands.isEmpty ? <String>[] : _splitTop(s.operands);
        }
        if (texts.length != params.length) continue;
        // Immediate markers written in the pseudo syntax (`mov rd, #imm`, `ldr rd, =imm`) are not part of the value.
        for (var i = 0; i < params.length; i++) {
          final mk = RegExp('([#=])${RegExp.escape(params[i])}\\b')
              .firstMatch(p.syntax);
          if (mk != null && texts[i].startsWith(mk.group(1)!)) {
            texts[i] = texts[i].substring(1);
          }
        }
        final map = {
          for (var i = 0; i < params.length; i++) params[i]: texts[i].trim(),
        };
        final variant = _pickVariant(p, map);
        final out = <_Resolved>[];
        for (final tmpl in variant.expand) {
          final line2 = _substitute(tmpl, map, parens: false);
          final s2 = _split(line2);
          final r = _resolveReal(s2.mnemonic, s2.operands, strict: true);
          if (r == null) {
            throw _AsmError(
              "Pseudo-instruction '${s.mnemonic}' expands to '$line2', which is not a valid instruction",
            );
          }
          out.add(r);
        }
        return out;
      }
      throw _AsmError(
        "Wrong operands for '${s.mnemonic}' (expected: ${pseudos.map((p) => p.syntax).join(' | ')})",
      );
    }

    if (_byMnemonic.containsKey(s.mnemonic)) {
      final forms = _byMnemonic[s.mnemonic]!
          .map((c) => '${c.ins.mnemonic} ${c.ins.syntax}'.trim())
          .toSet()
          .join(' | ');
      throw _AsmError("Wrong operands for '${s.mnemonic}' (expected: $forms)");
    }
    throw _AsmError("Unknown instruction '${s.mnemonic}'");
  }

  String _substitute(
    String template,
    Map<String, String> map, {
    required bool parens,
  }) {
    return template.replaceAllMapped(_identRe, (m) {
      final v = map[m.group(0)];
      if (v == null) return m.group(0)!;
      return parens ? '($v)' : v;
    });
  }

  PseudoVariant _pickVariant(PseudoSpec p, Map<String, String> map) {
    for (var i = 0; i < p.variants.length; i++) {
      final v = p.variants[i];
      if (v.when == null) return v;
      try {
        _unknownSymbol = false;
        final r = _evalExpr(_substitute(v.when!, map, parens: true));
        if (!_unknownSymbol && r != 0) return v;
      } on Object {
        // Unknown names or bad syntax in the condition: try the next variant.
      }
    }
    return p.variants.last;
  }

  /// Splits a mnemonic into its base and a condition suffix (`addeq` → `add` + eq). A mnemonic that exists as
  /// written is never split.
  ({String base, int? cond}) _conditionSplit(String mn) {
    final cs = spec.conditions;
    if (cs == null || _byMnemonic.containsKey(mn)) {
      return (base: mn, cond: null);
    }
    for (final c in cs.codes) {
      if (mn.length > c.suffix.length && mn.endsWith(c.suffix)) {
        final base = mn.substring(0, mn.length - c.suffix.length);
        final cands = _byMnemonic[base];
        if (cands != null && cands.any((x) => x.ins.cond)) {
          return (base: base, cond: c.value);
        }
      }
    }
    return (base: mn, cond: null);
  }

  /// Finds the instruction matching [mnemonic] and [operands]. At pass 1 the choice is by operand shape and (when
  /// all values are known) by whether the values fit; later forms are used for forward references.
  _Resolved? _resolveReal(
    String mnemonic,
    String operands, {
    required bool strict,
    bool requireFit = false,
  }) {
    final split = _conditionSplit(mnemonic);
    final cond = split.cond;
    final cands = _byMnemonic[split.base]
        ?.where((c) => cond == null || c.ins.cond)
        .toList();
    if (cands == null || cands.isEmpty) return null;
    _Resolved? lastShape;
    String? firstProblem;
    for (final c in cands) {
      final m = c.regex.firstMatch(operands);
      if (m == null) continue;
      final texts = [for (var i = 1; i <= m.groupCount; i++) m.group(i)!];
      final names = c.ins.operandOrder;
      if (names.length != texts.length) continue;
      // Register operands must really be registers.
      var shapeOk = true;
      for (var i = 0; i < names.length; i++) {
        if (c.ins.operands[names[i]] == OperandKind.reg &&
            spec.registerIndexByName(texts[i]) == null) {
          shapeOk = false;
          break;
        }
      }
      if (!shapeOk) continue;
      if (!requireFit) lastShape = (ins: c.ins, operands: texts, cond: cond);
      // With known values, check that they fit (picks the right addressing form).
      _unknownSymbol = false;
      try {
        _encode(c.ins, texts, 0, probe: true);
        if (!_unknownSymbol) return (ins: c.ins, operands: texts, cond: cond);
        // Forward reference: the size is what matters now; the value is checked in pass 2.
        lastShape = (ins: c.ins, operands: texts, cond: cond);
      } on _AsmError catch (e) {
        if (!_unknownSymbol) {
          firstProblem ??= e.message;
          continue;
        }
        // Unknown symbols: this form may fit later; keep it as the fallback.
        lastShape = (ins: c.ins, operands: texts, cond: cond);
        continue;
      } on ExprError catch (e) {
        firstProblem ??= e.message;
        continue;
      }
    }
    if (lastShape == null && (firstProblem == null || requireFit)) return null;
    if (lastShape == null) throw _AsmError(firstProblem!);
    return lastShape;
  }

  List<int> _encode(
    InstructionSpec ins,
    List<String> texts,
    int address, {
    bool probe = false,
    int? cond,
  }) {
    var word = ins.value;
    final names = ins.operandOrder;
    for (var i = 0; i < names.length; i++) {
      final name = names[i];
      final kind = ins.operands[name]!;
      final field = ins.fields[name]!;
      int value;
      switch (kind) {
        case OperandKind.reg:
          final idx = spec.registerIndexByName(texts[i]);
          if (idx == null || !spec.isFileRegister(idx)) {
            throw _AsmError("'${texts[i]}' is not a register");
          }
          value = idx;
        case OperandKind.imm:
          value = _evalExpr(texts[i]);
        case OperandKind.pcrel:
          _symbolRead = false;
          final target = _evalExpr(texts[i]);
          // A plain number is an offset from this instruction; anything using a label is a target address.
          value = _symbolRead ? target - (address + ins.pcrelBase) : target;
      }
      final r = field.range;
      if (kind == OperandKind.reg) {
        if (value < field.offset ||
            value - field.offset >= (1 << field.width)) {
          throw _AsmError(
            "Register '${texts[i]}' cannot be used here (this operand accepts r${field.offset}..r${field.offset + (1 << field.width) - 1})",
          );
        }
      } else {
        if (probe && _unknownSymbol) {
          // Not known yet: only the size matters.
        } else {
          if (field.shift > 0 && value % (1 << field.shift) != 0) {
            throw _AsmError(
              "Operand '${texts[i].trim()}' ($value) must be a multiple of ${1 << field.shift}",
            );
          }
          if (value < r.min || value > r.max) {
            // Unsigned fields also accept a negative number that fits as two's complement of the same width.
            throw _AsmError(
              "Value $value is out of range for '$name' (${r.min} to ${r.max})",
            );
          }
        }
      }
      if (probe && _unknownSymbol && kind != OperandKind.reg) continue;
      word |= field.insert(value);
    }
    final cs = spec.conditions;
    if (ins.cond && cs != null) {
      word |= cs.field.insert(cond ?? cs.defaultValue);
    }
    final out = <int>[];
    for (var i = 0; i < ins.bytes; i++) {
      out.add((word >>> (i * 8)) & 0xFF);
    }
    return spec.endian == Endian.little ? out : out.reversed.toList();
  }
}

class _SymbolEnv implements ExprEnv {
  _SymbolEnv(this.a);
  final Assembler a;

  @override
  int read(String name) {
    a._symbolRead = true;
    final v = a._symbols[name];
    if (v != null) return v;
    if (a.spec.registerIndexByName(name) != null) {
      throw ExprError(
        "'$name' is a register and cannot be used inside a value (is a displacement out of range?)",
      );
    }
    if (a._pass2) throw ExprError("Undefined symbol '$name'");
    a._unknownSymbol = true;
    return 0;
  }

  @override
  void write(String name, int value) =>
      throw ExprError('Cannot assign in an expression');

  @override
  int load(int size, int addr) =>
      throw ExprError('Memory cannot be read in an expression');

  @override
  void store(int size, int addr, int value) =>
      throw ExprError('Memory cannot be written in an expression');

  @override
  void call(String fn, List<Object> args) =>
      throw ExprError('Unexpected statement');
}

import 'dart:convert';

import 'package:dot_asm/core/sim/expr.dart';

/// Thrown by [ProcessorSpec.fromJson] when the structure is wrong (missing keys, bad types).
class SpecFormatError implements Exception {
  SpecFormatError(this.errors);
  final List<String> errors;

  @override
  String toString() => errors.join('\n');
}

int _int(Object? v, String what, List<String> errs, {int? or}) {
  if (v is int) return v;
  if (v is String) {
    final t = v.trim().replaceAll('_', '');
    final neg = t.startsWith('-');
    final b = neg ? t.substring(1) : t;
    final n = b.startsWith('0x') || b.startsWith('0X')
        ? int.tryParse(b.substring(2), radix: 16)
        : b.startsWith('0b') || b.startsWith('0B')
        ? int.tryParse(b.substring(2), radix: 2)
        : int.tryParse(b);
    if (n != null) return neg ? -n : n;
  }
  if (v == null && or != null) return or;
  errs.add("$what: expected a number but found '${v ?? 'nothing'}'");
  return or ?? 0;
}

String _str(Object? v, String what, List<String> errs, {String? or}) {
  if (v is String && v.isNotEmpty) return v;
  if (v == null && or != null) return or;
  errs.add('$what: expected text');
  return or ?? '';
}

enum Endian { little, big }

enum OperandKind {
  /// A register of the main register file.
  reg,

  /// An immediate or an expression with labels.
  imm,

  /// A label whose distance from the instruction becomes the value.
  pcrel,
}

/// The register file of `count` registers named `<prefix><index>` (`x0`..`x31`), with optional alternative names.
class RegisterFileSpec {
  const RegisterFileSpec({
    required this.prefix,
    required this.count,
    required this.width,
    this.aliases = const {},
    this.zeroIndex,
  });

  final String prefix;
  final int count;
  final int width;

  /// Alternative name → index (`sp` → 2).
  final Map<String, int> aliases;

  /// Index of a register hard-wired to zero (writes are ignored), if any.
  final int? zeroIndex;

  Map<String, dynamic> toJson() => {
    'prefix': prefix,
    'count': count,
    'width': width,
    if (aliases.isNotEmpty) 'aliases': aliases,
    if (zeroIndex != null) 'zero': zeroIndex,
  };
}

/// A single named register outside the register file (accumulator, status register, ...).
class RegisterSpec {
  const RegisterSpec({
    required this.name,
    required this.width,
    this.description = '',
  });
  final String name;
  final int width;
  final String description;

  Map<String, dynamic> toJson() => {
    'name': name,
    'width': width,
    if (description.isNotEmpty) 'description': description,
  };
}

class MemoryRegionSpec {
  const MemoryRegionSpec({
    required this.name,
    required this.base,
    required this.size,
    required this.perms,
    this.role = '',
  });

  final String name;
  final int base;
  final int size;

  /// Any of `r`, `w`, `x`.
  final String perms;

  /// `text`, `data`, `stack` or empty. The assembler puts `.text` / `.data` into the regions with that role.
  final String role;

  int get end => base + size;
  bool get canRead => perms.contains('r');
  bool get canWrite => perms.contains('w');
  bool get canExecute => perms.contains('x');

  Map<String, dynamic> toJson() => {
    'name': name,
    'base': '0x${base.toRadixString(16)}',
    'size': '0x${size.toRadixString(16)}',
    'perms': perms,
    if (role.isNotEmpty) 'role': role,
  };
}

/// Where an operand lives inside the instruction word.
///
/// Written `[31:25,11:7]` (segments from the most significant bits of the value to the least), optionally prefixed
/// with `s` for signed and suffixed with `<<n` for an implicit shift (`s[31,7,30:25,11:8]<<1`).
class FieldSpec {
  FieldSpec(
    this.source,
    this.segments,
    this.signed,
    this.shift, [
    this.offset = 0,
  ]) : width = segments.fold(0, (a, s) => a + (s.hi - s.lo + 1));

  final String source;
  final List<({int hi, int lo})> segments;
  final bool signed;
  final int shift;

  /// Added to the decoded value (and subtracted when encoding): AVR's `ldi` can only address r16..r31, written `[7:4]+16`.
  final int offset;

  /// Number of encoded bits (without the implicit shift).
  final int width;

  static final _re = RegExp(r'^(s)?\[([0-9:,\s]+)\](?:<<(\d+))?(?:\+(\d+))?$');

  static FieldSpec? parse(String src) {
    final m = _re.firstMatch(src.trim());
    if (m == null) return null;
    final segs = <({int hi, int lo})>[];
    for (final part in m.group(2)!.split(',')) {
      final b = part.trim().split(':');
      final hi = int.tryParse(b[0]);
      final lo = b.length == 2 ? int.tryParse(b[1]) : hi;
      if (hi == null || lo == null || b.length > 2 || hi < lo || lo < 0) {
        return null;
      }
      segs.add((hi: hi, lo: lo));
    }
    if (segs.isEmpty) return null;
    return FieldSpec(
      src.trim(),
      segs,
      m.group(1) != null,
      int.tryParse(m.group(3) ?? '0') ?? 0,
      int.tryParse(m.group(4) ?? '0') ?? 0,
    );
  }

  /// Highest bit position used.
  int get highestBit =>
      segments.map((s) => s.hi).reduce((a, b) => a > b ? a : b);

  /// Reads the field out of [word].
  int extract(int word) {
    var v = 0;
    for (final s in segments) {
      final w = s.hi - s.lo + 1;
      v = (v << w) | ((word >>> s.lo) & ((1 << w) - 1));
    }
    if (signed && (v & (1 << (width - 1))) != 0) v -= 1 << width;
    return (v << shift) + offset;
  }

  /// Scatters [value] (already range checked) into the instruction word bits.
  int insert(int value) {
    var v = (value - offset) >> shift;
    var word = 0;
    for (final s in segments.reversed) {
      final w = s.hi - s.lo + 1;
      word |= (v & ((1 << w) - 1)) << s.lo;
      v >>= w;
    }
    return word;
  }

  /// Smallest and largest value the field can hold (including the implicit shift).
  ({int min, int max}) get range => signed
      ? (
          min: (-(1 << (width - 1)) << shift) + offset,
          max: (((1 << (width - 1)) - 1) << shift) + offset,
        )
      : (min: offset, max: (((1 << width) - 1) << shift) + offset);
}

class InstructionSpec {
  InstructionSpec({
    required this.id,
    required this.mnemonic,
    required this.syntax,
    required this.bits,
    required this.mask,
    required this.value,
    required this.operands,
    required this.fields,
    required this.exec,
    this.description = '',
    this.cycles = 1,
    this.pcrelBase = 0,
    this.cond = false,
  });

  final String id;
  final String mnemonic;

  /// Operand template such as `rd, imm(rs1)`.
  final String syntax;

  /// Instruction size in bits (multiple of 8).
  final int bits;

  /// Bits that identify the instruction, and their required value.
  final int mask;
  final int value;
  final Map<String, OperandKind> operands;
  final Map<String, FieldSpec> fields;

  /// Semantics source, e.g. `rd = rs1 + imm;`.
  final String exec;
  final String description;
  final int cycles;

  /// Added to the instruction address before computing a `pcrel` operand (for ISAs that count from pc+offset).
  final int pcrelBase;

  /// Whether the instruction carries a condition (ARM-style `addeq`): the condition field of the processor is
  /// not part of [mask], and the semantics only run when the condition holds.
  final bool cond;

  int get bytes => bits ~/ 8;

  List<Stmt>? _compiled;

  /// Parsed semantics. Throws [ExprError] when [exec] is invalid.
  List<Stmt> get program => _compiled ??= parseProgram(exec);

  /// Operand names in syntax order.
  late final List<String> operandOrder = _order();

  List<String> _order() {
    final out = <String>[];
    for (final m in RegExp(r'[A-Za-z_][A-Za-z0-9_]*').allMatches(syntax)) {
      final n = m.group(0)!;
      if (operands.containsKey(n) && !out.contains(n)) out.add(n);
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'mnemonic': mnemonic,
    'syntax': syntax,
    'bits': bits,
    'mask': '0x${mask.toRadixString(16)}',
    'value': '0x${value.toRadixString(16)}',
    'operands': {for (final e in operands.entries) e.key: e.value.name},
    'fields': {for (final e in fields.entries) e.key: e.value.source},
    'exec': exec,
    if (description.isNotEmpty) 'description': description,
    if (cycles != 1) 'cycles': cycles,
    if (pcrelBase != 0) 'pcrelBase': pcrelBase,
    if (cond) 'cond': true,
  };
}

class PseudoVariant {
  const PseudoVariant({this.when, required this.expand});
  final String? when;
  final List<String> expand;

  Map<String, dynamic> toJson() => {
    if (when != null) 'when': when,
    'expand': expand,
  };
}

/// A convenience mnemonic that expands to real instructions (`li`, `mv`, `ret`, ...).
class PseudoSpec {
  const PseudoSpec({required this.syntax, required this.variants});

  /// `li rd, imm`: the first word is the mnemonic, the rest are operand placeholders.
  final String syntax;
  final List<PseudoVariant> variants;

  String get mnemonic => syntax.trim().split(RegExp(r'\s+')).first;

  List<String> get params {
    final rest = syntax.trim().substring(mnemonic.length);
    return RegExp(r'[A-Za-z_][A-Za-z0-9_]*')
        .allMatches(rest)
        .map((m) => m.group(0)!)
        .toList();
  }

  Map<String, dynamic> toJson() => {
    'syntax': syntax,
    'variants': [for (final v in variants) v.toJson()],
  };
}

/// One condition code: the mnemonic [suffix] (`eq`), its encoded [value] and the [test] expression over flags.
class ConditionCode {
  ConditionCode({
    required this.suffix,
    required this.value,
    required this.test,
  });
  final String suffix;
  final int value;
  final String test;

  Expr? _compiled;

  /// Parsed test. Throws [ExprError] when invalid.
  Expr get expr => _compiled ??= parseExpression(test);

  Map<String, dynamic> toJson() => {
    'suffix': suffix,
    'value': value,
    'test': test,
  };
}

/// Per-instruction conditional execution, as on ARM: a field of the instruction word selects one of [codes].
class ConditionSpec {
  ConditionSpec({
    required this.field,
    required this.defaultValue,
    required this.codes,
  }) : _byValue = {for (final c in codes) c.value: c},
       _bySuffix = {for (final c in codes) c.suffix.toLowerCase(): c};

  final FieldSpec field;

  /// The code used when the mnemonic has no suffix ("always").
  final int defaultValue;
  final List<ConditionCode> codes;
  final Map<int, ConditionCode> _byValue;
  final Map<String, ConditionCode> _bySuffix;

  ConditionCode? byValue(int v) => _byValue[v];
  ConditionCode? bySuffix(String s) => _bySuffix[s.toLowerCase()];

  Map<String, dynamic> toJson() => {
    'field': field.source,
    'default': defaultValue,
    'codes': [for (final c in codes) c.toJson()],
  };
}

/// Everything that defines a processor.
class ProcessorSpec {
  ProcessorSpec({
    required this.id,
    required this.name,
    required this.arch,
    this.description = '',
    this.vendor = '',
    this.year = 0,
    this.era = '',
    this.tags = const [],
    required this.wordBits,
    this.endian = Endian.little,
    this.instrBits = 32,
    this.alignedAccess = false,
    this.registerFile,
    this.registers = const [],
    this.flags = const [],
    this.memory = const [],
    this.init = const {},
    this.resetPc = 0,
    this.comments = const ['#', ';', '//'],
    this.pipeline = const [],
    this.conditions,
    this.hexPrefix = '',
    this.wordBytes = 4,
    this.operandRewrites = const [],
    this.sample = '',
    required this.instructions,
    this.pseudos = const [],
    this.builtin = false,
  }) {
    _index();
  }

  final String id;
  final String name;

  /// Family: `riscv`, `arm`, `x86`, `mos6502`, `avr`, `custom`, ...
  final String arch;
  final String description;

  /// Who designed it (`MOS Technology`), the year it appeared, `legacy` or `modern`, and gallery tags (`RISC`, `ARM`, ...).
  final String vendor;
  final int year;
  final String era;
  final List<String> tags;

  /// Width of the program counter and of address arithmetic.
  final int wordBits;
  final Endian endian;

  /// Default instruction width in bits.
  final int instrBits;

  /// Whether misaligned loads and stores fault.
  final bool alignedAccess;
  final RegisterFileSpec? registerFile;
  final List<RegisterSpec> registers;
  final List<String> flags;
  final List<MemoryRegionSpec> memory;

  /// Initial register values (name → value expression), e.g. the stack pointer.
  final Map<String, int> init;
  final int resetPc;
  final List<String> comments;

  /// Informational pipeline stage names (shown by the visualiser).
  final List<String> pipeline;

  /// Conditional execution (ARM-style), if the processor has it.
  final ConditionSpec? conditions;

  /// Prefix that marks hexadecimal numbers in assembly (`$` on the 6502), in addition to `0x`.
  final String hexPrefix;

  /// Size of the `.word` directive in bytes (2 on 8/16-bit chips and x86, 4 on 32-bit RISC).
  final int wordBytes;

  /// Regex rewrites applied to operand text before it is matched (`[ebx-4]` → `[ebx+-4]`), as [pattern, replacement]
  /// pairs; `$1` in the replacement is the first group.
  final List<List<String>> operandRewrites;

  /// Starter program for new projects.
  final String sample;
  final List<InstructionSpec> instructions;
  final List<PseudoSpec> pseudos;
  final bool builtin;

  /// The `.cpu` file this processor was loaded from (null for built-ins and unsaved ones).
  String? sourcePath;

  late final int _fileCount = registerFile?.count ?? 0;

  /// Total registers: the register file followed by the single registers.
  int get registerCount => _fileCount + registers.length;

  late final Map<String, int> _regByLowerName;
  late final Map<String, int> _regByName;
  late final List<String> _regNames;
  late final List<List<String>> _regAliases;
  late final List<int> _regWidths;

  void _index() {
    final byLower = <String, int>{};
    final byName = <String, int>{};
    final names = <String>[];
    final aliases = <List<String>>[];
    final widths = <int>[];
    final rf = registerFile;
    if (rf != null) {
      for (var i = 0; i < rf.count; i++) {
        final n = '${rf.prefix}$i';
        names.add(n);
        aliases.add([]);
        widths.add(rf.width);
        byLower[n.toLowerCase()] = i;
        byName[n] = i;
      }
      rf.aliases.forEach((a, i) {
        if (i >= 0 && i < rf.count) {
          aliases[i].add(a);
          byLower[a.toLowerCase()] = i;
          byName[a] = i;
        }
      });
    }
    for (final r in registers) {
      final i = names.length;
      names.add(r.name);
      aliases.add([]);
      widths.add(r.width);
      byLower[r.name.toLowerCase()] = i;
      byName[r.name] = i;
    }
    _regByLowerName = byLower;
    _regByName = byName;
    _regNames = names;
    _regAliases = aliases;
    _regWidths = widths;
  }

  String registerName(int index) => _regNames[index];
  List<String> registerAliases(int index) => _regAliases[index];
  int registerWidth(int index) => _regWidths[index];

  /// Case-insensitive lookup used by the assembler.
  int? registerIndexByName(String name) => _regByLowerName[name.toLowerCase()];

  /// Exact lookup used by the semantics.
  int? registerIndexExact(String name) => _regByName[name];

  /// True for registers in the main file (usable as `reg` operands).
  bool isFileRegister(int index) => index < _fileCount;

  int get fileCount => _fileCount;

  /// The register hard-wired to zero, or `-1`.
  int get zeroRegister => registerFile?.zeroIndex ?? -1;

  int get maxInstrBits =>
      instructions.fold(instrBits, (a, i) => i.bits > a ? i.bits : a);
  int get minInstrBits => instructions.isEmpty
      ? instrBits
      : instructions.map((i) => i.bits).reduce((a, b) => a < b ? a : b);

  MemoryRegionSpec? regionWithRole(String role) {
    for (final r in memory) {
      if (r.role == role) return r;
    }
    return null;
  }

  // -------------------------------------------------------------------------------------------------------------
  // JSON

  static ProcessorSpec parse(String source, {bool builtin = false}) {
    Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (e) {
      throw SpecFormatError(['Not valid JSON: ${e.message}']);
    }
    if (json is! Map<String, dynamic>) {
      throw SpecFormatError(['The file must contain a JSON object']);
    }
    return ProcessorSpec.fromJson(json, builtin: builtin);
  }

  factory ProcessorSpec.fromJson(
    Map<String, dynamic> m, {
    bool builtin = false,
  }) {
    final errs = <String>[];

    final wordBits = _int(m['wordBits'], 'wordBits', errs, or: 32);
    final instrBits = _int(m['instrBits'], 'instrBits', errs, or: 32);

    RegisterFileSpec? rf;
    final rfj = m['registerFile'];
    if (rfj is Map<String, dynamic>) {
      final al = <String, int>{};
      final aj = rfj['aliases'];
      if (aj is Map) {
        aj.forEach(
          (k, v) => al['$k'] = _int(v, 'registerFile.aliases.$k', errs),
        );
      }
      rf = RegisterFileSpec(
        prefix: _str(rfj['prefix'], 'registerFile.prefix', errs, or: 'r'),
        count: _int(rfj['count'], 'registerFile.count', errs),
        width: _int(rfj['width'], 'registerFile.width', errs, or: wordBits),
        aliases: al,
        zeroIndex: rfj['zero'] == null
            ? null
            : _int(rfj['zero'], 'registerFile.zero', errs),
      );
    } else if (rfj != null) {
      errs.add('registerFile: expected an object');
    }

    final regs = <RegisterSpec>[];
    final rj = m['registers'];
    if (rj is List) {
      for (var i = 0; i < rj.length; i++) {
        final r = rj[i];
        if (r is Map<String, dynamic>) {
          regs.add(
            RegisterSpec(
              name: _str(r['name'], 'registers[$i].name', errs),
              width: _int(
                r['width'],
                'registers[$i].width',
                errs,
                or: wordBits,
              ),
              description: r['description'] as String? ?? '',
            ),
          );
        } else {
          errs.add('registers[$i]: expected an object');
        }
      }
    } else if (rj != null) {
      errs.add('registers: expected a list');
    }

    final mem = <MemoryRegionSpec>[];
    final mj = m['memory'];
    if (mj is List) {
      for (var i = 0; i < mj.length; i++) {
        final r = mj[i];
        if (r is Map<String, dynamic>) {
          mem.add(
            MemoryRegionSpec(
              name: _str(r['name'], 'memory[$i].name', errs),
              base: _int(r['base'], 'memory[$i].base', errs),
              size: _int(r['size'], 'memory[$i].size', errs),
              perms: (r['perms'] as String?) ?? 'rwx',
              role: (r['role'] as String?) ?? '',
            ),
          );
        } else {
          errs.add('memory[$i]: expected an object');
        }
      }
    }

    final init = <String, int>{};
    final ij = m['init'];
    if (ij is Map) ij.forEach((k, v) => init['$k'] = _int(v, 'init.$k', errs));

    final instrs = <InstructionSpec>[];
    final xj = m['instructions'];
    if (xj is List) {
      for (var i = 0; i < xj.length; i++) {
        final x = xj[i];
        if (x is! Map<String, dynamic>) {
          errs.add('instructions[$i]: expected an object');
          continue;
        }
        final mn = _str(x['mnemonic'], 'instructions[$i].mnemonic', errs);
        final where = 'instruction ${mn.isEmpty ? '#$i' : mn}';
        final ops = <String, OperandKind>{};
        final oj = x['operands'];
        if (oj is Map) {
          oj.forEach((k, v) {
            final kind = OperandKind.values
                .where((e) => e.name == v)
                .firstOrNull;
            if (kind == null) {
              errs.add(
                "$where: operand '$k' has unknown kind '$v' (use reg, imm or pcrel)",
              );
            } else {
              ops['$k'] = kind;
            }
          });
        }
        final fields = <String, FieldSpec>{};
        final fj = x['fields'];
        if (fj is Map) {
          fj.forEach((k, v) {
            final f = v is String ? FieldSpec.parse(v) : null;
            if (f == null) {
              errs.add(
                "$where: field '$k' is not valid (expected like s[31:20] or [11:7])",
              );
            } else {
              fields['$k'] = f;
            }
          });
        }
        final bits = _int(x['bits'], '$where.bits', errs, or: instrBits);
        instrs.add(
          InstructionSpec(
            id: (x['id'] as String?) ?? mn,
            mnemonic: mn.toLowerCase(),
            syntax: (x['syntax'] as String?) ?? '',
            bits: bits,
            mask: _int(x['mask'], '$where.mask', errs),
            value: _int(x['value'], '$where.value', errs),
            operands: ops,
            fields: fields,
            exec: (x['exec'] as String?) ?? '',
            description: (x['description'] as String?) ?? '',
            cycles: _int(x['cycles'], '$where.cycles', errs, or: 1),
            pcrelBase: _int(x['pcrelBase'], '$where.pcrelBase', errs, or: 0),
            cond: x['cond'] == true,
          ),
        );
      }
    } else {
      errs.add('instructions: expected a list');
    }

    final pseudos = <PseudoSpec>[];
    final pj = m['pseudo'];
    if (pj is List) {
      for (var i = 0; i < pj.length; i++) {
        final p = pj[i];
        if (p is! Map<String, dynamic>) {
          errs.add('pseudo[$i]: expected an object');
          continue;
        }
        final vs = <PseudoVariant>[];
        final vj =
            p['variants'] ??
            [
              {'expand': p['expand']},
            ];
        if (vj is List) {
          for (final v in vj) {
            if (v is Map && v['expand'] is List) {
              vs.add(
                PseudoVariant(
                  when: v['when'] as String?,
                  expand: [for (final e in v['expand'] as List) '$e'],
                ),
              );
            } else {
              errs.add('pseudo[$i]: each variant needs an "expand" list');
            }
          }
        }
        pseudos.add(
          PseudoSpec(
            syntax: _str(p['syntax'], 'pseudo[$i].syntax', errs),
            variants: vs,
          ),
        );
      }
    }

    ConditionSpec? conditions;
    final cj = m['conditions'];
    if (cj is Map<String, dynamic>) {
      final f = cj['field'] is String
          ? FieldSpec.parse(cj['field'] as String)
          : null;
      if (f == null) {
        errs.add('conditions.field: expected a bit range like [31:28]');
      } else {
        final codes = <ConditionCode>[];
        final cl = cj['codes'];
        if (cl is List) {
          for (var i = 0; i < cl.length; i++) {
            final c = cl[i];
            if (c is Map<String, dynamic>) {
              codes.add(
                ConditionCode(
                  suffix: _str(
                    c['suffix'],
                    'conditions.codes[$i].suffix',
                    errs,
                  ),
                  value: _int(c['value'], 'conditions.codes[$i].value', errs),
                  test: _str(
                    c['test'],
                    'conditions.codes[$i].test',
                    errs,
                    or: '1',
                  ),
                ),
              );
            } else {
              errs.add('conditions.codes[$i]: expected an object');
            }
          }
        } else {
          errs.add('conditions.codes: expected a list');
        }
        conditions = ConditionSpec(
          field: f,
          defaultValue: _int(cj['default'], 'conditions.default', errs, or: 0),
          codes: codes,
        );
      }
    } else if (cj != null) {
      errs.add('conditions: expected an object');
    }

    if (errs.isNotEmpty) throw SpecFormatError(errs);

    return ProcessorSpec(
      id: _str(m['id'], 'id', errs, or: 'custom'),
      name: _str(m['name'], 'name', errs, or: 'Custom processor'),
      arch: (m['arch'] as String?) ?? 'custom',
      description: (m['description'] as String?) ?? '',
      vendor: (m['vendor'] as String?) ?? '',
      year: _int(m['year'], 'year', errs, or: 0),
      era: (m['era'] as String?) ?? '',
      tags: [for (final t in (m['tags'] as List? ?? const [])) '$t'],
      wordBits: wordBits,
      endian: m['endian'] == 'big' ? Endian.big : Endian.little,
      instrBits: instrBits,
      alignedAccess: m['alignedAccess'] as bool? ?? false,
      registerFile: rf,
      registers: regs,
      flags: [for (final f in (m['flags'] as List? ?? const [])) '$f'],
      memory: mem,
      init: init,
      resetPc: _int(m['resetPc'], 'resetPc', errs, or: 0),
      comments: [
        for (final c in (m['comments'] as List? ?? const ['#', ';', '//']))
          '$c',
      ],
      pipeline: [for (final s in (m['pipeline'] as List? ?? const [])) '$s'],
      conditions: conditions,
      hexPrefix: (m['hexPrefix'] as String?) ?? '',
      wordBytes: _int(m['wordBytes'], 'wordBytes', errs, or: 4),
      operandRewrites: [
        for (final r in (m['operandRewrites'] as List? ?? const []))
          if (r is List && r.length == 2) ['${r[0]}', '${r[1]}'],
      ],
      sample: (m['sample'] as String?) ?? '',
      instructions: instrs,
      pseudos: pseudos,
      builtin: builtin,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'arch': arch,
    if (description.isNotEmpty) 'description': description,
    if (vendor.isNotEmpty) 'vendor': vendor,
    if (year != 0) 'year': year,
    if (era.isNotEmpty) 'era': era,
    if (tags.isNotEmpty) 'tags': tags,
    'wordBits': wordBits,
    'endian': endian.name,
    'instrBits': instrBits,
    if (alignedAccess) 'alignedAccess': true,
    if (registerFile != null) 'registerFile': registerFile!.toJson(),
    if (registers.isNotEmpty)
      'registers': [for (final r in registers) r.toJson()],
    if (flags.isNotEmpty) 'flags': flags,
    'memory': [for (final r in memory) r.toJson()],
    if (init.isNotEmpty)
      'init': {
        for (final e in init.entries) e.key: '0x${e.value.toRadixString(16)}',
      },
    'resetPc': '0x${resetPc.toRadixString(16)}',
    'comments': comments,
    if (pipeline.isNotEmpty) 'pipeline': pipeline,
    if (conditions != null) 'conditions': conditions!.toJson(),
    if (hexPrefix.isNotEmpty) 'hexPrefix': hexPrefix,
    if (wordBytes != 4) 'wordBytes': wordBytes,
    if (operandRewrites.isNotEmpty) 'operandRewrites': operandRewrites,
    if (sample.isNotEmpty) 'sample': sample,
    'instructions': [for (final i in instructions) i.toJson()],
    if (pseudos.isNotEmpty) 'pseudo': [for (final p in pseudos) p.toJson()],
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  // -------------------------------------------------------------------------------------------------------------
  // Validation

  /// Human readable problems; empty when the processor is usable.
  List<String> validate() {
    final errs = <String>[];
    if (id.trim().isEmpty || !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(id)) {
      errs.add('id must contain only letters, digits, "_", "-" or "."');
    }
    if (![8, 16, 32, 64].contains(wordBits)) {
      errs.add('wordBits must be 8, 16, 32 or 64');
    }
    if (instrBits <= 0 || instrBits % 8 != 0 || instrBits > 64) {
      errs.add('instrBits must be a multiple of 8 up to 64');
    }

    final rf = registerFile;
    if (rf != null) {
      if (rf.count < 1 || rf.count > 256) {
        errs.add('registerFile.count must be between 1 and 256');
      }
      if (![8, 16, 32, 64].contains(rf.width)) {
        errs.add('registerFile.width must be 8, 16, 32 or 64');
      }
      if (rf.zeroIndex != null &&
          (rf.zeroIndex! < 0 || rf.zeroIndex! >= rf.count)) {
        errs.add('registerFile.zero must be a valid register index');
      }
      rf.aliases.forEach((a, i) {
        if (i < 0 || i >= rf.count) {
          errs.add("alias '$a' points to register $i, which does not exist");
        }
      });
    }
    final seen = <String>{};
    for (var i = 0; i < registerCount; i++) {
      for (final n in [registerName(i), ...registerAliases(i)]) {
        if (!seen.add(n.toLowerCase())) {
          errs.add("register name '$n' is used more than once");
        }
      }
    }
    for (final r in registers) {
      if (![8, 16, 32, 64].contains(r.width)) {
        errs.add("register '${r.name}': width must be 8, 16, 32 or 64");
      }
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(r.name)) {
        errs.add("register name '${r.name}' is not a valid identifier");
      }
    }
    for (final f in flags) {
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(f)) {
        errs.add("flag name '$f' is not a valid identifier");
      } else if (!seen.add(f.toLowerCase())) {
        errs.add("flag '$f' clashes with a register or flag of the same name");
      }
    }
    if (memory.isEmpty) {
      errs.add('The processor needs at least one memory region');
    }
    for (final r in memory) {
      if (r.size <= 0) errs.add("memory region '${r.name}' has no size");
      if (r.base < 0) errs.add("memory region '${r.name}' has a negative base");
      if (!RegExp(r'^[rwx]+$').hasMatch(r.perms)) {
        errs.add("memory region '${r.name}': perms must use r, w, x");
      }
      if (wordBits < 64 && r.end > (1 << wordBits)) {
        errs.add("memory region '${r.name}' is larger than the address space");
      }
    }
    for (var a = 0; a < memory.length; a++) {
      for (var b = a + 1; b < memory.length; b++) {
        if (memory[a].base < memory[b].end && memory[b].base < memory[a].end) {
          errs.add(
            "memory regions '${memory[a].name}' and '${memory[b].name}' overlap",
          );
        }
      }
    }
    init.forEach((k, v) {
      if (registerIndexExact(k) == null) {
        errs.add("init: unknown register '$k'");
      }
    });

    final names = <String>{
      'pc',
      'next',
      for (var i = 0; i < registerCount; i++) ...[
        registerName(i),
        ...registerAliases(i),
      ],
      ...flags,
    };

    final keys = <String>{};
    for (final ins in instructions) {
      final w = 'instruction "${ins.mnemonic}"';
      if (ins.mnemonic.isEmpty ||
          !RegExp(r'^[a-z0-9_.]+$').hasMatch(ins.mnemonic)) {
        errs.add('$w: the mnemonic must be letters, digits, "_" or "."');
      }
      if (!keys.add(
        '${ins.mnemonic} ${ins.syntax.replaceAll(RegExp(r'\s+'), '')} ${ins.bits}',
      )) {
        errs.add('$w is defined twice with the same operands and size');
      }
      if (ins.bits <= 0 || ins.bits % 8 != 0 || ins.bits > 64) {
        errs.add('$w: bits must be a multiple of 8 up to 64');
        continue;
      }
      final full = ins.bits >= 64 ? -1 : (1 << ins.bits) - 1;
      if ((ins.mask & ~full) != 0) {
        errs.add('$w: mask is wider than the instruction');
      }
      if ((ins.value & ~ins.mask) != 0) {
        errs.add('$w: value has bits that are not in the mask');
      }
      if (ins.mask == 0) errs.add('$w: mask is empty, every word would match');

      var used = ins.mask;
      for (final e in ins.fields.entries) {
        if (e.value.highestBit >= ins.bits) {
          errs.add(
            "$w: field '${e.key}' uses bit ${e.value.highestBit} outside the instruction",
          );
        }
        var fm = 0;
        for (final s in e.value.segments) {
          fm |= (((1 << (s.hi - s.lo + 1)) - 1) << s.lo);
        }
        if ((fm & ins.mask) != 0) {
          errs.add("$w: field '${e.key}' overlaps the opcode bits");
        }
        if ((fm & used & ~ins.mask) != 0) {
          errs.add("$w: field '${e.key}' overlaps another field");
        }
        used |= fm;
        if (!ins.operands.containsKey(e.key)) {
          errs.add("$w: field '${e.key}' is not an operand");
        }
      }
      for (final o in ins.operands.entries) {
        if (!ins.fields.containsKey(o.key)) {
          errs.add("$w: operand '${o.key}' has no field");
        }
        if (!RegExp('\\b${RegExp.escape(o.key)}\\b').hasMatch(ins.syntax)) {
          errs.add(
            "$w: operand '${o.key}' does not appear in the syntax '${ins.syntax}'",
          );
        }
        if (o.value == OperandKind.reg && rf == null) {
          errs.add(
            "$w: operand '${o.key}' is a register but the processor has no register file",
          );
        }
        if (o.value == OperandKind.reg) {
          final f = ins.fields[o.key];
          if (f != null && rf != null) {
            if (f.offset == 0 && (1 << f.width) < rf.count) {
              errs.add(
                "$w: field '${o.key}' is too narrow for ${rf.count} registers",
              );
            }
            if (f.offset >= rf.count) {
              errs.add(
                "$w: field '${o.key}' starts beyond the ${rf.count} registers in the file",
              );
            }
          }
        }
      }

      try {
        final prog = ins.program;
        final a = analyze(prog);
        final local = <String>{};
        final operandNames = ins.operands.keys.toSet();
        for (final wname in a.writes) {
          if (memSize(wname) != null) continue;
          if (names.contains(wname) || operandNames.contains(wname)) {
            if (ins.operands[wname] != null &&
                ins.operands[wname] != OperandKind.reg) {
              errs.add("$w: '$wname' is an immediate and cannot be assigned");
            }
          } else {
            local.add(wname);
          }
        }
        for (final r in a.reads) {
          if (!names.contains(r) &&
              !operandNames.contains(r) &&
              !local.contains(r)) {
            errs.add(
              "$w: semantics use '$r', which is not an operand, register, flag or temporary",
            );
          }
        }
        _checkCalls(prog, errs, w);
      } on ExprError catch (e) {
        errs.add('$w: semantics: ${e.message}');
      }
    }

    // Ambiguous encodings: two instructions of the same width that can match the same word where neither is a
    // refinement of the other.
    for (var a = 0; a < instructions.length; a++) {
      for (var b = a + 1; b < instructions.length; b++) {
        final x = instructions[a], y = instructions[b];
        if (x.bits != y.bits) continue;
        final overlap = ((x.value ^ y.value) & x.mask & y.mask) == 0;
        if (!overlap) continue;
        final xInY = (x.mask & y.mask) == y.mask;
        final yInX = (x.mask & y.mask) == x.mask;
        if (!xInY && !yInX || x.mask == y.mask) {
          errs.add(
            '"${x.mnemonic}" and "${y.mnemonic}" have overlapping encodings',
          );
        }
      }
    }

    for (final p in pseudos) {
      if (p.variants.isEmpty) {
        errs.add('pseudo "${p.mnemonic}" has no variants');
      }
    }

    for (final r in operandRewrites) {
      try {
        RegExp(r[0]);
      } on FormatException catch (e) {
        errs.add(
          'operandRewrites: "${r[0]}" is not a valid pattern (${e.message})',
        );
      }
    }

    final cs = conditions;
    if (cs != null) {
      final seenSuffix = <String>{};
      final seenValue = <int>{};
      for (final c in cs.codes) {
        if (!RegExp(r'^[a-z]{1,3}$').hasMatch(c.suffix)) {
          errs.add(
            "condition suffix '${c.suffix}' must be 1 to 3 lower-case letters",
          );
        }
        if (!seenSuffix.add(c.suffix)) {
          errs.add("condition suffix '${c.suffix}' is used twice");
        }
        if (!seenValue.add(c.value)) {
          errs.add('condition value ${c.value} is used twice');
        }
        if (c.value < 0 || c.value >= (1 << cs.field.width)) {
          errs.add(
            "condition '${c.suffix}': value ${c.value} does not fit the field",
          );
        }
        try {
          final reads = <String>{};
          collectReads(c.expr, reads);
          for (final r in reads) {
            if (!names.contains(r)) {
              errs.add(
                "condition '${c.suffix}': '$r' is not a register or flag",
              );
            }
          }
        } on ExprError catch (e) {
          errs.add("condition '${c.suffix}': ${e.message}");
        }
      }
      if (cs.byValue(cs.defaultValue) == null) {
        errs.add('conditions.default does not match any code');
      }
      var fm = 0;
      for (final sg in cs.field.segments) {
        fm |= ((1 << (sg.hi - sg.lo + 1)) - 1) << sg.lo;
      }
      for (final ins in instructions.where((i) => i.cond)) {
        if ((ins.mask & fm) != 0) {
          errs.add(
            'instruction "${ins.mnemonic}": the condition field is part of its mask',
          );
        }
        if (cs.field.highestBit >= ins.bits) {
          errs.add(
            'instruction "${ins.mnemonic}": too small for the condition field',
          );
        }
        for (final f in ins.fields.entries) {
          var m = 0;
          for (final sg in f.value.segments) {
            m |= ((1 << (sg.hi - sg.lo + 1)) - 1) << sg.lo;
          }
          if ((m & fm) != 0) {
            errs.add(
              "instruction \"${ins.mnemonic}\": field '${f.key}' overlaps the condition field",
            );
          }
        }
      }
    } else if (instructions.any((i) => i.cond)) {
      errs.add(
        'Some instructions are conditional but the processor defines no "conditions"',
      );
    }
    return errs;
  }

  void _checkCalls(List<Stmt> prog, List<String> errs, String where) {
    void expr(Expr e) {
      switch (e) {
        case CallExpr(:final fn, :final args):
          if (!exprFunctions.contains(fn)) {
            errs.add("$where: unknown function '$fn()'");
          }
          args.forEach(expr);
        case UnaryExpr(:final operand):
          expr(operand);
        case BinaryExpr(:final left, :final right):
          expr(left);
          expr(right);
        case CondExpr(:final cond, :final then, :final otherwise):
          expr(cond);
          expr(then);
          expr(otherwise);
        case IndexExpr(:final base, :final index):
          if (memSize(base) == null) {
            errs.add(
              "$where: '$base[...]' is not memory (use mem8, mem16, mem32 or mem64)",
            );
          }
          expr(index);
        default:
          break;
      }
    }

    void walk(List<Stmt> l) {
      for (final s in l) {
        switch (s) {
          case AssignStmt(:final target, :final value):
            if (target is IndexExpr && memSize(target.base) == null) {
              errs.add(
                "$where: '${target.base}[...]' cannot be assigned (use mem8, mem16, mem32 or mem64)",
              );
            }
            expr(value);
          case IfStmt(:final cond, :final then, :final otherwise):
            expr(cond);
            walk(then);
            walk(otherwise);
          case CallStmt(:final call):
            if (!stmtFunctions.contains(call.fn)) {
              errs.add("$where: unknown statement '${call.fn}()'");
            }
            for (final a in call.args) {
              if (a is! StrExpr) expr(a);
            }
        }
      }
    }

    walk(prog);
  }
}

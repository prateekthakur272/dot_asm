import 'package:dot_asm/core/sim/machine/memory.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';

/// One instruction picked out of a byte stream.
class Decoded {
  const Decoded({
    required this.instruction,
    required this.raw,
    required this.operands,
    this.condition,
  });

  final InstructionSpec instruction;

  /// The instruction word.
  final int raw;

  /// Operand name → decoded value (register index, signed immediate, or pc-relative offset).
  final Map<String, int> operands;

  /// The condition code of a conditional instruction (`eq`, `ne`, ...), or null for unconditional ones.
  final ConditionCode? condition;

  int get length => instruction.bytes;
}

int _popcount(int v) {
  var n = 0;
  while (v != 0) {
    n += v & 1;
    v >>>= 1;
  }
  return n;
}

class Decoder {
  Decoder(this.spec) {
    final byLen = <int, List<InstructionSpec>>{};
    for (final i in spec.instructions) {
      byLen.putIfAbsent(i.bits, () => []).add(i);
    }
    // Most specific encodings first, so refinements win over general patterns.
    for (final l in byLen.values) {
      l.sort((a, b) => _popcount(b.mask).compareTo(_popcount(a.mask)));
    }
    _lengths = byLen.keys.toList()..sort();
    _byLength = byLen;
  }

  final ProcessorSpec spec;
  late final List<int> _lengths;
  late final Map<int, List<InstructionSpec>> _byLength;

  int _word(List<int> bytes, int n) {
    var v = 0;
    if (spec.endian == Endian.little) {
      for (var i = n - 1; i >= 0; i--) {
        v = (v << 8) | bytes[i];
      }
    } else {
      for (var i = 0; i < n; i++) {
        v = (v << 8) | bytes[i];
      }
    }
    return v;
  }

  final Map<int, Decoded?> _cache = {};

  /// Decodes the instruction at the start of [bytes], or null when nothing matches.
  ///
  /// Results are cached per instruction word, so loops and large instruction sets cost almost nothing per step.
  Decoded? decode(List<int> bytes) {
    int? key;
    if (bytes.length <= 7) {
      var v = 0;
      for (var i = bytes.length - 1; i >= 0; i--) {
        v = (v << 8) | bytes[i];
      }
      key = (bytes.length << 56) | v;
      if (_cache.containsKey(key)) return _cache[key];
    }
    final d = _decodeUncached(bytes);
    if (key != null) {
      if (_cache.length > 16384) _cache.clear();
      _cache[key] = d;
    }
    return d;
  }

  Decoded? _decodeUncached(List<int> bytes) {
    final cs = spec.conditions;
    for (final bits in _lengths) {
      final n = bits ~/ 8;
      if (bytes.length < n) continue;
      final word = _word(bytes, n);
      for (final ins in _byLength[bits]!) {
        if ((word & ins.mask) != ins.value) continue;
        ConditionCode? cond;
        if (ins.cond && cs != null) {
          cond = cs.byValue(cs.field.extract(word));
          if (cond == null) continue;
        }
        return Decoded(
          instruction: ins,
          raw: word,
          operands: {
            for (final e in ins.fields.entries) e.key: e.value.extract(word),
          },
          condition: cond,
        );
      }
    }
    return null;
  }

  /// Text of a decoded instruction (`addi sp, sp, -16`). [pc] resolves pc-relative targets to addresses.
  String format(Decoded d, int pc, {bool aliases = true}) {
    final ins = d.instruction;
    var text = ins.syntax;
    for (final name in ins.operandOrder) {
      final v = d.operands[name] ?? 0;
      final kind = ins.operands[name]!;
      final s = switch (kind) {
        OperandKind.reg => _regText(v, aliases),
        OperandKind.imm => v.abs() > 9 && v >= 0 ? hex(v, 1) : '$v',
        OperandKind.pcrel => hex((pc + ins.pcrelBase + v) & _addrMask, 1),
      };
      text = text.replaceAllMapped(
        RegExp('\\b${RegExp.escape(name)}\\b'),
        (_) => s,
      );
    }
    final c = d.condition;
    final suffix = c == null || c.value == spec.conditions?.defaultValue
        ? ''
        : c.suffix;
    final out = text.isEmpty
        ? '${ins.mnemonic}$suffix'
        : '${ins.mnemonic}$suffix $text';
    return out.replaceAll('+-', '-');
  }

  int get _addrMask => spec.wordBits >= 64 ? -1 : (1 << spec.wordBits) - 1;

  String _regText(int idx, bool aliases) {
    if (idx < 0 || idx >= spec.registerCount) return '?$idx';
    if (aliases && spec.registerAliases(idx).isNotEmpty) {
      return spec.registerAliases(idx).first;
    }
    return spec.registerName(idx);
  }

  /// Disassembles [memory] from [start] up to (not including) [end]. Unknown words become `.byte`.
  List<DisasmLine> disassemble(
    Memory memory,
    int start,
    int end, {
    bool aliases = true,
  }) {
    final out = <DisasmLine>[];
    var pc = start;
    final maxBytes = spec.maxInstrBits ~/ 8;
    while (pc < end) {
      final avail = (end - pc) < maxBytes ? end - pc : maxBytes;
      final bytes = memory.peek(pc, avail);
      final d = decode(bytes);
      if (d == null) {
        out.add(
          DisasmLine(
            pc,
            bytes.take(1).toList(),
            '.byte ${hex(bytes.first, 2)}',
            null,
          ),
        );
        pc += 1;
      } else {
        out.add(
          DisasmLine(
            pc,
            bytes.take(d.length).toList(),
            format(d, pc, aliases: aliases),
            d,
          ),
        );
        pc += d.length;
      }
    }
    return out;
  }
}

class DisasmLine {
  const DisasmLine(this.address, this.bytes, this.text, this.decoded);
  final int address;
  final List<int> bytes;
  final String text;
  final Decoded? decoded;
}

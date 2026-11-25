/// A contiguous block of bytes to place in memory.
class Segment {
  Segment(this.address, [List<int>? bytes]) : bytes = bytes ?? [];
  final int address;
  final List<int> bytes;
  int get end => address + bytes.length;
}

class AsmDiagnostic {
  const AsmDiagnostic(this.line, this.message, {this.column = 0});

  /// 1-based source line.
  final int line;

  /// 1-based column, or 0 when unknown.
  final int column;
  final String message;

  @override
  String toString() => 'line $line: $message';
}

/// The result of assembling a source file.
class AssembledProgram {
  AssembledProgram({
    required this.segments,
    required this.entry,
    required this.symbols,
    required this.addressToLine,
    required this.errors,
  });

  final List<Segment> segments;
  final int entry;
  final Map<String, int> symbols;

  /// Instruction address → 1-based source line.
  final Map<int, int> addressToLine;
  final List<AsmDiagnostic> errors;

  bool get ok => errors.isEmpty;

  /// First address of an instruction for a source [line], or null.
  int? addressOfLine(int line) {
    int? best;
    addressToLine.forEach((a, l) {
      if (l == line && (best == null || a < best!)) best = a;
    });
    return best;
  }

  /// Address ranges (start, end) that hold code, for the disassembly view.
  late final List<({int start, int end})> codeRanges = _ranges();

  List<({int start, int end})> _ranges() {
    final addrs = addressToLine.keys.toList()..sort();
    final out = <({int start, int end})>[];
    for (final s in segments) {
      final inside = addrs.where((a) => a >= s.address && a < s.end).toList();
      if (inside.isEmpty) continue;
      out.add((start: inside.first, end: s.end));
    }
    return out;
  }
}

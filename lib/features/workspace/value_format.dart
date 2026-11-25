enum ValueFormat {
  hex('Hex'),
  dec('Signed'),
  udec('Unsigned'),
  bin('Binary');

  const ValueFormat(this.label);
  final String label;
}

/// Formats a register or memory [value] of [width] bits.
String formatValue(int value, int width, ValueFormat f) {
  final mask = width >= 64 ? -1 : (1 << width) - 1;
  final u = value & mask;
  switch (f) {
    case ValueFormat.hex:
      return '0x${(width >= 64 ? BigInt.from(u).toUnsigned(64) : BigInt.from(u)).toRadixString(16).padLeft(width ~/ 4, '0')}';
    case ValueFormat.dec:
      if (width >= 64) return '$u';
      return '${u >= (1 << (width - 1)) ? u - (1 << width) : u}';
    case ValueFormat.udec:
      return width >= 64 ? BigInt.from(u).toUnsigned(64).toString() : '$u';
    case ValueFormat.bin:
      final s = (width >= 64 ? BigInt.from(u).toUnsigned(64) : BigInt.from(u))
          .toRadixString(2)
          .padLeft(width, '0');
      return '0b${[for (var i = 0; i < s.length; i += 8) s.substring(i, i + 8)].join('_')}';
  }
}

/// Parses a value typed by the user: `0x1f`, `$1f`, `0b101`, decimal, an optional leading `-`, `_` separators.
/// Returns null when it is not a number. Values wrap to 64 bits.
int? parseValue(String text) {
  var t = text.trim().replaceAll('_', '').toLowerCase();
  if (t.isEmpty) return null;
  final neg = t.startsWith('-');
  if (neg) t = t.substring(1);
  BigInt? v;
  if (t.startsWith('0x')) {
    v = BigInt.tryParse(t.substring(2), radix: 16);
  } else if (t.startsWith(r'$')) {
    v = BigInt.tryParse(t.substring(1), radix: 16);
  } else if (t.startsWith('0b')) {
    v = BigInt.tryParse(t.substring(2), radix: 2);
  } else {
    v = BigInt.tryParse(t);
  }
  if (v == null) return null;
  if (neg) v = -v;
  return v.toSigned(64).toInt();
}

import 'dart:typed_data';

import 'package:dot_asm/core/sim/spec/processor_spec.dart';

/// A memory access that the processor is not allowed to make.
class MemFault implements Exception {
  MemFault(this.message, this.address);
  final String message;
  final int address;

  @override
  String toString() => message;
}

String hex(int v, [int digits = 8]) =>
    '0x${(v & 0xFFFFFFFFFFFFFFFF).toRadixString(16).padLeft(digits, '0')}';

/// Sparse paged byte memory with the permissions of the processor's memory regions.
class Memory {
  Memory(this.spec, {int? addressBits})
    : _mask = (addressBits ?? spec.wordBits) >= 64
          ? -1
          : (1 << (addressBits ?? spec.wordBits)) - 1;

  final ProcessorSpec spec;
  final int _mask;
  static const _pageBits = 12;
  static const _pageSize = 1 << _pageBits;
  final Map<int, Uint8List> _pages = {};

  /// Addresses written since the last [clearDirty] (for highlighting in the memory view).
  final Set<int> dirty = {};

  void clear() {
    _pages.clear();
    dirty.clear();
  }

  void clearDirty() => dirty.clear();

  MemoryRegionSpec? regionAt(int addr) {
    for (final r in spec.memory) {
      if (addr >= r.base && addr < r.end) return r;
    }
    return null;
  }

  Uint8List _page(int addr) =>
      _pages.putIfAbsent(addr >> _pageBits, () => Uint8List(_pageSize));

  int _rawByte(int addr) {
    final p = _pages[addr >> _pageBits];
    return p == null ? 0 : p[addr & (_pageSize - 1)];
  }

  void _rawSet(int addr, int v) {
    _page(addr)[addr & (_pageSize - 1)] = v & 0xFF;
  }

  void _check(int addr, int size, String need) {
    final r = regionAt(addr);
    final last = regionAt(addr + size - 1);
    if (r == null || last == null || !identical(r, last)) {
      throw MemFault('Access to unmapped memory at ${hex(addr)}', addr);
    }
    final ok = switch (need) {
      'r' => r.canRead,
      'w' => r.canWrite,
      _ => r.canExecute,
    };
    if (!ok) {
      final what = switch (need) {
        'r' => 'read from',
        'w' => 'write to',
        _ => 'execute code in',
      };
      throw MemFault(
        "Cannot $what '${r.name}' (${hex(addr)}): region is ${r.perms}",
        addr,
      );
    }
    if (spec.alignedAccess && need != 'x' && size > 1 && addr % size != 0) {
      throw MemFault('Misaligned ${size * 8}-bit access at ${hex(addr)}', addr);
    }
  }

  /// Loader/debugger write that ignores permissions.
  void poke(int addr, List<int> bytes) {
    for (var i = 0; i < bytes.length; i++) {
      _rawSet((addr + i) & _mask, bytes[i]);
    }
  }

  /// Debugger read of [len] bytes that ignores permissions.
  List<int> peek(int addr, int len) => [
    for (var i = 0; i < len; i++) _rawByte((addr + i) & _mask),
  ];

  int _compose(int addr, int size) {
    var v = 0;
    if (spec.endian == Endian.little) {
      for (var i = size - 1; i >= 0; i--) {
        v = (v << 8) | _rawByte((addr + i) & _mask);
      }
    } else {
      for (var i = 0; i < size; i++) {
        v = (v << 8) | _rawByte((addr + i) & _mask);
      }
    }
    return v;
  }

  /// Reads [size] bytes (1, 2, 4 or 8) as an unsigned value.
  int read(int addr, int size) {
    addr &= _mask;
    _check(addr, size, 'r');
    return _compose(addr, size);
  }

  /// Writes the low [size] bytes of [value]; returns the previous bytes.
  List<int> write(int addr, int size, int value) {
    addr &= _mask;
    _check(addr, size, 'w');
    final old = peek(addr, size);
    for (var i = 0; i < size; i++) {
      final shift = spec.endian == Endian.little ? i * 8 : (size - 1 - i) * 8;
      final a = (addr + i) & _mask;
      _rawSet(a, (value >>> shift) & 0xFF);
      dirty.add(a);
    }
    return old;
  }

  /// Instruction fetch: up to [max] bytes starting at [addr] from executable memory; returns fewer bytes when the
  /// region ends. Throws when not even one byte is executable.
  List<int> fetch(int addr, int max) {
    addr &= _mask;
    final r = regionAt(addr);
    if (r == null) {
      throw MemFault(
        'Instruction fetch from unmapped memory at ${hex(addr)}',
        addr,
      );
    }
    if (!r.canExecute) {
      throw MemFault(
        "Cannot execute code in '${r.name}' (${hex(addr)}): region is ${r.perms}",
        addr,
      );
    }
    final n = (r.end - addr) < max ? r.end - addr : max;
    return peek(addr, n);
  }
}

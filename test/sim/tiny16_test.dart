import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/core/sim/asm/assembler.dart';
import 'package:dot_asm/core/sim/machine/machine.dart';
import 'package:dot_asm/core/sim/dsl/processor_dsl.dart';

void main() {
  final spec = ProcessorDsl.parse(
    File('assets/templates/tiny16.cpu').readAsStringSync(),
    builtin: true,
  );

  test('Tiny-16 is a valid processor', () {
    expect(spec.validate(), isEmpty);
    expect(spec.wordBits, 16);
  });

  test('the sample program runs and prints 55', () {
    final p = Assembler(spec).assemble(spec.sample);
    expect(p.errors, isEmpty, reason: p.errors.join('\n'));
    final m = Machine(spec)..loadProgram(p);
    var n = 0;
    while (m.canStep && n++ < 10000) {
      m.step();
    }
    expect(m.fault, isNull);
    expect(m.status, MachineStatus.halted);
    expect(m.console.toString(), '55');
    expect(m.memory.peek(0x4000, 2), [55, 0]);
  });

  test('encodings and large immediates', () {
    final p = Assembler(spec)
        .assemble('li r1, 5\nadd r2, r1, r1\nli r3, 5000\nout r3\nhalt');
    expect(p.errors, isEmpty, reason: p.errors.join('\n'));
    final b = p.segments.first.bytes;
    expect(b[0] | (b[1] << 8), 0x2205); // li r1, 5
    expect(b[2] | (b[3] << 8), 0x0448); // add r2, r1, r1
    final m = Machine(spec)..loadProgram(p);
    while (m.canStep) {
      m.step();
    }
    expect(m.console.toString(), '5000');
  });

  test('call and return with the link register', () {
    final m = Machine(spec)
      ..loadProgram(
        Assembler(spec).assemble('''
main:
  li r1, 7
  call double
  out r1
  halt
double:
  add r1, r1, r1
  ret
'''),
      );
    while (m.canStep) {
      m.step();
    }
    expect(m.console.toString(), '14');
  });
}

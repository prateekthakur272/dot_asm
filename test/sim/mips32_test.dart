import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/core/sim/asm/assembler.dart';
import 'package:dot_asm/core/sim/machine/machine.dart';
import 'package:dot_asm/core/sim/dsl/processor_dsl.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';

Machine run(ProcessorSpec spec, String src) {
  final p = Assembler(spec).assemble(src);
  expect(p.errors, isEmpty, reason: p.errors.join('\n'));
  final m = Machine(spec)..loadProgram(p);
  var n = 0;
  while (m.canStep && n++ < 100000) {
    m.step();
  }
  return m;
}

void main() {
  final spec = ProcessorDsl.parse(
    File('assets/templates/mips32.cpu').readAsStringSync(),
    builtin: true,
  );

  test('valid', () => expect(spec.validate(), isEmpty));

  test('known encodings', () {
    final p = Assembler(spec).assemble('''
addu \$t0, \$t1, \$t2
addiu \$sp, \$sp, -8
lw \$t0, 4(\$sp)
sw \$ra, 0(\$sp)
lui \$t0, 0x1234
beq \$zero, \$zero, -4
jr \$ra
syscall
sll \$zero, \$zero, 0
''');
    expect(p.errors, isEmpty, reason: p.errors.join('\n'));
    final b = p.segments.first.bytes;
    int w(int i) =>
        b[i * 4] |
        (b[i * 4 + 1] << 8) |
        (b[i * 4 + 2] << 16) |
        (b[i * 4 + 3] << 24);
    expect(w(0), 0x012a4021);
    expect(w(1), 0x27bdfff8);
    expect(w(2), 0x8fa80004);
    expect(w(3), 0xafbf0000);
    expect(w(4), 0x3c081234);
    expect(w(5), 0x1000ffff); // offset -4 bytes = -1 word
    expect(w(6), 0x03e00008);
    expect(w(7), 0x0000000c);
    expect(w(8), 0);
  });

  test('the sample program', () {
    final m = run(spec, spec.sample);
    expect(m.fault, isNull);
    expect(m.status, MachineStatus.halted);
    expect(m.console.toString(), 'result = 110');
  });

  test('multiply, divide, HI/LO, pseudo branches and memory', () {
    final m = run(spec, '''
.data
buf: .word 0
.text
main:
  li \$t0, 100000
  li \$t1, 300000
  multu \$t0, \$t1
  mflo \$s0
  mfhi \$s1
  li \$t2, 17
  li \$t3, 5
  div \$t2, \$t3
  mflo \$s2
  mfhi \$s3
  li \$t4, -7
  blt \$t4, \$zero, neg
  li \$s4, 0
  j end
neg:
  li \$s4, 1
end:
  la \$t5, buf
  li \$t6, 0xdeadbeef
  sw \$t6, 0(\$t5)
  lbu \$s5, 0(\$t5)
  lb \$s6, 3(\$t5)
  break
''');
    expect(m.fault, isNull);
    int r(String n) => m.register(spec.registerIndexByName(n)!);
    expect(r(r'$s0'), (100000 * 300000) & 0xffffffff);
    expect(r(r'$s1'), (100000 * 300000) >> 32);
    expect(r(r'$s2'), 3);
    expect(r(r'$s3'), 2);
    expect(r(r'$s4'), 1);
    expect(r(r'$s5'), 0xef);
    expect(r(r'$s6'), 0xffffffde); // sign-extended 0xde
  });
}

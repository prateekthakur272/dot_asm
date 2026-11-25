import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/core/sim/asm/assembler.dart';
import 'package:dot_asm/core/sim/asm/program.dart';
import 'package:dot_asm/core/sim/machine/machine.dart';
import 'package:dot_asm/core/sim/dsl/processor_dsl.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';

ProcessorSpec loadRv32i() => ProcessorDsl.parse(
  File('assets/templates/rv32i.cpu').readAsStringSync(),
  builtin: true,
);

AssembledProgram asm(ProcessorSpec spec, String src) {
  final p = Assembler(spec).assemble(src);
  expect(p.errors, isEmpty, reason: p.errors.join('\n'));
  return p;
}

int word(AssembledProgram p, int index) {
  final b = p.segments.first.bytes;
  return b[index * 4] |
      (b[index * 4 + 1] << 8) |
      (b[index * 4 + 2] << 16) |
      (b[index * 4 + 3] << 24);
}

Machine run(ProcessorSpec spec, String src, {int max = 100000}) {
  final m = Machine(spec)..loadProgram(asm(spec, src));
  var n = 0;
  while (m.canStep && n++ < max) {
    m.step();
  }
  return m;
}

void main() {
  final spec = loadRv32i();

  test('the RV32I spec is valid', () {
    expect(spec.validate(), isEmpty);
    expect(spec.instructions.length, 40);
  });

  test('spec survives a JSON round trip', () {
    final again = ProcessorSpec.parse(spec.toJsonString());
    expect(again.validate(), isEmpty);
    expect(again.instructions.length, spec.instructions.length);
    expect(again.toJsonString(), spec.toJsonString());
  });

  group('assembler encodings', () {
    test('known machine words', () {
      final p = asm(spec, '''
addi x1, x0, 5
add x3, x1, x2
sub x1, x2, x3
lw x5, 8(x2)
sw x5, 8(x2)
lui x1, 0x12345
srai x1, x2, 3
jal x1, 8
nop
beq x0, x0, -4
ecall
''');
      expect(word(p, 0), 0x00500093);
      expect(word(p, 1), 0x002081b3);
      expect(word(p, 2), 0x403100b3);
      expect(word(p, 3), 0x00812283);
      expect(word(p, 4), 0x00512423);
      expect(word(p, 5), 0x123450b7);
      expect(word(p, 6), 0x40315093);
      expect(word(p, 7), 0x008000ef);
      expect(word(p, 8), 0x00000013);
      expect(word(p, 9), 0xfe000ee3);
      expect(word(p, 10), 0x00000073);
    });

    test('ABI names, labels, forward branches', () {
      final p = asm(spec, '''
start:
  beqz a0, done
  addi a0, a0, -1
  j start
done:
  ret
''');
      expect(p.symbols['done'], 12);
      expect(word(p, 3), 0x00008067); // ret = jalr x0, 0(x1)
    });

    test('li picks one or two instructions', () {
      final small = asm(spec, 'li a0, 100');
      expect(small.segments.first.bytes.length, 4);
      final big = asm(spec, 'li a0, 0x12345678');
      expect(big.segments.first.bytes.length, 8);
      final m = Machine(spec)..loadProgram(big);
      m.step();
      m.step();
      expect(m.register(10), 0x12345678);
      final neg = Machine(spec)..loadProgram(asm(spec, 'li a0, 0xdeadbeef'));
      neg.step();
      neg.step();
      expect(neg.register(10), 0xdeadbeef);
    });

    test('reports errors with line numbers', () {
      final p = Assembler(
        spec,
      ).assemble('nop\nfoo x1, x2\naddi x1, x2, 5000\nadd x1, x2\nj nowhere\n');
      expect(p.ok, isFalse);
      final byLine = {for (final e in p.errors) e.line: e.message};
      expect(byLine[2], contains('Unknown instruction'));
      expect(byLine[3], contains('out of range'));
      expect(byLine[4], contains('Wrong operands'));
      expect(byLine[5], contains('Undefined symbol'));
    });

    test('data directives and strings', () {
      final p = asm(spec, '''
.data
msg: .asciz "hi"
nums: .word 1, 2, 0x10
.byte 7
.text
main: nop
''');
      final data = p.segments.firstWhere((s) => s.address == 0x10000000);
      expect(data.bytes.sublist(0, 3), [104, 105, 0]);
      expect(p.symbols['nums'], 0x10000003);
    });
  });

  group('execution', () {
    test('sum of 1..10', () {
      final m = run(spec, '''
main:
  li t0, 0
  li t1, 1
  li t2, 10
loop:
  add t0, t0, t1
  addi t1, t1, 1
  ble t1, t2, loop
  mv a0, t0
  li a7, 10
  ecall
''');
      expect(m.status, MachineStatus.halted);
      expect(m.register(5), 55);
      expect(m.register(10), 55);
    });

    test('memory, data section and console output', () {
      final m = run(spec, '''
.data
msg: .asciz "sum="
.align 2
buf: .word 0
.text
main:
  la t0, buf
  li t1, 21
  sw t1, 0(t0)
  lw t2, 0(t0)
  add t2, t2, t2
  la a0, msg
  li a7, 4
  ecall
  mv a0, t2
  li a7, 1
  ecall
  li a7, 10
  ecall
''');
      expect(m.fault, isNull);
      expect(m.status, MachineStatus.halted);
      expect(m.console.toString(), 'sum=42');
    });

    test('x0 is hard-wired to zero', () {
      final m = run(spec, 'addi x0, x0, 5\nebreak');
      expect(m.register(0), 0);
    });

    test('signed and unsigned comparisons and shifts', () {
      final m = run(spec, '''
  li a0, -1
  li a1, 1
  slt a2, a0, a1
  sltu a3, a0, a1
  srli a4, a0, 28
  srai a5, a0, 28
  slli a6, a1, 31
  ebreak
''');
      expect(m.register(12), 1);
      expect(m.register(13), 0);
      expect(m.register(14), 0xf);
      expect(m.register(15), 0xffffffff);
      expect(m.register(16), 0x80000000);
    });

    test('jal/jalr call and return', () {
      final m = run(spec, '''
main:
  li a0, 6
  call double
  ebreak
double:
  add a0, a0, a0
  ret
''');
      expect(m.register(10), 12);
    });

    test('step trace describes the effects', () {
      final m = Machine(spec)
        ..loadProgram(asm(spec, 'li t0, 7\nsw t0, 0(sp)\nebreak'));
      final t1 = m.step()!;
      expect(t1.text, 'addi t0, zero, 7');
      expect(t1.regWrites.single.newValue, 7);
      expect(t1.pcAfter, 4);
      final t2 = m.step()!;
      expect(t2.memAccesses.single.write, isTrue);
      expect(t2.memAccesses.single.address, 0x7ffffff0);
      expect(t2.decoded!.instruction.mnemonic, 'sw');
    });

    test('back-step restores everything exactly', () {
      final m = Machine(spec)
        ..loadProgram(
          asm(spec, '''
.data
v: .word 5
.text
main:
  la t0, v
  lw t1, 0(t0)
  addi t1, t1, 1
  sw t1, 0(t0)
  li a0, 3
  li a7, 1
  ecall
  ebreak
'''),
        );
      List<int> snap() => [
        ...m.registers,
        m.pc,
        ...m.memory.peek(0x10000000, 4),
      ];
      final states = <List<int>>[snap()];
      while (m.canStep) {
        m.step();
        states.add(snap());
      }
      expect(m.console.toString(), '3');
      for (var i = states.length - 2; i >= 0; i--) {
        expect(m.undo(), isTrue);
        expect(snap(), states[i], reason: 'after undoing to step $i');
      }
      expect(m.canUndo, isFalse);
      expect(m.console.toString(), '');
      expect(m.status, MachineStatus.ready);
    });
  });

  group('faults', () {
    test('unmapped load', () {
      final m = run(spec, 'lui t0, 0x20000\nlw t1, 0(t0)\nebreak');
      expect(m.status, MachineStatus.faulted);
      expect(m.fault, contains('unmapped'));
      expect(m.pc, 4);
    });

    test('misaligned word access', () {
      final m = run(spec, 'li t0, 0x10000001\nlw t1, 0(t0)\nebreak');
      expect(m.fault, contains('Misaligned'));
    });

    test('writing to code is refused and leaves no partial state', () {
      final m = run(spec, 'li t0, 4\nli t1, 9\nsw t1, 0(t0)\nebreak');
      expect(m.status, MachineStatus.faulted);
      expect(m.fault, contains("write to 'text'"));
      expect(m.memory.peek(4, 4), isNot([9, 0, 0, 0]));
    });

    test('illegal instruction', () {
      final m = Machine(spec)..loadProgram(asm(spec, '.word 0xffffffff'));
      m.step();
      expect(m.status, MachineStatus.faulted);
      expect(m.fault, contains('Illegal instruction'));
    });

    test('running off the end of code', () {
      final m = run(spec, 'nop', max: 70000);
      expect(m.status, MachineStatus.faulted);
    });
  });

  group('validation', () {
    ProcessorSpec tweak(void Function(Map<String, dynamic>) f) {
      final j = ProcessorSpec.parse(spec.toJsonString()).toJson();
      f(j);
      return ProcessorSpec.fromJson(j);
    }

    test(
      'catches overlapping memory, bad semantics and ambiguous encodings',
      () {
        final bad = tweak((j) {
          (j['memory'] as List).add(<String, dynamic>{
            'name': 'x',
            'base': '0x100',
            'size': '0x100',
            'perms': 'rw',
          });
          final ins = j['instructions'] as List;
          (ins.first as Map)['exec'] = 'rd = rs1 + bogus;';
          ins.add(<String, dynamic>{
            ...(ins[1] as Map<String, dynamic>),
            'mnemonic': 'dup',
            'syntax': 'rd, rs1, rs2',
          });
        });
        final errs = bad.validate().join('\n');
        expect(errs, contains('overlap'));
        expect(errs, contains("'bogus'"));
        expect(errs, contains('overlapping encodings'));
      },
    );

    test('rejects malformed json', () {
      expect(() => ProcessorSpec.parse('{'), throwsA(isA<SpecFormatError>()));
      expect(() => ProcessorSpec.parse('[]'), throwsA(isA<SpecFormatError>()));
      expect(
        () => ProcessorSpec.parse('{"instructions": 3}'),
        throwsA(isA<SpecFormatError>()),
      );
    });
  });
}

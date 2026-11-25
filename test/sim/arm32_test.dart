import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/core/sim/asm/assembler.dart';
import 'package:dot_asm/core/sim/machine/machine.dart';
import 'package:dot_asm/core/sim/dsl/processor_dsl.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';

Machine run(ProcessorSpec spec, String src, {int max = 100000}) {
  final p = Assembler(spec).assemble(src);
  expect(p.errors, isEmpty, reason: p.errors.join('\n'));
  final m = Machine(spec)..loadProgram(p);
  var n = 0;
  while (m.canStep && n++ < max) {
    m.step();
  }
  return m;
}

void main() {
  final spec = ProcessorDsl.parse(
    File('assets/templates/arm32.cpu').readAsStringSync(),
    builtin: true,
  );
  int r(Machine m, String n) => m.register(spec.registerIndexByName(n)!);

  test('valid', () => expect(spec.validate(), isEmpty));

  test('known encodings', () {
    final p = Assembler(spec).assemble('''
add r0, r1, r2
mov r0, #5
cmp r1, #10
ldr r0, [r1, #4]
str r0, [r1]
push {lr}
pop {lr}
bx lr
movw r0, #0x1234
svc #4
addeq r0, r0, #1
adds r0, r1, r2
mul r0, r1, r2
lsl r0, r1, #2
movne r2, r3
''');
    expect(p.errors, isEmpty, reason: p.errors.join('\n'));
    final b = p.segments.first.bytes;
    int w(int i) =>
        b[i * 4] |
        (b[i * 4 + 1] << 8) |
        (b[i * 4 + 2] << 16) |
        (b[i * 4 + 3] << 24);
    expect(w(0), 0xe0810002);
    expect(w(1), 0xe3a00005);
    expect(w(2), 0xe351000a);
    expect(w(3), 0xe5910004);
    expect(w(4), 0xe5810000);
    expect(w(5), 0xe52de004);
    expect(w(6), 0xe49de004);
    expect(w(7), 0xe12fff1e);
    expect(w(8), 0xe3010234);
    expect(w(9), 0xef000004);
    expect(w(10), 0x02800001);
    expect(w(11), 0xe0910002);
    expect(w(12), 0xe0000291);
    expect(w(13), 0xe1a00101);
    expect(w(14), 0x11a02003);
  });

  test('the sample program', () {
    final m = run(spec, spec.sample);
    expect(m.fault, isNull);
    expect(m.status, MachineStatus.halted);
    expect(m.console.toString(), 'result = 110');
  });

  test('disassembly shows condition suffixes', () {
    final p = Assembler(spec)
        .assemble('movlt r0, #1\nbne main\nmain: addeq r1, r2, r3');
    final m = Machine(spec)..loadProgram(p);
    final lines = m.decoder
        .disassemble(m.memory, 0x8000, 0x8000 + 12)
        .map((l) => l.text)
        .toList();
    expect(lines, ['movlt r0, #1', 'bne 0x8008', 'addeq r1, r2, r3']);
  });

  test('flags: carry, overflow, zero, negative', () {
    final m = run(spec, '''
  ldr r0, =0x7fffffff
  adds r1, r0, #1          @ signed overflow: N=1 V=1 C=0 Z=0
  mov r2, #0
  movvs r2, #1             @ taken: V set
  movne r3, #1
  ldr r4, =0xffffffff
  adds r5, r4, #1          @ carry out, result 0: Z=1 C=1
  moveq r6, #1
  movcs r7, #1
  subs r8, r2, #5          @ 1 - 5 = -4: N=1, borrow so C=0
  movmi r9, #1
  movcc r10, #1
  svc #1
''');
    expect(m.fault, isNull);
    expect(r(m, 'r1'), 0x80000000);
    expect(r(m, 'r2'), 1);
    expect(
      r(m, 'r3'),
      1,
    ); // Z was 0 after the first adds? still Z=0 at that point
    expect(r(m, 'r5'), 0);
    expect(r(m, 'r6'), 1);
    expect(r(m, 'r7'), 1);
    expect(r(m, 'r8'), 0xfffffffc);
    expect(r(m, 'r9'), 1);
    expect(r(m, 'r10'), 1);
  });

  test('conditional execution skips instructions without side effects', () {
    final m = run(spec, '''
  mov r0, #3
  cmp r0, #3
  addne r0, r0, #100     @ not executed
  addeq r0, r0, #1       @ executed
  cmp r0, #10
  movgt r1, #1           @ not executed (4 > 10 is false)
  movle r2, #1
  svc #1
''');
    expect(r(m, 'r0'), 4);
    expect(r(m, 'r1'), 0);
    expect(r(m, 'r2'), 1);
  });

  test('memory, shifts, byte access, multiply and stack', () {
    final m = run(spec, '''
  .data
buf: .word 0
  .text
main:
  ldr r0, =buf
  ldr r1, =0x12345678
  str r1, [r0]
  ldrb r2, [r0]
  ldrb r3, [r0, #3]
  mov r4, #7
  mov r5, #6
  mul r6, r4, r5
  lsl r7, r4, #4
  lsr r8, r1, #16
  mov r9, #200
  neg r10, r4
  push {r4, r5, r9}
  mov r4, #0
  mov r5, #0
  pop {r4, r5, r9}
  svc #1
''');
    expect(m.fault, isNull);
    expect(r(m, 'r2'), 0x78);
    expect(r(m, 'r3'), 0x12);
    expect(r(m, 'r6'), 42);
    expect(r(m, 'r7'), 112);
    expect(r(m, 'r8'), 0x1234);
    expect(r(m, 'r10'), 0xfffffff9);
    expect(r(m, 'r4'), 7);
    expect(r(m, 'r5'), 6);
    expect(r(m, 'r9'), 200);
    expect(r(m, 'sp'), 0x2fff0);
  });
}

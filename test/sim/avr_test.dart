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
    File('assets/templates/avr.cpu').readAsStringSync(),
    builtin: true,
  );
  int r(Machine m, String n) => m.register(spec.registerIndexByName(n)!);
  int f(Machine m, String n) => m.flag(n);

  test(
    'valid',
    () => expect(
      spec.validate(),
      isEmpty,
      reason: spec.validate().take(10).join('\n'),
    ),
  );

  test('known encodings', () {
    final p = Assembler(spec).assemble('''
ldi r16, 5
add r1, r2
mov r24, r18
ld r20, X+
out 0x0d, r24
ret
push r16
sts 0x0100, r16
inc r17
sei
nop
''');
    expect(p.errors, isEmpty, reason: p.errors.join('\n'));
    final b = p.segments.first.bytes;
    int w(int i) => b[i * 2] | (b[i * 2 + 1] << 8);
    expect(w(0), 0xE005);
    expect(w(1), 0x0C12);
    expect(w(2), 0x2F82);
    expect(w(3), 0x914D);
    expect(w(4), 0xB98D);
    expect(w(5), 0x9508);
    expect(w(6), 0x930F);
    expect(w(7), 0x9300); // sts, first word
    expect(w(8), 0x0100); // sts, address
    expect(w(9), 0x9513);
    expect(w(10), 0x9478);
    expect(w(11), 0x0000);
  });

  test('ldi only accepts r16..r31', () {
    final p = Assembler(spec).assemble('ldi r5, 1');
    expect(p.errors.single.message, contains('r16..r31'));
  });

  test('the sample program', () {
    final m = run(spec, spec.sample);
    expect(m.fault, isNull, reason: m.fault);
    expect(m.status, MachineStatus.halted);
    expect(m.console.toString(), '67\n');
  });

  test('8-bit arithmetic flags', () {
    final m = run(spec, '''
  ldi r16, 200
  ldi r17, 100
  add r16, r17          ; 300 -> 44, C=1
  in r20, 0x3f          ; SREG
  ldi r18, 127
  inc r18               ; 128: V=1 N=1
  in r21, 0x3f
  ldi r19, 5
  cpi r19, 9            ; 5 - 9 borrows: C=1 N=1 S=1
  in r22, 0x3f
  sleep
''');
    expect(m.fault, isNull, reason: m.fault);
    expect(r(m, 'r16'), 44);
    expect(r(m, 'r20') & 1, 1);
    expect(r(m, 'r18'), 128);
    expect((r(m, 'r21') >> 3) & 1, 1); // V
    expect((r(m, 'r21') >> 2) & 1, 1); // N
    expect(r(m, 'r22') & 1, 1); // C (borrow)
    expect((r(m, 'r22') >> 4) & 1, 1); // S = N xor V = 1 xor 0
    expect(f(m, 'C'), 1);
  });

  test('16-bit add/sub with carry, multiply, shifts and the stack', () {
    final m = run(spec, '''
  ldi r16, 0xff
  ldi r17, 0x00         ; r17:r16 = 0x00ff
  ldi r18, 0x01
  ldi r19, 0x00         ; r19:r18 = 1
  add r16, r18          ; low byte: 0x00 with carry
  adc r17, r19          ; high byte: 0x01
  ldi r20, 12
  ldi r21, 13
  mul r20, r21          ; r1:r0 = 156
  ldi r22, 0x81
  lsr r22               ; 0x40, C=1
  ror r22               ; 0xa0, C=0
  swap r20
  ldi r23, 0xAB
  push r23
  clr r23
  pop r24
  sub r16, r18          ; 0 - 1 = 255, C=1
  sbc r17, r19          ; 1 - 0 - 1 = 0
  sleep
''');
    expect(m.fault, isNull, reason: m.fault);
    expect(r(m, 'r17'), 0);
    expect(r(m, 'r16'), 255);
    expect(r(m, 'r0') | (r(m, 'r1') << 8), 156);
    expect(r(m, 'r22'), 0xa0);
    expect(r(m, 'r20'), 0xC0);
    expect(r(m, 'r24'), 0xAB);
    expect(m.register(spec.registerIndexExact('SP')!), 0x8ff);
  });

  test('calls, pointers and data memory', () {
    final m = run(spec, '''
  .data
v: .byte 0, 0
  .text
main:
  ldi r16, 42
  sts v, r16
  lds r17, v
  ldi r26, lo8(v)
  ldi r27, hi8(v)
  ldi r18, 7
  st X+, r18
  st X, r16
  rcall sub1
  ldi r30, lo8(v)
  ldi r31, hi8(v)
  ld r19, Z+
  ld r20, Z
  sleep
sub1:
  ldi r25, 99
  ret
''');
    expect(m.fault, isNull, reason: m.fault);
    expect(r(m, 'r17'), 42);
    expect(r(m, 'r25'), 99);
    expect(r(m, 'r19'), 7);
    expect(r(m, 'r20'), 42);
  });
}

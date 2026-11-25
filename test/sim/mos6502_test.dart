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
    File('assets/templates/mos6502.cpu').readAsStringSync(),
    builtin: true,
  );
  int reg(Machine m, String n) => m.register(spec.registerIndexExact(n)!);

  test(
    'valid',
    () => expect(
      spec.validate(),
      isEmpty,
      reason: spec.validate().take(8).join('\n'),
    ),
  );

  test('known encodings and addressing modes', () {
    final p = Assembler(spec).assemble('''
main:
  lda #\$10
  lda \$10
  lda \$1234
  lda \$10,x
  lda \$1234,x
  lda \$1234,y
  lda (\$20,x)
  lda (\$20),y
  sta \$0200
  jmp main
  jsr main
  asl a
  inx
  bne main
  rts
''');
    expect(p.errors, isEmpty, reason: p.errors.join('\n'));
    final b = p.segments.first.bytes;
    expect(b, [
      0xA9, 0x10, //
      0xA5, 0x10,
      0xAD, 0x34, 0x12,
      0xB5, 0x10,
      0xBD, 0x34, 0x12,
      0xB9, 0x34, 0x12,
      0xA1, 0x20,
      0xB1, 0x20,
      0x8D, 0x00, 0x02,
      0x4C, 0x00, 0x08,
      0x20, 0x00, 0x08,
      0x0A,
      0xE8,
      0xD0, 0xE0, // back to main: -32
      0x60,
    ]);
  });

  test('forward references pick the wide form', () {
    final p = Assembler(spec).assemble('  lda later\n  nop\nlater: .byte 1');
    expect(p.errors, isEmpty, reason: p.errors.join('\n'));
    expect(p.segments.first.bytes.take(3).toList(), [
      0xAD,
      0x04,
      0x08,
    ]); // absolute, address $0804
  });

  test('the sample program', () {
    final m = run(spec, spec.sample);
    expect(m.fault, isNull);
    expect(m.status, MachineStatus.halted);
    expect(m.console.toString(), '67\n134');
  });

  test('flags: ADC carry/overflow, SBC borrow, compare', () {
    final m = run(spec, '''
  clc
  lda #\$7f
  adc #\$01        ; 127 + 1 = 128: V=1 N=1 C=0
  php
  pla
  tax              ; X = status
  sec
  lda #\$ff
  adc #\$01        ; 255 + 1 + 1: A=1, C=1
  sta \$10
  sec
  lda #\$05
  sbc #\$06        ; 5 - 6 = -1: A=ff, C=0
  sta \$11
  lda #\$40
  cmp #\$40        ; equal: Z=1 C=1
  php
  pla
  tay
  hlt
''');
    expect(m.fault, isNull);
    expect(reg(m, 'X') & 0xC1, 0xC0); // N and V set, C clear
    expect(m.memory.peek(0x10, 2), [1, 0xff]);
    expect(reg(m, 'Y') & 0x83, 0x03); // Z and C set, N clear
  });

  test('stack, indirect addressing, shifts and branches', () {
    final m = run(spec, '''
  .equ ptr, \$20
  .equ buf, \$40
  lda #<buf     ; low byte of the buffer address
  sta ptr
  lda #>buf     ; high byte
  sta ptr+1
  ldy #3
  lda #\$99
  sta (ptr),y   ; buf[3] = \$99
  lda (ptr),y
  tax
  lda #\$81
  asl a         ; C=1, A=\$02
  rol a         ; A=\$05, C=0
  ldy #\$0f
  tya
  pha
  lda #0
  pla
  hlt
''');
    expect(m.fault, isNull, reason: m.fault);
    expect(reg(m, 'X'), 0x99);
    expect(reg(m, 'A'), 0x0f);
    expect(m.memory.peek(0x43, 1), [0x99]);
    expect(reg(m, 'SP'), 0xff);
  });
}

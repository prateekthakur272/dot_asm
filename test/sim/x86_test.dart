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
    File('assets/templates/x86.cpu').readAsStringSync(),
    builtin: true,
  );
  int reg(Machine m, String n) => m.register(spec.registerIndexByName(n)!);

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
mov eax, ebx
mov ecx, 0x12345678
mov eax, [ebx+4]
mov [ebp-8], edx
mov eax, [esp+8]
add eax, 5
add eax, 1000
sub esp, 16
cmp ecx, ebx
inc ecx
dec edx
push eax
pop ebx
ret
nop
int 0x80
hlt
imul eax, ecx
shl eax, 2
''');
    expect(p.errors, isEmpty, reason: p.errors.join('\n'));
    expect(p.segments.first.bytes, [
      0x89, 0xD8, // mov eax, ebx  (89 /r, rm=eax reg=ebx)
      0xB9, 0x78, 0x56, 0x34, 0x12, // mov ecx, imm32
      0x8B, 0x43, 0x04, // mov eax, [ebx+4]
      0x89, 0x55, 0xF8, // mov [ebp-8], edx
      0x8B, 0x44, 0x24, 0x08, // mov eax, [esp+8] (SIB 0x24)
      0x83, 0xC0, 0x05, // add eax, 5
      0x81, 0xC0, 0xE8, 0x03, 0x00, 0x00, // add eax, 1000
      0x83, 0xEC, 0x10, // sub esp, 16
      0x39, 0xD9, // cmp ecx, ebx
      0x41, // inc ecx
      0x4A, // dec edx
      0x50, // push eax
      0x5B, // pop ebx
      0xC3, // ret
      0x90, // nop
      0xCD, 0x80, // int 0x80
      0xF4, // hlt
      0x0F, 0xAF, 0xC1, // imul eax, ecx
      0xC1, 0xE0, 0x02, // shl eax, 2
    ]);
  });

  test('disassembly round trip', () {
    final p = Assembler(spec)
        .assemble('mov eax, [ebx-4]\nadd ecx, edx\njne done\ndone: ret');
    expect(p.errors, isEmpty, reason: p.errors.join('\n'));
    final m = Machine(spec)..loadProgram(p);
    final lines = m.decoder
        .disassemble(
          m.memory,
          0x400000,
          0x400000 + p.segments.first.bytes.length,
        )
        .map((l) => l.text)
        .toList();
    expect(lines.length, 4);
    expect(lines[0], 'mov eax, [ebx-4]');
    expect(lines[1], 'add ecx, edx');
    expect(lines[2], startsWith('jne 0x'));
    expect(lines[3], 'ret');
  });

  test('the sample program', () {
    final m = run(spec, spec.sample);
    expect(m.fault, isNull, reason: m.fault);
    expect(m.status, MachineStatus.halted);
    expect(m.console.toString(), 'sum = 110');
    expect(m.memory.peek(0x500007, 4), [
      55,
      0,
      0,
      0,
    ]); // total follows "sum = \0"
  });

  test('flags and signed/unsigned jumps', () {
    final m = run(spec, '''
  mov eax, 0x7fffffff
  add eax, 1            ; OF=1 SF=1 CF=0
  jo ovf
  mov ebx, 111
ovf:
  mov ecx, 0xffffffff
  add ecx, 1            ; CF=1 ZF=1
  jc carry
  mov ebx, 222
carry:
  mov edx, 5
  cmp edx, 9            ; 5 - 9: borrow -> CF=1, SF=1
  jb below              ; unsigned below
  mov esi, 1
below:
  jl less               ; signed less
  mov edi, 1
less:
  mov ebx, 7
  hlt
''');
    expect(m.fault, isNull, reason: m.fault);
    expect(reg(m, 'ebx'), 7);
    expect(reg(m, 'esi'), 0);
    expect(reg(m, 'edi'), 0);
    expect(reg(m, 'eax'), 0x80000000);
  });

  test('memory, stack, lea, shifts and multiply', () {
    final m = run(spec, '''
  .data
buf: .long 0, 0, 0
  .text
main:
  mov ebx, buf
  mov eax, 7
  mov [ebx], eax
  mov [ebx+4], eax
  add eax, [ebx+4]
  mov [ebx+8], eax
  mov ecx, [ebx+8]
  lea edx, [ebx+8]
  mov esi, 6
  imul esi, ecx         ; 14 * 6 = 84
  shl esi, 1            ; 168
  sar esi, 2            ; 42
  mov edi, esp
  push 5
  push 6
  pop eax
  pop ebx
  hlt
''');
    expect(m.fault, isNull, reason: m.fault);
    expect(reg(m, 'ecx'), 14);
    expect(reg(m, 'edx'), 0x500008);
    expect(reg(m, 'esi'), 42);
    expect(reg(m, 'eax'), 6);
    expect(reg(m, 'ebx'), 5);
    expect(reg(m, 'esp'), 0x70fff0);
  });

  test('a displacement out of range gives a clear message', () {
    final p = Assembler(spec).assemble('mov eax, [ebx+1000]');
    expect(p.errors, isNotEmpty);
  });
}

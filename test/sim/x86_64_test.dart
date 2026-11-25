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
    File('assets/templates/x86_64.cpu').readAsStringSync(),
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

  test('known encodings (REX.W)', () {
    final p = Assembler(spec).assemble('''
mov rax, rbx
mov rax, [rbx+8]
mov [rbx-8], rdx
mov rax, [rsp+8]
mov rcx, 0x12345678
add rax, 5
inc rax
imul rax, rcx
push rax
pop rbx
syscall
mov rax, [0x600000]
ret
''');
    expect(p.errors, isEmpty, reason: p.errors.join('\n'));
    expect(p.segments.first.bytes, [
      0x48, 0x89, 0xD8, // mov rax, rbx
      0x48, 0x8B, 0x43, 0x08, // mov rax, [rbx+8]
      0x48, 0x89, 0x53, 0xF8, // mov [rbx-8], rdx
      0x48, 0x8B, 0x44, 0x24, 0x08, // mov rax, [rsp+8]
      0x48,
      0xC7,
      0xC1,
      0x78,
      0x56,
      0x34,
      0x12, // mov rcx, imm32 (sign-extended)
      0x48, 0x83, 0xC0, 0x05, // add rax, 5
      0x48, 0xFF, 0xC0, // inc rax
      0x48, 0x0F, 0xAF, 0xC1, // imul rax, rcx
      0x50, // push rax
      0x5B, // pop rbx
      0x0F, 0x05, // syscall
      0x48, 0x8B, 0x04, 0x25, 0x00, 0x00, 0x60, 0x00, // mov rax, [0x600000]
      0xC3, // ret
    ]);
  });

  test('the sample program', () {
    final m = run(spec, spec.sample);
    expect(m.fault, isNull, reason: m.fault);
    expect(m.status, MachineStatus.halted);
    expect(m.console.toString(), 'sum = 110');
  });

  test('64-bit arithmetic, carry and overflow', () {
    final m = run(spec, '''
  mov rax, 0x7fffffff
  shl rax, 32           ; 0x7fffffff00000000
  mov rbx, 0xffffffff
  add rax, rbx          ; 0x7fffffffffffffff
  mov rcx, rax
  add rcx, 1            ; overflow: OF=1 SF=1 CF=0
  jo ovf
  mov rdx, 111
ovf:
  mov rsi, 0
  sub rsi, 1            ; 0 - 1: CF=1 (borrow), SF=1
  jb carry
  mov rdx, 222
carry:
  mov rdi, rcx
  sar rdi, 63           ; arithmetic: all ones
  hlt
''');
    expect(m.fault, isNull, reason: m.fault);
    expect(reg(m, 'rcx'), 0x8000000000000000);
    expect(reg(m, 'rdx'), 0);
    expect(reg(m, 'rsi'), 0xffffffffffffffff);
    expect(reg(m, 'rdi'), 0xffffffffffffffff);
  });

  test('memory, stack and multiply with 64-bit values', () {
    final m = run(spec, '''
  .data
buf: .quad 0, 0
  .text
main:
  mov rbx, buf
  mov rax, 3000000000
  mov [rbx], rax
  mov [rbx+8], rax
  add rax, [rbx+8]
  mov rcx, [rbx]
  mov rsi, 100000
  imul rsi, rsi         ; 10_000_000_000
  push rcx
  pop rdx
  lea rdi, [rbx+8]
  hlt
''');
    expect(m.fault, isNull, reason: m.fault);
    expect(reg(m, 'rax'), 6000000000);
    expect(reg(m, 'rcx'), 3000000000);
    expect(reg(m, 'rdx'), 3000000000);
    expect(reg(m, 'rsi'), 10000000000);
    expect(reg(m, 'rdi'), 0x600008);
    expect(reg(m, 'rsp'), 0x7ffeff00);
  });
}

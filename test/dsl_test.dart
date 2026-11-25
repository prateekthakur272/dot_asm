import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'support/templates.dart';

import 'package:dot_asm/core/dsl/dsl.dart';
import 'package:dot_asm/core/sim/asm/assembler.dart';
import 'package:dot_asm/core/sim/dsl/processor_dsl.dart';
import 'package:dot_asm/core/sim/machine/machine.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';

/// Whitespace-insensitive view of a spec for comparing round trips.
String canon(ProcessorSpec s) {
  Object? norm(Object? v, String key) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()
        ..sort(); // key order carries no meaning
      return {for (final k in keys) k: norm(v[k], k)};
    }
    if (v is List) return [for (final x in v) norm(x, key)];
    if (v is String &&
        (key == 'exec' ||
            key == 'sample' ||
            key == 'description' ||
            key == 'test' ||
            key == 'when')) {
      return v.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return v;
  }

  return jsonEncode(norm(s.toJson(), ''));
}

String run(ProcessorSpec s) {
  final p = Assembler(s).assemble(s.sample);
  expect(p.errors, isEmpty, reason: p.errors.join('\n'));
  final m = Machine(s)..loadProgram(p);
  var n = 0;
  while (m.canStep && n++ < 200000) {
    m.step();
  }
  expect(m.fault, isNull);
  return m.console.toString();
}

void main() {
  group('generic DSL', () {
    test('statements, blocks, strings, comments', () {
      final nodes = DslParser('''
# comment
a 1 "two words" 0x10   // trailing
b {
  c x
  d "q\\"uote" {
    e
  }
}
text """
  line one
    indented
"""
''').parse();
      expect(nodes.map((n) => n.keyword), ['a', 'b', 'text']);
      expect(nodes[0].argTexts, ['1', 'two words', '0x10']);
      expect(nodes[1].children.map((c) => c.keyword), ['c', 'd']);
      expect(nodes[1].children[1].arg(0), 'q"uote');
      expect(nodes[1].children[1].children.single.keyword, 'e');
      expect(nodes[2].arg(0), 'line one\n  indented');
    });

    test('raw brace blocks keep nested braces and strings', () {
      final nodes = DslParser(
        'x {\n  exec {\n    if (a) { b = 1; }\n    c = "}";\n  }\n  after 1\n}\n',
        rawBlocks: {'exec': RawMode.braces},
      ).parse();
      final x = nodes.single;
      expect(x.children.map((c) => c.keyword), ['exec', 'after']);
      expect(x.children.first.raw, 'if (a) { b = 1; }\nc = "}";');
    });

    test('errors say where', () {
      expect(
        () => DslParser('a {\n b\n').parse(),
        throwsA(isA<DslError>().having((e) => e.line, 'line', 1)),
      );
      expect(() => DslParser('}\n').parse(), throwsA(isA<DslError>()));
      expect(
        () => DslParser('a "open\n').parse(),
        throwsA(
          isA<DslError>().having((e) => e.message, 'm', contains('not closed')),
        ),
      );
      expect(
        () => DslParser('a """never\nclosed\n').parse(),
        throwsA(isA<DslError>()),
      );
    });
  });

  group('processor DSL', () {
    final specs = [
      for (final f in templateFiles())
        ProcessorDsl.parse(f.readAsStringSync(), builtin: true),
    ];

    for (final s in specs) {
      test('${s.id}: spec → DSL → spec is lossless and still runs', () {
        final text = ProcessorDsl.write(s);
        expect(text, startsWith('# dot ASM processor definition'));
        final back = ProcessorDsl.parse(text);
        expect(
          back.validate(),
          isEmpty,
          reason: back.validate().take(4).join('\n'),
        );
        expect(canon(back), canon(s));
        expect(run(back), run(s));
        // Writing again gives the same text (stable formatting).
        expect(ProcessorDsl.write(back), text);
      });
    }

    test('semantics are written one statement per line and indented', () {
      final text = ProcessorDsl.write(specs.firstWhere((s) => s.id == 'rv32i'));
      expect(
        text,
        contains(
          'exec {\n      if (rs1 == rs2) {\n        pc = pc + target;\n      }\n    }',
        ),
      );
      expect(text, contains('} else if (a7 == 1) {'));
    });

    test('a hand-written processor', () {
      final spec = ProcessorDsl.parse('''
# A tiny accumulator machine
processor acc8 "Acc-8" {
  arch custom
  vendor "me"
  year 2026
  tags Educational 8-bit
  word 16 little
  fetch 16
  register ACC width 8 "accumulator"
  flags Z
  memory {
    rom at 0x0000 size 0x100 perms rx role text
    ram at 0x1000 size 0x100 perms rw role data
  }
  reset 0x0

  instruction ldi "imm" {
    size 16
    match 0xFF00 0x0100
    operand imm imm [7:0]
    exec {
      ACC = imm;
      Z = ACC == 0;
    }
  }
  instruction outp "" {
    size 16
    match 0xFFFF 0x0200
    exec {
      out("int", ACC);
    }
  }
  instruction stop "" {
    size 16
    match 0xFFFF 0x0300
    exec {
      halt();
    }
  }
  sample """
    ldi 42
    outp
    stop
  """
}
''');
      expect(spec.validate(), isEmpty, reason: spec.validate().join('\n'));
      expect(spec.tags, ['Educational', '8-bit']);
      expect(run(spec), '42');
    });

    test('JSON files from older versions still load', () {
      final s = specs.first;
      expect(canon(ProcessorDsl.parse(ProcessorDsl.toJsonText(s))), canon(s));
    });

    test('mistakes are reported with the line and a hint', () {
      DslError err(String src) {
        try {
          ProcessorDsl.parse(src);
        } on DslError catch (e) {
          return e;
        }
        fail('expected an error');
      }

      expect(
        err('processor a "A" {\n  regsters r count 4\n}').message,
        contains("did you mean 'registers'"),
      );
      expect(err('processor a "A" {\n  regsters r count 4\n}').line, 2);
      expect(
        err('processor a "A" {\n  word big\n}').message,
        contains('number'),
      );
      expect(
        err('processor a "A" {\n  memory {\n    r at 0x0\n  }\n}').message,
        contains("needs 'size'"),
      );
      expect(err('nothing here').message, contains('processor'));
      expect(
        err('processor a "A" {\n  instruction x "" {\n    bogus 1\n  }\n}')
            .message,
        contains("Unknown statement 'bogus'"),
      );
      expect(
        err('processor a "A" {\n  pseudo "p" {\n  }\n}').message,
        contains('expand'),
      );
    });
  });
}

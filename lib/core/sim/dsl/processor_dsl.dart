import 'dart:convert';

import 'package:dot_asm/core/dsl/dsl.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';

/// The processor definition language (`*.cpu`), the text form of a [ProcessorSpec].
///
/// ```
/// processor tiny16 "Tiny-16" {
///   arch custom
///   word 16 little
///   fetch 16
///   registers r count 8 width 16 {
///     zero 0
///     alias sp=7
///   }
///   flags N Z C
///   memory {
///     text at 0x0000 size 0x2000 perms rx role text
///   }
///   instruction add "rd, rs1, rs2" {
///     size 16
///     match 0xF007 0x0000
///     operand rd reg [11:9]
///     exec {
///       rd = rs1 + rs2;
///     }
///   }
/// }
/// ```
///
/// [toJsonMap] and [fromJsonMap] convert to and from the JSON model that [ProcessorSpec] reads, so the builder, the
/// importer and the engine all work on one structure.
class ProcessorDsl {
  const ProcessorDsl._();

  static const _raw = {
    'exec': RawMode.braces,
    'expand': RawMode.lines,
    'otherwise': RawMode.lines,
    'when': RawMode.lines,
  };

  /// True when [text] looks like the old JSON format.
  static bool looksLikeJson(String text) => text.trimLeft().startsWith('{');

  /// Parses `.cpu` text (or JSON, for files from older versions) into a [ProcessorSpec].
  static ProcessorSpec parse(String text, {bool builtin = false}) {
    if (looksLikeJson(text)) return ProcessorSpec.parse(text, builtin: builtin);
    return ProcessorSpec.fromJson(toJsonMap(text), builtin: builtin);
  }

  // -------------------------------------------------------------------------------------------------------------
  // DSL → JSON model

  static Map<String, dynamic> toJsonMap(String text) {
    final nodes = DslParser(text, rawBlocks: _raw).parse();
    final procs = nodes.where((n) => n.keyword == 'processor').toList();
    if (procs.isEmpty) {
      throw DslError(1, "Expected a 'processor <id> \"<name>\" { ... }' block");
    }
    if (procs.length > 1) {
      throw DslError(procs[1].line, 'A file defines one processor');
    }
    for (final n in nodes) {
      if (n.keyword != 'processor') {
        throw DslError(
          n.line,
          "Unexpected '${n.keyword}' outside the processor block",
        );
      }
    }
    return _processor(procs.single);
  }

  static int _int(DslNode n, int i, String what) {
    final v = n.arg(i);
    final x = v == null
        ? null
        : (v.startsWith('0x')
              ? int.tryParse(v.substring(2), radix: 16)
              : int.tryParse(v));
    if (x == null) {
      throw DslError(
        n.line,
        "'${n.keyword}' needs a number for $what${v == null ? '' : " (found '$v')"}",
      );
    }
    return x;
  }

  static String _need(DslNode n, int i, String what) {
    final v = n.arg(i);
    if (v == null) throw DslError(n.line, "'${n.keyword}' needs $what");
    return v;
  }

  /// Reads `key value key value ...` pairs from [args] starting at [from].
  static Map<String, String> _pairs(DslNode n, int from, Set<String> keys) {
    final out = <String, String>{};
    var i = from;
    while (i < n.args.length) {
      final k = n.args[i].text;
      if (!keys.contains(k)) {
        throw DslError(
          n.line,
          "Unexpected '$k' in '${n.keyword}' (expected one of: ${keys.join(', ')})",
        );
      }
      if (i + 1 >= n.args.length) throw DslError(n.line, "'$k' needs a value");
      out[k] = n.args[i + 1].text;
      i += 2;
    }
    return out;
  }

  static Map<String, dynamic> _kvList(DslNode n, int from) {
    final out = <String, dynamic>{};
    for (var i = from; i < n.args.length; i++) {
      final t = n.args[i].text.replaceAll(RegExp(r',$'), '');
      if (t.isEmpty) continue;
      final kv = t.split('=');
      if (kv.length != 2 || kv[0].isEmpty || kv[1].isEmpty) {
        throw DslError(
          n.line,
          "Expected name=value in '${n.keyword}' but found '$t'",
        );
      }
      out[kv[0]] = kv[1];
    }
    return out;
  }

  static Map<String, dynamic> _processor(DslNode p) {
    final j = <String, dynamic>{
      'id': _need(p, 0, 'an id'),
      'name': p.arg(1) ?? p.arg(0),
    };
    if (!p.hasBlock) {
      throw DslError(
        p.line,
        "The processor needs a block: processor ${p.arg(0)} \"name\" { ... }",
      );
    }
    for (final n in p.children) {
      switch (n.keyword) {
        case 'arch':
          j['arch'] = _need(n, 0, 'a family name');
        case 'vendor':
          j['vendor'] = _need(n, 0, 'a name');
        case 'year':
          j['year'] = _int(n, 0, 'the year');
        case 'era':
          j['era'] = _need(n, 0, 'legacy or modern');
        case 'tags':
          j['tags'] = n.argTexts;
        case 'describe':
          j['description'] = _need(n, 0, 'a text');
        case 'word':
          j['wordBits'] = _int(n, 0, 'the word size in bits');
          if (n.arg(1) != null) {
            final e = n.arg(1)!;
            if (e != 'little' && e != 'big') {
              throw DslError(n.line, "Byte order must be 'little' or 'big'");
            }
            j['endian'] = e;
          }
        case 'fetch':
          j['instrBits'] = _int(n, 0, 'the default instruction size in bits');
        case 'aligned':
          j['alignedAccess'] = true;
        case 'registers':
          j['registerFile'] = _registers(n);
        case 'register':
          (j['registers'] ??= <dynamic>[]).add(_register(n));
        case 'flags':
          j['flags'] = n.argTexts;
        case 'memory':
          j['memory'] = [for (final r in n.children) _region(r)];
        case 'init':
          j['init'] = _kvList(n, 0);
        case 'reset':
          j['resetPc'] = _need(n, 0, 'an address');
        case 'comments':
          j['comments'] = n.argTexts;
        case 'pipeline':
          j['pipeline'] = n.argTexts;
        case 'hexprefix':
          j['hexPrefix'] = _need(n, 0, 'a prefix');
        case 'wordbytes':
          j['wordBytes'] = _int(n, 0, 'a size in bytes');
        case 'rewrite':
          (j['operandRewrites'] ??= <dynamic>[]).add([
            _need(n, 0, 'a pattern'),
            _need(n, 1, 'a replacement'),
          ]);
        case 'conditions':
          j['conditions'] = _conditions(n);
        case 'instruction':
          (j['instructions'] ??= <dynamic>[]).add(_instruction(n));
        case 'pseudo':
          (j['pseudo'] ??= <dynamic>[]).add(_pseudo(n));
        case 'sample':
          j['sample'] = _need(n, 0, 'a """text""" block');
        default:
          throw DslError(
            n.line,
            "Unknown statement '${n.keyword}'${_hint(n.keyword)}",
          );
      }
    }
    j['instructions'] ??= <dynamic>[];
    return j;
  }

  static const _known = [
    'arch',
    'vendor',
    'year',
    'era',
    'tags',
    'describe',
    'word',
    'fetch',
    'aligned',
    'registers',
    'register',
    'flags',
    'memory',
    'init',
    'reset',
    'comments',
    'pipeline',
    'hexprefix',
    'wordbytes',
    'rewrite',
    'conditions',
    'instruction', 'pseudo', 'sample', //
  ];

  static String _hint(String kw) {
    String? best;
    var bestD = 3;
    for (final k in _known) {
      final d = _distance(kw, k);
      if (d < bestD) {
        bestD = d;
        best = k;
      }
    }
    return best == null ? '' : " (did you mean '$best'?)";
  }

  static int _distance(String a, String b) {
    final dp = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));
    for (var i = 0; i <= a.length; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        ].reduce((x, y) => x < y ? x : y);
      }
    }
    return dp[a.length][b.length];
  }

  static Map<String, dynamic> _registers(DslNode n) {
    final prefix = _need(n, 0, 'a name prefix (for example r or x)');
    final kv = _pairs(n, 1, {'count', 'width'});
    final out = <String, dynamic>{'prefix': prefix};
    if (kv['count'] == null) {
      throw DslError(n.line, "'registers' needs 'count N'");
    }
    out['count'] = int.tryParse(kv['count']!) ?? kv['count'];
    if (kv['width'] != null) {
      out['width'] = int.tryParse(kv['width']!) ?? kv['width'];
    }
    for (final c in n.children) {
      switch (c.keyword) {
        case 'zero':
          out['zero'] = _int(c, 0, 'the register index');
        case 'alias':
          final m = _kvList(c, 0);
          final aliases =
              (out['aliases'] ??= <String, dynamic>{}) as Map<String, dynamic>;
          m.forEach((k, v) => aliases[k] = int.tryParse('$v') ?? v);
        default:
          throw DslError(
            c.line,
            "Unknown statement '${c.keyword}' in 'registers' (use zero or alias)",
          );
      }
    }
    return out;
  }

  static Map<String, dynamic> _register(DslNode n) {
    final out = <String, dynamic>{'name': _need(n, 0, 'a name')};
    var i = 1;
    while (i < n.args.length) {
      if (n.args[i].text == 'width' && i + 1 < n.args.length) {
        out['width'] = int.tryParse(n.args[i + 1].text) ?? n.args[i + 1].text;
        i += 2;
      } else {
        out['description'] = n.args[i].text;
        i++;
      }
    }
    return out;
  }

  static Map<String, dynamic> _region(DslNode r) {
    final kv = _pairs(r, 0, {'at', 'size', 'perms', 'role'});
    for (final need in ['at', 'size']) {
      if (kv[need] == null) {
        throw DslError(r.line, "Memory region '${r.keyword}' needs '$need'");
      }
    }
    return {
      'name': r.keyword,
      'base': kv['at'],
      'size': kv['size'],
      'perms': kv['perms'] ?? 'rwx',
      if (kv['role'] != null) 'role': kv['role'],
    };
  }

  static Map<String, dynamic> _conditions(DslNode n) {
    final kv = _pairs(n, 0, {'field', 'default'});
    if (kv['field'] == null) {
      throw DslError(n.line, "'conditions' needs 'field [hi:lo]'");
    }
    final codes = <Map<String, dynamic>>[];
    for (final c in n.children) {
      if (c.args.length < 3 || c.args[1].text != 'when') {
        throw DslError(
          c.line,
          "Write a condition as: <suffix> <value> when <expression>   (for example: eq 0 when Z)",
        );
      }
      codes.add({
        'suffix': c.keyword,
        'value': int.tryParse(c.args[0].text) ?? c.args[0].text,
        'test': c.args.skip(2).map((a) => a.text).join(' '),
      });
    }
    return {
      'field': kv['field'],
      'default': int.tryParse(kv['default'] ?? '0') ?? 0,
      'codes': codes,
    };
  }

  static Map<String, dynamic> _instruction(DslNode n) {
    final mn = _need(n, 0, 'a mnemonic');
    final j = <String, dynamic>{'mnemonic': mn, 'syntax': n.arg(1) ?? ''};
    final operands = <String, dynamic>{};
    final fields = <String, dynamic>{};
    if (!n.hasBlock) {
      throw DslError(n.line, "The instruction '$mn' needs a block { ... }");
    }
    for (final c in n.children) {
      switch (c.keyword) {
        case 'size':
          j['bits'] = _int(c, 0, 'the size in bits');
        case 'match':
          j['mask'] = _need(c, 0, 'a mask');
          j['value'] = _need(c, 1, 'a value');
        case 'operand':
          final name = _need(c, 0, 'a name');
          operands[name] = _need(c, 1, 'a kind (reg, imm or pcrel)');
          fields[name] = _need(
            c,
            2,
            'a bit field such as [11:7]',
          ).replaceAll(RegExp(r'\s+'), '');
        case 'cycles':
          j['cycles'] = _int(c, 0, 'a cycle count');
        case 'base':
          j['pcrelBase'] = _int(c, 0, 'a byte count');
        case 'conditional':
          j['cond'] = true;
        case 'describe':
          j['description'] = _need(c, 0, 'a text');
        case 'exec':
          j['exec'] = (c.raw ?? '')
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .join(' ');
        default:
          throw DslError(
            c.line,
            "Unknown statement '${c.keyword}' in instruction '$mn' (size, match, operand, cycles, base, conditional, describe, exec)",
          );
      }
    }
    j['operands'] = operands;
    j['fields'] = fields;
    j['exec'] ??= '';
    return j;
  }

  static Map<String, dynamic> _pseudo(DslNode n) {
    final syntax = _need(n, 0, 'a syntax such as "li rd, imm"');
    final variants = <Map<String, dynamic>>[];
    for (final c in n.children) {
      List<String> lines() => (c.raw ?? '')
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      switch (c.keyword) {
        case 'when':
          variants.add({'when': _need(c, 0, 'a condition'), 'expand': lines()});
        case 'otherwise' || 'expand':
          variants.add({'expand': lines()});
        default:
          throw DslError(
            c.line,
            "Unknown statement '${c.keyword}' in pseudo '$syntax' (use when, otherwise or expand)",
          );
      }
    }
    if (variants.isEmpty) {
      throw DslError(
        n.line,
        "The pseudo-instruction '$syntax' needs an 'expand { ... }' block",
      );
    }
    return {'syntax': syntax, 'variants': variants};
  }

  // -------------------------------------------------------------------------------------------------------------
  // JSON model → DSL

  static String write(ProcessorSpec spec) => fromJsonMap(spec.toJson());

  static String fromJsonMap(Map<String, dynamic> j) {
    final b = StringBuffer();
    String t(Object? v) => v == null ? '' : '$v';
    List<Map<String, dynamic>> list(Object? v) =>
        v is List ? v.whereType<Map<String, dynamic>>().toList() : [];

    b.writeln(
      '# dot ASM processor definition. Edit here or in the processor builder.',
    );
    b.writeln('processor ${dslWord(t(j['id']))} ${dslQuote(t(j['name']))} {');
    void kv(String key, String value) => b.writeln('  $key $value');
    if (j['arch'] != null) kv('arch', dslWord(t(j['arch'])));
    if (t(j['vendor']).isNotEmpty) kv('vendor', dslQuote(t(j['vendor'])));
    if (j['year'] != null) kv('year', t(j['year']));
    if (t(j['era']).isNotEmpty) kv('era', dslWord(t(j['era'])));
    if (j['tags'] is List && (j['tags'] as List).isNotEmpty) {
      kv('tags', (j['tags'] as List).map((e) => dslWord('$e')).join(' '));
    }
    if (t(j['description']).isNotEmpty) {
      kv('describe', dslQuote(t(j['description']), indent: '  '));
    }
    b.writeln();
    kv(
      'word',
      '${t(j['wordBits'])} ${j['endian'] == 'big' ? 'big' : 'little'}',
    );
    if (j['instrBits'] != null) kv('fetch', t(j['instrBits']));
    if (j['alignedAccess'] == true) b.writeln('  aligned');
    if (j['hexPrefix'] != null) kv('hexprefix', dslQuote(t(j['hexPrefix'])));
    if (j['wordBytes'] != null) kv('wordbytes', t(j['wordBytes']));
    if (j['comments'] is List) {
      kv(
        'comments',
        (j['comments'] as List).map((e) => dslQuote('$e')).join(' '),
      );
    }
    if (j['operandRewrites'] is List) {
      for (final r in j['operandRewrites'] as List) {
        if (r is List && r.length == 2) {
          kv('rewrite', '${dslQuote('${r[0]}')} ${dslQuote('${r[1]}')}');
        }
      }
    }
    b.writeln();

    final rf = j['registerFile'];
    if (rf is Map) {
      final head =
          'registers ${dslWord(t(rf['prefix']))} count ${t(rf['count'])} width ${t(rf['width'])}';
      final aliases = rf['aliases'];
      if (rf['zero'] != null || (aliases is Map && aliases.isNotEmpty)) {
        b.writeln('  $head {');
        if (rf['zero'] != null) b.writeln('    zero ${t(rf['zero'])}');
        if (aliases is Map && aliases.isNotEmpty) {
          // Wrap long alias lists.
          final pairs = [
            for (final e in aliases.entries) '${e.key}=${e.value}',
          ];
          for (var i = 0; i < pairs.length; i += 8) {
            b.writeln(
              '    alias ${pairs.sublist(i, i + 8 > pairs.length ? pairs.length : i + 8).join(' ')}',
            );
          }
        }
        b.writeln('  }');
      } else {
        b.writeln('  $head');
      }
    }
    for (final r in list(j['registers'])) {
      b.writeln(
        '  register ${dslWord(t(r['name']))} width ${t(r['width'])}${t(r['description']).isEmpty ? '' : ' ${dslQuote(t(r['description']))}'}',
      );
    }
    if (j['flags'] is List && (j['flags'] as List).isNotEmpty) {
      kv('flags', (j['flags'] as List).map((e) => dslWord('$e')).join(' '));
    }
    if (j['init'] is Map && (j['init'] as Map).isNotEmpty) {
      kv(
        'init',
        [for (final e in (j['init'] as Map).entries) '${e.key}=${e.value}']
            .join(' '),
      );
    }
    if (j['resetPc'] != null) kv('reset', t(j['resetPc']));
    if (j['pipeline'] is List && (j['pipeline'] as List).isNotEmpty) {
      kv(
        'pipeline',
        (j['pipeline'] as List).map((e) => dslWord('$e')).join(' '),
      );
    }
    b.writeln();

    final mem = list(j['memory']);
    b.writeln('  memory {');
    final nameW = mem.fold<int>(
      0,
      (a, r) =>
          dslWord(t(r['name'])).length > a ? dslWord(t(r['name'])).length : a,
    );
    for (final r in mem) {
      b.writeln(
        '    ${dslWord(t(r['name'])).padRight(nameW)} at ${t(r['base'])} size ${t(r['size'])} perms ${t(r['perms'])}${t(r['role']).isEmpty ? '' : ' role ${t(r['role'])}'}',
      );
    }
    b.writeln('  }');

    final cond = j['conditions'];
    if (cond is Map) {
      b.writeln();
      b.writeln(
        '  conditions field ${t(cond['field'])} default ${t(cond['default'])} {',
      );
      for (final c in list(cond['codes'])) {
        b.writeln(
          '    ${t(c['suffix'])} ${t(c['value'])} when ${t(c['test'])}',
        );
      }
      b.writeln('  }');
    }

    for (final i in list(j['instructions'])) {
      b.writeln();
      b.writeln(
        '  instruction ${dslWord(t(i['mnemonic']))} ${dslQuote(t(i['syntax']))} {',
      );
      b.writeln('    size ${t(i['bits'])}');
      b.writeln('    match ${t(i['mask'])} ${t(i['value'])}');
      final ops = i['operands'] is Map ? i['operands'] as Map : const {};
      final fields = i['fields'] is Map ? i['fields'] as Map : const {};
      for (final e in ops.entries) {
        b.writeln(
          '    operand ${e.key} ${e.value} ${t(fields[e.key]).replaceAll(RegExp(r'\s+'), '')}',
        );
      }
      if (i['cycles'] != null) b.writeln('    cycles ${t(i['cycles'])}');
      if (i['pcrelBase'] != null) b.writeln('    base ${t(i['pcrelBase'])}');
      if (i['cond'] == true) b.writeln('    conditional');
      if (t(i['description']).isNotEmpty) {
        b.writeln(
          '    describe ${dslQuote(t(i['description']), indent: '    ')}',
        );
      }
      final ex = _formatExec(t(i['exec']));
      if (ex.isEmpty) {
        b.writeln('    exec {');
        b.writeln('    }');
      } else {
        b.writeln('    exec {');
        for (final l in ex) {
          b.writeln('      $l');
        }
        b.writeln('    }');
      }
      b.writeln('  }');
    }

    for (final p in list(j['pseudo'])) {
      b.writeln();
      b.writeln('  pseudo ${dslQuote(t(p['syntax']))} {');
      final vs = list(p['variants']);
      for (final v in vs) {
        final w = t(v['when']);
        final head = w.isNotEmpty
            ? 'when ${dslQuote(w)} {'
            : (vs.length > 1 ? 'otherwise {' : 'expand {');
        b.writeln('    $head');
        for (final l
            in (v['expand'] is List ? v['expand'] as List : const [])) {
          b.writeln('      $l');
        }
        b.writeln('    }');
      }
      b.writeln('  }');
    }

    if (t(j['sample']).isNotEmpty) {
      b.writeln();
      b.writeln(
        '  sample ${dslQuote(t(j['sample']).trimRight(), indent: '  ')}',
      );
    }
    b.writeln('}');
    return b.toString();
  }

  /// Splits semantics onto one statement per line, indenting `if` bodies.
  static List<String> _formatExec(String src) {
    final out = <String>[];
    final cur = StringBuffer();
    var depth = 0; // brace depth
    var paren = 0;
    var inStr = false;
    void flush() {
      final s = cur.toString().trim();
      if (s.isNotEmpty) out.add('${'  ' * depth}$s');
      cur.clear();
    }

    for (var k = 0; k < src.length; k++) {
      final c = src[k];
      if (inStr) {
        cur.write(c);
        if (c == r'\' && k + 1 < src.length) {
          cur.write(src[++k]);
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') {
        inStr = true;
        cur.write(c);
      } else if (c == '(') {
        paren++;
        cur.write(c);
      } else if (c == ')') {
        paren--;
        cur.write(c);
      } else if (c == ';' && paren == 0) {
        cur.write(c);
        flush();
      } else if (c == '{' && paren == 0) {
        cur.write(c);
        flush();
        depth++;
      } else if (c == '}' && paren == 0) {
        flush();
        depth--;
        // "} else {" stays on one line.
        cur.write(c);
        var m = k + 1;
        while (m < src.length && src[m] == ' ') {
          m++;
        }
        if (src.startsWith('else', m)) {
          // Continue the same line with the else part.
          continue;
        }
        flush();
      } else {
        cur.write(c);
      }
    }
    flush();
    return out;
  }

  /// Collapses whitespace in semantics so two spellings compare equal.
  static String normalizeExec(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Pretty JSON, for the JSON export that older tools expect.
  static String toJsonText(ProcessorSpec spec) =>
      const JsonEncoder.withIndent('  ').convert(spec.toJson());
}

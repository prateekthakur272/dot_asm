import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot_asm/features/workspace/editor_logic.dart';

import 'support/templates.dart';

TextEditingValue v(String text, [int? a, int? b]) {
  // "|" marks the caret; "[" and "]" mark a selection when no offsets are given.
  if (a != null) {
    return TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: a, extentOffset: b ?? a),
    );
  }
  final caret = text.indexOf('|');
  if (caret >= 0) {
    return TextEditingValue(
      text: text.replaceFirst('|', ''),
      selection: TextSelection.collapsed(offset: caret),
    );
  }
  final s = text.indexOf('[');
  final e = text.indexOf(']') - 1;
  return TextEditingValue(
    text: text.replaceAll('[', '').replaceAll(']', ''),
    selection: TextSelection(baseOffset: s, extentOffset: e),
  );
}

String show(TextEditingValue x) {
  final t = x.text;
  final s = x.selection;
  if (s.isCollapsed) return t.replaceRange(s.start, s.start, '|');
  return t.replaceRange(s.end, s.end, ']').replaceRange(s.start, s.start, '[');
}

void main() {
  setUpAll(loadTemplates);

  group('indent', () {
    test('a caret moves to the next tab stop', () {
      expect(show(EditorOps.indent(v('|add'))), '    |add');
      expect(show(EditorOps.indent(v('ab|'))), 'ab  |');
    });
    test('a multi-line selection indents and outdents every line', () {
      final a = EditorOps.indent(v('[a\nb\n\nc]'));
      expect(a.text, '    a\n    b\n\n    c');
      final b = EditorOps.indent(a, outdent: true);
      expect(b.text, 'a\nb\n\nc');
    });
    test('outdent removes at most one tab stop', () {
      expect(EditorOps.indent(v('      |x'), outdent: true).text, '  x');
      expect(show(EditorOps.indent(v('  |x'), outdent: true)), '|x');
    });
  });

  group('comments', () {
    test('toggle adds then removes the marker', () {
      final on = EditorOps.toggleComment(v('  add x|\n  sub y'), '#');
      expect(on.text, '  # add x\n  sub y');
      final off = EditorOps.toggleComment(on, '#');
      expect(off.text, '  add x\n  sub y');
    });
    test('a block comments every non-blank line at the shallowest indent', () {
      final on = EditorOps.toggleComment(v('[    a\n\n  b]'), '#');
      expect(on.text, '  #   a\n\n  # b');
      expect(EditorOps.toggleComment(on, '#').text, '    a\n\n  b');
    });
  });

  group('lines', () {
    test('duplicate puts a copy below and the caret in it', () {
      expect(show(EditorOps.duplicateLines(v('a|b\nc'))), 'ab\na|b\nc');
    });
    test('delete removes the line and keeps the column', () {
      expect(show(EditorOps.deleteLines(v('one\nt|wo\nthree'))), 'one\nt|hree');
      expect(EditorOps.deleteLines(v('one\ntwo|')).text, 'one');
      expect(EditorOps.deleteLines(v('only|')).text, '');
    });
    test('move swaps with the neighbour and the selection follows', () {
      expect(show(EditorOps.moveLines(v('a\nb|\nc'), up: true)), 'b|\na\nc');
      expect(show(EditorOps.moveLines(v('a\nb|\nc'), up: false)), 'a\nc\nb|');
      expect(EditorOps.moveLines(v('|a\nb'), up: true).text, 'a\nb');
      expect(EditorOps.moveLines(v('a\n|b'), up: false).text, 'a\nb');
    });
  });

  group('typing assistance', () {
    TextEditingValue type(TextEditingValue old, String ch) {
      final s = old.selection;
      final now = TextEditingValue(
        text: old.text.replaceRange(s.start, s.end, ch),
        selection: TextSelection.collapsed(offset: s.start + ch.length),
      );
      return EditorOps.assist(old, now) ?? now;
    }

    test('Enter keeps the indentation', () {
      expect(show(type(v('    add x|'), '\n')), '    add x\n    |');
      expect(show(type(v('add x|'), '\n')), 'add x\n|');
    });
    test('Enter after a label indents the code', () {
      expect(show(type(v('main:|'), '\n')), 'main:\n    |');
    });
    test('brackets and quotes close themselves and can be typed over', () {
      final a = type(v('lw x1, 4|'), '(');
      expect(show(a), 'lw x1, 4(|)');
      expect(show(type(a, ')')), 'lw x1, 4()|');
      final q = type(v('.ascii |'), '"');
      expect(show(q), '.ascii "|"');
      expect(show(type(q, '"')), '.ascii ""|');
    });
    test('an apostrophe style quote inside a word is left alone', () {
      expect(show(type(v('it|'), '"')), 'it"|');
    });
    test('a selection is wrapped by the pair', () {
      expect(show(type(v('[abc]'), '(')), '([abc])');
    });
    test('backspace inside an empty pair removes both', () {
      final old = v('f(|)');
      final now = TextEditingValue(
        text: 'f)',
        selection: const TextSelection.collapsed(offset: 1),
      );
      expect(EditorOps.assist(old, now)!.text, 'f');
    });
  });

  test('bracket matching finds the partner from either side', () {
    expect(EditorOps.matchingBracket('a(b[c]d)', 2), (a: 1, b: 7));
    expect(EditorOps.matchingBracket('a(b[c]d)', 8), (a: 1, b: 7));
    expect(EditorOps.matchingBracket('a(b', 2), isNull);
  });

  test('find is case-insensitive unless asked', () {
    expect(EditorOps.findAll('Add add ADD', 'add').length, 3);
    expect(
      EditorOps.findAll('Add add ADD', 'add', caseSensitive: true).length,
      1,
    );
    expect(EditorOps.findAll('abc', ''), isEmpty);
  });

  test('line and column helpers', () {
    expect(EditorOps.lineCol('ab\ncd', 4), (line: 2, col: 2));
    expect(EditorOps.lineStart('ab\ncd\nef', 3), 6);
    expect(EditorOps.lineStart('ab\ncd', 99), 3);
    expect(EditorOps.lineStart('ab\ncd', 1), 0);
  });

  group('completion', () {
    late CompletionIndex idx;
    setUpAll(() => idx = CompletionIndex(template('rv32i')));

    test('the first word on a line offers instructions and directives', () {
      final r = idx.suggest('  ad', 4);
      expect(r.items.map((i) => i.label), contains('add'));
      expect(r.items.first.kind, CompletionKind.mnemonic);
      expect(r.start, 2);
      final d = idx.suggest('.wo', 3);
      expect(d.items.map((i) => i.label), contains('.word'));
    });
    test('operands offer registers and labels', () {
      final r = idx.suggest('  add a', 7, labels: {'loop', 'again'});
      final labels = r.items.map((i) => i.label).toList();
      expect(labels, containsAll(['a0', 'again']));
      expect(labels, isNot(contains('add')));
    });
    test(
      'code after a label on the same line still counts as the first word',
      () {
        final r = idx.suggest('main: ad', 8);
        expect(r.items.map((i) => i.label), contains('add'));
      },
    );
    test('nothing inside comments, strings or numbers', () {
      expect(idx.suggest('  add # ad', 10).items, isEmpty);
      expect(idx.suggest('.ascii "ad', 10).items, isEmpty);
      expect(idx.suggest('  addi x1, x0, 12', 17).items, isEmpty);
    });
    test('an exact single match is not offered again', () {
      expect(idx.suggest('  ecall', 7).items, isEmpty);
    });
    test('force lists everything for an empty word', () {
      expect(idx.suggest('  ', 2).items, isEmpty);
      expect(idx.suggest('  ', 2, force: true).items, isNotEmpty);
    });
    test('labels and constants are collected from the source', () {
      expect(
        CompletionIndex.labelsIn(
          'main:\n  j loop\nloop: add x1,x1,x1\n.equ SIZE, 4\n',
        ),
        {'main', 'loop', 'SIZE'},
      );
    });
    test('instruction details carry the syntax', () {
      final add = idx.describe('ADD')!;
      expect(add.detail, isNotEmpty);
      expect(idx.describe('nope'), isNull);
    });
  });
}

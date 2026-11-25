import 'package:flutter/services.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';

/// Text transformations and code intelligence for the source editor. Everything here is a pure function of the text
/// (and the processor), so it can be tested without a widget.

const int kTabSize = 4;

// ---------------------------------------------------------------------------------------------------------------
// Line-based edits

class _Block {
  _Block(this.start, this.end, this.lines);
  final int start; // offset of the first character of the first line
  final int
  end; // offset just past the last character of the last line (before its \n)
  final List<String> lines;
}

_Block _blockOf(String text, TextSelection sel) {
  final a = sel.start.clamp(0, text.length);
  var b = sel.end.clamp(0, text.length);
  // A selection that ends at the very start of a line does not include that line.
  if (b > a && b > 0 && text[b - 1] == '\n') b--;
  final start = a == 0 ? 0 : text.lastIndexOf('\n', a - 1) + 1;
  var end = text.indexOf('\n', b);
  if (end < 0) end = text.length;
  return _Block(start, end, text.substring(start, end).split('\n'));
}

typedef _LineEdit = ({String line, int col, int delta});

/// Rewrites every line of the selected block and keeps the selection on the same text.
TextEditingValue _mapLines(
  TextEditingValue v,
  _LineEdit Function(String line) edit,
) {
  final text = v.text;
  final block = _blockOf(text, v.selection);
  final edits = [for (final l in block.lines) edit(l)];
  final out = StringBuffer();
  for (var i = 0; i < edits.length; i++) {
    if (i > 0) out.write('\n');
    out.write(edits[i].line);
  }
  final total = edits.fold<int>(0, (s, e) => s + e.delta);
  int map(int offset) {
    if (offset < block.start) return offset;
    if (offset > block.end) return offset + total;
    var oldPos = block.start;
    var newPos = block.start;
    for (var i = 0; i < block.lines.length; i++) {
      final len = block.lines[i].length;
      if (offset <= oldPos + len) {
        final e = edits[i];
        final col = offset - oldPos;
        var nc = col;
        if (col > e.col) nc = (col + e.delta).clamp(e.col, e.line.length);
        return newPos + nc;
      }
      oldPos += len + 1;
      newPos += edits[i].line.length + 1;
    }
    return offset + total;
  }

  final sel = v.selection;
  final newText = text.replaceRange(block.start, block.end, out.toString());
  return TextEditingValue(
    text: newText,
    selection: TextSelection(
      baseOffset: map(sel.baseOffset),
      extentOffset: map(sel.extentOffset),
    ),
  );
}

class EditorOps {
  /// Tab / Shift+Tab. A caret (or a selection inside one line) inserts spaces up to the next tab stop; a selection over
  /// several lines indents them all.
  static TextEditingValue indent(
    TextEditingValue v, {
    bool outdent = false,
    int size = kTabSize,
  }) {
    final sel = v.selection;
    final multi = v.text.substring(sel.start, sel.end).contains('\n');
    if (!outdent && !multi) {
      final lineStart = sel.start == 0
          ? 0
          : v.text.lastIndexOf('\n', sel.start - 1) + 1;
      final col = sel.start - lineStart;
      final n = size - col % size;
      return _replace(v, sel.start, sel.end, ' ' * n);
    }
    return _mapLines(v, (line) {
      if (!outdent) {
        if (line.trim().isEmpty) return (line: line, col: 0, delta: 0);
        return (line: '${' ' * size}$line', col: 0, delta: size);
      }
      var n = 0;
      while (n < size && n < line.length && line[n] == ' ') {
        n++;
      }
      if (n == 0 && line.startsWith('\t')) n = 1;
      return (line: line.substring(n), col: 0, delta: -n);
    });
  }

  /// Comments or uncomments the selected lines with the processor's first comment marker.
  static TextEditingValue toggleComment(TextEditingValue v, String marker) {
    final block = _blockOf(v.text, v.selection);
    final code = block.lines.where((l) => l.trim().isNotEmpty).toList();
    if (code.isEmpty) return v;
    final allCommented = code.every((l) => l.trimLeft().startsWith(marker));
    var indent = code
        .map((l) => l.length - l.trimLeft().length)
        .reduce((a, b) => a < b ? a : b);
    return _mapLines(v, (line) {
      if (line.trim().isEmpty) return (line: line, col: 0, delta: 0);
      if (allCommented) {
        final at = line.length - line.trimLeft().length;
        var cut = marker.length;
        if (line.startsWith(' ', at + cut)) cut++;
        return (
          line: line.replaceRange(at, at + cut, ''),
          col: at,
          delta: -cut,
        );
      }
      return (
        line: line.replaceRange(indent, indent, '$marker '),
        col: indent,
        delta: marker.length + 1,
      );
    });
  }

  /// Copies the selected lines below themselves; the selection moves to the copy.
  static TextEditingValue duplicateLines(TextEditingValue v) {
    final block = _blockOf(v.text, v.selection);
    final chunk = v.text.substring(block.start, block.end);
    final text = v.text.replaceRange(block.end, block.end, '\n$chunk');
    final off = chunk.length + 1;
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: v.selection.baseOffset + off,
        extentOffset: v.selection.extentOffset + off,
      ),
    );
  }

  /// Deletes the selected lines.
  static TextEditingValue deleteLines(TextEditingValue v) {
    final block = _blockOf(v.text, v.selection);
    final col = v.selection.extentOffset - block.start;
    var from = block.start;
    var to = block.end;
    if (to < v.text.length) {
      to++; // take the newline after the block
    } else if (from > 0) {
      from--; // last line: take the newline before it
    }
    final lastLine = block.end >= v.text.length;
    final text = v.text.replaceRange(from, to, '');
    // The caret lands on the line that took the deleted one's place (the previous line when it was the last).
    final lineStart = lastLine
        ? (text.isEmpty ? 0 : text.lastIndexOf('\n') + 1)
        : block.start;
    var lineEnd = text.indexOf('\n', lineStart);
    if (lineEnd < 0) lineEnd = text.length;
    final caret = (lineStart + col).clamp(lineStart, lineEnd);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret.clamp(0, text.length)),
    );
  }

  /// Moves the selected lines up or down by one line.
  static TextEditingValue moveLines(TextEditingValue v, {required bool up}) {
    final text = v.text;
    final block = _blockOf(text, v.selection);
    final chunk = text.substring(block.start, block.end);
    int shift;
    String out;
    if (up) {
      if (block.start == 0) return v;
      final prevStart = block.start == 1
          ? 0
          : text.lastIndexOf('\n', block.start - 2) + 1;
      final prev = text.substring(prevStart, block.start - 1);
      out = text.replaceRange(prevStart, block.end, '$chunk\n$prev');
      shift = -(prev.length + 1);
    } else {
      if (block.end >= text.length) return v;
      var nextEnd = text.indexOf('\n', block.end + 1);
      if (nextEnd < 0) nextEnd = text.length;
      final next = text.substring(block.end + 1, nextEnd);
      out = text.replaceRange(block.start, nextEnd, '$next\n$chunk');
      shift = next.length + 1;
    }
    return TextEditingValue(
      text: out,
      selection: TextSelection(
        baseOffset: v.selection.baseOffset + shift,
        extentOffset: v.selection.extentOffset + shift,
      ),
    );
  }

  static TextEditingValue _replace(
    TextEditingValue v,
    int start,
    int end,
    String with_,
  ) => TextEditingValue(
    text: v.text.replaceRange(start, end, with_),
    selection: TextSelection.collapsed(offset: start + with_.length),
  );

  // -------------------------------------------------------------------------------------------------------------
  // Typing assistance (used from a TextInputFormatter so it also works with IME input)

  static const _pairs = {'(': ')', '[': ']', '{': '}', '"': '"'};
  static const _closers = {')', ']', '}', '"'};

  static bool _isWord(String c) => RegExp(r'[A-Za-z0-9_]').hasMatch(c);

  /// Auto-indent after Enter, closing brackets and quotes, typing over a closer, and deleting a pair together.
  /// Returns null when the edit needs no help.
  static TextEditingValue? assist(
    TextEditingValue old,
    TextEditingValue now, {
    int unit = kTabSize,
    bool blocks = false,
    bool pairs = true,
  }) {
    if (!now.selection.isCollapsed ||
        old.composing.isValid && !old.composing.isCollapsed) {
      return null;
    }
    final os = old.selection;
    final removed = os.end - os.start;
    final delta = now.text.length - (old.text.length - removed);

    // Enter
    if (delta == 1 &&
        now.selection.start > 0 &&
        now.text[now.selection.start - 1] == '\n' &&
        now.selection.start - 1 == os.start) {
      final before = now.text.substring(0, os.start);
      final lineStart = before.lastIndexOf('\n') + 1;
      final prev = before.substring(lineStart);
      var pad = prev.length - prev.trimLeft().length;
      // Under a label the code is indented one step.
      final code = _stripComment(prev).trimRight();
      final at = now.selection.start;
      if (blocks) {
        // Inside braces: one step deeper after `{`, and a closing `}` that was waiting goes on its own line.
        if (code.endsWith('{')) {
          pad += unit;
          final next = at < now.text.length ? now.text[at] : '';
          if (next == '}') {
            return TextEditingValue(
              text: now.text.replaceRange(
                at,
                at,
                '${' ' * pad}\n${' ' * (pad - unit)}',
              ),
              selection: TextSelection.collapsed(offset: at + pad),
            );
          }
        }
      } else if (code.endsWith(':') && pad == 0) {
        pad = unit;
      }
      if (pad == 0) return null;
      final ins = ' ' * pad;
      return TextEditingValue(
        text: now.text.replaceRange(at, at, ins),
        selection: TextSelection.collapsed(offset: at + pad),
      );
    }

    // A single character typed
    if (delta == 1 && now.selection.start > 0) {
      final at = now.selection.start - 1;
      final c = now.text[at];
      final after = at + 1 < now.text.length ? now.text[at + 1] : '';
      // A `}` typed on a line that holds only indentation steps back one level.
      if (blocks && c == '}' && removed == 0) {
        final ls = now.text.lastIndexOf('\n', at - 1) + 1;
        final lead = now.text.substring(ls, at);
        if (lead.isNotEmpty && lead.trim().isEmpty && lead.length >= unit) {
          return TextEditingValue(
            text: now.text.replaceRange(at - unit, at, ''),
            selection: TextSelection.collapsed(offset: at - unit + 1),
          );
        }
      }
      // Brackets and quotes close themselves only when that is switched on.
      if (!pairs) return null;
      // Selection wrapped in a pair.
      if (removed > 0 && _pairs.containsKey(c)) {
        final sel = old.text.substring(os.start, os.end);
        final close = _pairs[c]!;
        return TextEditingValue(
          text: old.text.replaceRange(os.start, os.end, '$c$sel$close'),
          selection: TextSelection(
            baseOffset: os.start + 1,
            extentOffset: os.start + 1 + sel.length,
          ),
        );
      }
      if (removed > 0) return null;
      // Type over a closer that is already there.
      if (_closers.contains(c) && after == c) {
        return TextEditingValue(
          text: now.text.replaceRange(at, at + 1, ''),
          selection: TextSelection.collapsed(offset: at + 1),
        );
      }
      if (_pairs.containsKey(c)) {
        final prev = at > 0 ? now.text[at - 1] : '';
        if (c == '"' && (_isWord(prev) || _isWord(after))) return null;
        if (c != '"' && after.isNotEmpty && _isWord(after)) return null;
        final close = _pairs[c]!;
        return TextEditingValue(
          text: now.text.replaceRange(at + 1, at + 1, close),
          selection: TextSelection.collapsed(offset: at + 1),
        );
      }
      return null;
    }

    // Backspace between an empty pair
    if (pairs && delta == -1 && removed == 0 && os.start > 0) {
      final gone = old.text[os.start - 1];
      final next = os.start < old.text.length ? old.text[os.start] : '';
      if (_pairs[gone] == next && next.isNotEmpty) {
        return TextEditingValue(
          text: old.text.replaceRange(os.start - 1, os.start + 1, ''),
          selection: TextSelection.collapsed(offset: os.start - 1),
        );
      }
    }
    return null;
  }

  static String _stripComment(
    String line, [
    List<String> markers = const ['#', ';', '//', '@'],
  ]) {
    var inStr = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inStr) {
        if (c == r'\') i++;
        if (c == '"') inStr = false;
        continue;
      }
      if (c == '"') {
        inStr = true;
        continue;
      }
      if (markers.any((m) => line.startsWith(m, i))) {
        return line.substring(0, i);
      }
    }
    return line;
  }

  // -------------------------------------------------------------------------------------------------------------
  // Brackets

  static const _open = '([{';
  static const _close = ')]}';

  /// Offsets of the bracket at or before the caret and its partner, or null.
  static ({int a, int b})? matchingBracket(String text, int caret) {
    for (final at in [caret - 1, caret]) {
      if (at < 0 || at >= text.length) continue;
      final c = text[at];
      final oi = _open.indexOf(c);
      final ci = _close.indexOf(c);
      if (oi >= 0) {
        var depth = 0;
        for (var i = at; i < text.length; i++) {
          if (text[i] == c) depth++;
          if (text[i] == _close[oi]) depth--;
          if (depth == 0) return (a: at, b: i);
        }
      } else if (ci >= 0) {
        var depth = 0;
        for (var i = at; i >= 0; i--) {
          if (text[i] == c) depth++;
          if (text[i] == _open[ci]) depth--;
          if (depth == 0) return (a: i, b: at);
        }
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------------------------------------------
  // Find

  static List<TextRange> findAll(
    String text,
    String query, {
    bool caseSensitive = false,
  }) {
    if (query.isEmpty) return const [];
    final hay = caseSensitive ? text : text.toLowerCase();
    final needle = caseSensitive ? query : query.toLowerCase();
    final out = <TextRange>[];
    var i = 0;
    while (true) {
      i = hay.indexOf(needle, i);
      if (i < 0) break;
      out.add(TextRange(start: i, end: i + needle.length));
      i += needle.length;
    }
    return out;
  }

  /// Line (1-based) and column (1-based) of [offset].
  static ({int line, int col}) lineCol(String text, int offset) {
    final o = offset.clamp(0, text.length);
    var line = 1;
    var last = -1;
    for (var i = 0; i < o; i++) {
      if (text.codeUnitAt(i) == 10) {
        line++;
        last = i;
      }
    }
    return (line: line, col: o - last);
  }

  /// Offset of the start of 1-based [line] (clamped).
  static int lineStart(String text, int line) {
    var l = 1;
    for (var i = 0; i < text.length && l < line; i++) {
      if (text.codeUnitAt(i) == 10) {
        l++;
        if (l == line) return i + 1;
      }
    }
    return l == line ? 0 : text.lastIndexOf('\n') + 1;
  }
}

/// Plugs [EditorOps.assist] into a text field.
class AssistFormatter extends TextInputFormatter {
  const AssistFormatter({
    this.unit = kTabSize,
    this.blocks = false,
    this.pairs = true,
  });

  /// Spaces per indent level, whether `{ }` blocks drive the indentation, and whether brackets and quotes close
  /// themselves.
  final int unit;
  final bool blocks;
  final bool pairs;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      EditorOps.assist(
        oldValue,
        newValue,
        unit: unit,
        blocks: blocks,
        pairs: pairs,
      ) ??
      newValue;
}

// ---------------------------------------------------------------------------------------------------------------
// Completion

enum CompletionKind { mnemonic, register, directive, label }

class CompletionItem {
  const CompletionItem({
    required this.label,
    required this.kind,
    this.insert,
    this.detail = '',
    this.doc = '',
  });
  final String label;
  final CompletionKind kind;

  /// Text that replaces the word; defaults to [label].
  final String? insert;
  final String detail;
  final String doc;
  String get text => insert ?? label;
}

class CompletionResult {
  const CompletionResult(this.start, this.end, this.items);
  final int start;
  final int end;
  final List<CompletionItem> items;
  static const none = CompletionResult(0, 0, []);
}

const Map<String, String> _directiveDocs = {
  '.text': 'Switch to the code section',
  '.data': 'Switch to the initialised data section',
  '.bss': 'Switch to the zero-initialised data section',
  '.rodata': 'Switch to the read-only data section',
  '.section': 'Switch to a named section',
  '.org': 'Set the location counter to an address',
  '.align': 'Align to a power of two',
  '.balign': 'Align to a number of bytes',
  '.equ': 'Define a constant: .equ NAME, value',
  '.set': 'Define a constant: .set NAME, value',
  '.byte': 'Emit 8-bit values',
  '.half': 'Emit 16-bit values',
  '.short': 'Emit 16-bit values',
  '.word': 'Emit machine words',
  '.long': 'Emit 32-bit values',
  '.dword': 'Emit 64-bit values',
  '.quad': 'Emit 64-bit values',
  '.ascii': 'Emit a string without a terminator',
  '.asciz': 'Emit a zero-terminated string',
  '.asciiz': 'Emit a zero-terminated string',
  '.string': 'Emit a zero-terminated string',
  '.space': 'Reserve zeroed bytes',
  '.zero': 'Reserve zeroed bytes',
  '.skip': 'Reserve zeroed bytes',
  '.entry': 'Set the entry point',
  '.globl': 'Export a symbol',
  '.global': 'Export a symbol',
};

/// What the editor can suggest for one processor.
class CompletionIndex {
  CompletionIndex(ProcessorSpec spec)
    : comments = spec.comments.isEmpty ? const ['#'] : spec.comments {
    final byMnemonic = <String, InstructionSpec>{};
    for (final i in spec.instructions) {
      byMnemonic.putIfAbsent(i.mnemonic, () => i);
    }
    final syntaxes = <String, List<String>>{};
    for (final i in spec.instructions) {
      (syntaxes[i.mnemonic] ??= []).add(i.syntax.trim());
    }
    for (final e in byMnemonic.entries) {
      final forms = syntaxes[e.key]!.toSet().toList();
      mnemonics.add(
        CompletionItem(
          label: e.key,
          kind: CompletionKind.mnemonic,
          insert: '${e.key} ',
          detail: forms.first,
          doc: [
            e.value.description,
            if (forms.length > 1) forms.skip(1).take(3).join('\n'),
          ].where((s) => s.isNotEmpty).join('\n'),
        ),
      );
    }
    for (final p in spec.pseudos) {
      if (byMnemonic.containsKey(p.mnemonic)) continue;
      mnemonics.add(
        CompletionItem(
          label: p.mnemonic,
          kind: CompletionKind.mnemonic,
          insert: '${p.mnemonic} ',
          detail: p.syntax.trim(),
          doc: 'Pseudo-instruction',
        ),
      );
    }
    for (var i = 0; i < spec.registerCount; i++) {
      final aliases = spec.registerAliases(i);
      registers.add(
        CompletionItem(
          label: spec.registerName(i),
          kind: CompletionKind.register,
          detail: aliases.isEmpty ? 'register' : aliases.join(', '),
        ),
      );
      for (final a in aliases) {
        registers.add(
          CompletionItem(
            label: a,
            kind: CompletionKind.register,
            detail: spec.registerName(i),
          ),
        );
      }
    }
    for (final r in spec.registers) {
      registers.add(
        CompletionItem(
          label: r.name,
          kind: CompletionKind.register,
          detail: r.description.isEmpty
              ? '${r.width}-bit register'
              : r.description,
        ),
      );
    }
    for (final e in _directiveDocs.entries) {
      directives.add(
        CompletionItem(
          label: e.key,
          kind: CompletionKind.directive,
          doc: e.value,
        ),
      );
    }
    mnemonics.sort((a, b) => a.label.compareTo(b.label));
    _mnemonicSet = {for (final m in mnemonics) m.label.toLowerCase()};
    _registerSet = {for (final r in registers) r.label.toLowerCase()};
  }

  final List<String> comments;
  final List<CompletionItem> mnemonics = [];
  final List<CompletionItem> registers = [];
  final List<CompletionItem> directives = [];
  late final Set<String> _mnemonicSet;
  late final Set<String> _registerSet;

  bool isMnemonic(String s) => _mnemonicSet.contains(s.toLowerCase());
  bool isRegister(String s) => _registerSet.contains(s.toLowerCase());

  /// Documentation for the word under the cursor, if it is an instruction or directive.
  CompletionItem? describe(String word) {
    final w = word.toLowerCase();
    for (final m in mnemonics) {
      if (m.label.toLowerCase() == w) return m;
    }
    for (final d in directives) {
      if (d.label == w) return d;
    }
    return null;
  }

  static final _labelDef = RegExp(
    r'^\s*([A-Za-z_.$][\w.$]*)\s*:',
    multiLine: true,
  );
  static final _equDef = RegExp(
    r'^\s*\.(?:equ|set)\s+([A-Za-z_.$][\w.$]*)',
    multiLine: true,
  );

  /// Labels and constants defined in [text].
  static Set<String> labelsIn(String text) => {
    for (final m in _labelDef.allMatches(text)) m.group(1)!,
    for (final m in _equDef.allMatches(text)) m.group(1)!,
  };

  static final _wordChar = RegExp(r'[A-Za-z0-9_.$%]');

  /// Suggestions for the word ending at [caret]. With [force] an empty word is allowed too (Ctrl+Space).
  CompletionResult suggest(
    String text,
    int caret, {
    Set<String>? labels,
    bool force = false,
  }) {
    if (caret < 0 || caret > text.length) return CompletionResult.none;
    var start = caret;
    while (start > 0 && _wordChar.hasMatch(text[start - 1])) {
      start--;
    }
    var end = caret;
    while (end < text.length && _wordChar.hasMatch(text[end])) {
      end++;
    }
    final prefix = text.substring(start, caret);
    if (prefix.isEmpty && !force) return CompletionResult.none;

    final lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    final before = text.substring(lineStart, start);
    if (_inCommentOrString(before)) return CompletionResult.none;
    // Digits are numbers, not names.
    if (prefix.isNotEmpty && RegExp(r'^[0-9]').hasMatch(prefix)) {
      return CompletionResult.none;
    }

    // Code before the word on this line, without a leading label.
    final code = before.replaceFirst(RegExp(r'^\s*[A-Za-z_.$][\w.$]*\s*:'), '');
    final firstOnLine = code.trim().isEmpty;

    final pool = <CompletionItem>[];
    if (prefix.startsWith('.')) {
      pool.addAll(directives);
      if (!firstOnLine) {
        pool.addAll(_labelItems(labels));
      }
    } else if (firstOnLine) {
      pool.addAll(mnemonics);
      pool.addAll(directives);
    } else {
      pool.addAll(registers);
      pool.addAll(_labelItems(labels));
    }

    final p = prefix.toLowerCase();
    final starts = <CompletionItem>[];
    final contains = <CompletionItem>[];
    final seen = <String>{};
    for (final it in pool) {
      final l = it.label.toLowerCase();
      if (!seen.add('${it.kind.name}:$l')) continue;
      if (p.isEmpty || l.startsWith(p)) {
        starts.add(it);
      } else if (l.contains(p)) {
        contains.add(it);
      }
    }
    final items = [...starts, ...contains];
    // A complete word that is the only match needs no popup.
    if (items.length == 1 &&
        items.first.label.toLowerCase() == p &&
        end == caret) {
      return CompletionResult.none;
    }
    if (items.isEmpty) return CompletionResult.none;
    return CompletionResult(start, end, items.take(60).toList());
  }

  Iterable<CompletionItem> _labelItems(Set<String>? labels) => [
    for (final l in (labels ?? const <String>{}))
      CompletionItem(label: l, kind: CompletionKind.label, detail: 'label'),
  ];

  bool _inCommentOrString(String before) {
    var inStr = false;
    for (var i = 0; i < before.length; i++) {
      final c = before[i];
      if (inStr) {
        if (c == r'\') i++;
        if (i < before.length && before[i] == '"') inStr = false;
        continue;
      }
      if (c == '"') {
        inStr = true;
        continue;
      }
      if (comments.any((m) => before.startsWith(m, i))) return true;
    }
    return inStr;
  }
}

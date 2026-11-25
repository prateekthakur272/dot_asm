import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dot_asm/features/workspace/editor_logic.dart';
import 'package:dot_asm/features/workspace/editor_parts.dart';
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/theme.dart';

/// Indentation of the `.cpu` / `.dotasm` block language.
const int kDslTab = 2;

const Color _kString = Color(0xFFA3BE8C);
const Color _kNumber = Color(0xFFD08770);
const Color _kType = Color(0xFFB48EAD);
const Color _kFunction = Color(0xFF54C5F8);

/// Statement keywords of a processor file, with what each one is for.
const Map<String, String> kDslKeywords = {
  'processor': 'processor id "Name" { … }  The processor definition',
  'arch': 'arch custom  The architecture family',
  'vendor': 'vendor "Name"  Who made it',
  'year': 'year 1985  When it appeared',
  'era': 'era legacy | modern  Which gallery era it belongs to',
  'tags': 'tags RISC 32-bit  Filters in the processor gallery',
  'describe': 'describe "text"  A short description',
  'word': 'word 32 little  Address and word size in bits, and the byte order',
  'fetch': 'fetch 32  Default instruction size in bits',
  'aligned': 'aligned  Fault on misaligned loads and stores',
  'registers':
      'registers r count 8 width 16 { … }  A bank of numbered registers',
  'register': 'register ACC width 8 "accumulator"  One extra named register',
  'flags': 'flags N Z C V  Single-bit condition flags',
  'memory':
      'memory { name at 0x0 size 0x1000 perms rx role text }  The memory map',
  'init': 'init sp=0x7ffe  Register values before the first instruction',
  'reset': 'reset 0x0  Where execution starts',
  'comments': 'comments "#" ";"  The assembler\'s comment markers',
  'pipeline': 'pipeline IF ID EX MEM WB  Stage names shown for the processor',
  'hexprefix': 'hexprefix "\$"  The prefix of hexadecimal numbers in assembly',
  'wordbytes': 'wordbytes 4  Bytes of a .word',
  'rewrite': 'rewrite "from" "to"  Rewrites operand text before parsing',
  'conditions': 'conditions { … }  Condition codes such as the ARM suffixes',
  'instruction': 'instruction add "rd, rs1, rs2" { … }  One instruction',
  'pseudo':
      'pseudo "li rd, imm" { … }  A mnemonic that expands to real instructions',
  'sample': 'sample """…"""  The starter program of new projects',
  'zero': 'zero 0  The register that always reads 0',
  'alias': 'alias sp=2 ra=1  Alternative register names',
  'size': 'size 16  Instruction size in bits',
  'match':
      'match 0xfe00707f 0x33  Mask and value that identify the instruction',
  'operand': 'operand rd reg [11:7]  An operand: its kind and where it sits in the word',
  'cycles': 'cycles 3  Cycles the instruction takes',
  'base': 'base 4  Added to the pc for pc-relative operands',
  'conditional': 'conditional  The instruction can carry a condition suffix',
  'exec': 'exec { … }  What the instruction does',
  'when': 'when expr { … }  A variant used when the expression holds',
  'otherwise': 'otherwise { … }  The variant used when none matched',
  'expand': 'expand { … }  The instructions a pseudo-instruction becomes',
};

/// Words that appear as values after a keyword.
const Map<String, String> kDslValues = {
  'reg': 'A register operand',
  'imm': 'An immediate (number) operand',
  'pcrel': 'A pc-relative operand (a branch target)',
  'little': 'Least significant byte first',
  'big': 'Most significant byte first',
  'legacy': 'Before about 2000',
  'modern': 'Recent designs',
  'custom': 'Your own architecture',
};

const Set<String> _rawBlocks = {'exec', 'when', 'otherwise', 'expand'};

/// Colours a `.cpu` file: comments, strings (also `"""` blocks), numbers, statement keywords and operand kinds. The
/// bodies of `exec` blocks are read as code, with function calls highlighted.
class DslEditingController extends TextEditingController {
  DslEditingController({super.text});

  static final _token = RegExp(
    r'("(?:[^"\\]|\\.)*"?)|(0[xX][0-9a-fA-F_]+|0[bB][01_]+|\b\d[\d_]*\b)|([A-Za-z_$@.][A-Za-z0-9_$@.\-]*)',
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final p = context.pal;
    final base = (style ?? const TextStyle())
        .merge(kEditorTextStyle)
        .copyWith(color: p.text);
    final cComment = p.muted.withOpacity(0.85);
    TextStyle c(Color col, {FontWeight? w, FontStyle? it}) =>
        base.copyWith(color: col, fontWeight: w, fontStyle: it);

    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    var inTriple = false;
    // Depth of braces inside a raw block (exec ...), or 0 when outside one.
    var raw = 0;
    for (var li = 0; li < lines.length; li++) {
      final line = lines[li];
      var from = 0;
      if (inTriple) {
        final end = line.indexOf('"""');
        if (end < 0) {
          spans.add(TextSpan(text: line, style: c(_kString)));
          if (li < lines.length - 1) {
            spans.add(TextSpan(text: '\n', style: base));
          }
          continue;
        }
        spans.add(
          TextSpan(text: line.substring(0, end + 3), style: c(_kString)),
        );
        from = end + 3;
        inTriple = false;
      }
      var first = from == 0;
      var pos = from;
      final startsRaw = raw == 0;
      var lineRaw = raw > 0;
      for (final m in _token.allMatches(line, from)) {
        // Text between tokens: punctuation, comments.
        final gap = line.substring(pos, m.start);
        if (gap.isNotEmpty) {
          final cm = _commentAt(gap);
          if (cm >= 0) {
            spans.add(TextSpan(text: gap.substring(0, cm), style: base));
            spans.add(
              TextSpan(
                text: line.substring(pos + cm),
                style: c(cComment, it: FontStyle.italic),
              ),
            );
            pos = line.length;
            break;
          }
          spans.add(TextSpan(text: gap, style: c(p.muted)));
        }
        final t = m.group(0)!;
        pos = m.end;
        if (m.group(1) != null) {
          if (t.startsWith('"""')) {
            final rest = line.substring(m.start + 3);
            final close = rest.indexOf('"""');
            if (close < 0) {
              spans.add(
                TextSpan(text: line.substring(m.start), style: c(_kString)),
              );
              pos = line.length;
              inTriple = true;
              break;
            }
            final stop = m.start + 3 + close + 3;
            spans.add(
              TextSpan(text: line.substring(m.start, stop), style: c(_kString)),
            );
            pos = stop;
            continue;
          }
          spans.add(TextSpan(text: t, style: c(_kString)));
        } else if (m.group(2) != null) {
          spans.add(TextSpan(text: t, style: c(_kNumber)));
        } else if (lineRaw) {
          final next = m.end < line.length ? line[m.end] : '';
          spans.add(
            TextSpan(text: t, style: next == '(' ? c(_kFunction) : base),
          );
        } else if (first && kDslKeywords.containsKey(t)) {
          spans.add(
            TextSpan(
              text: t,
              style: c(p.accent, w: FontWeight.w700),
            ),
          );
          if (_rawBlocks.contains(t)) lineRaw = true;
        } else if (kDslValues.containsKey(t)) {
          spans.add(TextSpan(text: t, style: c(_kType)));
        } else if (kDslKeywords.containsKey(t) && !first) {
          // Sub-keywords inside a statement: at, size, perms, role, count, width ...
          spans.add(TextSpan(text: t, style: c(p.accent.withOpacity(0.7))));
        } else {
          spans.add(TextSpan(text: t, style: base));
        }
        first = false;
      }
      if (pos < line.length) {
        final tail = line.substring(pos);
        final cm = _commentAt(tail);
        if (cm >= 0) {
          spans.add(TextSpan(text: tail.substring(0, cm), style: c(p.muted)));
          spans.add(
            TextSpan(
              text: tail.substring(cm),
              style: c(cComment, it: FontStyle.italic),
            ),
          );
        } else {
          spans.add(TextSpan(text: tail, style: c(p.muted)));
        }
      }
      // Track raw-block depth from the braces on this line (outside strings and comments).
      if (startsRaw && lineRaw && raw == 0) raw = 0;
      var depth = raw;
      var inStr = false;
      for (var i = 0; i < line.length; i++) {
        final ch = line[i];
        if (inStr) {
          if (ch == r'\') i++;
          if (i < line.length && line[i] == '"') inStr = false;
          continue;
        }
        if (ch == '"') {
          inStr = true;
        } else if (ch == '#' ||
            (ch == '/' && i + 1 < line.length && line[i + 1] == '/')) {
          break;
        } else if (ch == '{' && (lineRaw || depth > 0)) {
          depth++;
        } else if (ch == '}' && depth > 0) {
          depth--;
        }
      }
      raw = depth;
      if (li < lines.length - 1) spans.add(TextSpan(text: '\n', style: base));
    }
    return TextSpan(style: base, children: spans);
  }

  /// Index of a comment start (`#` or `//`) in [s], or -1.
  static int _commentAt(String s) {
    final h = s.indexOf('#');
    final d = s.indexOf('//');
    if (h < 0) return d;
    if (d < 0) return h;
    return h < d ? h : d;
  }
}

/// A code editor for `.cpu` text: line numbers, highlighting, keyword suggestions, brace-aware indentation, find and
/// replace, and the line shortcuts of the assembly editor. [errorLine] marks where the text does not parse.
class DslEditor extends StatefulWidget {
  const DslEditor({
    super.key,
    required this.controller,
    required this.fileName,
    required this.subtitle,
    this.errorLine,
    this.errorMessage,
    this.onChanged,
    this.onSubmit,
  });

  final DslEditingController controller;
  final String fileName;
  final String subtitle;

  /// 1-based line that failed to parse, with the message.
  final int? errorLine;
  final String? errorMessage;
  final VoidCallback? onChanged;

  /// Called for Mod+Enter.
  final VoidCallback? onSubmit;

  @override
  State<DslEditor> createState() => _DslEditorState();
}

class _DslEditorState extends State<DslEditor> {
  final ScrollController _vScroll = ScrollController();
  final ScrollController _hScroll = ScrollController();
  late final FocusNode _focus;
  final Object _tapGroup = Object();
  final double _charW = measureEditorChar();
  String _lastText = '';

  CompletionResult? _comp;
  int _compSel = 0;
  bool _suppress = false;

  bool _findOpen = false;
  bool _caseSensitive = false;
  int _focusTick = 0;
  final TextEditingController _findCtl = TextEditingController();
  final TextEditingController _replaceCtl = TextEditingController();
  List<TextRange> _matches = const [];
  int _matchIdx = 0;

  DslEditingController get _c => widget.controller;
  bool get _popupOpen => _comp != null && _comp!.items.isNotEmpty;
  int get _caret => _c.selection.isValid ? _c.selection.extentOffset : 0;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode(onKeyEvent: _onKey);
    _lastText = _c.text;
    _c.addListener(_onController);
  }

  @override
  void didUpdateWidget(DslEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onController);
    _vScroll.dispose();
    _hScroll.dispose();
    _focus.dispose();
    _findCtl.dispose();
    _replaceCtl.dispose();
    super.dispose();
  }

  // --- sync ---

  void _onController() {
    final text = _c.text;
    final changed = text != _lastText;
    _lastText = text;
    final sel = _c.selection;
    if (changed) {
      widget.onChanged?.call();
      if (_findOpen) _recompute();
      if (!_suppress && sel.isValid && sel.isCollapsed) {
        _updateCompletion();
      }
    } else if (_comp != null) {
      final r = _comp!;
      if (!sel.isCollapsed || _caret < r.start || _caret > r.end) _comp = null;
    }
    _suppress = false;
    if (_focus.hasFocus) _scheduleReveal(_caret);
    if (mounted) setState(() {});
  }

  void _apply(TextEditingValue v) {
    _suppress = true;
    _comp = null;
    _c.value = v.copyWith(composing: TextRange.empty);
  }

  void _scheduleReveal(int offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealOffset(offset);
    });
  }

  void _revealOffset(int offset) {
    final lc = EditorOps.lineCol(_c.text, offset);
    if (_vScroll.hasClients) {
      final top = 12 + (lc.line - 1) * kEditorLineHeight;
      final view = _vScroll.position.viewportDimension;
      final off = _vScroll.offset;
      double? target;
      if (top < off + 4) {
        target = top - 4;
      } else if (top + kEditorLineHeight > off + view - 8) {
        target = top + kEditorLineHeight - view + 8;
      }
      if (target != null) {
        _vScroll.jumpTo(target.clamp(0.0, _vScroll.position.maxScrollExtent));
      }
    }
    if (_hScroll.hasClients) {
      final x = 8 + (lc.col - 1) * _charW;
      final view = _hScroll.position.viewportDimension;
      final off = _hScroll.offset;
      double? target;
      if (x < off + 8) {
        target = x - 24;
      } else if (x > off + view - 40) {
        target = x - view + 60;
      }
      if (target != null) {
        _hScroll.jumpTo(target.clamp(0.0, _hScroll.position.maxScrollExtent));
      }
    }
  }

  // --- suggestions ---

  static final _word = RegExp(r'[A-Za-z_]');

  /// Keywords at the start of a statement; operand kinds and byte orders after the keywords that take them.
  CompletionResult _suggest(String text, int caret, {bool force = false}) {
    if (caret < 0 || caret > text.length) return CompletionResult.none;
    var start = caret;
    while (start > 0 && _word.hasMatch(text[start - 1])) {
      start--;
    }
    var end = caret;
    while (end < text.length && _word.hasMatch(text[end])) {
      end++;
    }
    final prefix = text.substring(start, caret);
    if (prefix.isEmpty && !force) return CompletionResult.none;
    final ls = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    final before = text.substring(ls, start);
    if (before.contains('#') || before.contains('//')) {
      return CompletionResult.none;
    }
    if ('"'.allMatches(before).length.isOdd) return CompletionResult.none;
    if (_insideRaw(text, ls)) return CompletionResult.none;

    final words = before.trim().isEmpty
        ? const <String>[]
        : before.trim().split(RegExp(r'\s+'));
    final pool = <CompletionItem>[];
    if (words.isEmpty) {
      for (final e in kDslKeywords.entries) {
        final i = e.value.indexOf('  ');
        pool.add(
          CompletionItem(
            label: e.key,
            kind: CompletionKind.mnemonic,
            insert: '${e.key} ',
            detail: i < 0 ? '' : e.value.substring(0, i),
            doc: i < 0 ? e.value : e.value.substring(i + 2),
          ),
        );
      }
    } else if (words.first == 'operand' && words.length == 2) {
      for (final k in ['reg', 'imm', 'pcrel']) {
        pool.add(
          CompletionItem(
            label: k,
            kind: CompletionKind.directive,
            doc: kDslValues[k]!,
          ),
        );
      }
    } else if (words.first == 'word' && words.length == 2) {
      for (final k in ['little', 'big']) {
        pool.add(
          CompletionItem(
            label: k,
            kind: CompletionKind.directive,
            doc: kDslValues[k]!,
          ),
        );
      }
    } else if (words.first == 'era' && words.length == 1) {
      for (final k in ['legacy', 'modern']) {
        pool.add(
          CompletionItem(
            label: k,
            kind: CompletionKind.directive,
            doc: kDslValues[k]!,
          ),
        );
      }
    }
    final p = prefix.toLowerCase();
    final items = [
      for (final i in pool)
        if (p.isEmpty || i.label.startsWith(p)) i,
    ];
    if (items.isEmpty) return CompletionResult.none;
    if (items.length == 1 && items.first.label == p && end == caret) {
      return CompletionResult.none;
    }
    return CompletionResult(start, end, items);
  }

  /// Whether the line starting at [lineStart] is inside the braces of an `exec`-like block.
  bool _insideRaw(String text, int lineStart) {
    var depth = 0;
    var rawFrom = -1; // depth at which a raw block opened
    for (final line in text.substring(0, lineStart).split('\n')) {
      final t = line.trim();
      final word = RegExp(r'^[A-Za-z_]+').stringMatch(t) ?? '';
      var inStr = false;
      for (var i = 0; i < t.length; i++) {
        final ch = t[i];
        if (inStr) {
          if (ch == r'\') i++;
          if (i < t.length && t[i] == '"') inStr = false;
          continue;
        }
        if (ch == '"') {
          inStr = true;
        } else if (ch == '#' ||
            (ch == '/' && i + 1 < t.length && t[i + 1] == '/')) {
          break;
        } else if (ch == '{') {
          if (rawFrom < 0 && _rawBlocks.contains(word)) rawFrom = depth;
          depth++;
        } else if (ch == '}') {
          depth--;
          if (rawFrom >= 0 && depth <= rawFrom) rawFrom = -1;
        }
      }
    }
    return rawFrom >= 0;
  }

  void _updateCompletion({bool force = false}) {
    final sel = _c.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      _comp = null;
      return;
    }
    final r = _suggest(_c.text, sel.extentOffset, force: force);
    _comp = r.items.isEmpty ? null : r;
    _compSel = 0;
  }

  void _accept(int i) {
    final r = _comp;
    if (r == null || i < 0 || i >= r.items.length) return;
    final text = _c.text;
    var insert = r.items[i].text;
    if (insert.endsWith(' ') && r.end < text.length && text[r.end] == ' ') {
      insert = insert.trimRight();
    }
    _apply(
      TextEditingValue(
        text: text.replaceRange(r.start, r.end, insert),
        selection: TextSelection.collapsed(offset: r.start + insert.length),
      ),
    );
    _focus.requestFocus();
    setState(() {});
  }

  // --- keyboard ---

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final hk = HardwareKeyboard.instance;
    final mod = Platform.isMac ? hk.isMetaPressed : hk.isControlPressed;
    final shift = hk.isShiftPressed;
    final alt = hk.isAltPressed;
    KeyEventResult done(VoidCallback f) {
      f();
      return KeyEventResult.handled;
    }

    if (_popupOpen) {
      final n = _comp!.items.length;
      if (k == LogicalKeyboardKey.arrowDown) {
        return done(() => setState(() => _compSel = (_compSel + 1) % n));
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        return done(() => setState(() => _compSel = (_compSel - 1 + n) % n));
      }
      if ((k == LogicalKeyboardKey.enter && !mod) ||
          k == LogicalKeyboardKey.numpadEnter ||
          (k == LogicalKeyboardKey.tab && !shift)) {
        return done(() => _accept(_compSel));
      }
      if (k == LogicalKeyboardKey.escape) {
        return done(() => setState(() => _comp = null));
      }
    }
    if (k == LogicalKeyboardKey.escape && _findOpen) return done(_closeFind);
    if (mod && k == LogicalKeyboardKey.enter && widget.onSubmit != null) {
      return done(widget.onSubmit!);
    }
    if (hk.isControlPressed && k == LogicalKeyboardKey.space) {
      return done(() => setState(() => _updateCompletion(force: true)));
    }
    final v = _c.value;
    if (k == LogicalKeyboardKey.tab && !mod && !alt) {
      return done(
        () => _apply(EditorOps.indent(v, outdent: shift, size: kDslTab)),
      );
    }
    if (mod && !alt && k == LogicalKeyboardKey.slash) {
      return done(() => _apply(EditorOps.toggleComment(v, '#')));
    }
    if (mod && !shift && !alt && k == LogicalKeyboardKey.keyD) {
      return done(() => _apply(EditorOps.duplicateLines(v)));
    }
    if (mod && shift && k == LogicalKeyboardKey.keyK) {
      return done(() => _apply(EditorOps.deleteLines(v)));
    }
    if (alt &&
        !mod &&
        (k == LogicalKeyboardKey.arrowUp ||
            k == LogicalKeyboardKey.arrowDown)) {
      return done(
        () =>
            _apply(EditorOps.moveLines(v, up: k == LogicalKeyboardKey.arrowUp)),
      );
    }
    if (mod && !alt && k == LogicalKeyboardKey.keyF) return done(_openFind);
    if (k == LogicalKeyboardKey.f3 && _findOpen) {
      return done(() => _step(shift ? -1 : 1));
    }
    return KeyEventResult.ignored;
  }

  // --- find / replace ---

  void _openFind() {
    final sel = _c.selection;
    setState(() {
      _findOpen = true;
      _focusTick++;
      if (sel.isValid && !sel.isCollapsed) {
        final t = sel.textInside(_c.text);
        if (!t.contains('\n')) _findCtl.text = t;
      }
      _findCtl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _findCtl.text.length,
      );
      _comp = null;
      _recompute();
    });
  }

  void _closeFind() {
    setState(() {
      _findOpen = false;
      _matches = const [];
    });
    _focus.requestFocus();
  }

  void _recompute() {
    _matches = EditorOps.findAll(
      _c.text,
      _findCtl.text,
      caseSensitive: _caseSensitive,
    );
    final at = _c.selection.isValid ? _c.selection.start : 0;
    final i = _matches.indexWhere((m) => m.start >= at);
    _matchIdx = _matches.isEmpty ? 0 : (i < 0 ? 0 : i);
  }

  void _select(int i) {
    if (_matches.isEmpty) return;
    _matchIdx = (i % _matches.length + _matches.length) % _matches.length;
    final m = _matches[_matchIdx];
    _c.selection = TextSelection(baseOffset: m.start, extentOffset: m.end);
    _scheduleReveal(m.start);
    setState(() {});
  }

  void _step(int d) => _select(_matchIdx + d);

  void _replaceCurrent() {
    if (_matches.isEmpty) return;
    final m = _matches[_matchIdx];
    final text = _c.text.replaceRange(m.start, m.end, _replaceCtl.text);
    _apply(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(
          offset: m.start + _replaceCtl.text.length,
        ),
      ),
    );
    setState(_recompute);
    if (_matches.isNotEmpty) _select(_matchIdx);
  }

  void _replaceAll() {
    if (_matches.isEmpty) return;
    var text = _c.text;
    for (final m in _matches.reversed) {
      text = text.replaceRange(m.start, m.end, _replaceCtl.text);
    }
    _apply(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(
          offset: _caret.clamp(0, text.length),
        ),
      ),
    );
    setState(_recompute);
  }

  void _gotoError() {
    final l = widget.errorLine;
    if (l == null) return;
    final off = EditorOps.lineStart(_c.text, l);
    _c.selection = TextSelection.collapsed(offset: off);
    _focus.requestFocus();
    _scheduleReveal(off);
  }

  // --- build ---

  Rect _cell(int offset, int length) {
    final lc = EditorOps.lineCol(_c.text, offset);
    return Rect.fromLTWH(
      8 + (lc.col - 1) * _charW,
      12 + (lc.line - 1) * kEditorLineHeight,
      length * _charW,
      kEditorLineHeight,
    );
  }

  Widget _box(Rect r, Color c, {Color? border}) => Positioned(
    left: r.left,
    top: r.top,
    width: r.width,
    height: r.height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(2),
        border: border == null ? null : Border.all(color: border),
      ),
    ),
  );

  CompletionItem? _hint(String text) {
    final lc = EditorOps.lineCol(text, _caret);
    final start = EditorOps.lineStart(text, lc.line);
    var end = text.indexOf('\n', start);
    if (end < 0) end = text.length;
    final m = RegExp(r'^\s*([A-Za-z_]+)')
        .firstMatch(text.substring(start, end));
    final w = m?.group(1);
    if (w == null || !kDslKeywords.containsKey(w)) return null;
    final v = kDslKeywords[w]!;
    final i = v.indexOf('  ');
    return CompletionItem(
      label: w,
      kind: CompletionKind.mnemonic,
      detail: i < 0 ? '' : v.substring(0, i),
      doc: i < 0 ? v : v.substring(i + 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final hasError = widget.errorLine != null;
    final text = _c.text;
    final sel = _c.selection;
    final lc = EditorOps.lineCol(text, _caret);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorHeader(
          fileName: widget.fileName,
          processorName: widget.subtitle,
          problems: hasError ? 1 : 0,
          onProblems: _gotoError,
          onFind: _openFind,
          findShortcut: Platform.isMac ? '⌘F' : 'Ctrl+F',
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _editor(p, text, sel)),
              if (_findOpen)
                Positioned(
                  top: 10,
                  right: 18,
                  child: FindBar(
                    find: _findCtl,
                    replace: _replaceCtl,
                    focusTick: _focusTick,
                    matchCount: _matches.length,
                    matchIndex: _matchIdx,
                    caseSensitive: _caseSensitive,
                    onQuery: (_) {
                      setState(_recompute);
                      if (_matches.isNotEmpty) _select(_matchIdx);
                    },
                    onNext: () => _step(1),
                    onPrev: () => _step(-1),
                    onReplace: _replaceCurrent,
                    onReplaceAll: _replaceAll,
                    onToggleCase: () => setState(() {
                      _caseSensitive = !_caseSensitive;
                      _recompute();
                    }),
                    onClose: _closeFind,
                  ),
                ),
            ],
          ),
        ),
        EditorStatus(
          line: lc.line,
          col: lc.col,
          selected: sel.isValid ? sel.end - sel.start : 0,
          lines: '\n'.allMatches(text).length + 1,
          hint: _hint(text),
          tabSize: kDslTab,
        ),
      ],
    );
  }

  Widget _editor(Pal p, String text, TextSelection sel) {
    final lines = text.split('\n');
    final maxLen = lines.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    final caretLine = EditorOps.lineCol(text, _caret).line;
    final errLine = widget.errorLine;
    final height = lines.length * kEditorLineHeight + 24 + 260;
    final bracket = sel.isValid && sel.isCollapsed
        ? EditorOps.matchingBracket(text, sel.extentOffset)
        : null;

    return LayoutBuilder(
      builder: (context, c) {
        final viewport = (c.maxWidth - EditorGutter.width).clamp(
          100.0,
          double.infinity,
        );
        final contentW = (maxLen + 8) * _charW + 24;
        final width = contentW > viewport ? contentW : viewport;

        Widget? popup;
        if (_popupOpen) {
          final r = _comp!;
          final lc = EditorOps.lineCol(text, r.start);
          final h = CompletionPopup.heightFor(r.items, _compSel);
          final hOff = _hScroll.hasClients ? _hScroll.offset : 0.0;
          final vOff = _vScroll.hasClients ? _vScroll.offset : 0.0;
          var left = EditorGutter.width + 8 + (lc.col - 1) * _charW - hOff - 30;
          left = left.clamp(
            EditorGutter.width,
            (c.maxWidth - CompletionPopup.width - 8).clamp(
              EditorGutter.width,
              double.infinity,
            ),
          );
          var top = 12 + lc.line * kEditorLineHeight + 2;
          if (top - vOff + h > c.maxHeight) {
            top = 12 + (lc.line - 1) * kEditorLineHeight - h - 2;
          }
          popup = Positioned(
            left: left,
            top: top,
            child: CompletionPopup(
              items: _comp!.items,
              selected: _compSel,
              tapGroup: _tapGroup,
              onPick: _accept,
            ),
          );
        }

        Widget band(int line, Color color) => Positioned(
          top: 12 + (line - 1) * kEditorLineHeight,
          left: 0,
          right: 0,
          height: kEditorLineHeight,
          child: ColoredBox(color: color),
        );

        // Faint guides at every indent step.
        final guides = <Widget>[];
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (l.trim().isEmpty) continue;
          var n = 0;
          while (n < l.length && l[n] == ' ') {
            n++;
          }
          for (var col = kDslTab; col <= n; col += kDslTab) {
            guides.add(
              Positioned(
                left: 8 + (col - kDslTab) * _charW,
                top: 12 + i * kEditorLineHeight,
                width: 1,
                height: kEditorLineHeight,
                child: ColoredBox(color: p.text.withOpacity(0.07)),
              ),
            );
          }
        }

        final err = widget.errorMessage;
        Widget? errMark;
        if (errLine != null && errLine >= 1 && errLine <= lines.length) {
          final l = lines[errLine - 1];
          final lead = l.length - l.trimLeft().length;
          final trimmed = l.trimRight();
          final left = 8 + (trimmed.length + 3) * _charW;
          errMark = Positioned.fill(
            child: Stack(
              children: [
                if (trimmed.length > lead)
                  Positioned(
                    left: 8 + lead * _charW,
                    top: 12 + errLine * kEditorLineHeight - 5,
                    width: (trimmed.length - lead) * _charW,
                    height: 4,
                    child: CustomPaint(painter: SquigglePainter(p.err)),
                  ),
                if (err != null && width - left - 12 > 60)
                  Positioned(
                    left: left,
                    top: 12 + (errLine - 1) * kEditorLineHeight,
                    width: width - left - 12,
                    height: kEditorLineHeight,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          err,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: p.err.withOpacity(0.8),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        return Container(
          color: p.field,
          child: TextSelectionTheme(
            data: TextSelectionThemeData(
              cursorColor: p.accent,
              selectionColor: p.accent.withOpacity(0.28),
            ),
            child: Scrollbar(
              controller: _vScroll,
              child: SingleChildScrollView(
                controller: _vScroll,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  height: height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      band(caretLine, p.text.withOpacity(0.04)),
                      if (errLine != null)
                        band(errLine, p.err.withOpacity(0.07)),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          EditorGutter(
                            lineCount: lines.length,
                            current: null,
                            caretLine: caretLine,
                            breakpoints: const {},
                            errors: {?errLine: err ?? 'Error'},
                            onToggle: (_) {},
                            breakpointsEnabled: false,
                          ),
                          Expanded(
                            child: Scrollbar(
                              controller: _hScroll,
                              child: SingleChildScrollView(
                                controller: _hScroll,
                                scrollDirection: Axis.horizontal,
                                physics: const ClampingScrollPhysics(),
                                child: SizedBox(
                                  width: width,
                                  child: Stack(
                                    children: [
                                      ...guides,
                                      if (_findOpen)
                                        for (
                                          var i = 0;
                                          i < _matches.length && i < 400;
                                          i++
                                        )
                                          _box(
                                            _cell(
                                              _matches[i].start,
                                              _matches[i].end -
                                                  _matches[i].start,
                                            ),
                                            p.warn.withOpacity(
                                              i == _matchIdx ? 0.45 : 0.2,
                                            ),
                                          ),
                                      if (bracket != null) ...[
                                        _box(
                                          _cell(bracket.a, 1),
                                          p.accent.withOpacity(0.18),
                                          border: p.accent.withOpacity(0.6),
                                        ),
                                        _box(
                                          _cell(bracket.b, 1),
                                          p.accent.withOpacity(0.18),
                                          border: p.accent.withOpacity(0.6),
                                        ),
                                      ],
                                      ?errMark,
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 12,
                                          left: 8,
                                          right: 16,
                                        ),
                                        child: TextField(
                                          controller: _c,
                                          focusNode: _focus,
                                          groupId: _tapGroup,
                                          maxLines: null,
                                          keyboardType: TextInputType.multiline,
                                          cursorColor: p.accent,
                                          cursorHeight: kEditorFontSize + 2,
                                          scrollPhysics:
                                              const NeverScrollableScrollPhysics(),
                                          inputFormatters: const [
                                            _TabsToSpaces(),
                                            AssistFormatter(
                                              unit: kDslTab,
                                              blocks: true,
                                            ),
                                          ],
                                          strutStyle: const StrutStyle(
                                            fontSize: kEditorFontSize,
                                            height:
                                                kEditorLineHeight /
                                                kEditorFontSize,
                                            forceStrutHeight: true,
                                          ),
                                          style: kEditorTextStyle,
                                          decoration:
                                              const InputDecoration.collapsed(
                                                hintText: '',
                                              ),
                                          enableSuggestions: false,
                                          autocorrect: false,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      ?popup,
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Pasted tabs become two spaces.
class _TabsToSpaces extends TextInputFormatter {
  const _TabsToSpaces();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.text.contains('\t')) return newValue;
    final n = '\t'
        .allMatches(
          newValue.text.substring(
            0,
            newValue.selection.end.clamp(0, newValue.text.length),
          ),
        )
        .length;
    return TextEditingValue(
      text: newValue.text.replaceAll('\t', ' ' * kDslTab),
      selection: TextSelection.collapsed(
        offset: newValue.selection.end + n * (kDslTab - 1),
      ),
    );
  }
}

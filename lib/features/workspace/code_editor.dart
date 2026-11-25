import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/core/model/models.dart' show AppSettings;
import 'package:dot_asm/core/sim/spec/processor_spec.dart';
import 'package:dot_asm/features/workspace/editor_logic.dart';
import 'package:dot_asm/features/workspace/editor_parts.dart';
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/theme.dart';

/// A text controller that colours assembly source for a given processor.
class AsmEditingController extends TextEditingController {
  AsmEditingController({super.text, required ProcessorSpec spec}) {
    setSpec(spec);
  }

  late CompletionIndex index;
  Set<String> labels = {};
  List<String> comments = const ['#'];

  void setSpec(ProcessorSpec spec) {
    index = CompletionIndex(spec);
    comments = index.comments;
  }

  static final _tokenRe = RegExp(
    r'''("(?:[^"\\]|\\.)*")|(0[xX][0-9a-fA-F_]+|0[bB][01_]+|\b\d+\b)|([A-Za-z_.$%][A-Za-z0-9_.$]*:?)''',
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
    final cText = p.muted.withOpacity(0.85);
    final cLabel = p.warn;
    final cDirective = const Color(0xFFB48EAD);
    final cMnemonic = p.accent;
    final cReg = p.ok;
    final cNum = const Color(0xFFD08770);
    final cStr = const Color(0xFFA3BE8C);

    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    for (var li = 0; li < lines.length; li++) {
      final line = lines[li];
      // Find the comment start (outside strings).
      var cut = line.length;
      var inStr = false;
      for (var i = 0; i < line.length; i++) {
        final c = line[i];
        if (inStr) {
          if (c == r'\') {
            i++;
          } else if (c == '"') {
            inStr = false;
          }
          continue;
        }
        if (c == '"') {
          inStr = true;
          continue;
        }
        if (comments.any((cm) => line.startsWith(cm, i))) {
          cut = i;
          break;
        }
      }
      final code = line.substring(0, cut);
      var pos = 0;
      var firstWord = true;
      for (final m in _tokenRe.allMatches(code)) {
        if (m.start > pos) {
          spans.add(TextSpan(text: code.substring(pos, m.start), style: base));
        }
        final t = m.group(0)!;
        Color color = base.color!;
        if (m.group(1) != null) {
          color = cStr;
        } else if (m.group(2) != null) {
          color = cNum;
        } else {
          if (t.endsWith(':')) {
            color = cLabel;
          } else if (t.startsWith('.')) {
            color = cDirective;
          } else if (index.isRegister(t)) {
            color = cReg;
          } else if (firstWord && index.isMnemonic(t)) {
            color = cMnemonic;
          } else if (labels.contains(t)) {
            color = cLabel;
          } else if (t.startsWith('%')) {
            color = cNum;
          }
          if (!t.endsWith(':')) firstWord = false;
        }
        spans.add(
          TextSpan(
            text: t,
            style: base.copyWith(color: color),
          ),
        );
        pos = m.end;
      }
      if (pos < code.length) {
        spans.add(TextSpan(text: code.substring(pos), style: base));
      }
      if (cut < line.length) {
        spans.add(
          TextSpan(
            text: line.substring(cut),
            style: base.copyWith(color: cText, fontStyle: FontStyle.italic),
          ),
        );
      }
      if (li < lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: base));
      }
    }
    return TextSpan(style: base, children: spans);
  }
}

/// Source editor: syntax colouring, line numbers, breakpoints, suggestions, find and replace, and the usual editing
/// shortcuts (indent, comment, duplicate, move and delete lines, bracket matching).
class CodeEditor extends StatefulWidget {
  const CodeEditor({super.key, required this.state});
  final AppState state;

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  late AsmEditingController _controller;
  final ScrollController _vScroll = ScrollController();
  final ScrollController _hScroll = ScrollController();
  late final FocusNode _focus;
  final Object _tapGroup = Object();
  double get _charW => EditorMetrics.charWidth;
  int _revision = -1;
  AppSettings? _settingsSeen;
  String _lastText = '';

  // Suggestions
  CompletionResult? _comp;
  int _compSel = 0;
  bool _suppressPopup = false;

  // Find / replace
  bool _findOpen = false;
  bool _caseSensitive = false;
  int _focusTick = 0;
  final TextEditingController _findCtl = TextEditingController();
  final TextEditingController _replaceCtl = TextEditingController();
  List<TextRange> _matches = const [];
  int _matchIdx = 0;

  AppState get state => widget.state;
  bool get _popupOpen => _comp != null && _comp!.items.isNotEmpty;
  int get _caret =>
      _controller.selection.isValid ? _controller.selection.extentOffset : 0;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode(onKeyEvent: _onKey);
    _controller = AsmEditingController(
      text: state.source,
      spec: state.activeProcessor!,
    );
    _lastText = _controller.text;
    _controller.labels = CompletionIndex.labelsIn(_lastText);
    _revision = state.sourceRevision;
    _controller.addListener(_onController);
    state.addListener(_onState);
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    _controller.dispose();
    _vScroll.dispose();
    _hScroll.dispose();
    _focus.dispose();
    _findCtl.dispose();
    _replaceCtl.dispose();
    super.dispose();
  }

  // --- Controller / state sync ---

  void _onController() {
    final text = _controller.text;
    final changed = text != _lastText;
    _lastText = text;
    if (changed) {
      state.onSourceChanged(text);
      _controller.labels = CompletionIndex.labelsIn(text);
      if (_findOpen) _recomputeMatches();
    }
    final sel = _controller.selection;
    if (changed &&
        !_suppressPopup &&
        state.settings.autoSuggest &&
        sel.isValid &&
        sel.isCollapsed) {
      _updateCompletion();
    } else if (!changed && _comp != null) {
      // Moving the caret out of the word closes the list.
      final r = _comp!;
      if (!sel.isCollapsed || _caret < r.start || _caret > r.end) _comp = null;
    }
    _suppressPopup = false;
    if (_focus.hasFocus) _scheduleReveal(_caret);
    if (mounted) setState(() {});
  }

  void _onState() {
    // Preferences (tab size, guides ...) apply to the open editor as soon as they change.
    if (mounted && _settingsSeen != state.settings) {
      _settingsSeen = state.settings;
      setState(() {});
    }
    if (_revision != state.sourceRevision) {
      _revision = state.sourceRevision;
      final spec = state.activeProcessor;
      if (spec != null) _controller.setSpec(spec);
      _controller.removeListener(_onController);
      _controller.text = state.source;
      _lastText = _controller.text;
      _controller.labels = CompletionIndex.labelsIn(_lastText);
      _controller.addListener(_onController);
      _comp = null;
      if (_findOpen) _recomputeMatches();
      if (mounted) setState(() {});
    }
  }

  void _apply(TextEditingValue v) {
    _suppressPopup = true;
    _comp = null;
    _controller.value = v.copyWith(composing: TextRange.empty);
  }

  // --- Scrolling ---

  /// Scrolls the current execution line into view.
  void _reveal(int line) {
    if (!_vScroll.hasClients) return;
    final top = (line - 1) * kEditorLineHeight;
    final view = _vScroll.position.viewportDimension;
    final off = _vScroll.offset;
    if (top < off + 8 || top > off + view - kEditorLineHeight * 2) {
      _vScroll.animateTo(
        (top - view / 3).clamp(0.0, _vScroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    }
  }

  void _scheduleReveal(int offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealOffset(offset);
    });
  }

  /// Keeps the text position [offset] inside the viewport.
  void _revealOffset(int offset) {
    final lc = EditorOps.lineCol(_controller.text, offset);
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

  // --- Suggestions ---

  void _updateCompletion({bool force = false}) {
    final sel = _controller.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      _comp = null;
      return;
    }
    final r = _controller.index.suggest(
      _controller.text,
      sel.extentOffset,
      labels: _controller.labels,
      force: force,
    );
    _comp = r.items.isEmpty ? null : r;
    _compSel = 0;
  }

  void _accept(int i) {
    final r = _comp;
    if (r == null || i < 0 || i >= r.items.length) return;
    final text = _controller.text;
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

  // --- Keyboard ---

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
      if (k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.numpadEnter ||
          (k == LogicalKeyboardKey.tab && !shift)) {
        return done(() => _accept(_compSel));
      }
      if (k == LogicalKeyboardKey.escape) {
        return done(() => setState(() => _comp = null));
      }
    }
    if (k == LogicalKeyboardKey.escape && _findOpen) {
      return done(_closeFind);
    }
    if (hk.isControlPressed && k == LogicalKeyboardKey.space) {
      return done(() => setState(() => _updateCompletion(force: true)));
    }
    final v = _controller.value;
    if (k == LogicalKeyboardKey.tab && !mod && !alt) {
      return done(
        () => _apply(
          EditorOps.indent(
            v,
            outdent: shift,
            size: state.settings.editorTabSize,
          ),
        ),
      );
    }
    if (mod && !alt && k == LogicalKeyboardKey.slash) {
      return done(() {
        final marker = _controller.comments.first;
        _apply(EditorOps.toggleComment(v, marker));
      });
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
    if (mod && !alt && k == LogicalKeyboardKey.keyF) {
      return done(_openFind);
    }
    if (k == LogicalKeyboardKey.f3 && _findOpen) {
      return done(() => shift ? _step(-1) : _step(1));
    }
    return KeyEventResult.ignored;
  }

  // --- Find / replace ---

  void _openFind() {
    final sel = _controller.selection;
    setState(() {
      _findOpen = true;
      _focusTick++;
      if (sel.isValid && !sel.isCollapsed) {
        final t = sel.textInside(_controller.text);
        if (!t.contains('\n')) _findCtl.text = t;
      }
      _findCtl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _findCtl.text.length,
      );
      _comp = null;
      _recomputeMatches();
    });
  }

  void _closeFind() {
    setState(() {
      _findOpen = false;
      _matches = const [];
    });
    _focus.requestFocus();
  }

  void _recomputeMatches() {
    _matches = EditorOps.findAll(
      _controller.text,
      _findCtl.text,
      caseSensitive: _caseSensitive,
    );
    final at = _controller.selection.isValid ? _controller.selection.start : 0;
    final i = _matches.indexWhere((m) => m.start >= at);
    _matchIdx = _matches.isEmpty ? 0 : (i < 0 ? 0 : i);
  }

  void _onQuery(String _) {
    setState(_recomputeMatches);
    if (_matches.isNotEmpty) _select(_matchIdx);
  }

  void _select(int i) {
    if (_matches.isEmpty) return;
    _matchIdx = (i % _matches.length + _matches.length) % _matches.length;
    final m = _matches[_matchIdx];
    _controller.selection = TextSelection(
      baseOffset: m.start,
      extentOffset: m.end,
    );
    _scheduleReveal(m.start);
    setState(() {});
  }

  void _step(int d) => _select(_matchIdx + d);

  void _replaceCurrent() {
    if (_matches.isEmpty) return;
    final m = _matches[_matchIdx];
    final text = _controller.text.replaceRange(
      m.start,
      m.end,
      _replaceCtl.text,
    );
    final next = m.start + _replaceCtl.text.length;
    _apply(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: next),
      ),
    );
    setState(_recomputeMatches);
    if (_matches.isNotEmpty) _select(_matchIdx);
  }

  void _replaceAll() {
    if (_matches.isEmpty) return;
    var text = _controller.text;
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
    setState(_recomputeMatches);
  }

  // --- Build ---

  Rect _cellRect(int offset, int length) {
    final lc = EditorOps.lineCol(_controller.text, offset);
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

  /// The instruction or directive at the start of the caret's line, for the status strip.
  CompletionItem? _hint(String text) {
    final lc = EditorOps.lineCol(text, _caret);
    final start = EditorOps.lineStart(text, lc.line);
    var end = text.indexOf('\n', start);
    if (end < 0) end = text.length;
    var line = text.substring(start, end);
    line = line.replaceFirst(RegExp(r'^\s*[A-Za-z_.$][\w.$]*\s*:'), '');
    final m = RegExp(r'^\s*([A-Za-z_.][\w.]*)').firstMatch(line);
    if (m == null) return null;
    return _controller.index.describe(m.group(1)!);
  }

  /// Moves the caret to the first line with a problem.
  void _gotoFirstProblem() {
    final errs = state.sim.errors;
    if (errs.isEmpty) return;
    final line = errs.map((e) => e.line).reduce((a, b) => a < b ? a : b);
    final off = EditorOps.lineStart(_controller.text, line);
    _controller.selection = TextSelection.collapsed(offset: off);
    _focus.requestFocus();
    _scheduleReveal(off);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mod = Platform.isMac ? '⌘F' : 'Ctrl+F';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: state.sim,
          builder: (context, _) => EditorHeader(
            fileName: state.activeProject?.config.source ?? 'main.s',
            processorName: state.activeProcessor?.name ?? '',
            problems: state.sim.errors.length,
            onProblems: _gotoFirstProblem,
            onFind: _openFind,
            findShortcut: mod,
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _buildEditor(p)),
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
                    onQuery: _onQuery,
                    onNext: () => _step(1),
                    onPrev: () => _step(-1),
                    onReplace: _replaceCurrent,
                    onReplaceAll: _replaceAll,
                    onToggleCase: () {
                      setState(() {
                        _caseSensitive = !_caseSensitive;
                        _recomputeMatches();
                      });
                    },
                    onClose: _closeFind,
                  ),
                ),
            ],
          ),
        ),
        _buildStatus(),
      ],
    );
  }

  Widget _buildStatus() {
    final text = _controller.text;
    final sel = _controller.selection;
    final lc = EditorOps.lineCol(text, _caret);
    return EditorStatus(
      line: lc.line,
      col: lc.col,
      selected: sel.isValid ? sel.end - sel.start : 0,
      lines: '\n'.allMatches(text).length + 1,
      hint: _hint(text),
      tabSize: state.settings.editorTabSize,
    );
  }

  /// Faint vertical lines at every indent step, so nesting is easy to follow.
  List<Widget> _indentGuides(List<String> lines, Pal p) {
    final out = <Widget>[];
    if (!state.settings.indentGuides) return out;
    final tab = state.settings.editorTabSize;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.trim().isEmpty) continue;
      var n = 0;
      while (n < l.length && l[n] == ' ') {
        n++;
      }
      for (var c = tab; c <= n; c += tab) {
        out.add(
          Positioned(
            left: 8 + (c - tab) * _charW,
            top: 12 + i * kEditorLineHeight,
            width: 1,
            height: kEditorLineHeight,
            child: ColoredBox(color: p.text.withOpacity(0.07)),
          ),
        );
      }
    }
    return out;
  }

  /// Wavy underlines under the lines the assembler rejected, with its message after the code.
  List<Widget> _problemMarks(List<String> lines, Pal p, double areaWidth) {
    final out = <Widget>[];
    final seen = <int>{};
    for (final e in state.sim.errors) {
      if (e.line < 1 || e.line > lines.length || !seen.add(e.line)) continue;
      final l = lines[e.line - 1];
      final lead = l.length - l.trimLeft().length;
      final trimmed = l.trimRight();
      if (trimmed.length > lead) {
        out.add(
          Positioned(
            left: 8 + lead * _charW,
            top: 12 + e.line * kEditorLineHeight - 5,
            width: (trimmed.length - lead) * _charW,
            height: 4,
            child: CustomPaint(painter: SquigglePainter(p.err)),
          ),
        );
      }
      final left = 8 + (trimmed.length + 3) * _charW;
      final room = areaWidth - left - 12;
      if (room > 60) {
        out.add(
          Positioned(
            left: left,
            top: 12 + (e.line - 1) * kEditorLineHeight,
            width: room,
            height: kEditorLineHeight,
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  e.message,
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
        );
      }
    }
    return out;
  }

  Widget _buildEditor(Pal p) {
    return ListenableBuilder(
      listenable: state.sim,
      builder: (context, _) {
        final sim = state.sim;
        final text = _controller.text;
        final lines = text.split('\n');
        final lineCount = lines.length;
        final maxLen = lines.fold<int>(
          0,
          (m, l) => l.length > m ? l.length : m,
        );
        final caretLc = EditorOps.lineCol(text, _caret);
        final current = sim.currentLine;
        final errorByLine = {
          for (final e in sim.errors.reversed) e.line: e.message,
        };
        if (current != null && sim.running == false && !_focus.hasFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _reveal(current);
          });
        }
        final height = lineCount * kEditorLineHeight + 24 + 260;
        final sel = _controller.selection;
        final bracket = sel.isValid && sel.isCollapsed
            ? EditorOps.matchingBracket(text, sel.extentOffset)
            : null;

        return LayoutBuilder(
          builder: (context, c) {
            final textViewport = (c.maxWidth - EditorGutter.width).clamp(
              100.0,
              double.infinity,
            );
            final contentW = (maxLen + 8) * _charW + 24;
            final width = contentW > textViewport ? contentW : textViewport;

            // The suggestion list sits under the word being typed.
            Widget? popup;
            if (_popupOpen) {
              final r = _comp!;
              final lc = EditorOps.lineCol(text, r.start);
              final h = CompletionPopup.heightFor(r.items, _compSel);
              final hOff = _hScroll.hasClients ? _hScroll.offset : 0.0;
              final vOff = _vScroll.hasClients ? _vScroll.offset : 0.0;
              var left =
                  EditorGutter.width + 8 + (lc.col - 1) * _charW - hOff - 30;
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
                  items: r.items,
                  selected: _compSel,
                  tapGroup: _tapGroup,
                  onPick: _accept,
                ),
              );
            }

            Widget band(int line, Color color, {bool bar = false}) =>
                Positioned(
                  top: 12 + (line - 1) * kEditorLineHeight,
                  left: 0,
                  right: 0,
                  height: kEditorLineHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: bar ? null : color,
                      gradient: bar
                          ? LinearGradient(
                              colors: [color, color.withOpacity(0.02)],
                            )
                          : null,
                      border: bar
                          ? Border(left: BorderSide(color: p.accent, width: 3))
                          : null,
                    ),
                  ),
                );

            return Container(
              color: p.field,
              child: TextSelectionTheme(
                data: TextSelectionThemeData(
                  cursorColor: p.accent,
                  selectionColor: p.accent.withOpacity(0.28),
                ),
                child: Scrollbar(
                  controller: _vScroll,
                  thumbVisibility: false,
                  child: SingleChildScrollView(
                    controller: _vScroll,
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(
                      height: height,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          band(caretLc.line, p.text.withOpacity(0.04)),
                          if (current != null)
                            band(
                              current,
                              p.accent.withOpacity(0.13),
                              bar: true,
                            ),
                          for (final l in {for (final e in sim.errors) e.line})
                            band(l, p.err.withOpacity(0.07)),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              EditorGutter(
                                lineCount: lineCount,
                                current: current,
                                caretLine: caretLc.line,
                                breakpoints: sim.breakpoints,
                                errors: errorByLine,
                                onToggle: sim.toggleBreakpoint,
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
                                          ..._indentGuides(lines, p),
                                          if (_findOpen)
                                            for (
                                              var i = 0;
                                              i < _matches.length && i < 400;
                                              i++
                                            )
                                              _box(
                                                _cellRect(
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
                                              _cellRect(bracket.a, 1),
                                              p.accent.withOpacity(0.18),
                                              border: p.accent.withOpacity(0.6),
                                            ),
                                            _box(
                                              _cellRect(bracket.b, 1),
                                              p.accent.withOpacity(0.18),
                                              border: p.accent.withOpacity(0.6),
                                            ),
                                          ],
                                          ..._problemMarks(lines, p, width),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 12,
                                              left: 8,
                                              right: 16,
                                            ),
                                            child: TextField(
                                              controller: _controller,
                                              focusNode: _focus,
                                              groupId: _tapGroup,
                                              maxLines: null,
                                              keyboardType:
                                                  TextInputType.multiline,
                                              cursorColor: p.accent,
                                              cursorHeight: kEditorFontSize + 2,
                                              scrollPhysics:
                                                  const NeverScrollableScrollPhysics(),
                                              inputFormatters: [
                                                FilteringTextInputFormatter.deny(
                                                  RegExp(r'\t'),
                                                  replacementString: '    ',
                                                ),
                                                AssistFormatter(
                                                  unit: state
                                                      .settings
                                                      .editorTabSize,
                                                  pairs: state
                                                      .settings
                                                      .autoClosePairs,
                                                ),
                                              ],
                                              strutStyle: EditorMetrics.strut,
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
      },
    );
  }
}

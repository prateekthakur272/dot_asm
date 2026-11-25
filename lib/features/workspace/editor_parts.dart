import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/selectable_row.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/features/workspace/editor_logic.dart';
import 'package:dot_asm/theme/theme.dart';

/// The editor's font size and what follows from it. The size comes from Preferences; the line height, the width of a
/// character (the font is monospaced, so overlays can be positioned by line and column) and the text styles are derived
/// from it. [AppShell] applies the preference before the editors build.
class EditorMetrics {
  const EditorMetrics._();

  /// Sizes offered in Preferences.
  static const List<int> sizes = [11, 12, 13, 14, 15, 16, 18];
  static const double defaultSize = 13;

  static double fontSize = defaultSize;

  /// 13 gives 20, the size the layout was drawn for.
  static double get lineHeight => (fontSize * 20 / 13).roundToDouble();

  /// The editor's text style. A font list must be passed as fallbacks: a comma separated string is read as one name.
  static TextStyle get textStyle => TextStyle(
    fontFamily: kMonoFamily,
    fontFamilyFallback: kMonoFallback,
    fontSize: fontSize,
    height: lineHeight / fontSize,
  );

  /// Forces every line to the same height whatever glyphs it holds.
  static StrutStyle get strut => StrutStyle(
    fontSize: fontSize,
    height: lineHeight / fontSize,
    forceStrutHeight: true,
  );

  static final Map<double, double> _widths = {};

  /// Width of one character of the editor font.
  static double get charWidth => _widths.putIfAbsent(fontSize, () {
    final tp = TextPainter(
      text: TextSpan(text: 'MMMMMMMMMM', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width / 10;
  });
}

double get kEditorFontSize => EditorMetrics.fontSize;
double get kEditorLineHeight => EditorMetrics.lineHeight;
TextStyle get kEditorTextStyle => EditorMetrics.textStyle;

// ---------------------------------------------------------------------------------------------------------------
// Gutter

class EditorGutter extends StatelessWidget {
  const EditorGutter({
    super.key,
    required this.lineCount,
    required this.current,
    required this.caretLine,
    required this.breakpoints,
    required this.errors,
    required this.onToggle,
    this.breakpointsEnabled = true,
  });

  /// Wide enough for a four-digit line number at the current font size.
  static double get width =>
      56 + (EditorMetrics.fontSize - 13).clamp(0.0, 6.0) * 3;

  /// False for editors that have nothing to break on: no hover dot, no click.
  final bool breakpointsEnabled;

  final int lineCount;
  final int? current;
  final int caretLine;
  final Set<int> breakpoints;
  final Map<int, String> errors;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            for (var line = 1; line <= lineCount; line++)
              HoverBuilder(
                cursor: breakpointsEnabled
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                onTap: breakpointsEnabled ? () => onToggle(line) : null,
                builder: (context, hovered) {
                  final isBp = breakpoints.contains(line);
                  final isErr = errors.containsKey(line);
                  final isCur = current == line;
                  final isCaret = caretLine == line;
                  Widget? marker;
                  if (isBp) {
                    marker = Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: p.err,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: p.err.withOpacity(0.5),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                    );
                  } else if (isErr) {
                    marker = Tooltip(
                      message: errors[line]!,
                      child: Icon(Icons.error_rounded, size: 12, color: p.err),
                    );
                  } else if (hovered && breakpointsEnabled) {
                    marker = Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: p.err.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                    );
                  }
                  return SizedBox(
                    height: kEditorLineHeight,
                    child: Row(
                      children: [
                        SizedBox(width: 22, child: Center(child: marker)),
                        Expanded(
                          child: Transform.translate(
                            offset: const Offset(0, 1.5),
                            child: Text(
                              '$line',
                              textAlign: TextAlign.right,
                              strutStyle: EditorMetrics.strut,
                              style: TextStyle(
                                fontFamily: kMonoFamily,
                                fontFamilyFallback: kMonoFallback,
                                fontSize: kEditorFontSize - 1.5,
                                height: kEditorLineHeight / kEditorFontSize,
                                color: isCur
                                    ? p.accent
                                    : (isCaret
                                          ? p.text
                                          : p.muted.withOpacity(0.55)),
                                fontWeight: isCur || isCaret
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Completion popup

class CompletionPopup extends StatefulWidget {
  const CompletionPopup({
    super.key,
    required this.items,
    required this.selected,
    required this.onPick,
    required this.tapGroup,
  });

  static const double rowHeight = 24;
  static const int maxRows = 8;
  static const double width = 380;
  static const double docHeight = 40;

  final List<CompletionItem> items;
  final int selected;
  final ValueChanged<int> onPick;
  final Object tapGroup;

  /// Height of the popup for [items].
  static double heightFor(List<CompletionItem> items, int selected) {
    final rows = items.length.clamp(1, maxRows);
    final hasDoc =
        selected >= 0 &&
        selected < items.length &&
        items[selected].doc.isNotEmpty;
    return rows * rowHeight + (hasDoc ? docHeight : 0) + 2;
  }

  @override
  State<CompletionPopup> createState() => _CompletionPopupState();
}

class _CompletionPopupState extends State<CompletionPopup> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(CompletionPopup old) {
    super.didUpdateWidget(old);
    if (!_scroll.hasClients) return;
    final top = widget.selected * CompletionPopup.rowHeight;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + CompletionPopup.rowHeight > _scroll.offset + view) {
      _scroll.jumpTo(top + CompletionPopup.rowHeight - view);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static (String, Color Function(Pal)) _badge(CompletionKind k) => switch (k) {
    CompletionKind.mnemonic => ('I', (p) => p.accent),
    CompletionKind.register => ('R', (p) => p.ok),
    CompletionKind.directive => ('D', (_) => const Color(0xFFB48EAD)),
    CompletionKind.label => ('L', (p) => p.warn),
  };

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final items = widget.items;
    final sel = items.isEmpty ? null : items[widget.selected];
    final rows = items.length.clamp(1, CompletionPopup.maxRows);
    return TapRegion(
      groupId: widget.tapGroup,
      child: Container(
        width: CompletionPopup.width,
        decoration: BoxDecoration(
          color: p.panel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: p.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: rows * CompletionPopup.rowHeight,
              child: ListView.builder(
                controller: _scroll,
                physics: const ClampingScrollPhysics(),
                itemExtent: CompletionPopup.rowHeight,
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final it = items[i];
                  final (letter, colour) = _badge(it.kind);
                  final c = colour(p);
                  final active = i == widget.selected;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onPick(i),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: SelectableRow(
                        selected: active,
                        radius: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: c.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                letter,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: c,
                                  height: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              it.label,
                              style: TextStyle(
                                fontFamily: kMonoFamily,
                                fontFamilyFallback: kMonoFallback,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: p.text,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                it.detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontFamily: kMonoFamily,
                                  fontFamilyFallback: kMonoFallback,
                                  fontSize: 10.5,
                                  color: p.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (sel != null && sel.doc.isNotEmpty)
              Container(
                height: CompletionPopup.docHeight,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: p.border)),
                ),
                child: Text(
                  sel.doc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: p.muted, height: 1.3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Find and replace

class FindBar extends StatelessWidget {
  const FindBar({
    super.key,
    required this.find,
    required this.replace,
    required this.focusTick,
    required this.matchCount,
    required this.matchIndex,
    required this.caseSensitive,
    required this.onQuery,
    required this.onNext,
    required this.onPrev,
    required this.onReplace,
    required this.onReplaceAll,
    required this.onToggleCase,
    required this.onClose,
  });

  final TextEditingController find;
  final TextEditingController replace;
  final int focusTick;
  final int matchCount;
  final int matchIndex;
  final bool caseSensitive;
  final ValueChanged<String> onQuery;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onReplace;
  final VoidCallback onReplaceAll;
  final VoidCallback onToggleCase;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget field(
      TextEditingController c,
      String hint, {
      bool autofocus = false,
      Key? key,
      ValueChanged<String>? onChanged,
      VoidCallback? onEnter,
    }) {
      return SizedBox(
        height: 28,
        child: Focus(
          onKeyEvent: (node, e) {
            if (e is! KeyDownEvent) return KeyEventResult.ignored;
            if (e.logicalKey == LogicalKeyboardKey.escape) {
              onClose();
              return KeyEventResult.handled;
            }
            if (e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.numpadEnter) {
              if (HardwareKeyboard.instance.isShiftPressed &&
                  onEnter == onNext) {
                onPrev();
              } else {
                onEnter?.call();
              }
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            key: key,
            controller: c,
            autofocus: autofocus,
            onChanged: onChanged,
            cursorColor: p.accent,
            style: TextStyle(
              fontFamily: kMonoFamily,
              fontFamilyFallback: kMonoFallback,
              fontSize: 12,
              color: p.text,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: TextStyle(fontSize: 12, color: p.muted),
              filled: true,
              fillColor: p.field,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 7,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: BorderSide(color: p.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: BorderSide(color: p.accent.withOpacity(0.7)),
              ),
            ),
          ),
        ),
      );
    }

    final label = find.text.isEmpty
        ? ''
        : (matchCount == 0 ? 'No results' : '${matchIndex + 1} of $matchCount');
    return Container(
      width: 400,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: field(
                  find,
                  'Find',
                  autofocus: true,
                  key: ValueKey('find-$focusTick'),
                  onChanged: onQuery,
                  onEnter: onNext,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 62,
                child: T(
                  label,
                  size: 10.5,
                  color: matchCount == 0 && find.text.isNotEmpty
                      ? p.err
                      : p.muted,
                  maxLines: 1,
                ),
              ),
              IconBtn(
                icon: Icons.keyboard_arrow_up_rounded,
                tooltip: 'Previous match',
                size: 26,
                onClick: matchCount == 0 ? null : onPrev,
              ),
              IconBtn(
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: 'Next match',
                size: 26,
                onClick: matchCount == 0 ? null : onNext,
              ),
              IconBtn(
                tooltip: 'Match case',
                size: 26,
                active: caseSensitive,
                onClick: onToggleCase,
                child: Text(
                  'Aa',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: caseSensitive ? p.accent : p.muted,
                  ),
                ),
              ),
              IconBtn(
                icon: Icons.close_rounded,
                tooltip: 'Close (Esc)',
                size: 26,
                onClick: onClose,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: field(replace, 'Replace', onEnter: onReplace)),
              const SizedBox(width: 6),
              Btn(
                label: 'Replace',
                height: 26,
                fontSize: 11.5,
                outlined: true,
                onClick: matchCount == 0 ? null : onReplace,
              ),
              const SizedBox(width: 4),
              Btn(
                label: 'All',
                height: 26,
                fontSize: 11.5,
                outlined: true,
                onClick: matchCount == 0 ? null : onReplaceAll,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Status strip

class EditorStatus extends StatelessWidget {
  const EditorStatus({
    super.key,
    required this.line,
    required this.col,
    required this.selected,
    required this.lines,
    required this.hint,
    this.tabSize = kTabSize,
  });

  final int tabSize;
  final int line;
  final int col;
  final int selected;
  final int lines;
  final CompletionItem? hint;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mono = TextStyle(
      fontFamily: kMonoFamily,
      fontFamilyFallback: kMonoFallback,
      fontSize: 10.5,
      color: p.muted,
    );
    Widget dot() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: p.muted.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
      ),
    );
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: p.panel,
        border: Border(top: BorderSide(color: p.border.withOpacity(0.7))),
      ),
      child: Row(
        children: [
          if (hint != null)
            Expanded(
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 12,
                    color: p.muted,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: hint!.detail.isEmpty
                                ? hint!.label
                                : hint!.detail,
                            style: mono.copyWith(color: p.text),
                          ),
                          if (hint!.doc.isNotEmpty)
                            TextSpan(
                              text: '   ${hint!.doc.split('\n').first}',
                              style: TextStyle(fontSize: 10.5, color: p.muted),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 12),
          Text(
            selected > 0
                ? 'Ln $line, Col $col ($selected selected)'
                : 'Ln $line, Col $col',
            style: mono,
          ),
          dot(),
          Text('$lines lines', style: mono),
          dot(),
          Text('Spaces: $tabSize', style: mono),
        ],
      ),
    );
  }
}

/// The strip above the editor: the file, the processor it runs on, the problems found, and a few actions.
class EditorHeader extends StatelessWidget {
  const EditorHeader({
    super.key,
    required this.fileName,
    required this.processorName,
    required this.problems,
    required this.onProblems,
    required this.onFind,
    required this.findShortcut,
  });

  final String fileName;
  final String processorName;
  final int problems;
  final VoidCallback onProblems;
  final VoidCallback onFind;
  final String findShortcut;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ok = problems == 0;
    final c = ok ? p.ok : p.err;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.panel,
        border: Border(bottom: BorderSide(color: p.border.withOpacity(0.7))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: p.field,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: p.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.code_rounded, size: 13, color: p.accent),
                const SizedBox(width: 7),
                T(fileName, size: 11.5, weight: FontWeight.w600),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Icon(Icons.memory_rounded, size: 12, color: p.muted),
                const SizedBox(width: 5),
                Flexible(
                  child: T(
                    processorName,
                    size: 11,
                    color: p.muted,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          HoverBuilder(
            cursor: ok ? SystemMouseCursors.basic : SystemMouseCursors.click,
            onTap: ok ? null : onProblems,
            builder: (context, hovered) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: c.withOpacity(hovered ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    ok ? Icons.check_circle_rounded : Icons.error_rounded,
                    size: 12,
                    color: c,
                  ),
                  const SizedBox(width: 5),
                  T(
                    ok
                        ? 'No problems'
                        : '$problems problem${problems == 1 ? '' : 's'}',
                    size: 10.5,
                    weight: FontWeight.w600,
                    color: c,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconBtn(
            icon: Icons.search_rounded,
            tooltip: 'Find and replace ($findShortcut)',
            size: 28,
            onClick: onFind,
          ),
        ],
      ),
    );
  }
}

/// A wavy underline, like the one under a misspelled word.
class SquigglePainter extends CustomPainter {
  const SquigglePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(0, size.height / 2);
    var x = 0.0;
    var up = true;
    while (x < size.width) {
      x += 2.5;
      path.lineTo(x.clamp(0, size.width), up ? 0 : size.height);
      up = !up;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
  }

  @override
  bool shouldRepaint(SquigglePainter old) => old.color != color;
}

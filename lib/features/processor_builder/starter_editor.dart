import 'package:flutter/material.dart';
import 'package:dot_asm/app/processor_draft.dart';
import 'package:dot_asm/features/processor_builder/dsl_editor.dart';
import 'package:dot_asm/features/workspace/code_editor.dart';
import 'package:dot_asm/features/workspace/editor_logic.dart';
import 'package:dot_asm/theme/theme.dart';

/// The starter program of a processor in a real code editor: assembly highlighting for the processor being built,
/// suggestions for its instructions and registers, and the editor's shortcuts. New projects begin with this text.
class StarterCodeEditor extends StatefulWidget {
  const StarterCodeEditor({super.key, required this.draft, this.height = 360});
  final ProcessorDraft draft;
  final double height;

  @override
  State<StarterCodeEditor> createState() => _StarterCodeEditorState();
}

class _StarterCodeEditorState extends State<StarterCodeEditor> {
  late final AsmEditingController _c;
  int _revision = -1;

  ProcessorDraft get draft => widget.draft;

  @override
  void initState() {
    super.initState();
    _c = AsmEditingController(
      text: _text(draft.json['sample']),
      spec: draft.spec!,
    );
    _revision = draft.revision;
  }

  @override
  void didUpdateWidget(StarterCodeEditor old) {
    super.didUpdateWidget(old);
    if (_revision == draft.revision) return;
    _revision = draft.revision;
    // The instructions may have changed, which changes what is highlighted and suggested.
    final spec = draft.spec;
    if (spec != null) _c.setSpec(spec);
    // The text changed from elsewhere (the Source tab, Reload): follow it.
    final text = _text(draft.json['sample']);
    if (text != _c.text) _c.text = text;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  CompletionResult _suggest(String text, int caret, {bool force = false}) =>
      _c.index.suggest(
        text,
        caret,
        labels: CompletionIndex.labelsIn(text),
        force: force,
      );

  CompletionItem? _hint(String line) {
    final code = line.replaceFirst(RegExp(r'^\s*[A-Za-z_.$][\w.$]*\s*:'), '');
    final m = RegExp(r'^\s*([A-Za-z_.][\w.]*)').firstMatch(code);
    return m == null ? null : _c.index.describe(m.group(1)!);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      height: widget.height,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: p.field,
          borderRadius: BorderRadius.circular(8),
        ),
        // Painted over the editor, so its header and gutter can never cover the rounded border.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.border),
        ),
        child: SourceEditor(
          controller: _c,
          fileName: 'starter.s',
          subtitle: draft.spec?.name ?? '',
          suggester: _suggest,
          hintFor: _hint,
          tabSize: 4,
          blocks: false,
          commentMarker: _c.comments.first,
          onChanged: () {
            if (_c.text != _text(draft.json['sample'])) {
              draft.set('sample', _c.text);
            }
          },
        ),
      ),
    );
  }
}

String _text(Object? v) => v == null ? '' : '$v';

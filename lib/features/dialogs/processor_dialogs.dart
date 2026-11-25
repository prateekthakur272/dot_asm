import 'dart:io';

import 'package:flutter/material.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/components/inputs.dart';
import 'package:dot_asm/components/layout.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';

/// Import a processor by choosing a JSON file or pasting its text.
class ImportProcessorDialog extends StatefulWidget {
  const ImportProcessorDialog({super.key, required this.state});
  final AppState state;

  @override
  State<ImportProcessorDialog> createState() => _ImportProcessorDialogState();
}

class _ImportProcessorDialogState extends State<ImportProcessorDialog> {
  final TextEditingController _text = TextEditingController();
  List<String> _problems = const [];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _chooseFile() async {
    final path = await Platform.pickFile('Choose a processor file', [
      'cpu',
      'json',
    ]);
    if (path == null) return;
    try {
      final content = await File(path).readAsString();
      if (!mounted) return;
      setState(() {
        _text.text = content;
        _problems = const [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _problems = ['Cannot read the file: $e']);
    }
  }

  void _import() {
    final problems = widget.state.importProcessor(_text.text);
    if (problems.isEmpty) {
      widget.state.modal = null;
    } else {
      setState(() => _problems = problems);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ModalScaffold(
      title: 'Import processor',
      width: 620,
      onClose: () => widget.state.modal = null,
      actions: [
        Btn(
          label: 'Cancel',
          height: 32,
          onClick: () => widget.state.modal = null,
        ),
        Btn(
          label: 'Import',
          primary: true,
          height: 32,
          onClick: _text.text.trim().isEmpty ? null : _import,
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 440),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: T(
                    'Choose a processor .cpu file (or an older .json file), or paste its text below. It is saved into the open project\'s cpu/ folder.',
                    size: 12,
                    color: p.muted,
                  ),
                ),
                Btn(
                  label: 'Choose file…',
                  icon: AppIcons.folder,
                  height: 28,
                  fontSize: 11.5,
                  onClick: _chooseFile,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BoundTextField(
                      value: _text.text,
                      revision: _text.text.length,
                      mono: true,
                      lines: 10,
                      hint: 'processor my-cpu "My CPU" { ... }',
                      onChanged: (v) => setState(() {
                        _text.text = v;
                        _problems = const [];
                      }),
                    ),
                    if (_problems.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: p.err.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: p.err.withOpacity(0.45)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            T(
                              "This file can't be imported:",
                              size: 11.5,
                              weight: FontWeight.w700,
                              color: p.err,
                            ),
                            const SizedBox(height: 4),
                            for (final e in _problems.take(12))
                              MonoText(
                                '• $e',
                                size: 11,
                                maxLines: 3,
                                softWrap: true,
                              ),
                            if (_problems.length > 12)
                              T(
                                '…and ${_problems.length - 12} more',
                                size: 11,
                                color: p.muted,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ConfirmDeleteProcessorDialog extends StatelessWidget {
  const ConfirmDeleteProcessorDialog({
    super.key,
    required this.state,
    required this.processor,
  });
  final AppState state;
  final ProcessorSpec processor;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final used = state.activeProcessor?.id == processor.id ? 1 : 0;
    return ModalScaffold(
      title: 'Delete processor',
      width: 440,
      onClose: () => state.modal = null,
      actions: [
        Btn(label: 'Cancel', height: 32, onClick: () => state.modal = null),
        Btn(
          label: 'Delete',
          primary: true,
          danger: true,
          height: 32,
          onClick: () {
            state.modal = null;
            state.deleteProcessor(processor);
          },
        ),
      ],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.alert, size: 22, color: p.err),
          const SizedBox(width: 12),
          Expanded(
            child: T(
              used > 0
                  ? "Delete '${processor.name}'? This project uses it and will not be able to run until you choose or add another processor."
                  : "Delete '${processor.name}'? Export it first if you want to keep a copy.",
              size: 12.5,
              overflow: TextOverflow.visible,
            ),
          ),
        ],
      ),
    );
  }
}

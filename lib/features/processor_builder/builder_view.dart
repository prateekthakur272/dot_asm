import 'package:flutter/material.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/features/processor_builder/processor_editor.dart';

/// The processor builder: the editor for the open project's processor.
class BuilderView extends StatelessWidget {
  const BuilderView({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final draft = state.builderDraft;
    if (draft == null) return const SizedBox.shrink();
    return ProcessorEditor(key: ObjectKey(draft), state: state, draft: draft);
  }
}

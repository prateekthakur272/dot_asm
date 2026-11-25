import 'package:flutter/material.dart';
import 'package:dot_asm/components/empty_state.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/components/inputs.dart';
import 'package:dot_asm/components/layout.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/app/gallery.dart';
import 'package:dot_asm/app/processor_catalog.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/core/model/project.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';

/// Create a project: a name, the folder to create it in, and the processor template to start from.
class NewProjectDialog extends StatefulWidget {
  const NewProjectDialog({
    super.key,
    required this.state,
    this.templateId,
    this.openInBuilder = false,
  });
  final AppState state;

  /// Preselected template.
  final String? templateId;

  /// Start with "open in the builder" ticked (customising a template).
  final bool openInBuilder;

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<NewProjectDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.state.suggestProjectName(),
  );
  late String _parent = AppStore.lastProjectParent;
  String? _templateId;
  late bool _openBuilder = widget.openInBuilder;
  String? _error;

  @override
  void initState() {
    super.initState();
    final all = TemplateCatalog.templates;
    _templateId = widget.templateId ?? (all.isEmpty ? null : all.first.id);
    _name.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final dir = await Platform.pickDirectory(
      'Choose where to create the project',
    );
    if (dir != null && mounted) {
      setState(() {
        _parent = dir;
        _error = null;
      });
    }
  }

  void _create() {
    final id = _templateId;
    if (id == null) return;
    final err = widget.state.createProject(
      name: _name.text,
      parentDir: _parent,
      templateId: id,
      openInBuilder: _openBuilder,
    );
    if (err == null) {
      widget.state.modal = null;
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final templates = TemplateCatalog.templates;
    final folder = _name.text.trim().isEmpty
        ? '…'
        : AppStore.folderNameFor(_name.text);
    return ModalScaffold(
      title: 'New project',
      width: 860,
      onClose: () => widget.state.modal = null,
      actions: [
        Btn(
          label: 'Cancel',
          height: 32,
          onClick: () => widget.state.modal = null,
        ),
        Btn(
          label: 'Create',
          primary: true,
          height: 32,
          onClick: _templateId == null || _parent.isEmpty ? null : _create,
        ),
      ],
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const T('Name', size: 12, weight: FontWeight.w600),
            const SizedBox(height: 6),
            AppTextField(
              controller: _name,
              hint: 'Project name',
              autofocus: true,
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 14),
            const T('Location', size: 12, weight: FontWeight.w600),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: p.field,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: p.border),
                    ),
                    child: MonoText(
                      _parent.isEmpty ? 'Choose a folder…' : _parent,
                      size: 12,
                      color: _parent.isEmpty ? p.muted : p.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Btn(
                  label: 'Browse…',
                  icon: AppIcons.folder,
                  height: 34,
                  fontSize: 12,
                  onClick: _browse,
                ),
              ],
            ),
            const SizedBox(height: 6),
            T(
              'A folder "$folder" is created here with project.dotasm, your source, and the chosen processor as a .cpu file in its cpu/ folder.',
              size: 11,
              color: p.muted,
              overflow: TextOverflow.visible,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.err.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: p.err.withOpacity(0.45)),
                ),
                child: T(
                  _error!,
                  size: 11.5,
                  color: p.err,
                  overflow: TextOverflow.visible,
                ),
              ),
            ],
            const SizedBox(height: 16),
            const T('Processor', size: 12, weight: FontWeight.w600),
            const SizedBox(height: 2),
            T(
              'Pick the architecture to learn on. It is copied into the project as an editable .cpu file.',
              size: 11,
              color: p.muted,
              overflow: TextOverflow.visible,
            ),
            const SizedBox(height: 8),
            TemplatePicker(
              templates: templates,
              selectedId: _templateId,
              onSelected: (id) => setState(() => _templateId = id),
            ),
            const SizedBox(height: 6),
            HoverBuilder(
              cursor: SystemMouseCursors.click,
              onTap: () => setState(() => _openBuilder = !_openBuilder),
              builder: (context, hovered) => Row(
                children: [
                  Checkbox(
                    value: _openBuilder,
                    activeColor: p.accent,
                    checkColor: p.onAccent,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => setState(() => _openBuilder = v ?? false),
                  ),
                  const Expanded(
                    child: T(
                      'Open the processor in the builder after creating the project',
                      size: 11.5,
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chooses a processor template: a searchable list grouped by family on the left, and on the right everything worth
/// knowing about the selected one (what it is, key facts, and a look at its sample program).
class TemplatePicker extends StatefulWidget {
  const TemplatePicker({
    super.key,
    required this.templates,
    required this.selectedId,
    required this.onSelected,
  });
  final List<ProcessorTemplate> templates;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  State<TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<TemplatePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final entries = [
      for (final t in widget.templates) GalleryEntry.fromTemplate(t),
    ];
    final q = _query.trim().toLowerCase();
    bool matches(GalleryEntry e) =>
        q.isEmpty ||
        '${e.name} ${e.vendor} ${e.year} ${e.tags.join(' ')} ${e.description}'
            .toLowerCase()
            .contains(q);
    final shown = entries.where(matches).toList();
    final selected = widget.templates
        .where((t) => t.id == widget.selectedId)
        .firstOrNull;

    return Container(
      height: 340,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: BoundTextField(
                    value: _query,
                    height: 30,
                    hint: 'Search: arm, 8-bit, intel, 1975…',
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Container(height: 1, color: p.border),
                Expanded(
                  child: shown.isEmpty
                      ? Center(
                          child: EmptyState(
                            art: EmptyArt.search,
                            artSize: 84,
                            title: 'No processor matches "$_query"',
                            subtitle:
                                'Try a name, a vendor or a tag like 8-bit.',
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                          physics: const ClampingScrollPhysics(),
                          children: [
                            for (final g in GalleryGroup.values)
                              if (shown.any((e) => e.group == g)) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    6,
                                    8,
                                    6,
                                    4,
                                  ),
                                  child: T(
                                    g.label.toUpperCase(),
                                    size: 10,
                                    weight: FontWeight.w700,
                                    color: p.muted,
                                  ),
                                ),
                                for (final e in shown.where(
                                  (e) => e.group == g,
                                ))
                                  _PickerRow(
                                    entry: e,
                                    selected: e.id == widget.selectedId,
                                    onTap: () => widget.onSelected(e.id),
                                  ),
                              ],
                          ],
                        ),
                ),
              ],
            ),
          ),
          Container(width: 1, color: p.border),
          Expanded(
            child: selected == null
                ? Center(
                    child: T('Select a processor', size: 12, color: p.muted),
                  )
                : _PickerDetail(template: selected),
          ),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });
  final GalleryEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final e = entry;
    final meta = [
      if (e.vendor.isNotEmpty) e.vendor,
      if (e.year > 0) '${e.year}',
    ].join(' · ');
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      onTap: onTap,
      builder: (context, hovered) => Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? p.accent.withOpacity(0.14)
              : (hovered ? p.hover : Colors.transparent),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? p.accent.withOpacity(0.7) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.field,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: p.border),
              ),
              child: T(
                e.bits > 0 ? '${e.bits}' : '·',
                size: 11,
                weight: FontWeight.w800,
                color: selected ? p.accent : p.muted,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  T(
                    e.name,
                    size: 12,
                    weight: selected ? FontWeight.w700 : FontWeight.w600,
                    maxLines: 1,
                  ),
                  if (meta.isNotEmpty)
                    T(meta, size: 10.5, color: p.muted, maxLines: 1),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 15, color: p.accent),
          ],
        ),
      ),
    );
  }
}

class _PickerDetail extends StatelessWidget {
  const _PickerDetail({required this.template});
  final ProcessorTemplate template;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = template.spec;
    final e = GalleryEntry.fromTemplate(template);
    final regs = (s.registerFile?.count ?? 0) + s.registers.length;
    final lengths = {for (final i in s.instructions) i.bits};
    final fixed = lengths.length <= 1;
    final facts = <(String, String)>[
      ('Word size', '${s.wordBits}-bit, ${s.endian.name} endian'),
      (
        'Registers',
        regs == 0
            ? 'none'
            : '$regs${s.flags.isEmpty ? '' : ' + ${s.flags.length} flags'}',
      ),
      (
        'Instructions',
        '${s.instructions.length} · ${fixed ? 'fixed ${lengths.isEmpty ? s.instrBits : lengths.first}-bit' : 'variable length (${(lengths.toList()..sort()).map((b) => '${b ~/ 8}').join('/')} bytes)'}',
      ),
      ('Memory', s.memory.map((r) => r.name).join(', ')),
    ];
    final lines = s.sample.split('\n');
    final preview =
        lines.take(14).join('\n') + (lines.length > 14 ? '\n…' : '');

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: T(
                  s.name,
                  size: 14,
                  weight: FontWeight.w700,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              _Chip(e.legacy ? 'Legacy' : 'Modern', e.legacy ? p.warn : p.ok),
            ],
          ),
          const SizedBox(height: 2),
          T(
            [
              if (s.vendor.isNotEmpty) s.vendor,
              if (s.year > 0) '${s.year}',
            ].join(' · '),
            size: 11,
            color: p.muted,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final t in s.tags)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: p.field,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.border),
                  ),
                  child: T(
                    t,
                    size: 10,
                    weight: FontWeight.w600,
                    color: p.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (s.description.isNotEmpty)
            T(
              s.description,
              size: 11.5,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 10),
          for (final f in facts)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 82, child: T(f.$1, size: 11, color: p.muted)),
                  Expanded(
                    child: T(
                      f.$2,
                      size: 11,
                      weight: FontWeight.w600,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          T(
            'Starter program',
            size: 10.5,
            weight: FontWeight.w700,
            color: p.muted,
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: p.field,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: p.border),
              ),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: double.infinity,
                  child: MonoText(
                    preview,
                    size: 10.5,
                    color: p.muted,
                    maxLines: null,
                    softWrap: false,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.14),
      borderRadius: BorderRadius.circular(4),
    ),
    child: T(label, size: 10, weight: FontWeight.w700, color: color),
  );
}

class RenameProjectDialog extends StatefulWidget {
  const RenameProjectDialog({
    super.key,
    required this.state,
    required this.project,
  });
  final AppState state;
  final Project project;

  @override
  State<RenameProjectDialog> createState() => _RenameProjectDialogState();
}

class _RenameProjectDialogState extends State<RenameProjectDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.project.name,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    widget.state.modal = null;
    widget.state.renameProject(widget.project, _name.text);
  }

  @override
  Widget build(BuildContext context) => ModalScaffold(
    title: 'Rename project',
    width: 420,
    onClose: () => widget.state.modal = null,
    actions: [
      Btn(
        label: 'Cancel',
        height: 32,
        onClick: () => widget.state.modal = null,
      ),
      Btn(label: 'Rename', primary: true, height: 32, onClick: _save),
    ],
    child: AppTextField(
      controller: _name,
      hint: 'Project name',
      autofocus: true,
      onSubmitted: (_) => _save(),
    ),
  );
}

class ConfirmDeleteProjectDialog extends StatefulWidget {
  const ConfirmDeleteProjectDialog({
    super.key,
    required this.state,
    required this.project,
  });
  final AppState state;
  final Project project;

  @override
  State<ConfirmDeleteProjectDialog> createState() =>
      _ConfirmDeleteProjectDialogState();
}

class _ConfirmDeleteProjectDialogState
    extends State<ConfirmDeleteProjectDialog> {
  bool _deleteFiles = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final project = widget.project;
    return ModalScaffold(
      title: 'Remove project',
      width: 480,
      onClose: () => widget.state.modal = null,
      actions: [
        Btn(
          label: 'Cancel',
          height: 32,
          onClick: () => widget.state.modal = null,
        ),
        Btn(
          label: _deleteFiles ? 'Delete folder' : 'Remove from list',
          primary: true,
          danger: _deleteFiles,
          height: 32,
          onClick: () {
            widget.state.modal = null;
            widget.state.removeProject(project, deleteFiles: _deleteFiles);
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AppIcons.alert,
                size: 22,
                color: _deleteFiles ? p.err : p.warn,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: T(
                  _deleteFiles
                      ? "Delete the folder of '${project.name}' and everything in it (source, project file, processors)? This cannot be undone."
                      : "Remove '${project.name}' from the list? Its folder and files stay where they are, and you can open it again later.",
                  size: 12.5,
                  overflow: TextOverflow.visible,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          MonoText(project.path, size: 11, color: p.muted),
          const SizedBox(height: 8),
          HoverBuilder(
            cursor: SystemMouseCursors.click,
            onTap: () => setState(() => _deleteFiles = !_deleteFiles),
            builder: (context, hovered) => Row(
              children: [
                Checkbox(
                  value: _deleteFiles,
                  activeColor: p.err,
                  checkColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => setState(() => _deleteFiles = v ?? false),
                ),
                const Expanded(
                  child: T(
                    'Also delete the project folder from disk',
                    size: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

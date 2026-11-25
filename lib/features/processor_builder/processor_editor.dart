import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/app/processor_catalog.dart';
import 'package:dot_asm/app/processor_draft.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/core/dsl/dsl.dart';
import 'package:dot_asm/core/sim/dsl/processor_dsl.dart';
import 'package:dot_asm/components/inputs.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/selectable_row.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/features/processor_builder/builder_widgets.dart';
import 'package:dot_asm/features/processor_builder/dsl_editor.dart';
import 'package:dot_asm/features/processor_builder/instruction_editor.dart';
import 'package:dot_asm/features/processor_builder/starter_editor.dart';
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';

enum _Section {
  general('General', Icons.badge_outlined),
  registers('Registers & flags', Icons.developer_board_rounded),
  memory('Memory map', Icons.grid_view_rounded),
  instructions('Instructions', Icons.code_rounded),
  advanced('Advanced', Icons.tune_rounded),
  json('Source (.cpu)', Icons.data_object_rounded);

  const _Section(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Edits one processor: forms for every part of the spec, live validation, save and export.
class ProcessorEditor extends StatefulWidget {
  const ProcessorEditor({super.key, required this.state, required this.draft});
  final AppState state;
  final ProcessorDraft draft;

  @override
  State<ProcessorEditor> createState() => _ProcessorEditorState();
}

class _ProcessorEditorState extends State<ProcessorEditor> {
  _Section _section = _Section.general;
  bool _confirmDiscard = false;
  bool _problemsOpen = true;

  AppState get state => widget.state;
  ProcessorDraft get draft => widget.draft;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        // The builder paints its own background, so it never shows whatever is behind it.
        return ColoredBox(
          color: p.bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, p),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _nav(p),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _section == _Section.instructions
                                ? InstructionsTab(draft: draft)
                                : _section == _Section.json
                                ? _JsonTab(draft: draft)
                                : ListView(
                                    padding: EdgeInsets.zero,
                                    physics: const ClampingScrollPhysics(),
                                    children: [
                                      switch (_section) {
                                        _Section.general => _GeneralTab(
                                          draft: draft,
                                        ),
                                        _Section.registers => _RegistersTab(
                                          draft: draft,
                                        ),
                                        _Section.memory => _MemoryTab(
                                          draft: draft,
                                        ),
                                        _ => _AdvancedTab(draft: draft),
                                      },
                                    ],
                                  ),
                          ),
                          _problems(p),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Where the processor is (or will be) saved.
  String _where() {
    final project = state.activeProject;
    return 'saved as ${project == null ? 'cpu/' : '${project.name}/cpu/'}${draft.id}.cpu';
  }

  Widget _header(BuildContext context, Pal p) {
    final spec = draft.spec;
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: p.panel,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          IconBtn(
            icon: AppIcons.back,
            tooltip: 'Back to the project',
            size: 30,
            onClick: () {
              if (draft.dirty && !_confirmDiscard) {
                setState(() => _confirmDiscard = true);
              } else {
                state.closeDraft();
              }
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: T(
                        draft.name.isEmpty ? 'Untitled processor' : draft.name,
                        size: 14.5,
                        weight: FontWeight.w700,
                        maxLines: 1,
                      ),
                    ),
                    if (draft.dirty) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: p.warn.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: p.warn,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            T(
                              'Unsaved',
                              size: 10,
                              weight: FontWeight.w700,
                              color: p.warn,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (spec == null)
                      T(
                        'Fix the structure to see a summary',
                        size: 10.5,
                        color: p.muted,
                      )
                    else ...[
                      _MetaChip('${spec.wordBits}-bit'),
                      _MetaChip('${spec.registerCount} registers'),
                      _MetaChip('${spec.instructions.length} instructions'),
                    ],
                    Flexible(
                      child: T(
                        _where(),
                        size: 10.5,
                        color: p.muted.withOpacity(0.8),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_confirmDiscard) ...[
            T('Discard unsaved changes?', size: 11.5, color: p.warn),
            const SizedBox(width: 8),
            Btn(
              label: 'Discard',
              height: 30,
              danger: true,
              outlined: true,
              fontSize: 12,
              onClick: state.closeDraft,
            ),
            const SizedBox(width: 6),
            Btn(
              label: 'Keep editing',
              height: 30,
              fontSize: 12,
              onClick: () => setState(() => _confirmDiscard = false),
            ),
          ] else ...[
            IconBtn(
              icon: AppIcons.download,
              tooltip: 'Export the .cpu file…',
              size: 30,
              onClick: spec == null ? null : () => state.exportProcessor(spec),
            ),
            IconBtn(
              icon: AppIcons.copy,
              tooltip: 'Copy the processor source (.cpu)',
              size: 30,
              onClick: () {
                Platform.copy(ProcessorDsl.fromJsonMap(draft.json));
                state.showToast('Processor source (.cpu) copied');
              },
            ),
            const SizedBox(width: 8),
            Btn(
              label: 'Save',
              icon: Icons.save_outlined,
              primary: true,
              height: 30,
              fontSize: 12,
              onClick: draft.dirty || draft.originalId == null
                  ? state.saveDraft
                  : null,
            ),
            const SizedBox(width: 6),
            if (state.activeProject != null)
              Btn(
                label: 'Use in project',
                icon: AppIcons.play,
                height: 30,
                fontSize: 12,
                outlined: true,
                onClick: !draft.isValid
                    ? null
                    : () {
                        if (state.saveDraft()) {
                          final saved = state.processors
                              .where((x) => x.id == draft.id)
                              .firstOrNull;
                          if (saved != null) state.useProcessor(saved);
                        }
                      },
              ),
          ],
        ],
      ),
    );
  }

  /// A count shown beside a section in the navigation.
  int? _count(_Section s) {
    final spec = draft.spec;
    if (spec == null) return null;
    return switch (s) {
      _Section.registers => spec.registerCount,
      _Section.memory => spec.memory.length,
      _Section.instructions => spec.instructions.length,
      _ => null,
    };
  }

  Widget _nav(Pal p) {
    final problems = draft.problems;
    final ok = problems.isEmpty;
    return Container(
      width: 208,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      decoration: BoxDecoration(
        color: p.sidebar,
        border: Border(right: BorderSide(color: p.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in _Section.values)
            HoverBuilder(
              cursor: SystemMouseCursors.click,
              onTap: () => setState(() => _section = s),
              builder: (context, hovered) {
                final active = s == _section;
                final n = _count(s);
                return SelectableRow(
                  selected: active,
                  hovered: hovered,
                  height: 34,
                  margin: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      Icon(
                        s.icon,
                        size: 15,
                        color: active ? p.accent : p.muted,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: T(
                          s.label,
                          size: 12,
                          weight: active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? p.text : p.muted,
                          maxLines: 1,
                        ),
                      ),
                      if (n != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: p.field,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: p.border),
                          ),
                          child: T('$n', size: 9.5, color: p.muted),
                        ),
                    ],
                  ),
                );
              },
            ),
          const Spacer(),
          // Whether the processor can be used
          HoverBuilder(
            cursor: ok ? SystemMouseCursors.basic : SystemMouseCursors.click,
            onTap: ok
                ? null
                : () => setState(() => _problemsOpen = !_problemsOpen),
            builder: (context, hovered) => Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (ok ? p.ok : p.err).withOpacity(hovered ? 0.16 : 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (ok ? p.ok : p.err).withOpacity(0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    ok ? Icons.check_circle_rounded : Icons.error_rounded,
                    size: 16,
                    color: ok ? p.ok : p.err,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        T(
                          ok
                              ? 'Ready to use'
                              : '${problems.length} problem${problems.length == 1 ? '' : 's'}',
                          size: 11.5,
                          weight: FontWeight.w700,
                          color: ok ? p.ok : p.err,
                        ),
                        T(
                          ok ? 'Validation passed' : 'Click to see them',
                          size: 10,
                          color: p.muted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _problems(Pal p) {
    final problems = draft.problems;
    final ok = problems.isEmpty;
    // When everything is fine the navigation already says so.
    if (ok) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: p.panel,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoverBuilder(
            cursor: SystemMouseCursors.click,
            onTap: () => setState(() => _problemsOpen = !_problemsOpen),
            builder: (context, hovered) => Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: hovered ? p.hover : null,
              child: Row(
                children: [
                  Icon(
                    ok
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    size: 14,
                    color: ok ? p.ok : p.err,
                  ),
                  const SizedBox(width: 8),
                  T(
                    ok
                        ? 'No problems: this processor is ready to use'
                        : '${problems.length} problem${problems.length == 1 ? '' : 's'}',
                    size: 11.5,
                    weight: FontWeight.w600,
                    color: ok ? p.ok : p.err,
                  ),
                  const Spacer(),
                  if (!ok)
                    Icon(
                      _problemsOpen
                          ? Icons.expand_more_rounded
                          : Icons.expand_less_rounded,
                      size: 16,
                      color: p.muted,
                    ),
                ],
              ),
            ),
          ),
          if (!ok && _problemsOpen)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 130),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                physics: const ClampingScrollPhysics(),
                children: [
                  for (final e in problems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.circle, size: 5, color: p.err),
                          const SizedBox(width: 8),
                          Expanded(
                            child: MonoText(
                              e,
                              size: 11,
                              maxLines: 3,
                              softWrap: true,
                            ),
                          ),
                        ],
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

// ---------------------------------------------------------------------------------------------------------------

int intOf(Object? v, int fallback) {
  if (v is int) return v;
  if (v is String) {
    final t = v.trim();
    return t.startsWith('0x')
        ? (int.tryParse(t.substring(2), radix: 16) ?? fallback)
        : (int.tryParse(t) ?? fallback);
  }
  return fallback;
}

String textOf(Object? v) => v == null ? '' : '$v';

class _GeneralTab extends StatelessWidget {
  const _GeneralTab({required this.draft});
  final ProcessorDraft draft;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final j = draft.json;
    // Architecture families come from the templates the app can read, plus the one being edited.
    final arch = textOf(j['arch']);
    final archs = <String>{
      'custom',
      for (final t in TemplateCatalog.templates) t.spec.arch,
      if (arch.isNotEmpty) arch,
    }.toList();
    final aligned = j['alignedAccess'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Identity',
          icon: Icons.badge_outlined,
          subtitle: 'How the processor is named and listed.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormGrid(
                children: [
                  Labeled(
                    'Name',
                    BoundTextField(
                      value: textOf(j['name']),
                      revision: draft.revision,
                      hint: 'My processor',
                      onChanged: (v) => draft.set('name', v),
                    ),
                  ),
                  Labeled(
                    'Id',
                    BoundTextField(
                      value: textOf(j['id']),
                      revision: draft.revision,
                      mono: true,
                      hint: 'my-processor',
                      onChanged: (v) => draft.set('id', v),
                    ),
                    hint: 'Letters, digits, - _ . ; used as the file name.',
                  ),
                  Labeled(
                    'Architecture family',
                    AppDropdown<String>(
                      value: archs.contains(arch) ? arch : 'custom',
                      items: [
                        for (final a in archs)
                          DropdownMenuItem(
                            value: a,
                            child: Text(
                              a == 'custom' ? 'custom' : a.toUpperCase(),
                            ),
                          ),
                      ],
                      onChanged: (v) => draft.set('arch', v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Labeled(
                'Description',
                BoundTextField(
                  value: textOf(j['description']),
                  revision: draft.revision,
                  lines: 3,
                  hint: 'What is special about this processor?',
                  onChanged: (v) => draft.set('description', v),
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Gallery listing',
          icon: Icons.collections_bookmark_outlined,
          subtitle:
              'How the processor is categorised in the processor gallery.',
          child: FormGrid(
            minColumnWidth: 200,
            children: [
              Labeled(
                'Vendor',
                BoundTextField(
                  value: textOf(j['vendor']),
                  revision: draft.revision,
                  hint: 'Who designed it',
                  onChanged: (v) => draft.set('vendor', v),
                ),
              ),
              Labeled(
                'Year',
                BoundTextField(
                  value: textOf(j['year']),
                  revision: draft.revision,
                  hint: '1975',
                  onChanged: (v) => draft.set(
                    'year',
                    v.trim().isEmpty ? null : numberOrText(v),
                  ),
                ),
              ),
              Labeled(
                'Era',
                AppDropdown<String>(
                  value: const ['legacy', 'modern'].contains(textOf(j['era']))
                      ? textOf(j['era'])
                      : '',
                  items: const [
                    DropdownMenuItem(
                      value: '',
                      child: Text('Automatic (by year)'),
                    ),
                    DropdownMenuItem(value: 'legacy', child: Text('Legacy')),
                    DropdownMenuItem(value: 'modern', child: Text('Modern')),
                  ],
                  onChanged: (v) => draft.set('era', v),
                ),
              ),
              Labeled(
                'Tags',
                BoundTextField(
                  value: j['tags'] is List
                      ? (j['tags'] as List).join(', ')
                      : '',
                  revision: draft.revision,
                  hint: 'RISC, 8-bit',
                  onChanged: (v) {
                    final l = v
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                    draft.edit((j) {
                      if (l.isEmpty) {
                        j.remove('tags');
                      } else {
                        j['tags'] = l;
                      }
                    });
                  },
                ),
                hint: 'RISC, CISC, ARM, x86, 8-bit, ...',
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Word and instruction format',
          icon: Icons.straighten_rounded,
          subtitle: 'The width of addresses and registers, and how instructions are laid out in memory.',
          child: FormGrid(
            children: [
              Labeled(
                'Word size',
                AppDropdown<int>(
                  value: [8, 16, 32, 64].contains(intOf(j['wordBits'], 32))
                      ? intOf(j['wordBits'], 32)
                      : 32,
                  items: [
                    for (final b in [8, 16, 32, 64])
                      DropdownMenuItem(value: b, child: Text('$b-bit')),
                  ],
                  onChanged: (v) => draft.set('wordBits', v),
                ),
                hint: 'Size of the program counter and of addresses.',
              ),
              Labeled(
                'Byte order',
                AppDropdown<String>(
                  value: j['endian'] == 'big' ? 'big' : 'little',
                  items: const [
                    DropdownMenuItem(
                      value: 'little',
                      child: Text('Little endian'),
                    ),
                    DropdownMenuItem(value: 'big', child: Text('Big endian')),
                  ],
                  onChanged: (v) => draft.set('endian', v),
                ),
              ),
              Labeled(
                'Default instruction size',
                AppDropdown<int>(
                  value:
                      [
                        8,
                        16,
                        24,
                        32,
                        40,
                        48,
                        56,
                        64,
                      ].contains(intOf(j['instrBits'], 32))
                      ? intOf(j['instrBits'], 32)
                      : 32,
                  items: [
                    for (final b in [8, 16, 24, 32, 40, 48, 56, 64])
                      DropdownMenuItem(value: b, child: Text('$b bits')),
                  ],
                  onChanged: (v) => draft.set('instrBits', v),
                ),
                hint: 'Each instruction can override this to mix sizes.',
              ),
              Labeled(
                'Alignment',
                HoverBuilder(
                  cursor: SystemMouseCursors.click,
                  onTap: () => draft.edit((j) {
                    if (!aligned) {
                      j['alignedAccess'] = true;
                    } else {
                      j.remove('alignedAccess');
                    }
                  }),
                  builder: (context, hovered) => Container(
                    height: 34,
                    padding: const EdgeInsets.only(left: 6, right: 10),
                    decoration: BoxDecoration(
                      color: hovered ? p.hover : p.field,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: p.border),
                    ),
                    child: Row(
                      children: [
                        IgnorePointer(
                          child: AppCheckbox(value: aligned, onChanged: (_) {}),
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: T(
                            'Fault on misaligned access',
                            size: 12,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------

class _RegistersTab extends StatelessWidget {
  const _RegistersTab({required this.draft});
  final ProcessorDraft draft;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final j = draft.json;
    final rf = j['registerFile'] is Map
        ? Map<String, dynamic>.from(j['registerFile'] as Map)
        : null;
    final wordBits = intOf(j['wordBits'], 32);
    final extra = draft.listOf('registers');

    void setRf(String key, Object? v) => draft.edit((j) {
      final m = j['registerFile'] as Map<String, dynamic>;
      if (v == null || v == '') {
        m.remove(key);
      } else {
        m[key] = v;
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Register file',
          icon: Icons.developer_board_rounded,
          subtitle: 'A bank of numbered general-purpose registers (x0..x31, r0..r15, ...). Instructions select them with register operands.',
          trailing: AppCheckbox(
            value: rf != null,
            onChanged: (on) => draft.edit((j) {
              if (on) {
                j['registerFile'] = <String, dynamic>{
                  'prefix': 'r',
                  'count': 16,
                  'width': wordBits,
                };
              } else {
                j.remove('registerFile');
              }
            }),
          ),
          child: rf == null
              ? T(
                  'This processor has no register file (for example an accumulator machine). Use extra registers below.',
                  size: 11.5,
                  color: p.muted,
                  overflow: TextOverflow.visible,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FormGrid(
                      minColumnWidth: 170,
                      children: [
                        Labeled(
                          'Name prefix',
                          BoundTextField(
                            value: textOf(rf['prefix']),
                            revision: draft.revision,
                            mono: true,
                            hint: 'r',
                            onChanged: (v) => setRf('prefix', v),
                          ),
                        ),
                        Labeled(
                          'Number of registers',
                          BoundTextField(
                            value: textOf(rf['count']),
                            revision: draft.revision,
                            hint: '16',
                            onChanged: (v) => setRf('count', numberOrText(v)),
                          ),
                        ),
                        Labeled(
                          'Register width',
                          AppDropdown<int>(
                            value:
                                [
                                  8,
                                  16,
                                  32,
                                  64,
                                ].contains(intOf(rf['width'], wordBits))
                                ? intOf(rf['width'], wordBits)
                                : wordBits,
                            items: [
                              for (final b in [8, 16, 32, 64])
                                DropdownMenuItem(
                                  value: b,
                                  child: Text('$b-bit'),
                                ),
                            ],
                            onChanged: (v) => setRf('width', v),
                          ),
                        ),
                        Labeled(
                          'Zero register index',
                          BoundTextField(
                            value: textOf(rf['zero']),
                            revision: draft.revision,
                            hint: 'none',
                            onChanged: (v) => setRf(
                              'zero',
                              v.trim().isEmpty ? null : numberOrText(v),
                            ),
                          ),
                          hint: 'Always reads 0, ignores writes.',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Labeled(
                      'Alternative names',
                      BoundTextField(
                        value: formatAssignments(rf['aliases']),
                        revision: draft.revision,
                        mono: true,
                        hint: 'zero=0, ra=1, sp=2',
                        onChanged: (v) {
                          final m = parseAssignments(v);
                          if (m != null) setRf('aliases', m.isEmpty ? null : m);
                        },
                      ),
                      hint: 'name=index pairs, separated by commas.',
                    ),
                  ],
                ),
        ),
        SectionCard(
          title: 'Extra registers',
          icon: Icons.add_box_outlined,
          subtitle: 'Named registers outside the file: an accumulator, a stack pointer, a status register.',
          trailing: Btn(
            label: 'Add',
            icon: AppIcons.add,
            height: 26,
            fontSize: 11,
            onClick: () => draft.edit((j) {
              final l = (j['registers'] as List?) ?? <dynamic>[];
              l.add(<String, dynamic>{
                'name': 'R${l.length}',
                'width': wordBits,
              });
              j['registers'] = l;
            }),
          ),
          child: extra.isEmpty
              ? T('None.', size: 11.5, color: p.muted)
              : Column(
                  children: [
                    for (var i = 0; i < extra.length; i++)
                      Padding(
                        key: ObjectKey(extra[i]),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: BoundTextField(
                                value: textOf(extra[i]['name']),
                                revision: draft.revision,
                                mono: true,
                                hint: 'Name',
                                onChanged: (v) =>
                                    draft.edit((_) => extra[i]['name'] = v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 100,
                              child: AppDropdown<int>(
                                value:
                                    [8, 16, 32, 64].contains(
                                      intOf(extra[i]['width'], wordBits),
                                    )
                                    ? intOf(extra[i]['width'], wordBits)
                                    : wordBits,
                                items: [
                                  for (final b in [8, 16, 32, 64])
                                    DropdownMenuItem(
                                      value: b,
                                      child: Text('$b-bit'),
                                    ),
                                ],
                                onChanged: (v) =>
                                    draft.edit((_) => extra[i]['width'] = v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 4,
                              child: BoundTextField(
                                value: textOf(extra[i]['description']),
                                revision: draft.revision,
                                hint: 'Description (optional)',
                                onChanged: (v) => draft.edit((_) {
                                  if (v.isEmpty) {
                                    extra[i].remove('description');
                                  } else {
                                    extra[i]['description'] = v;
                                  }
                                }),
                              ),
                            ),
                            MiniAction(
                              icon: AppIcons.delete,
                              tooltip: 'Remove',
                              danger: true,
                              onTap: () => draft.edit(
                                (j) =>
                                    (j['registers'] as List).remove(extra[i]),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        SectionCard(
          title: 'Flags',
          icon: Icons.flag_outlined,
          subtitle: 'Single-bit condition flags set by instructions (for example N, Z, C, V). Semantics read and write them by name.',
          child: BoundTextField(
            value: (j['flags'] is List ? (j['flags'] as List).join(', ') : ''),
            revision: draft.revision,
            mono: true,
            hint: 'N, Z, C, V',
            onChanged: (v) {
              final names = v
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              draft.edit((j) {
                if (names.isEmpty) {
                  j.remove('flags');
                } else {
                  j['flags'] = names;
                }
              });
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------

class _MemoryTab extends StatelessWidget {
  const _MemoryTab({required this.draft});
  final ProcessorDraft draft;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final regions = draft.listOf('memory');
    const perms = ['r', 'rw', 'rx', 'rwx', 'w', 'x'];
    const roles = ['', 'text', 'data', 'stack'];
    return SectionCard(
      title: 'Memory map',
      icon: Icons.grid_view_rounded,
      subtitle: 'Regions of the address space and what the processor may do in each. The assembler places .text and .data in the regions with those roles.',
      trailing: Btn(
        label: 'Add region',
        icon: AppIcons.add,
        height: 26,
        fontSize: 11,
        onClick: () => draft.edit((j) {
          final l = (j['memory'] as List?) ?? <dynamic>[];
          var next = 0;
          for (final r in l.whereType<Map>()) {
            final end = intOf(r['base'], 0) + intOf(r['size'], 0);
            if (end > next) next = end;
          }
          l.add(<String, dynamic>{
            'name': 'region${l.length}',
            'base': '0x${next.toRadixString(16)}',
            'size': '0x1000',
            'perms': 'rw',
          });
          j['memory'] = l;
        }),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: T(
                  'Name',
                  size: 10.5,
                  color: p.muted,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: T(
                  'Base address',
                  size: 10.5,
                  color: p.muted,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: T(
                  'Size',
                  size: 10.5,
                  color: p.muted,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: T(
                  'Access',
                  size: 10.5,
                  color: p.muted,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: T(
                  'Role',
                  size: 10.5,
                  color: p.muted,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 28),
            ],
          ),
          const SizedBox(height: 6),
          for (final r in regions)
            Padding(
              key: ObjectKey(r),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: BoundTextField(
                      value: textOf(r['name']),
                      revision: draft.revision,
                      mono: true,
                      onChanged: (v) => draft.edit((_) => r['name'] = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: BoundTextField(
                      value: textOf(r['base']),
                      revision: draft.revision,
                      mono: true,
                      hint: '0x0',
                      onChanged: (v) => draft.edit((_) => r['base'] = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: BoundTextField(
                      value: textOf(r['size']),
                      revision: draft.revision,
                      mono: true,
                      hint: '0x1000',
                      onChanged: (v) => draft.edit((_) => r['size'] = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 84,
                    child: AppDropdown<String>(
                      value: perms.contains(textOf(r['perms']))
                          ? textOf(r['perms'])
                          : 'rw',
                      items: [
                        for (final x in perms)
                          DropdownMenuItem(value: x, child: Text(x)),
                      ],
                      onChanged: (v) => draft.edit((_) => r['perms'] = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: AppDropdown<String>(
                      value: roles.contains(textOf(r['role']))
                          ? textOf(r['role'])
                          : '',
                      items: [
                        for (final x in roles)
                          DropdownMenuItem(
                            value: x,
                            child: Text(x.isEmpty ? 'none' : x),
                          ),
                      ],
                      onChanged: (v) => draft.edit((_) {
                        if (v == null || v.isEmpty) {
                          r.remove('role');
                        } else {
                          r['role'] = v;
                        }
                      }),
                    ),
                  ),
                  MiniAction(
                    icon: AppIcons.delete,
                    tooltip: 'Remove region',
                    danger: true,
                    onTap: () =>
                        draft.edit((j) => (j['memory'] as List).remove(r)),
                  ),
                ],
              ),
            ),
          if (regions.isEmpty)
            T('No regions yet: add at least one.', size: 11.5, color: p.err),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------

class _AdvancedTab extends StatelessWidget {
  const _AdvancedTab({required this.draft});
  final ProcessorDraft draft;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final j = draft.json;
    final pseudo = draft.listOf('pseudo');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Reset state',
          icon: Icons.restart_alt_rounded,
          subtitle: 'Where execution starts and which registers hold a value before the first instruction.',
          child: FormGrid(
            minColumnWidth: 260,
            children: [
              Labeled(
                'Reset address (pc)',
                BoundTextField(
                  value: textOf(j['resetPc']),
                  revision: draft.revision,
                  mono: true,
                  hint: '0x0',
                  onChanged: (v) => draft.set('resetPc', v),
                ),
              ),
              Labeled(
                'Initial registers',
                BoundTextField(
                  value: formatAssignments(j['init'], hex: true),
                  revision: draft.revision,
                  mono: true,
                  hint: 'sp=0x7ffe',
                  onChanged: (v) {
                    final m = parseAssignments(v);
                    if (m != null) {
                      draft.edit((j) {
                        if (m.isEmpty) {
                          j.remove('init');
                        } else {
                          j['init'] = {
                            for (final e in m.entries)
                              e.key: '0x${e.value.toRadixString(16)}',
                          };
                        }
                      });
                    }
                  },
                ),
                hint: 'name=value pairs.',
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Assembler and pipeline',
          icon: Icons.settings_suggest_outlined,
          child: FormGrid(
            minColumnWidth: 260,
            children: [
              Labeled(
                'Comment markers',
                BoundTextField(
                  value: (j['comments'] is List
                      ? (j['comments'] as List).join(' ')
                      : ''),
                  revision: draft.revision,
                  mono: true,
                  hint: '# ; //',
                  onChanged: (v) => draft.edit(
                    (j) => j['comments'] = v
                        .split(RegExp(r'\s+'))
                        .where((e) => e.isNotEmpty)
                        .toList(),
                  ),
                ),
                hint: 'Separated by spaces.',
              ),
              Labeled(
                'Pipeline stages',
                BoundTextField(
                  value: (j['pipeline'] is List
                      ? (j['pipeline'] as List).join(', ')
                      : ''),
                  revision: draft.revision,
                  mono: true,
                  hint: 'IF, ID, EX, MEM, WB',
                  onChanged: (v) {
                    final l = v
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                    draft.edit((j) {
                      if (l.isEmpty) {
                        j.remove('pipeline');
                      } else {
                        j['pipeline'] = l;
                      }
                    });
                  },
                ),
                hint: 'Informational for now.',
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Starter program',
          icon: Icons.code_rounded,
          subtitle: 'New projects for this processor begin with this code.',
          child: draft.spec != null
              ? StarterCodeEditor(draft: draft)
              : BoundTextField(
                  value: textOf(j['sample']),
                  revision: draft.revision,
                  mono: true,
                  lines: 10,
                  hint: '# assembly source',
                  onChanged: (v) => draft.set('sample', v),
                ),
        ),
        SectionCard(
          title: 'Pseudo-instructions',
          icon: Icons.auto_fix_high_rounded,
          subtitle: 'Convenience mnemonics that expand to real instructions. Edit them in the Source tab.',
          child: pseudo.isEmpty
              ? T('None defined.', size: 11.5, color: p.muted)
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final ps in pseudo)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: p.field,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: p.border),
                        ),
                        child: MonoText(textOf(ps['syntax']), size: 11),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------

class _JsonTab extends StatefulWidget {
  const _JsonTab({required this.draft});
  final ProcessorDraft draft;

  @override
  State<_JsonTab> createState() => _JsonTabState();
}

class _JsonTabState extends State<_JsonTab> {
  late final DslEditingController _c = DslEditingController(text: _pretty());
  Timer? _debounce;
  int? _errLine;
  String? _error;
  bool _edited = false;

  String _pretty() => ProcessorDsl.fromJsonMap(widget.draft.json);

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// Parses the text; null when it is fine, otherwise the problem (and its line, when known).
  ({Map<String, dynamic>? map, int? line, String? message}) _parse() {
    try {
      final text = _c.text;
      if (ProcessorDsl.looksLikeJson(text)) {
        final v = jsonDecode(text);
        if (v is! Map<String, dynamic>) {
          return (map: null, line: null, message: 'The JSON must be an object');
        }
        return (map: v, line: null, message: null);
      }
      return (map: ProcessorDsl.toJsonMap(text), line: null, message: null);
    } on DslError catch (e) {
      return (map: null, line: e.line > 0 ? e.line : null, message: e.message);
    } on FormatException catch (e) {
      return (map: null, line: null, message: 'Not valid JSON: ${e.message}');
    }
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final r = _parse();
      setState(() {
        _errLine = r.line;
        _error = r.message;
      });
    });
    if (!_edited) setState(() => _edited = true);
  }

  void _apply() {
    _debounce?.cancel();
    final r = _parse();
    if (r.map == null) {
      setState(() {
        _errLine = r.line;
        _error = r.message;
      });
      return;
    }
    widget.draft.replace(r.map!);
    setState(() {
      _errLine = null;
      _error = null;
      _edited = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      color: p.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: T(
                    'The processor exactly as it is saved in the project\'s cpu/ folder. Edit it for anything the forms do not cover, then Apply (${Platform.isMac ? '⌘' : 'Ctrl+'}Enter).',
                    size: 11.5,
                    color: p.muted,
                    overflow: TextOverflow.visible,
                  ),
                ),
                const SizedBox(width: 8),
                Btn(
                  label: 'Reload from form',
                  height: 28,
                  fontSize: 11.5,
                  onClick: () => setState(() {
                    _debounce?.cancel();
                    _c.text = _pretty();
                    _errLine = null;
                    _error = null;
                    _edited = false;
                  }),
                ),
                const SizedBox(width: 6),
                Btn(
                  label: 'Apply',
                  primary: true,
                  height: 28,
                  fontSize: 11.5,
                  onClick: _edited || _error != null ? _apply : null,
                ),
              ],
            ),
          ),
          Container(height: 1, color: p.border.withOpacity(0.7)),
          Expanded(
            child: ClipRect(
              child: SourceEditor(
                controller: _c,
                fileName:
                    '${widget.draft.id.isEmpty ? 'processor' : widget.draft.id}.cpu',
                subtitle: widget.draft.name,
                errorLine: _errLine,
                errorMessage: _error,
                onChanged: _changed,
                onSubmit: _apply,
              ),
            ),
          ),
          if (_error != null && _errLine == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: T(
                _error!,
                size: 11.5,
                color: p.err,
                overflow: TextOverflow.visible,
              ),
            ),
        ],
      ),
    );
  }
}

/// A small rounded label in the header, such as "32-bit".
class _MetaChip extends StatelessWidget {
  const _MetaChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
      ),
      child: T(text, size: 10, color: p.muted),
    );
  }
}

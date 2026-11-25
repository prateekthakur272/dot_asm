import 'package:flutter/material.dart';
import 'package:dot_asm/app/processor_draft.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/components/inputs.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/core/sim/spec/processor_spec.dart';
import 'package:dot_asm/features/processor_builder/builder_widgets.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';

String _t(Object? v) => v == null ? '' : '$v';

int _i(Object? v, int fallback) {
  if (v is int) return v;
  final s = _t(v).trim();
  if (s.startsWith('0x')) {
    return int.tryParse(s.substring(2), radix: 16) ?? fallback;
  }
  return int.tryParse(s) ?? fallback;
}

/// The instruction list of a processor: add, edit, duplicate and remove instructions, with the encoding drawn as bits.
class InstructionsTab extends StatefulWidget {
  const InstructionsTab({super.key, required this.draft});
  final ProcessorDraft draft;

  @override
  State<InstructionsTab> createState() => _InstructionsTabState();
}

class _InstructionsTabState extends State<InstructionsTab> {
  final Set<Map<String, dynamic>> _open = {};
  final ScrollController _scroll = ScrollController();
  String _query = '';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  ProcessorDraft get draft => widget.draft;

  Map<String, dynamic> _blank() {
    final bits = _i(draft.json['instrBits'], 32);
    return <String, dynamic>{
      'mnemonic': 'new',
      'syntax': '',
      'bits': bits,
      'mask': '0x0',
      'value': '0x0',
      'operands': <String, dynamic>{},
      'fields': <String, dynamic>{},
      'exec': '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final all = draft.listOf('instructions');
    final spec = draft.spec;
    final shown = [
      for (var i = 0; i < all.length; i++)
        if (_query.isEmpty ||
            _t(all[i]['mnemonic']).toLowerCase().contains(_query.toLowerCase()))
          i,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            color: p.panel,
            border: Border(
              bottom: BorderSide(color: p.border.withOpacity(0.7)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: T(
                  '${all.length} instruction${all.length == 1 ? '' : 's'}. Each one has an encoding (which bits identify it), operands (where they sit in the word) and semantics (what it does).',
                  size: 11.5,
                  color: p.muted,
                  overflow: TextOverflow.visible,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: BoundTextField(
                  value: _query,
                  height: 30,
                  hint: 'Filter…',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 8),
              Btn(
                label: 'Add instruction',
                icon: AppIcons.add,
                primary: true,
                height: 30,
                fontSize: 12,
                onClick: () {
                  final m = _blank();
                  draft.edit((j) {
                    final l = (j['instructions'] as List?) ?? <dynamic>[];
                    l.add(m);
                    j['instructions'] = l;
                  });
                  setState(() {
                    _query = '';
                    _open.add(m);
                  });
                  // Show the new instruction (it is appended at the end of the list).
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scroll.hasClients) {
                      _scroll.jumpTo(_scroll.position.maxScrollExtent);
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scroll.hasClients) {
                        _scroll.jumpTo(_scroll.position.maxScrollExtent);
                      }
                    });
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            itemCount: shown.length,
            itemBuilder: (context, k) {
              final idx = shown[k];
              final m = all[idx];
              final parsed =
                  spec != null && spec.instructions.length == all.length
                  ? spec.instructions[idx]
                  : null;
              final mn = _t(m['mnemonic']);
              final hasProblem = draft.problems.any(
                (e) => e.contains('"${mn.toLowerCase()}"'),
              );
              return _InstructionCard(
                key: ObjectKey(m),
                draft: draft,
                map: m,
                parsed: parsed,
                hasProblem: hasProblem,
                open: _open.contains(m),
                onToggle: () => setState(
                  () => _open.contains(m) ? _open.remove(m) : _open.add(m),
                ),
                onDuplicate: () {
                  final copy =
                      ProcessorDraft(<String, dynamic>{'x': m}).json['x']
                          as Map<String, dynamic>;
                  copy['mnemonic'] = '${mn}2';
                  draft.edit(
                    (j) => (j['instructions'] as List).insert(idx + 1, copy),
                  );
                  setState(() => _open.add(copy));
                },
                onDelete: () {
                  draft.edit((j) => (j['instructions'] as List).remove(m));
                  setState(() => _open.remove(m));
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({
    super.key,
    required this.draft,
    required this.map,
    required this.parsed,
    required this.hasProblem,
    required this.open,
    required this.onToggle,
    required this.onDuplicate,
    required this.onDelete,
  });

  final ProcessorDraft draft;
  final Map<String, dynamic> map;
  final InstructionSpec? parsed;
  final bool hasProblem;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  Map<String, dynamic> get _operands => (map['operands'] is Map
      ? map['operands'] as Map<String, dynamic>
      : (map['operands'] = <String, dynamic>{}));
  Map<String, dynamic> get _fields => (map['fields'] is Map
      ? map['fields'] as Map<String, dynamic>
      : (map['fields'] = <String, dynamic>{}));

  void _set(String key, Object? v) => draft.edit((_) {
    if (v == null ||
        (v is String &&
            v.isEmpty &&
            key != 'mnemonic' &&
            key != 'syntax' &&
            key != 'exec')) {
      map.remove(key);
    } else {
      map[key] = v;
    }
  });

  /// Renames an operand in both the operands and the fields map, keeping the order.
  void _rename(String from, String to) {
    if (to.isEmpty || (to != from && _operands.containsKey(to))) return;
    Map<String, dynamic> re(Map<String, dynamic> m) => {
      for (final e in m.entries) e.key == from ? to : e.key: e.value,
    };
    draft.edit((_) {
      final o = re(_operands);
      final f = re(_fields);
      map['operands'] = o;
      map['fields'] = f;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mn = _t(map['mnemonic']);
    final bits = _i(map['bits'], _i(draft.json['instrBits'], 32));
    return Container(
      decoration: BoxDecoration(
        color: open
            ? Color.alphaBlend(p.accent.withOpacity(0.04), p.panel)
            : p.panel,
        border: Border(
          bottom: BorderSide(
            color: hasProblem
                ? p.err.withOpacity(0.6)
                : p.border.withOpacity(0.6),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoverBuilder(
            cursor: SystemMouseCursors.click,
            onTap: onToggle,
            builder: (context, hovered) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              decoration: BoxDecoration(color: hovered ? p.hover : null),
              child: Row(
                children: [
                  Icon(
                    open
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    size: 16,
                    color: p.muted,
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 74,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (hasProblem ? p.err : p.accent).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: MonoText(
                      mn.isEmpty ? '?' : mn,
                      size: 12,
                      weight: FontWeight.w700,
                      color: hasProblem ? p.err : p.text,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MonoText(
                      _t(map['syntax']),
                      size: 11.5,
                      color: p.muted,
                    ),
                  ),
                  if (parsed != null)
                    Tooltip(
                      message:
                          '$bits-bit  mask ${_t(map['mask'])}  value ${_t(map['value'])}',
                      child: MiniEncoding(ins: parsed!, width: 132),
                    )
                  else
                    T('$bits-bit', size: 10.5, color: p.muted),
                  const SizedBox(width: 8),
                  if (hasProblem)
                    Icon(Icons.error_outline_rounded, size: 14, color: p.err),
                  MiniAction(
                    icon: AppIcons.copy,
                    tooltip: 'Duplicate',
                    onTap: onDuplicate,
                  ),
                  MiniAction(
                    icon: AppIcons.delete,
                    tooltip: 'Remove',
                    danger: true,
                    onTap: onDelete,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormGrid(
                    minColumnWidth: 160,
                    children: [
                      Labeled(
                        'Mnemonic',
                        BoundTextField(
                          value: mn,
                          revision: draft.revision,
                          mono: true,
                          onChanged: (v) => _set('mnemonic', v),
                        ),
                      ),
                      Labeled(
                        'Operands syntax',
                        BoundTextField(
                          value: _t(map['syntax']),
                          revision: draft.revision,
                          mono: true,
                          hint: 'rd, rs1, imm',
                          onChanged: (v) => _set('syntax', v),
                        ),
                      ),
                      Labeled(
                        'Size',
                        AppDropdown<int>(
                          value: [8, 16, 24, 32, 40, 48, 56, 64].contains(bits)
                              ? bits
                              : 32,
                          items: [
                            for (final b in [8, 16, 24, 32, 40, 48, 56, 64])
                              DropdownMenuItem(
                                value: b,
                                child: Text('$b bits'),
                              ),
                          ],
                          onChanged: (v) => _set('bits', v),
                        ),
                      ),
                      Labeled(
                        'Cycles',
                        BoundTextField(
                          value: _t(map['cycles'] ?? 1),
                          revision: draft.revision,
                          onChanged: (v) => _set(
                            'cycles',
                            v.trim() == '1' ? null : numberOrText(v),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FormGrid(
                    minColumnWidth: 220,
                    children: [
                      Labeled(
                        'Mask',
                        BoundTextField(
                          value: _t(map['mask']),
                          revision: draft.revision,
                          mono: true,
                          hint: '0xfe00707f',
                          onChanged: (v) => _set('mask', v),
                        ),
                        hint: 'Bits that identify the instruction.',
                      ),
                      Labeled(
                        'Value',
                        BoundTextField(
                          value: _t(map['value']),
                          revision: draft.revision,
                          mono: true,
                          hint: '0x00000033',
                          onChanged: (v) => _set('value', v),
                        ),
                        hint: 'What those bits must equal.',
                      ),
                    ],
                  ),
                  if (draft.json['conditions'] is Map) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.only(left: 12),
                      decoration: BoxDecoration(
                        color: p.field,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: p.border),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: T(
                              'Conditional: can take a condition suffix (addeq, bne). The condition field must stay out of the mask.',
                              size: 11.5,
                              maxLines: 2,
                            ),
                          ),
                          AppCheckbox(
                            value: map['cond'] == true,
                            onChanged: (v) => draft.edit((_) {
                              if (v) {
                                map['cond'] = true;
                              } else {
                                map.remove('cond');
                              }
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (parsed != null) ...[
                    const SizedBox(height: 12),
                    EncodingBar(ins: parsed!),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(
                        child: T(
                          'Operands',
                          size: 11.5,
                          weight: FontWeight.w700,
                        ),
                      ),
                      Btn(
                        label: 'Add operand',
                        icon: AppIcons.add,
                        height: 24,
                        fontSize: 10.5,
                        onClick: () => draft.edit((_) {
                          var n = 1;
                          while (_operands.containsKey('op$n')) {
                            n++;
                          }
                          map['operands'] = {..._operands, 'op$n': 'reg'};
                          map['fields'] = {..._fields, 'op$n': '[0:0]'};
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_operands.isEmpty)
                    T('No operands.', size: 11, color: p.muted)
                  else
                    for (var k = 0; k < _operands.keys.length; k++)
                      Builder(
                        builder: (context) {
                          final name = _operands.keys.elementAt(k);
                          final kind = _t(_operands[name]);
                          return Padding(
                            key: ValueKey('op$k'),
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: BoundTextField(
                                    value: name,
                                    revision: draft.revision,
                                    mono: true,
                                    hint: 'name',
                                    onChanged: (v) => _rename(name, v.trim()),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 150,
                                  child: AppDropdown<String>(
                                    value:
                                        const [
                                          'reg',
                                          'imm',
                                          'pcrel',
                                        ].contains(kind)
                                        ? kind
                                        : 'imm',
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'reg',
                                        child: Text('Register'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'imm',
                                        child: Text('Immediate'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'pcrel',
                                        child: Text('PC-relative'),
                                      ),
                                    ],
                                    onChanged: (v) =>
                                        draft.edit((_) => _operands[name] = v),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 5,
                                  child: BoundTextField(
                                    value: _t(_fields[name]),
                                    revision: draft.revision,
                                    mono: true,
                                    hint: 's[31:20]   or   [31,7,30:25]<<1',
                                    onChanged: (v) =>
                                        draft.edit((_) => _fields[name] = v),
                                  ),
                                ),
                                MiniAction(
                                  icon: AppIcons.close,
                                  tooltip: 'Remove operand',
                                  danger: true,
                                  onTap: () => draft.edit((_) {
                                    map['operands'] = {
                                      for (final e in _operands.entries)
                                        if (e.key != name) e.key: e.value,
                                    };
                                    map['fields'] = {
                                      for (final e in _fields.entries)
                                        if (e.key != name) e.key: e.value,
                                    };
                                  }),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  const SizedBox(height: 6),
                  T(
                    'Field syntax: [hi:lo] bit range, several ranges joined by commas (most significant first), a leading s for signed, a trailing <<n for an implicit shift.',
                    size: 10.5,
                    color: p.muted,
                    overflow: TextOverflow.visible,
                  ),
                  const SizedBox(height: 14),
                  Labeled(
                    'Semantics',
                    BoundTextField(
                      value: _t(map['exec']),
                      revision: draft.revision,
                      mono: true,
                      lines: 3,
                      hint: 'rd = rs1 + rs2;',
                      onChanged: (v) => _set('exec', v),
                    ),
                    hint: 'Statements ending in ";". Operands, registers, flags, pc, next, mem8/16/32/64[addr], if/else, halt(), trap("…"), out("int", x).',
                  ),
                  const SizedBox(height: 12),
                  Labeled(
                    'Description',
                    BoundTextField(
                      value: _t(map['description']),
                      revision: draft.revision,
                      hint: 'What the instruction does (shown in the decode view)',
                      onChanged: (v) => _set('description', v),
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

/// The whole instruction word as a thin strip: opcode bits in grey, each operand field in its own colour.
class MiniEncoding extends StatelessWidget {
  const MiniEncoding({super.key, required this.ins, this.width = 120});
  final InstructionSpec ins;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final bits = ins.bits;
    final palette = [
      p.accent,
      p.ok,
      p.warn,
      const Color(0xFFB48EAD),
      const Color(0xFF54C5F8),
      const Color(0xFFD08770),
    ];
    final names = ins.fields.keys.toList();
    final owner = List<int>.filled(bits, -1);
    for (var b = 0; b < bits; b++) {
      if (((ins.mask >> b) & 1) == 1) owner[b] = -2;
    }
    for (var k = 0; k < names.length; k++) {
      for (final s in ins.fields[names[k]]!.segments) {
        for (var b = s.lo; b <= s.hi && b < bits; b++) {
          owner[b] = k;
        }
      }
    }
    return SizedBox(
      width: width,
      height: 10,
      child: Row(
        children: [
          for (var b = bits - 1; b >= 0; b--)
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 0.6),
                decoration: BoxDecoration(
                  color: owner[b] == -1
                      ? p.border.withOpacity(0.5)
                      : owner[b] == -2
                      ? p.muted.withOpacity(0.55)
                      : palette[owner[b] % palette.length],
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Draws an instruction word: fixed (opcode) bits show their value, operand fields are coloured, free bits are dots.
class EncodingBar extends StatelessWidget {
  const EncodingBar({super.key, required this.ins});
  final InstructionSpec ins;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final bits = ins.bits;
    final palette = [
      p.accent,
      p.ok,
      p.warn,
      const Color(0xFFB48EAD),
      const Color(0xFF54C5F8),
      const Color(0xFFD08770),
    ];
    final names = ins.fields.keys.toList();
    final owner = List<int>.filled(
      bits,
      -1,
    ); // -1 free, -2 opcode, >=0 field index
    for (var b = 0; b < bits; b++) {
      if (((ins.mask >> b) & 1) == 1) owner[b] = -2;
    }
    for (var k = 0; k < names.length; k++) {
      for (final s in ins.fields[names[k]]!.segments) {
        for (var b = s.lo; b <= s.hi && b < bits; b++) {
          owner[b] = k;
        }
      }
    }
    final cells = <Widget>[];
    for (var b = bits - 1; b >= 0; b--) {
      final o = owner[b];
      final c = o >= 0 ? palette[o % palette.length] : p.muted;
      cells.add(
        Container(
          width: 16,
          height: 28,
          margin: EdgeInsets.only(right: b % 4 == 0 && b != 0 ? 5 : 1),
          decoration: BoxDecoration(
            color: o == -1
                ? Colors.transparent
                : c.withOpacity(o == -2 ? 0.12 : 0.22),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: o == -1 ? p.border : c.withOpacity(0.55)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MonoText(
                o == -2 ? '${(ins.value >> b) & 1}' : (o == -1 ? '·' : ''),
                size: 11,
                color: c,
                weight: FontWeight.w700,
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: Row(children: cells),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            _Legend(p.muted, 'opcode bits'),
            for (var k = 0; k < names.length; k++)
              _Legend(
                palette[k % palette.length],
                '${names[k]}  ${ins.fields[names[k]]!.source}',
              ),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label);
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color.withOpacity(0.5),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 5),
      MonoText(label, size: 10.5, color: context.pal.muted),
    ],
  );
}

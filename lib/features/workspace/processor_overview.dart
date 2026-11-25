import 'package:flutter/material.dart';
import 'package:dot_asm/app/sim_session.dart';
import 'package:dot_asm/components/empty_state.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/core/sim/machine/decoder.dart';
import 'package:dot_asm/core/sim/machine/machine.dart';
import 'package:dot_asm/core/sim/machine/memory.dart' show hex;
import 'package:dot_asm/core/sim/spec/processor_spec.dart';
import 'package:dot_asm/features/workspace/value_format.dart';
import 'package:dot_asm/theme/theme.dart';

const Color _kDecode = Color(0xFFB48EAD);
const Color _kBlue = Color(0xFF54C5F8);

/// A dashboard of the processor: what runs next, how the last instruction flowed through decode, execute, memory and
/// write-back, and which registers have been active.
class ProcessorOverview extends StatelessWidget {
  const ProcessorOverview({
    super.key,
    required this.sim,
    required this.machine,
    required this.onOpenTab,
  });
  final SimSession sim;
  final Machine machine;

  /// Opens another tab of the panel by id.
  final ValueChanged<String> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 700;
        final trace = machine.history.isEmpty ? null : machine.history.last;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          physics: const ClampingScrollPhysics(),
          children: [
            _Hero(sim: sim, machine: machine),
            _Title(
              'Instruction flow',
              trailing: trace == null
                  ? null
                  : 'last executed  #${machine.instructionCount}',
            ),
            if (trace == null)
              _NoTrace(color: p.muted)
            else
              _Flow(
                machine: machine,
                trace: trace,
                wide: wide,
                token: machine.instructionCount,
              ),
            _Title(
              'Register activity',
              trailing: 'open registers',
              onTrailing: () => onOpenTab('registers'),
            ),
            _Heat(machine: machine, onTap: () => onOpenTab('registers')),
            if (machine.spec.flags.isNotEmpty) ...[
              const _Title('Flags'),
              _Flags(machine: machine, trace: trace),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------

class _Title extends StatelessWidget {
  const _Title(this.text, {this.trailing, this.onTrailing});
  final String text;
  final String? trailing;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(
        children: [
          T(
            text.toUpperCase(),
            size: 10.5,
            weight: FontWeight.w700,
            color: p.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(height: 1, color: p.border.withOpacity(0.6)),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            onTrailing == null
                ? T(trailing!, size: 10, color: p.muted)
                : HoverBuilder(
                    cursor: SystemMouseCursors.click,
                    onTap: onTrailing,
                    builder: (context, hovered) => T(
                      trailing!,
                      size: 10,
                      color: hovered ? p.accent : p.muted,
                      weight: FontWeight.w600,
                    ),
                  ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Hero

Color _statusColor(Pal p, MachineStatus s) => switch (s) {
  MachineStatus.ready => p.ok,
  MachineStatus.halted => p.muted,
  MachineStatus.faulted => p.err,
  MachineStatus.empty => p.muted,
};

String _statusLabel(SimSession sim, MachineStatus s) => sim.running
    ? 'Running'
    : switch (s) {
        MachineStatus.ready => 'Ready',
        MachineStatus.halted => 'Halted',
        MachineStatus.faulted => 'Fault',
        MachineStatus.empty => 'No program',
      };

Decoded? _decodeAt(Machine m, int pc) {
  try {
    return m.decoder.decode(m.memory.fetch(pc, m.spec.maxInstrBits ~/ 8));
  } catch (_) {
    return null;
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.sim, required this.machine});
  final SimSession sim;
  final Machine machine;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = machine;
    final spec = m.spec;
    final status = m.status;
    final sc = sim.running ? p.accent : _statusColor(p, status);
    final d = m.canStep ? _decodeAt(m, m.pc) : null;
    final cpi = m.instructionCount == 0
        ? null
        : m.cycleCount / m.instructionCount;

    String headline;
    String? caption;
    switch (status) {
      case MachineStatus.ready:
        headline = d == null ? '(cannot decode)' : m.decoder.format(d, m.pc);
        caption = d == null
            ? 'No instruction decodes at this address.'
            : [
                'word ${hex(d.raw, d.instruction.bits ~/ 4)}',
                '"${d.instruction.mnemonic}"',
                if (d.instruction.description.isNotEmpty)
                  d.instruction.description.split(RegExp(r'[.\n]')).first,
              ].join('  ·  ');
      case MachineStatus.halted:
        headline = 'Program finished';
        caption = 'Reset to run it again.';
      case MachineStatus.faulted:
        headline = 'Stopped by a fault';
        caption = m.fault;
      case MachineStatus.empty:
        headline = 'No program loaded';
        caption = 'Write some assembly and it is assembled automatically.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.accent.withOpacity(0.06), p.field],
        ),
        border: Border.all(color: p.accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Pill(_statusLabel(sim, status), sc),
              const SizedBox(width: 8),
              T(
                status == MachineStatus.ready ? 'NEXT INSTRUCTION' : '',
                size: 9.5,
                weight: FontWeight.w700,
                color: p.muted,
              ),
              const Spacer(),
              T('PC', size: 10, color: p.muted, weight: FontWeight.w700),
              const SizedBox(width: 6),
              MonoText(
                hex(m.pc, spec.wordBits ~/ 4),
                size: 12,
                color: p.accent,
                weight: FontWeight.w700,
              ),
            ],
          ),
          const SizedBox(height: 10),
          MonoText(
            headline,
            size: 17,
            weight: FontWeight.w700,
            color: status == MachineStatus.faulted ? p.err : p.text,
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            T(
              caption,
              size: 11,
              color: p.muted,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  _Metric('Instructions', '${m.instructionCount}'),
                  _Metric('Cycles', '${m.cycleCount}'),
                  _Metric('CPI', cpi == null ? '–' : cpi.toStringAsFixed(2)),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: _Activity(machine: m),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        T(text, size: 10.5, weight: FontWeight.w700, color: color),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        T(label, size: 10, color: p.muted),
        const SizedBox(height: 2),
        MonoText(value, size: 15, weight: FontWeight.w700),
      ],
    );
  }
}

/// Bars for the last instructions: how many registers and memory cells each one touched.
class _Activity extends StatelessWidget {
  const _Activity({required this.machine});
  final Machine machine;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final h = machine.history;
    if (h.isEmpty) return const SizedBox.shrink();
    int work(StepTrace t) =>
        (t.regWrites.length + t.flagWrites.length + t.memAccesses.length).clamp(
          0,
          6,
        );
    return LayoutBuilder(
      builder: (context, c) {
        // As many bars as fit (5px each), up to 28.
        final fit = c.maxWidth.isFinite ? c.maxWidth : 140.0;
        final n = (fit / 5).floor().clamp(0, 28);
        final recent = h.length > n ? h.sublist(h.length - n) : h;
        if (recent.isEmpty) return const SizedBox.shrink();
        return Tooltip(
          message:
              'Registers, flags and memory cells touched by the last '
              '${recent.length} instructions',
          child: SizedBox(
            height: 30,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < recent.length; i++)
                  Container(
                    width: 3,
                    height: 4 + work(recent[i]) * 4.2,
                    margin: const EdgeInsets.only(left: 2),
                    decoration: BoxDecoration(
                      color: i == recent.length - 1
                          ? p.accent
                          : p.accent.withOpacity(
                              0.28 + 0.4 * i / recent.length,
                            ),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Flow

class _NoTrace extends StatelessWidget {
  const _NoTrace({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          const EmptyArtView(art: EmptyArt.steps, size: 84),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const T(
                  'Nothing has run yet',
                  size: 12.5,
                  weight: FontWeight.w700,
                ),
                const SizedBox(height: 3),
                T(
                  'Step or run the program to see an instruction move through decode, execute, memory and write-back.',
                  size: 11,
                  color: color,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Flow extends StatelessWidget {
  const _Flow({
    required this.machine,
    required this.trace,
    required this.wide,
    required this.token,
  });
  final Machine machine;
  final StepTrace trace;
  final bool wide;
  final int token;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final stages = [
      _Stage(
        0,
        'Decode',
        'instruction → fields',
        Icons.account_tree_outlined,
        _kDecode,
        _decodeBody(context),
      ),
      _Stage(
        1,
        'Execute',
        'what it computes',
        Icons.calculate_outlined,
        p.accent,
        _executeBody(context),
      ),
      _Stage(
        2,
        'Memory',
        'loads and stores',
        Icons.sd_storage_outlined,
        p.warn,
        _memoryBody(context),
      ),
      _Stage(
        3,
        'Write-back',
        'registers, flags, PC',
        Icons.edit_note_rounded,
        p.ok,
        _writeBody(context),
      ),
    ];
    if (wide) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < stages.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: p.muted,
                  ),
                ),
              Expanded(
                child: _StageCard(stage: stages[i], token: token),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < stages.length; i++) ...[
          if (i > 0) _Connector(color: stages[i].color),
          _StageCard(stage: stages[i], token: token),
        ],
      ],
    );
  }

  // --- stage contents ---

  Decoded? get _d => trace.decoded;

  /// The value a register had before the instruction ran.
  int _before(int reg) {
    for (final c in trace.regWrites) {
      if (c.index == reg) return c.oldValue;
    }
    return machine.register(reg);
  }

  String _operand(String name, Decoded d) {
    final spec = machine.spec;
    final v = d.operands[name] ?? 0;
    switch (d.instruction.operands[name]!) {
      case OperandKind.reg:
        final al = spec.registerAliases(v);
        return '${spec.registerName(v)}${al.isEmpty ? '' : ' (${al.first})'}';
      case OperandKind.imm:
        return '$v';
      case OperandKind.pcrel:
        return 'pc ${v < 0 ? '-' : '+'} ${v.abs()}';
    }
  }

  Widget _decodeBody(BuildContext context) {
    final p = context.pal;
    final d = _d;
    if (d == null) {
      return T('The instruction could not be decoded.', size: 11, color: p.err);
    }
    final names = d.instruction.fields.keys.toList();
    final palette = [
      p.accent,
      p.ok,
      p.warn,
      _kDecode,
      _kBlue,
      const Color(0xFFD08770),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MonoText(trace.text, size: 12, weight: FontWeight.w700),
        const SizedBox(height: 8),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (var i = 0; i < names.length; i++)
              _Tag(
                '${names[i]}  ${_operand(names[i], d)}',
                palette[i % palette.length],
              ),
          ],
        ),
        const SizedBox(height: 8),
        T(
          'word ${hex(d.raw, d.instruction.bits ~/ 4)} matched "${d.instruction.mnemonic}"',
          size: 10,
          color: p.muted,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _executeBody(BuildContext context) {
    final p = context.pal;
    final d = _d;
    if (d == null) return T('–', size: 11, color: p.muted);
    final ins = d.instruction;
    final spec = machine.spec;
    final inputs = <String>[
      for (final e in ins.operands.entries)
        if (e.value == OperandKind.reg)
          '${e.key} = ${formatValue(_before(d.operands[e.key] ?? 0), spec.registerWidth(d.operands[e.key] ?? 0), ValueFormat.hex)}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: p.bg.withOpacity(0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: MonoText(
            ins.exec.isEmpty ? '(no effect)' : ins.exec,
            size: 10.5,
            maxLines: 5,
            softWrap: true,
          ),
        ),
        if (inputs.isNotEmpty) ...[
          const SizedBox(height: 8),
          T('registers before', size: 9.5, color: p.muted),
          const SizedBox(height: 4),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [for (final s in inputs) _Tag(s, p.muted)],
          ),
        ],
        const SizedBox(height: 8),
        T(
          '${trace.cycles} cycle${trace.cycles == 1 ? '' : 's'}',
          size: 10,
          color: p.muted,
        ),
      ],
    );
  }

  Widget _memoryBody(BuildContext context) {
    final p = context.pal;
    if (trace.memAccesses.isEmpty) {
      return T('No memory access', size: 11, color: p.muted);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in trace.memAccesses)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  a.write
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 13,
                  color: a.write ? p.warn : p.ok,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: MonoText(
                    '${a.write ? 'store' : 'load'} ${a.size}B  ${hex(a.address)}',
                    size: 10.5,
                    color: a.write ? p.warn : p.ok,
                  ),
                ),
              ],
            ),
          ),
        for (final a in trace.memAccesses.take(1))
          MonoText(
            'value ${formatValue(a.value, a.size * 8, ValueFormat.hex)}',
            size: 10.5,
            color: p.muted,
          ),
      ],
    );
  }

  Widget _writeBody(BuildContext context) {
    final p = context.pal;
    final spec = machine.spec;
    final empty =
        trace.regWrites.isEmpty &&
        trace.flagWrites.isEmpty &&
        trace.output.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in trace.regWrites)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Wrap(
              spacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Tag(spec.registerName(c.index), p.ok),
                MonoText(
                  formatValue(
                    c.oldValue,
                    spec.registerWidth(c.index),
                    ValueFormat.hex,
                  ),
                  size: 10,
                  color: p.muted,
                ),
                Icon(Icons.arrow_right_alt_rounded, size: 13, color: p.muted),
                MonoText(
                  formatValue(
                    c.newValue,
                    spec.registerWidth(c.index),
                    ValueFormat.hex,
                  ),
                  size: 10.5,
                  color: p.ok,
                  weight: FontWeight.w700,
                ),
              ],
            ),
          ),
        for (final f in trace.flagWrites)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Wrap(
              spacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Tag('flag ${f.name}', p.warn),
                MonoText(
                  '${f.oldValue} → ${f.newValue}',
                  size: 10.5,
                  color: p.warn,
                ),
              ],
            ),
          ),
        if (trace.output.isNotEmpty)
          _Tag('print  ${trace.output.trim()}', p.muted),
        if (empty) T('No register or flag changed', size: 11, color: p.muted),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            T('PC', size: 10, color: p.muted, weight: FontWeight.w700),
            MonoText(
              '${hex(trace.pcBefore, spec.wordBits ~/ 4)} → ${hex(machine.pc, spec.wordBits ~/ 4)}',
              size: 10,
              maxLines: 2,
              softWrap: true,
              color: trace.pcAfter == trace.pcBefore + trace.length
                  ? p.muted
                  : p.accent,
            ),
          ],
        ),
      ],
    );
  }
}

class _Stage {
  const _Stage(
    this.index,
    this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.body,
  );
  final int index;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget body;
}

/// One stage of the flow. Its border lights up each time a new instruction has been executed, then fades.
class _StageCard extends StatelessWidget {
  const _StageCard({required this.stage, required this.token});
  final _Stage stage;
  final int token;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = stage.color;
    return TweenAnimationBuilder<double>(
      key: ValueKey('${stage.index}-$token'),
      tween: Tween(begin: 1, end: 0),
      duration: Duration(milliseconds: 500 + stage.index * 220),
      curve: Curves.easeOut,
      builder: (context, t, child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Color.lerp(p.field, c.withOpacity(0.12), t),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Color.lerp(p.border, c.withOpacity(0.8), t)!,
          ),
          boxShadow: [
            if (t > 0.01)
              BoxShadow(color: c.withOpacity(0.22 * t), blurRadius: 14 * t),
          ],
        ),
        child: child,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: c.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(stage.icon, size: 14, color: c),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    T(stage.title, size: 12, weight: FontWeight.w700),
                    T(stage.subtitle, size: 9.5, color: p.muted, maxLines: 1),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          stage.body,
        ],
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 18,
    child: Center(
      child: Icon(
        Icons.arrow_downward_rounded,
        size: 14,
        color: color.withOpacity(0.8),
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.13),
      borderRadius: BorderRadius.circular(4),
    ),
    child: MonoText(text, size: 10, color: color),
  );
}

// ---------------------------------------------------------------------------------------------------------------
// Register activity

class _Heat extends StatelessWidget {
  const _Heat({required this.machine, required this.onTap});
  final Machine machine;
  final VoidCallback onTap;

  static const int _window = 24;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final spec = machine.spec;
    final h = machine.history;
    // How many instructions ago each register was last written.
    final age = <int, int>{};
    for (var k = 1; k <= h.length && k <= _window; k++) {
      for (final w in h[h.length - k].regWrites) {
        age.putIfAbsent(w.index, () => k - 1);
      }
    }
    final read = <int>{};
    final last = h.isEmpty ? null : h.last;
    final d = last?.decoded;
    if (d != null) {
      for (final e in d.instruction.operands.entries) {
        if (e.value == OperandKind.reg) read.add(d.operands[e.key] ?? 0);
      }
    }
    final wide = spec.registerCount > 16;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var i = 0; i < spec.registerCount; i++)
                _tile(context, i, age[i], read.contains(i), wide),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _Key(p.accent, 'written by the last instruction'),
              _Key(p.accent.withOpacity(0.35), 'written recently'),
              _Key(p.ok, 'read by the last instruction'),
              _Key(p.muted.withOpacity(0.55), 'holds a value', outlined: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, int i, int? age, bool isRead, bool small) {
    final p = context.pal;
    final spec = machine.spec;
    final value = machine.register(i);
    final w = spec.registerWidth(i);
    final al = spec.registerAliases(i);
    Color fill;
    if (age == 0) {
      fill = p.accent.withOpacity(0.85);
    } else if (age != null) {
      fill = p.accent.withOpacity(0.12 + 0.3 * (1 - age / _window));
    } else if (value != 0) {
      fill = p.field;
    } else {
      fill = p.bg.withOpacity(0.5);
    }
    final label = spec.registerName(i);
    return Tooltip(
      message:
          '$label${al.isEmpty ? '' : ' (${al.first})'} = ${formatValue(value, w, ValueFormat.hex)}\n'
          '${formatValue(value, w, ValueFormat.dec)}'
          '${age == null ? '' : '\nwritten ${age == 0 ? 'by the last instruction' : '$age instruction${age == 1 ? '' : 's'} earlier'}'}'
          '${isRead ? '\nread by the last instruction' : ''}',
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: small ? 38 : 46,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: isRead
                    ? p.ok
                    : (age == null && value != 0
                          ? p.muted.withOpacity(0.55)
                          : Colors.transparent),
                width: 1.5,
              ),
            ),
            child: MonoText(
              label,
              size: 10,
              weight: age == 0 ? FontWeight.w700 : FontWeight.w500,
              color: age == 0
                  ? p.onAccent
                  : (value == 0 && age == null ? p.muted : p.text),
            ),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.color, this.label, {this.outlined = false});
  final Color color;
  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: outlined ? null : color,
          border: outlined ? Border.all(color: color, width: 1.5) : null,
          borderRadius: BorderRadius.circular(2.5),
        ),
      ),
      const SizedBox(width: 5),
      T(label, size: 9.5, color: context.pal.muted),
    ],
  );
}

class _Flags extends StatelessWidget {
  const _Flags({required this.machine, required this.trace});
  final Machine machine;
  final StepTrace? trace;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final changed = {
      for (final f in trace?.flagWrites ?? const <FlagChange>[]) f.name,
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in machine.spec.flags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: machine.flag(f) == 1
                  ? p.accent.withOpacity(0.15)
                  : p.field,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: changed.contains(f)
                    ? p.accent
                    : (machine.flag(f) == 1
                          ? p.accent.withOpacity(0.4)
                          : p.border),
                width: changed.contains(f) ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MonoText(
                  f,
                  size: 12,
                  weight: FontWeight.w700,
                  color: machine.flag(f) == 1 ? p.accent : p.muted,
                ),
                const SizedBox(width: 8),
                Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: machine.flag(f) == 1
                        ? p.accent
                        : p.muted.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: MonoText(
                    '${machine.flag(f)}',
                    size: 10.5,
                    weight: FontWeight.w700,
                    color: machine.flag(f) == 1 ? p.onAccent : p.muted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

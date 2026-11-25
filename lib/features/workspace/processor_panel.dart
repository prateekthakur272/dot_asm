import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dot_asm/components/empty_state.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/app/sim_session.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/core/sim/machine/decoder.dart';
import 'package:dot_asm/core/sim/machine/machine.dart';
import 'package:dot_asm/core/sim/machine/memory.dart' show hex;
import 'package:dot_asm/core/sim/spec/processor_spec.dart';
import 'package:dot_asm/features/workspace/processor_overview.dart';
import 'package:dot_asm/features/workspace/value_format.dart';
import 'package:dot_asm/theme/theme.dart';

enum PanelTab {
  overview('overview', 'Overview', Icons.space_dashboard_outlined),
  registers('registers', 'Registers', Icons.developer_board_rounded),
  memory('memory', 'Memory', Icons.grid_view_rounded),
  disassembly('disassembly', 'Disassembly', Icons.list_alt_rounded),
  decode('decode', 'Decode', Icons.account_tree_outlined),
  trace('trace', 'Trace', Icons.history_rounded);

  const PanelTab(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;

  static PanelTab fromId(String id) =>
      values.firstWhere((t) => t.id == id, orElse: () => overview);
}

/// The live internal view of the processor of the open project.
class ProcessorPanel extends StatefulWidget {
  const ProcessorPanel({super.key, required this.state});
  final AppState state;

  @override
  State<ProcessorPanel> createState() => _ProcessorPanelState();
}

class _ProcessorPanelState extends State<ProcessorPanel> {
  late ValueFormat _format = ValueFormat.values.firstWhere(
    (f) => f.name == widget.state.settings.valueFormat,
    orElse: () => ValueFormat.hex,
  );
  int? _memTarget;
  int _memTick = 0;

  void _showInMemory(int addr) {
    setState(() {
      _memTarget = addr;
      _memTick++;
    });
    widget.state.setPanelTab(PanelTab.memory.id);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final state = widget.state;
    final tab = PanelTab.fromId(state.uiState.panelTab);
    return Container(
      color: p.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final showIcons = c.maxWidth / PanelTab.values.length >= 104;
                return Row(
                  children: [
                    for (final t in PanelTab.values)
                      Expanded(
                        child: HoverBuilder(
                          cursor: SystemMouseCursors.click,
                          onTap: () => state.setPanelTab(t.id),
                          builder: (context, hovered) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: t == tab
                                      ? p.accent
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (showIcons) ...[
                                  Icon(
                                    t.icon,
                                    size: 13,
                                    color: t == tab ? p.accent : p.muted,
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                Flexible(
                                  child: T(
                                    t.label,
                                    size: 11.5,
                                    maxLines: 1,
                                    weight: t == tab
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: t == tab
                                        ? p.text
                                        : (hovered ? p.text : p.muted),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (tab == PanelTab.registers || tab == PanelTab.memory)
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: p.border.withOpacity(0.6)),
                ),
              ),
              child: Row(
                children: [
                  T('Show as', size: 10.5, color: p.muted),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: _FormatMenu(
                        value: _format,
                        onChanged: (f) {
                          setState(() => _format = f);
                          // The choice is remembered as the default for next time.
                          state.updateSettings(
                            state.settings.copyWith(valueFormat: f.name),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListenableBuilder(
              listenable: state.sim,
              builder: (context, _) {
                final sim = state.sim;
                final m = sim.machine;
                if (m == null) return const SizedBox.shrink();
                return switch (tab) {
                  PanelTab.overview => ProcessorOverview(
                    sim: sim,
                    machine: m,
                    onOpenTab: state.setPanelTab,
                  ),
                  PanelTab.registers => _RegistersView(
                    sim: sim,
                    machine: m,
                    format: _format,
                    onShowInMemory: _showInMemory,
                  ),
                  PanelTab.memory => _MemoryView(
                    sim: sim,
                    machine: m,
                    format: _format,
                    jumpTo: _memTarget,
                    jumpTick: _memTick,
                  ),
                  PanelTab.disassembly => _DisassemblyView(
                    sim: sim,
                    machine: m,
                  ),
                  PanelTab.decode => _DecodeView(sim: sim, machine: m),
                  PanelTab.trace => _TraceView(sim: sim, machine: m),
                };
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatMenu extends StatelessWidget {
  const _FormatMenu({required this.value, required this.onChanged});
  final ValueFormat value;
  final ValueChanged<ValueFormat> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
      children: [
        for (final f in ValueFormat.values)
          HoverBuilder(
            cursor: SystemMouseCursors.click,
            onTap: () => onChanged(f),
            builder: (context, hovered) => Container(
              margin: const EdgeInsets.only(left: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: f == value
                    ? p.accent.withOpacity(0.14)
                    : (hovered ? p.hover : Colors.transparent),
                borderRadius: BorderRadius.circular(4),
              ),
              child: T(
                f.label,
                size: 10.5,
                weight: FontWeight.w600,
                color: f == value ? p.accent : p.muted,
              ),
            ),
          ),
      ],
    );
  }
}

Color _statusColor(Pal p, MachineStatus s) => switch (s) {
  MachineStatus.ready => p.ok,
  MachineStatus.halted => p.muted,
  MachineStatus.faulted => p.err,
  MachineStatus.empty => p.muted,
};

String _statusLabel(MachineStatus s) => switch (s) {
  MachineStatus.ready => 'Ready',
  MachineStatus.halted => 'Halted',
  MachineStatus.faulted => 'Fault',
  MachineStatus.empty => 'No program',
};

// ---------------------------------------------------------------------------------------------------------------

/// A small text field for editing a value in place. Enter commits, Escape (or losing focus) cancels.
class _InlineEdit extends StatefulWidget {
  const _InlineEdit({
    required this.initial,
    required this.onSubmit,
    required this.onCancel,
    this.size = 11.5,
    this.maxLength,
    this.align = TextAlign.right,
  });
  final String initial;
  final bool Function(String text) onSubmit;
  final VoidCallback onCancel;
  final double size;
  final int? maxLength;
  final TextAlign align;

  @override
  State<_InlineEdit> createState() => _InlineEditState();
}

class _InlineEditState extends State<_InlineEdit> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );
  late final FocusNode _focus = FocusNode();
  bool _bad = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
    _focus.addListener(() {
      if (!_focus.hasFocus && !_done) {
        _done = true;
        widget.onCancel();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.onSubmit(_c.text)) {
      _done = true;
    } else {
      setState(() => _bad = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final field = Focus(
      onKeyEvent: (node, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          _done = true;
          widget.onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: _c,
        focusNode: _focus,
        autofocus: true,
        maxLength: widget.maxLength,
        textAlign: widget.align,
        // Without this, Enter would take the focus away (and cancel the edit) even when the value is rejected.
        onEditingComplete: () {},
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_bad) setState(() => _bad = false);
        },
        cursorColor: p.accent,
        style: TextStyle(
          fontFamily: kMonoFamily,
          fontFamilyFallback: kMonoFallback,
          fontSize: widget.size,
          color: _bad ? p.err : p.text,
        ),
        decoration: const InputDecoration.collapsed(hintText: '')
            .copyWith(counterText: ''),
      ),
    );
    return field;
  }
}

/// What the user edits in the register view.
enum _Target { none, pc }

class _RegistersView extends StatefulWidget {
  const _RegistersView({
    required this.sim,
    required this.machine,
    required this.format,
    required this.onShowInMemory,
  });
  final SimSession sim;
  final Machine machine;
  final ValueFormat format;
  final ValueChanged<int> onShowInMemory;

  @override
  State<_RegistersView> createState() => _RegistersViewState();
}

class _RegistersViewState extends State<_RegistersView> {
  int? _editing; // register index
  _Target _target = _Target.none;

  SimSession get sim => widget.sim;
  Machine get machine => widget.machine;
  ValueFormat get format => widget.format;

  void _stop() => setState(() {
    _editing = null;
    _target = _Target.none;
  });

  bool _commitRegister(int i, String text) {
    final v = parseValue(text);
    if (v == null) return false;
    sim.editRegister(i, v);
    _stop();
    return true;
  }

  bool _commitPc(String text) {
    final v = parseValue(text);
    if (v == null) return false;
    sim.editPc(v);
    _stop();
    return true;
  }

  String _tip(int value, int width) => [
    for (final f in ValueFormat.values)
      '${f.label}: ${formatValue(value, width, f)}',
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final spec = machine.spec;
    final changed = sim.changedRegisters;
    final changedFlags = sim.changedFlags;
    final editable = !sim.running;
    final prev = {
      for (final c in sim.lastTrace?.regWrites ?? const <RegChange>[])
        c.index: c.oldValue,
    };

    Widget cell(int i, int cols) {
      final isChanged = changed.contains(i);
      final w = spec.registerWidth(i);
      final aliases = spec.registerAliases(i);
      final value = machine.register(i);
      final isZero = i == spec.zeroRegister;
      final pinned = sim.watched.contains(i);
      final points = machine.memory.regionAt(value) != null && value != 0;
      final nonZero = value != 0;
      return HoverBuilder(
        cursor: editable && !isZero
            ? SystemMouseCursors.text
            : SystemMouseCursors.basic,
        onTap: editable && !isZero ? () => setState(() => _editing = i) : null,
        builder: (context, hovered) => Container(
          height: 32,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: isChanged
                ? p.accent.withOpacity(0.13)
                : (hovered ? p.hover : p.field),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _editing == i
                  ? p.accent
                  : (isChanged
                        ? p.accent.withOpacity(0.55)
                        : p.border.withOpacity(0.8)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                color: isChanged ? p.accent : Colors.transparent,
              ),
              const SizedBox(width: 7),
              SizedBox(
                width: 34,
                child: T(
                  spec.registerName(i),
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: isChanged ? p.accent : p.text,
                ),
              ),
              Expanded(
                child: T(
                  aliases.isEmpty ? '' : aliases.first,
                  size: 10.5,
                  color: p.muted,
                  maxLines: 1,
                ),
              ),
              if (isChanged && cols == 1 && _editing != i) ...[
                MonoText(
                  formatValue(prev[i] ?? 0, w, format),
                  size: 10,
                  color: p.muted.withOpacity(0.8),
                ),
                Icon(Icons.arrow_right_alt_rounded, size: 13, color: p.muted),
              ],
              if (_editing == i)
                SizedBox(
                  width: 110,
                  child: _InlineEdit(
                    initial: formatValue(value, w, ValueFormat.hex),
                    onSubmit: (t) => _commitRegister(i, t),
                    onCancel: _stop,
                  ),
                )
              else
                Tooltip(
                  message: [
                    _tip(value, w),
                    if (isChanged)
                      'Was: ${formatValue(prev[i] ?? 0, w, format)}',
                  ].join('\n'),
                  waitDuration: const Duration(milliseconds: 500),
                  child: _Value(
                    formatValue(value, w, format),
                    color: isChanged ? p.accent : (nonZero ? p.text : p.muted),
                    bold: isChanged,
                    dimZeros: format == ValueFormat.hex,
                  ),
                ),
              if (points && (hovered || pinned) && _editing != i)
                _MiniAction(
                  icon: Icons.memory_rounded,
                  tooltip: 'Show in memory',
                  onTap: () => widget.onShowInMemory(value),
                ),
              if (hovered || pinned)
                _MiniAction(
                  icon: pinned ? Icons.star_rounded : Icons.star_border_rounded,
                  tooltip: pinned ? 'Unpin' : 'Pin to the top',
                  active: pinned,
                  onTap: () => sim.toggleWatch(i),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      );
    }

    Widget grid(List<int> regs, int cols) => Column(
      children: [
        for (var i = 0; i < regs.length; i += cols) ...[
          Row(
            children: [
              for (var k = 0; k < cols; k++) ...[
                if (k > 0) const SizedBox(width: 6),
                Expanded(
                  child: i + k < regs.length
                      ? cell(regs[i + k], cols)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 430 ? 2 : 1;
        final pins = sim.watched.where((i) => i < spec.registerCount).toList()
          ..sort();
        return ListView(
          padding: const EdgeInsets.all(12),
          physics: const ClampingScrollPhysics(),
          children: [
            Row(
              children: [
                _Stat(
                  'PC',
                  hex(machine.pc, spec.wordBits ~/ 4),
                  p.accent,
                  tooltip: editable ? 'Click to set the program counter' : null,
                  onTap: editable
                      ? () => setState(() => _target = _Target.pc)
                      : null,
                  editor: _target == _Target.pc
                      ? _InlineEdit(
                          initial: hex(machine.pc, spec.wordBits ~/ 4),
                          align: TextAlign.left,
                          onSubmit: _commitPc,
                          onCancel: _stop,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                _Stat(
                  'State',
                  _statusLabel(machine.status),
                  _statusColor(p, machine.status),
                ),
                const SizedBox(width: 8),
                _Stat('Instructions', '${machine.instructionCount}', p.text),
                const SizedBox(width: 8),
                _Stat('Cycles', '${machine.cycleCount}', p.text),
              ],
            ),
            if (machine.fault != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p.err.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: p.err.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, size: 15, color: p.err),
                    const SizedBox(width: 8),
                    Expanded(
                      child: T(
                        machine.fault!,
                        size: 11.5,
                        color: p.err,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (spec.flags.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectionHeader(
                'Flags',
                hint: editable ? 'click to toggle' : null,
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in spec.flags)
                    HoverBuilder(
                      cursor: editable
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic,
                      onTap: editable
                          ? () => sim.editFlag(f, machine.flag(f) ^ 1)
                          : null,
                      builder: (context, hovered) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: machine.flag(f) == 1
                              ? p.accent.withOpacity(hovered ? 0.26 : 0.16)
                              : (hovered ? p.hover : p.field),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: changedFlags.contains(f)
                                ? p.accent
                                : p.border,
                            width: changedFlags.contains(f) ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: machine.flag(f) == 1
                                    ? p.accent
                                    : p.muted.withOpacity(0.35),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            MonoText(
                              f,
                              size: 11.5,
                              weight: FontWeight.w700,
                              color: machine.flag(f) == 1 ? p.accent : p.muted,
                            ),
                            const SizedBox(width: 6),
                            MonoText(
                              '${machine.flag(f)}',
                              size: 11.5,
                              color: machine.flag(f) == 1 ? p.accent : p.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (pins.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectionHeader('Watch', count: pins.length),
              grid(pins, cols),
            ],
            const SizedBox(height: 12),
            _SectionHeader(
              'Registers',
              count: spec.registerCount,
              hint: editable ? 'click a value to edit it' : null,
            ),
            grid([for (var i = 0; i < spec.registerCount; i++) i], cols),
          ],
        );
      },
    );
  }
}

/// A small upper-case heading for a block of the panel, with an optional count and hint.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.count, this.hint});
  final String title;
  final int? count;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Row(
        children: [
          T(
            title.toUpperCase(),
            size: 10.5,
            weight: FontWeight.w700,
            color: p.muted,
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: p.field,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: p.border),
              ),
              child: T('$count', size: 9.5, color: p.muted),
            ),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: Container(height: 1, color: p.border.withOpacity(0.6)),
          ),
          if (hint != null) ...[
            const SizedBox(width: 10),
            T(hint!, size: 10, color: p.muted.withOpacity(0.8)),
          ],
        ],
      ),
    );
  }
}

/// A number in monospace; in hex the leading zeros are dimmed so the significant digits stand out.
class _Value extends StatelessWidget {
  const _Value(
    this.text, {
    this.color,
    this.bold = false,
    this.dimZeros = false,
  });
  final String text;
  final Color? color;
  final bool bold;
  final bool dimZeros;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = color ?? p.text;
    final base = TextStyle(
      fontFamily: kMonoFamily,
      fontFamilyFallback: kMonoFallback,
      fontSize: 11.5,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: c,
    );
    if (!dimZeros || !text.startsWith('0x') || text.length < 4) {
      return Text(text, maxLines: 1, style: base);
    }
    final digits = text.substring(2);
    var zeros = RegExp(r'^0*').stringMatch(digits)!.length;
    final dim = c.withOpacity(0.38);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(
            text: '0x${digits.substring(0, zeros)}',
            style: base.copyWith(color: dim),
          ),
          TextSpan(text: digits.substring(zeros)),
        ],
      ),
      maxLines: 1,
    );
  }
}

/// A tiny icon button used inside cells and rows.
class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(icon, size: 14, color: active ? p.warn : p.muted),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(
    this.label,
    this.value,
    this.color, {
    this.onTap,
    this.tooltip,
    this.editor,
  });
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  final String? tooltip;
  final Widget? editor;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget box(bool hovered) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: hovered ? p.hover : p.field,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: editor != null ? p.accent : p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          T(label, size: 10, color: p.muted),
          const SizedBox(height: 1),
          editor ??
              MonoText(
                value,
                size: 11.5,
                color: color,
                weight: FontWeight.w700,
              ),
        ],
      ),
    );
    if (onTap == null) return Expanded(child: box(false));
    return Expanded(
      child: Tooltip(
        message: tooltip ?? '',
        child: HoverBuilder(
          cursor: SystemMouseCursors.text,
          onTap: onTap,
          builder: (context, hovered) => box(hovered),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------

class _MemoryView extends StatefulWidget {
  const _MemoryView({
    required this.sim,
    required this.machine,
    required this.format,
    this.jumpTo,
    this.jumpTick = 0,
  });
  final SimSession sim;
  final Machine machine;
  final ValueFormat format;

  /// An address to scroll to when [jumpTick] changes (and when the view first appears).
  final int? jumpTo;
  final int jumpTick;

  @override
  State<_MemoryView> createState() => _MemoryViewState();
}

class _MemoryViewState extends State<_MemoryView> {
  int _region = 0;
  int _perRow = 8;
  int? _selected; // address
  int? _editAddr;
  bool _gotoBad = false;
  final ScrollController _scroll = ScrollController();
  final TextEditingController _goto = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.jumpTo != null) _scheduleJump(widget.jumpTo!);
  }

  @override
  void didUpdateWidget(_MemoryView old) {
    super.didUpdateWidget(old);
    if (widget.jumpTick != old.jumpTick && widget.jumpTo != null) {
      _scheduleJump(widget.jumpTo!);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _goto.dispose();
    super.dispose();
  }

  static String _size(int bytes) => bytes >= 1024 * 1024
      ? '${bytes ~/ (1024 * 1024)} MiB'
      : bytes >= 1024
      ? '${bytes ~/ 1024} KiB'
      : '$bytes bytes';

  void _scheduleJump(int addr) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jump(addr);
      });

  /// Shows [addr]: switches to its region, scrolls there and selects the byte. False when it is not mapped.
  bool _jump(int addr) {
    final spec = widget.machine.spec;
    final idx = spec.memory.indexWhere((r) => addr >= r.base && addr < r.end);
    if (idx < 0) return false;
    setState(() {
      _region = idx;
      _selected = addr;
      _editAddr = null;
    });
    final row = (addr - spec.memory[idx].base) ~/ _perRow;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(
          (row * 20.0 - 40).clamp(0.0, _scroll.position.maxScrollExtent),
        );
      }
    });
    return true;
  }

  void _submitGoto(String text) {
    final v = parseValue(text);
    final ok = v != null && _jump(v);
    setState(() => _gotoBad = !ok);
  }

  bool _commitByte(int addr, String text) {
    // A bare one or two digits are hex, like the cell shows them.
    final t = text.trim();
    final v = RegExp(r'^[0-9a-fA-F]{1,2}$').hasMatch(t)
        ? int.parse(t, radix: 16)
        : parseValue(t);
    if (v == null || v < -128 || v > 255) return false;
    widget.sim.editByte(addr, v);
    setState(() => _editAddr = null);
    return true;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      _perRow = c.maxWidth >= 620 ? 16 : 8;
      return _content(context, _perRow);
    },
  );

  Widget _content(BuildContext context, int perRow) {
    final p = context.pal;
    final m = widget.machine;
    final spec = m.spec;
    if (spec.memory.isEmpty) return const SizedBox.shrink();
    final region = spec.memory[_region.clamp(0, spec.memory.length - 1)];
    final rows = (region.size + perRow - 1) ~/ perRow;
    final last = widget.sim.lastTrace;
    final touched = <int, bool>{}; // address → wrote
    for (final a in last?.memAccesses ?? const <MemAccess>[]) {
      for (var i = 0; i < a.size; i++) {
        touched[a.address + i] = a.write || (touched[a.address + i] ?? false);
      }
    }
    final pcRow = m.pc >= region.base && m.pc < region.end
        ? (m.pc - region.base) ~/ perRow
        : null;

    final spIdx = spec.registerIndexByName('sp');
    final colWidth = 22.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < spec.memory.length; i++)
                      HoverBuilder(
                        cursor: SystemMouseCursors.click,
                        onTap: () => setState(() {
                          _region = i;
                          if (_scroll.hasClients) _scroll.jumpTo(0);
                        }),
                        builder: (context, hovered) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: i == _region
                                ? p.accent.withOpacity(0.14)
                                : (hovered ? p.hover : Colors.transparent),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: i == _region
                                  ? p.accent.withOpacity(0.7)
                                  : p.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              T(
                                spec.memory[i].name,
                                size: 11,
                                color: i == _region ? p.accent : p.text,
                                weight: FontWeight.w600,
                              ),
                              const SizedBox(width: 5),
                              T(
                                spec.memory[i].perms,
                                size: 9.5,
                                color: p.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _SmallLink('PC', () => _jump(m.pc)),
              if (spIdx != null)
                _SmallLink('SP', () => _jump(m.register(spIdx))),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: T(
                  '${hex(region.base)} – ${hex(region.end - 1)}  ·  ${_size(region.size)}',
                  size: 10.5,
                  color: p.muted,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 168,
                height: 26,
                child: TextField(
                  controller: _goto,
                  onSubmitted: _submitGoto,
                  onChanged: (_) {
                    if (_gotoBad) setState(() => _gotoBad = false);
                  },
                  cursorColor: p.accent,
                  style: TextStyle(
                    fontFamily: kMonoFamily,
                    fontFamilyFallback: kMonoFallback,
                    fontSize: 11.5,
                    color: _gotoBad ? p.err : p.text,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 14,
                      color: p.muted,
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 26,
                    ),
                    hintText: 'Go to 0x…',
                    hintStyle: TextStyle(fontSize: 11, color: p.muted),
                    filled: true,
                    fillColor: p.field,
                    contentPadding: const EdgeInsets.only(right: 8),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide(
                        color: _gotoBad ? p.err : p.border,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide(
                        color: _gotoBad ? p.err : p.accent.withOpacity(0.7),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Column offsets
        Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: p.field.withOpacity(0.6),
            border: Border(
              top: BorderSide(color: p.border.withOpacity(0.6)),
              bottom: BorderSide(color: p.border.withOpacity(0.6)),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: (2 + spec.wordBits ~/ 4) * 6.7 + 12,
                child: T('Address', size: 9.5, color: p.muted),
              ),
              for (var i = 0; i < perRow; i++) ...[
                SizedBox(
                  width: colWidth,
                  child: Center(
                    child: MonoText(
                      i.toRadixString(16).padLeft(2, '0'),
                      size: 9.5,
                      color: p.muted.withOpacity(0.8),
                    ),
                  ),
                ),
                if (i == perRow ~/ 2 - 1) const SizedBox(width: 6),
              ],
              const SizedBox(width: 10),
              T('ASCII', size: 9.5, color: p.muted),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            itemExtent: 20,
            itemCount: rows,
            physics: const ClampingScrollPhysics(),
            itemBuilder: (context, row) {
              final addr = region.base + row * perRow;
              final bytes = m.memory.peek(addr, perRow);
              final isPcRow = pcRow == row;
              final children = <Widget>[];
              for (var i = 0; i < perRow; i++) {
                final a = addr + i;
                final t = touched[a];
                final dirty = m.memory.dirty.contains(a);
                final color = t == true
                    ? p.warn
                    : t == false
                    ? p.accent
                    : dirty
                    ? p.ok
                    : (bytes[i] == 0 ? p.muted.withOpacity(0.55) : p.text);
                final isSel = _selected == a;
                final canEdit = !widget.sim.running;
                children.add(
                  HoverBuilder(
                    cursor: SystemMouseCursors.click,
                    onTap: () => setState(() {
                      _selected = a;
                      _editAddr = null;
                    }),
                    onDoubleTap: canEdit
                        ? () => setState(() {
                            _selected = a;
                            _editAddr = a;
                          })
                        : null,
                    builder: (context, hovered) => Container(
                      width: 22,
                      alignment: Alignment.center,
                      decoration: isSel
                          ? BoxDecoration(
                              color: p.accent.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: p.accent),
                            )
                          : (t != null || hovered
                                ? BoxDecoration(
                                    color: (t != null ? color : p.hover)
                                        .withOpacity(t != null ? 0.18 : 1),
                                    borderRadius: BorderRadius.circular(3),
                                  )
                                : null),
                      child: _editAddr == a
                          ? _InlineEdit(
                              initial: bytes[i]
                                  .toRadixString(16)
                                  .padLeft(2, '0'),
                              size: 11,
                              maxLength: 4,
                              align: TextAlign.center,
                              onSubmit: (txt) => _commitByte(a, txt),
                              onCancel: () => setState(() => _editAddr = null),
                            )
                          : MonoText(
                              bytes[i].toRadixString(16).padLeft(2, '0'),
                              size: 11,
                              color: color,
                              weight: t != null
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                    ),
                  ),
                );
                if (i == perRow ~/ 2 - 1) {
                  children.add(const SizedBox(width: 6));
                }
              }
              final ascii = String.fromCharCodes([
                for (final b in bytes) b >= 32 && b < 127 ? b : 46,
              ]);
              return Container(
                color: isPcRow ? p.accent.withOpacity(0.07) : null,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    MonoText(
                      hex(addr, spec.wordBits ~/ 4),
                      size: 11,
                      color: isPcRow ? p.accent : p.muted,
                    ),
                    const SizedBox(width: 12),
                    ...children,
                    const SizedBox(width: 10),
                    Expanded(child: MonoText(ascii, size: 11, color: p.muted)),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selected != null) ...[
                _Interpretation(machine: m, address: _selected!),
                const SizedBox(height: 4),
              ],
              Wrap(
                spacing: 12,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Legend(p.accent, 'read'),
                  _Legend(p.warn, 'written now'),
                  _Legend(p.ok, 'written earlier'),
                  T('double-click a byte to edit', size: 10, color: p.muted),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The bytes at the selected address read as numbers of several sizes.
class _Interpretation extends StatelessWidget {
  const _Interpretation({required this.machine, required this.address});
  final Machine machine;
  final int address;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final big = machine.spec.endian == Endian.big;
    int read(int n) {
      final b = machine.memory.peek(address, n);
      var v = 0;
      for (var i = 0; i < n; i++) {
        v = (v << 8) | b[big ? i : n - 1 - i];
      }
      return v;
    }

    final parts = <String>[
      hex(address, machine.spec.wordBits ~/ 4),
      for (final n in [1, 2, 4])
        if (n == 1 || n <= machine.spec.wordBytes * 2)
          '${n * 8}-bit ${formatValue(read(n), n * 8, ValueFormat.hex)} = ${formatValue(read(n), n * 8, ValueFormat.dec)}',
      if (machine.memory.peek(address, 1).first >= 32 &&
          machine.memory.peek(address, 1).first < 127)
        "'${String.fromCharCode(machine.memory.peek(address, 1).first)}'",
    ];
    return MonoText(
      parts.join('   '),
      size: 10.5,
      color: p.text,
      maxLines: 2,
      softWrap: true,
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
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 5),
      T(label, size: 10, color: context.pal.muted),
    ],
  );
}

class _SmallLink extends StatelessWidget {
  const _SmallLink(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      onTap: onTap,
      builder: (context, hovered) => Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: hovered ? p.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: p.border),
        ),
        child: T(label, size: 10.5, color: p.muted, weight: FontWeight.w700),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------

class _DisassemblyView extends StatefulWidget {
  const _DisassemblyView({required this.sim, required this.machine});
  final SimSession sim;
  final Machine machine;

  @override
  State<_DisassemblyView> createState() => _DisassemblyViewState();
}

class _DisassemblyViewState extends State<_DisassemblyView> {
  static const double _row = 22;
  final ScrollController _scroll = ScrollController();
  int? _lastPc;

  SimSession get sim => widget.sim;
  Machine get machine => widget.machine;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the next instruction on screen as the program counter moves.
  void _follow(double top) {
    final pc = machine.pc;
    if (pc == _lastPc) return;
    _lastPc = pc;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final view = _scroll.position.viewportDimension;
      final off = _scroll.offset;
      if (top < off + _row || top + _row * 2 > off + view) {
        _scroll.animateTo(
          (top - view / 3).clamp(0.0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final prog = sim.program;
    if (prog == null || !sim.hasProgram) {
      return Center(
        child: EmptyState(
          art: EmptyArt.code,
          title: sim.errors.isEmpty
              ? 'Nothing assembled yet'
              : 'The source has errors',
          subtitle: sim.errors.isEmpty
              ? 'Write some assembly and it appears here.'
              : 'Fix them to see the disassembly.',
        ),
      );
    }
    final lines = [
      for (final r in prog.codeRanges)
        ...machine.decoder.disassemble(machine.memory, r.start, r.end),
    ];
    final labelAt = <int, List<String>>{};
    prog.symbols.forEach((n, a) => (labelAt[a] ??= []).add(n));
    final bpAddrs = {for (final l in sim.breakpoints) ?prog.addressOfLine(l)};
    final w = machine.spec.wordBits ~/ 4;

    // Every row is the same height (a label adds one more), so the program counter's position is known.
    var y = 4.0;
    for (final l in lines) {
      if (labelAt.containsKey(l.address)) y += _row;
      if (l.address == machine.pc) _follow(y);
      y += _row;
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      itemCount: lines.length,
      physics: const ClampingScrollPhysics(),
      itemBuilder: (context, i) {
        final l = lines[i];
        final isPc = l.address == machine.pc;
        final labels = labelAt[l.address];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (labels != null)
              Container(
                height: _row,
                alignment: Alignment.bottomLeft,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 3),
                child: MonoText(
                  '${labels.join(', ')}:',
                  size: 11,
                  color: p.warn,
                  weight: FontWeight.w700,
                ),
              ),
            HoverBuilder(
              onTap: () => sim.toggleBreakpointAt(l.address),
              builder: (context, hovered) => Container(
                height: _row,
                decoration: BoxDecoration(
                  color: isPc
                      ? p.accent.withOpacity(0.16)
                      : (hovered ? p.hover : null),
                  border: Border(
                    left: BorderSide(
                      color: isPc ? p.accent : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                padding: const EdgeInsets.only(left: 9, right: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      child: bpAddrs.contains(l.address)
                          ? Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: p.err,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: p.err.withOpacity(0.45),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            )
                          : isPc
                          ? Icon(
                              Icons.arrow_right_rounded,
                              size: 14,
                              color: p.accent,
                            )
                          : (hovered
                                ? Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: p.err.withOpacity(0.3),
                                      shape: BoxShape.circle,
                                    ),
                                  )
                                : null),
                    ),
                    MonoText(
                      hex(l.address, w),
                      size: 11,
                      color: isPc ? p.accent : p.muted,
                    ),
                    const SizedBox(width: 12),
                    MonoText(
                      l.decoded == null
                          ? ''
                          : l.bytes.reversed
                                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                                .join(),
                      size: 11,
                      color: p.muted,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: MonoText(
                        l.text,
                        size: 11.5,
                        color: isPc ? p.accent : p.text,
                        weight: isPc ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    if (hovered && !sim.running) ...[
                      _MiniAction(
                        icon: Icons.keyboard_double_arrow_right_rounded,
                        tooltip: 'Run to here',
                        onTap: () => sim.runTo(l.address),
                      ),
                      const SizedBox(width: 2),
                      _MiniAction(
                        icon: Icons.my_location_rounded,
                        tooltip: 'Set the program counter here',
                        onTap: () => sim.editPc(l.address),
                      ),
                      const SizedBox(width: 8),
                    ],
                    T(
                      'line ${prog.addressToLine[l.address] ?? ''}',
                      size: 10,
                      color: p.muted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------

/// How the next (or last) instruction is decoded: opcode match, operand fields and semantics.
class _DecodeView extends StatelessWidget {
  const _DecodeView({required this.sim, required this.machine});
  final SimSession sim;
  final Machine machine;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final spec = machine.spec;
    // Show the instruction about to execute; fall back to the last executed one.
    var showingNext = machine.canStep;
    var pc = machine.pc;
    Decoded? d = showingNext ? _decodeAt(machine, pc) : null;
    if (d == null && sim.lastTrace?.decoded != null) {
      showingNext = false;
      pc = sim.lastTrace!.pcBefore;
      d = sim.lastTrace!.decoded;
    }
    if (d == null) {
      return Center(child: T('No instruction to decode', color: p.muted));
    }

    final ins = d.instruction;
    final bits = ins.bits;
    // Colour map for each bit position.
    final owner = List<String?>.filled(bits, null);
    for (var b = 0; b < bits; b++) {
      if ((ins.mask >> b) & 1 == 1) owner[b] = '';
    }
    for (final e in ins.fields.entries) {
      for (final s in e.value.segments) {
        for (var b = s.lo; b <= s.hi; b++) {
          owner[b] = e.key;
        }
      }
    }
    final palette = [
      p.accent,
      p.ok,
      p.warn,
      const Color(0xFFB48EAD),
      const Color(0xFF54C5F8),
      const Color(0xFFD08770),
    ];
    final fieldNames = ins.fields.keys.toList();
    Color colorFor(String? o) => o == null
        ? p.muted
        : o.isEmpty
        ? p.muted
        : palette[fieldNames.indexOf(o) % palette.length];

    final word = d.raw;
    List<Widget> bitCells(double cw) => [
      for (var b = bits - 1; b >= 0; b--)
        Container(
          width: cw,
          height: 24,
          alignment: Alignment.center,
          margin: EdgeInsets.only(right: b % 4 == 0 && b != 0 ? 3 : 0),
          decoration: BoxDecoration(
            color: colorFor(owner[b]).withOpacity(owner[b] == '' ? 0.08 : 0.2),
            borderRadius: BorderRadius.circular(3),
          ),
          child: MonoText(
            '${(word >> b) & 1}',
            size: cw < 11 ? 9.5 : 11,
            color: colorFor(owner[b]),
            weight: FontWeight.w700,
          ),
        ),
    ];

    final trace = showingNext ? null : sim.lastTrace;

    return ListView(
      padding: const EdgeInsets.all(12),
      physics: const ClampingScrollPhysics(),
      children: [
        T(
          showingNext ? 'Next instruction' : 'Last instruction',
          size: 10.5,
          color: p.muted,
          weight: FontWeight.w600,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            MonoText(
              hex(pc, spec.wordBits ~/ 4),
              size: 12,
              color: p.accent,
              weight: FontWeight.w700,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MonoText(
                machine.decoder.format(d, pc),
                size: 13,
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // The bits share the width of the panel, in groups of four.
        LayoutBuilder(
          builder: (context, c) {
            final gaps = (bits ~/ 4 - 1) * 3.0;
            final cw = ((c.maxWidth - gaps) / bits - 0.6).clamp(8.0, 16.0);
            return Row(children: bitCells(cw));
          },
        ),
        const SizedBox(height: 4),
        T(
          'word ${hex(word, bits ~/ 4)}  ·  $bits bits  ·  matches "${ins.mnemonic}" (mask ${hex(ins.mask, bits ~/ 4)} = value ${hex(ins.value, bits ~/ 4)})',
          size: 10.5,
          color: p.muted,
        ),
        const SizedBox(height: 12),
        _SectionHeader('Operands', count: ins.fields.length),
        if (ins.fields.isEmpty)
          T('This instruction has no operands.', size: 11, color: p.muted)
        else
          for (final name in ins.fields.keys)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: p.field,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: p.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colorFor(name),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 56,
                    child: MonoText(name, size: 11.5, weight: FontWeight.w700),
                  ),
                  SizedBox(
                    width: 90,
                    child: T(
                      '${ins.operands[name]!.name} ${ins.fields[name]!.source}',
                      size: 10.5,
                      color: p.muted,
                    ),
                  ),
                  Expanded(
                    child: MonoText(
                      _operandText(machine, d, name),
                      size: 11.5,
                      color: p.text,
                    ),
                  ),
                ],
              ),
            ),
        _SectionHeader('Semantics'),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: p.field,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: p.border),
          ),
          child: MonoText(
            ins.exec.isEmpty ? '(no effect)' : ins.exec,
            size: 11.5,
            maxLines: 8,
            softWrap: true,
          ),
        ),
        if (ins.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          T(
            ins.description,
            size: 11,
            color: p.muted,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (trace != null) ...[
          _SectionHeader('Effects'),
          _Effects(machine: machine, trace: trace),
        ],
      ],
    );
  }

  static Decoded? _decodeAt(Machine m, int pc) {
    try {
      return m.decoder.decode(m.memory.fetch(pc, m.spec.maxInstrBits ~/ 8));
    } catch (_) {
      return null;
    }
  }

  static String _operandText(Machine m, Decoded d, String name) {
    final ins = d.instruction;
    final v = d.operands[name] ?? 0;
    switch (ins.operands[name]!) {
      case OperandKind.reg:
        final n = m.spec.registerName(v);
        final al = m.spec.registerAliases(v);
        return '$n${al.isEmpty ? '' : ' (${al.first})'}  =  ${formatValue(m.register(v), m.spec.registerWidth(v), ValueFormat.hex)}';
      case OperandKind.imm:
        return '$v  (${hex(v & 0xFFFFFFFF, 1)})';
      case OperandKind.pcrel:
        return 'offset $v → ${hex(m.pc + ins.pcrelBase + v, 1)}';
    }
  }
}

class _Effects extends StatelessWidget {
  const _Effects({required this.machine, required this.trace});
  final Machine machine;
  final StepTrace trace;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final spec = machine.spec;
    final rows = <Widget>[];
    Widget row(IconData icon, Color c, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 6),
          Expanded(
            child: MonoText(text, size: 11, maxLines: 2, softWrap: true),
          ),
        ],
      ),
    );
    for (final c in trace.regWrites) {
      final w = spec.registerWidth(c.index);
      rows.add(
        row(
          Icons.edit_rounded,
          p.accent,
          '${spec.registerName(c.index)}: ${formatValue(c.oldValue, w, ValueFormat.hex)} → ${formatValue(c.newValue, w, ValueFormat.hex)}',
        ),
      );
    }
    for (final c in trace.flagWrites) {
      rows.add(
        row(
          Icons.flag_rounded,
          p.accent,
          '${c.name}: ${c.oldValue} → ${c.newValue}',
        ),
      );
    }
    for (final a in trace.memAccesses) {
      rows.add(
        row(
          a.write ? Icons.south_west_rounded : Icons.north_east_rounded,
          a.write ? p.warn : p.ok,
          '${a.write ? 'store' : 'load'} ${a.size * 8}-bit ${hex(a.address)} = ${hex(a.value, a.size * 2)}',
        ),
      );
    }
    if (trace.pcAfter != trace.pcBefore + trace.length) {
      rows.add(
        row(
          Icons.alt_route_rounded,
          p.accent,
          'pc: ${hex(trace.pcBefore + trace.length)} → ${hex(trace.pcAfter)} (jump)',
        ),
      );
    }
    if (trace.output.isNotEmpty) {
      rows.add(
        row(
          Icons.terminal_rounded,
          p.ok,
          'output: ${trace.output.replaceAll('\n', '⏎')}',
        ),
      );
    }
    if (trace.halted) {
      rows.add(row(Icons.stop_circle_outlined, p.muted, 'program halted'));
    }
    if (rows.isEmpty) {
      rows.add(T('No visible effect', size: 11, color: p.muted));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

// ---------------------------------------------------------------------------------------------------------------

/// A small coloured label for one effect of an instruction.
class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: MonoText(text, size: 10, color: color),
  );
}

class _TraceView extends StatelessWidget {
  const _TraceView({required this.sim, required this.machine});
  final SimSession sim;
  final Machine machine;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final h = machine.history;
    if (h.isEmpty) {
      return const Center(
        child: EmptyState(
          art: EmptyArt.steps,
          title: 'No trace yet',
          subtitle: 'Step or run the program to record each instruction.',
        ),
      );
    }
    final spec = machine.spec;
    final total = machine.instructionCount;
    final shown = h.length > 400 ? 400 : h.length;
    return ListView.builder(
      itemCount: shown,
      physics: const ClampingScrollPhysics(),
      itemBuilder: (context, i) {
        final t = h[h.length - 1 - i];
        final n = total - i;
        final chips = <_Chip>[
          for (final c in t.regWrites)
            _Chip(
              '${spec.registerName(c.index)}  ${formatValue(c.oldValue, spec.registerWidth(c.index), ValueFormat.hex)} → ${formatValue(c.newValue, spec.registerWidth(c.index), ValueFormat.hex)}',
              p.accent,
            ),
          for (final c in t.flagWrites)
            _Chip('${c.name}  ${c.oldValue} → ${c.newValue}', p.warn),
          for (final a in t.memAccesses)
            _Chip(
              '${a.write ? 'store' : 'load'}  ${a.size}B @ ${hex(a.address)}',
              a.write ? p.warn : p.ok,
            ),
          if (t.output.isNotEmpty) _Chip('print  ${t.output.trim()}', p.muted),
        ];
        return HoverBuilder(
          cursor: i == 0 || sim.running
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onTap: i == 0 || sim.running
              ? null
              : () => sim.rewindTo(h.length - i),
          builder: (context, hovered) => Tooltip(
            message: i == 0
                ? 'The last instruction executed'
                : 'Rewind to just after this instruction',
            waitDuration: const Duration(milliseconds: 600),
            child: Container(
              padding: const EdgeInsets.fromLTRB(9, 6, 12, 6),
              decoration: BoxDecoration(
                color: i == 0
                    ? p.accent.withOpacity(0.09)
                    : (hovered ? p.hover : null),
                border: Border(
                  left: BorderSide(
                    color: i == 0 ? p.accent : Colors.transparent,
                    width: 3,
                  ),
                  bottom: BorderSide(color: p.border.withOpacity(0.4)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: MonoText('#$n', size: 10.5, color: p.muted),
                      ),
                      Expanded(
                        child: MonoText(
                          t.text,
                          size: 11.5,
                          weight: FontWeight.w700,
                        ),
                      ),
                      MonoText(
                        hex(t.pcBefore, spec.wordBits ~/ 4),
                        size: 10.5,
                        color: p.muted,
                      ),
                    ],
                  ),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Padding(
                      padding: const EdgeInsets.only(left: 36),
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [for (final c in chips) c],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

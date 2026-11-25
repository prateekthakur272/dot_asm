import 'package:flutter/material.dart';
import 'package:dot_asm/components/empty_state.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/app/sim_session.dart';
import 'package:dot_asm/components/drag_devices.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/core/sim/machine/machine.dart';
import 'package:dot_asm/core/sim/machine/memory.dart' show hex;
import 'package:dot_asm/features/workspace/code_editor.dart';
import 'package:dot_asm/features/workspace/processor_panel.dart';
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/theme.dart';

/// The main screen of an open project: source editor on the left, live processor internals on the right.
class WorkspaceView extends StatelessWidget {
  const WorkspaceView({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final project = state.activeProject;
    final spec = state.activeProcessor;
    if (project == null) return const SizedBox.shrink();
    if (spec == null) {
      return Center(
        child: T(
          "The processor '${project.processor.value}' used by this project was not found.",
          color: p.muted,
        ),
      );
    }
    final ui = state.uiState;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(state: state),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final panelW = ui.panelWidth.clamp(
                320.0,
                (c.maxWidth - 280).clamp(320.0, 900.0),
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: CodeEditor(
                            key: ValueKey(project.id),
                            state: state,
                          ),
                        ),
                        _BottomPanel(state: state),
                      ],
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      supportedDevices: kDragDevices,
                      onHorizontalDragUpdate: (d) => state.updateUiState(
                        (s) => s.copyWith(
                          panelWidth: (panelW - d.delta.dx).clamp(320.0, 900.0),
                        ),
                      ),
                      child: Container(
                        width: 5,
                        color: Colors.transparent,
                        child: Center(
                          child: Container(width: 1, color: p.border),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: panelW,
                    child: ProcessorPanel(state: state),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final project = state.activeProject!;
    final spec = state.activeProcessor!;
    final mac = Platform.isMac;
    return ListenableBuilder(
      listenable: state.sim,
      builder: (context, _) {
        final sim = state.sim;
        final m = sim.machine;
        return Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: p.panel,
            border: Border(bottom: BorderSide(color: p.border)),
          ),
          child: Row(
            children: [
              // Where we are: project > processor
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: T(
                          project.name,
                          size: 12.5,
                          weight: FontWeight.w700,
                          maxLines: 1,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 15,
                        color: p.muted,
                      ),
                      Icon(Icons.memory_rounded, size: 12, color: p.muted),
                      const SizedBox(width: 4),
                      Flexible(
                        child: T(
                          spec.name,
                          size: 11,
                          color: p.muted,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Run controls, like the debug toolbar of an IDE
              _ToolGroup(
                children: [
                  if (sim.running)
                    _ToolButton(
                      icon: Icons.pause_rounded,
                      label: 'Pause',
                      tooltip: 'Pause (F5)',
                      color: p.warn,
                      onTap: sim.pause,
                    )
                  else
                    _ToolButton(
                      icon: Icons.play_arrow_rounded,
                      label: 'Run',
                      tooltip: 'Run (F5)',
                      color: p.ok,
                      onTap: sim.canRun ? sim.run : null,
                    ),
                  _ToolButton(
                    icon: Icons.skip_next_rounded,
                    tooltip: 'Step (F10)',
                    onTap: sim.canStep ? sim.stepOnce : null,
                  ),
                  _ToolButton(
                    icon: Icons.skip_previous_rounded,
                    tooltip: 'Step back (Shift+F10)',
                    onTap: sim.canUndo ? sim.stepBack : null,
                  ),
                  _ToolButton(
                    icon: Icons.restart_alt_rounded,
                    tooltip: 'Reset the processor',
                    onTap: m == null ? null : sim.reset,
                  ),
                ],
              ),
              const SizedBox(width: 8),
              _ToolGroup(
                children: [
                  _ToolButton(
                    icon: Icons.build_circle_outlined,
                    tooltip: 'Assemble (${mac ? "⌘⇧B" : "Ctrl+Shift+B"})',
                    onTap: state.assembleNow,
                  ),
                ],
              ),
              const SizedBox(width: 8),
              // Speed
              _ToolGroup(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    child: Tooltip(
                      message: 'Run speed',
                      child: Icon(
                        Icons.speed_rounded,
                        size: 14,
                        color: p.muted,
                      ),
                    ),
                  ),
                  for (final s in SimSpeed.values)
                    HoverBuilder(
                      cursor: SystemMouseCursors.click,
                      onTap: () => sim.setSpeed(s),
                      builder: (context, hovered) => Container(
                        height: 24,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        decoration: BoxDecoration(
                          color: s == sim.speed
                              ? p.accent.withOpacity(0.16)
                              : (hovered ? p.hover : Colors.transparent),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: T(
                          s.label,
                          size: 10.5,
                          weight: FontWeight.w600,
                          color: s == sim.speed ? p.accent : p.muted,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              if (m != null) ...[
                Tooltip(
                  message: 'Program counter',
                  child: Row(
                    children: [
                      T(
                        'PC',
                        size: 10,
                        color: p.muted,
                        weight: FontWeight.w700,
                      ),
                      const SizedBox(width: 5),
                      MonoText(
                        hex(m.pc, spec.wordBits ~/ 4),
                        size: 11,
                        color: p.text,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
              ],
              _StatusPill(sim: sim),
              const SizedBox(width: 10),
              _ToolGroup(
                children: [
                  _ToolButton(
                    icon: Icons.developer_board_rounded,
                    tooltip: 'Processor builder',
                    onTap: state.openBuilder,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A rounded strip that groups related toolbar buttons.
class _ToolGroup extends StatelessWidget {
  const _ToolGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// An icon button of the toolbar, optionally with a label and an accent colour (Run is green, Pause amber).
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.label,
    this.color,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final String? label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final enabled = onTap != null;
    final fg = !enabled ? p.muted.withOpacity(0.4) : (color ?? p.text);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: HoverBuilder(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: onTap,
        builder: (context, hovered) => Container(
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 5 : 8),
          decoration: BoxDecoration(
            color: enabled && color != null
                ? color!.withOpacity(hovered ? 0.24 : 0.14)
                : (enabled && hovered ? p.hover : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: fg),
              if (label != null) ...[
                const SizedBox(width: 3),
                T(label!, size: 11.5, weight: FontWeight.w700, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.sim});
  final SimSession sim;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = sim.machine;
    String label;
    Color color;
    if (sim.errors.isNotEmpty) {
      label = '${sim.errors.length} error${sim.errors.length == 1 ? '' : 's'}';
      color = p.err;
    } else if (sim.running) {
      label = 'Running';
      color = p.accent;
    } else if (m == null || sim.program == null) {
      label = 'Not assembled';
      color = p.muted;
    } else {
      switch (m.status) {
        case MachineStatus.ready:
          label = 'Ready';
          color = p.ok;
        case MachineStatus.halted:
          label = 'Finished';
          color = p.muted;
        case MachineStatus.faulted:
          label = 'Fault';
          color = p.err;
        case MachineStatus.empty:
          label = 'Not assembled';
          color = p.muted;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
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
          T(label, size: 11, weight: FontWeight.w600, color: color),
        ],
      ),
    );
  }
}

/// Program output and assembler problems under the editor.
class _BottomPanel extends StatefulWidget {
  const _BottomPanel({required this.state});
  final AppState state;

  @override
  State<_BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<_BottomPanel> {
  bool _problems = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: widget.state.sim,
      builder: (context, _) {
        final sim = widget.state.sim;
        final errors = sim.errors;
        final output = sim.machine?.console.toString() ?? '';
        Widget tab(
          String label,
          bool active,
          VoidCallback onTap, {
          int? badge,
        }) => HoverBuilder(
          cursor: SystemMouseCursors.click,
          onTap: onTap,
          builder: (context, hovered) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? p.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                T(
                  label,
                  size: 11.5,
                  weight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? p.text : p.muted,
                ),
                if (badge != null && badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: p.err.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: T(
                      '$badge',
                      size: 10,
                      color: p.err,
                      weight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
        final showErr = errors.isNotEmpty && (_problems || output.isEmpty);
        return Container(
          height: 150,
          decoration: BoxDecoration(
            color: p.panel,
            border: Border(top: BorderSide(color: p.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 30,
                child: Row(
                  children: [
                    tab(
                      'Output',
                      !showErr,
                      () => setState(() => _problems = false),
                    ),
                    tab(
                      'Problems',
                      showErr,
                      () => setState(() => _problems = true),
                      badge: errors.length,
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: p.border),
              Expanded(
                child: showErr
                    ? ListView(
                        padding: const EdgeInsets.all(8),
                        physics: const ClampingScrollPhysics(),
                        children: [
                          for (final e in errors)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    size: 13,
                                    color: p.err,
                                  ),
                                  const SizedBox(width: 6),
                                  MonoText(
                                    'line ${e.line}',
                                    size: 11,
                                    color: p.muted,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: MonoText(
                                      e.message,
                                      size: 11,
                                      color: p.text,
                                      maxLines: 3,
                                      softWrap: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(10),
                        physics: const ClampingScrollPhysics(),
                        child: SizedBox(
                          width: double.infinity,
                          child: output.isEmpty
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const EmptyArtView(
                                      art: EmptyArt.terminal,
                                      size: 84,
                                    ),
                                    const SizedBox(width: 14),
                                    T(
                                      'The program output appears here.',
                                      size: 11,
                                      color: p.muted,
                                    ),
                                  ],
                                )
                              : MonoText(
                                  output,
                                  size: 12,
                                  maxLines: null,
                                  softWrap: true,
                                ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

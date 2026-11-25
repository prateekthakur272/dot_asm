import 'package:flutter/material.dart';
import 'package:dot_asm/components/empty_state.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/app/sim_session.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/components/drag_devices.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/core/sim/machine/machine.dart';
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
    final mod = Platform.isMac;
    return ListenableBuilder(
      listenable: state.sim,
      builder: (context, _) {
        final sim = state.sim;
        final m = sim.machine;
        return Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: p.panel,
            border: Border(bottom: BorderSide(color: p.border)),
          ),
          child: Row(
            children: [
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      T(
                        project.name,
                        size: 13,
                        weight: FontWeight.w700,
                        maxLines: 1,
                      ),
                      T(spec.name, size: 10.5, color: p.muted, maxLines: 1),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              if (sim.running)
                Btn(
                  label: 'Pause',
                  icon: Icons.pause_rounded,
                  primary: true,
                  height: 30,
                  fontSize: 12,
                  onClick: sim.pause,
                )
              else
                Btn(
                  label: 'Run',
                  icon: Icons.play_arrow_rounded,
                  primary: true,
                  height: 30,
                  fontSize: 12,
                  onClick: sim.canRun ? sim.run : null,
                ),
              const SizedBox(width: 6),
              Btn(
                label: 'Step',
                icon: Icons.skip_next_rounded,
                height: 30,
                fontSize: 12,
                onClick: sim.canStep ? sim.stepOnce : null,
              ),
              const SizedBox(width: 6),
              IconBtn(
                icon: Icons.undo_rounded,
                tooltip: 'Step back',
                size: 30,
                onClick: sim.canUndo ? sim.stepBack : null,
              ),
              IconBtn(
                icon: Icons.restart_alt_rounded,
                tooltip: 'Reset',
                size: 30,
                onClick: m == null ? null : sim.reset,
              ),
              IconBtn(
                icon: Icons.build_circle_outlined,
                tooltip: 'Assemble (${mod ? "⌘⇧B" : "Ctrl+Shift+B"})',
                size: 30,
                onClick: state.assembleNow,
              ),
              const SizedBox(width: 10),
              Container(width: 1, height: 20, color: p.border),
              const SizedBox(width: 10),
              T('Speed', size: 11, color: p.muted),
              const SizedBox(width: 6),
              for (final s in SimSpeed.values)
                HoverBuilder(
                  cursor: SystemMouseCursors.click,
                  onTap: () => sim.setSpeed(s),
                  builder: (context, hovered) => Container(
                    margin: const EdgeInsets.only(right: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: s == sim.speed
                          ? p.accent.withOpacity(0.16)
                          : (hovered ? p.hover : Colors.transparent),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: T(
                      s.label,
                      size: 10.5,
                      weight: FontWeight.w600,
                      color: s == sim.speed ? p.accent : p.muted,
                    ),
                  ),
                ),
              const Spacer(),
              Btn(
                label: 'Processor builder',
                icon: Icons.memory_rounded,
                height: 30,
                fontSize: 12,
                outlined: true,
                onClick: state.openBuilder,
              ),
              const SizedBox(width: 10),
              _StatusPill(sim: sim),
            ],
          ),
        );
      },
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

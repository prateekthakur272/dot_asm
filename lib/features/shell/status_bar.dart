import 'package:flutter/material.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/components/context_menu.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/core/sim/machine/memory.dart' show hex;
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';
import 'package:dot_asm/utils/app_config.dart';
import 'package:dot_asm/utils/app_metadata.dart';
import 'package:dot_asm/utils/issue_report.dart';

/// Bottom desktop status bar: quick actions on the left, version, update badge and palette hint on the right.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;

    Widget click(VoidCallback f, Widget child, {String? tooltip}) {
      Widget w = ClickableNoRipple(
        onClick: f,
        child: MouseRegion(cursor: SystemMouseCursors.click, child: child),
      );
      if (tooltip != null) w = Tooltip(message: tooltip, child: w);
      return w;
    }

    final ui = state.uiState;
    final mod = Platform.isMac ? '⌘' : 'Ctrl+';
    final spec = state.activeProcessor;
    final sim = state.sim;
    final m = sim.machine;
    final projects = state.projects;

    return Container(
      height: 24,
      color: p.panel,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: CustomPaint(
        painter: _TopBorderPainter(p.border),
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 900;
            final normal = c.maxWidth >= 720;
            return Row(
              children: [
                // Quick actions
                IconBtn(
                  icon: AppIcons.sidebar,
                  tooltip: ui.sidebarVisible ? 'Hide sidebar' : 'Show sidebar',
                  size: 20,
                  iconSize: 13,
                  color: ui.sidebarVisible ? p.accent : p.muted,
                  onClick: state.toggleSidebar,
                ),
                const SizedBox(width: 4),
                IconBtn(
                  icon: AppIcons.settings,
                  tooltip: 'Preferences ($mod,)',
                  size: 20,
                  iconSize: 13,
                  color: p.muted,
                  onClick: () => state.modal = const ModalSettings(),
                ),
                const SizedBox(width: 4),
                IconBtn(
                  icon: AppIcons.info,
                  tooltip: 'About ${AppConfig.NAME}',
                  size: 20,
                  iconSize: 13,
                  color: p.muted,
                  onClick: () => state.modal = const ModalAbout(),
                ),
                const SizedBox(width: 4),
                // The developer profile: click for the dialog, right-click for links
                Builder(
                  builder: (btnCtx) => GestureDetector(
                    onSecondaryTapUp: (d) => ContextMenu.show(
                      btnCtx,
                      d.globalPosition,
                      _developerMenu(),
                    ),
                    child: IconBtn(
                      icon: AppIcons.github,
                      tooltip: 'Developer & project (right-click for links)',
                      size: 20,
                      iconSize: 13,
                      color: p.muted,
                      onClick: () => state.modal = const ModalDeveloper(),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconBtn(
                  key: const ValueKey('report-issue'),
                  icon: AppIcons.bug,
                  tooltip: 'Report an issue',
                  size: 20,
                  iconSize: 13,
                  color: p.muted,
                  onClick: () => Platform.openUrl(IssueReport.url().toString()),
                ),
                if (state.availableUpdate != null) ...[
                  const SizedBox(width: 4),
                  IconBtn(
                    icon: AppIcons.download,
                    tooltip:
                        'Update available: ${state.availableUpdate} — click to view',
                    size: 20,
                    iconSize: 13,
                    color: p.accent,
                    onClick: () => state.modal = ModalUpdateAvailable(
                      state.availableUpdate!,
                    ),
                  ),
                ],
                const SizedBox(width: 14),
                // Projects
                click(
                  () => state.modal = const ModalNewProject(),
                  T(
                    '${projects.length} project${projects.length == 1 ? '' : 's'}',
                    size: 11,
                    color: p.muted,
                  ),
                  tooltip: 'New project',
                ),
                const Spacer(),
                // What is open: processor, word size, and where the program counter is
                if (spec != null && normal) ...[
                  click(
                    state.openBuilder,
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.memory_rounded, size: 11, color: p.muted),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: wide ? 240 : 150,
                          ),
                          child: T(
                            '${spec.name}  ·  ${spec.wordBits}-bit',
                            size: 11,
                            color: p.muted,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                    tooltip: 'Open the processor builder',
                  ),
                  const SizedBox(width: 14),
                ],
                if (m != null && spec != null && wide) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      T('PC', size: 11, color: p.muted),
                      const SizedBox(width: 4),
                      MonoText(
                        hex(m.pc, spec.wordBits ~/ 4),
                        size: 11,
                        color: p.text,
                      ),
                      const SizedBox(width: 10),
                      T(
                        '${m.instructionCount} instr',
                        size: 11,
                        color: p.muted,
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                ],
                T('v${AppMetadata.version}', size: 11, color: p.muted),
                const SizedBox(width: 14),
                click(
                  () => state.paletteOpen = true,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MonoText(
                        Platform.isMac ? '⌘K' : 'Ctrl+K',
                        size: 11,
                        color: p.accent,
                        weight: FontWeight.w600,
                      ),
                      const SizedBox(width: 4),
                      T('commands', size: 11, color: p.muted),
                    ],
                  ),
                  tooltip:
                      'Open Command Palette (${Platform.isMac ? "⌘K" : "Ctrl+K"})',
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Links shown when the developer button is right-clicked.
  List<ContextMenuItem> _developerMenu() => [
    ContextMenuItem(
      label: 'Developer & Project…',
      icon: AppIcons.info,
      action: () => state.modal = const ModalDeveloper(),
    ),
    ContextMenuItem(
      label: '${AppConfig.NAME} Repository',
      icon: AppIcons.external,
      action: () => Platform.openUrl(AppConfig.REPOSITORY),
    ),
    ContextMenuItem(
      label: 'Star on GitHub',
      icon: Icons.star_rounded,
      action: () => Platform.openUrl(AppConfig.REPOSITORY),
    ),
    ContextMenuItem(
      label: 'Releases & Changelog',
      icon: AppIcons.download,
      action: () => Platform.openUrl(AppConfig.RELEASES_URL),
    ),
    const ContextMenuItem(label: ''),
    ContextMenuItem(
      label: 'Report an Issue…',
      icon: AppIcons.bug,
      action: () => Platform.openUrl(IssueReport.url().toString()),
    ),
    ContextMenuItem(
      label: 'Explore More Apps',
      icon: Icons.apps_rounded,
      action: () => Platform.openUrl(AppConfig.MORE_APPS_URL),
    ),
  ];
}

class _TopBorderPainter extends CustomPainter {
  const _TopBorderPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      const Offset(0, 0.5),
      Offset(size.width, 0.5),
      Paint()
        ..color = color
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(_TopBorderPainter oldDelegate) =>
      color != oldDelegate.color;
}

import 'package:flutter/material.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';
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

    return Container(
      height: 24,
      color: p.panel,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: CustomPaint(
        painter: _TopBorderPainter(p.border),
        child: Row(
          children: [
            IconBtn(
              icon: AppIcons.sidebar,
              tooltip: state.uiState.sidebarVisible
                  ? 'Hide sidebar'
                  : 'Show sidebar',
              size: 20,
              iconSize: 13,
              active: state.uiState.sidebarVisible,
              onClick: state.toggleSidebar,
            ),
            const SizedBox(width: 4),
            IconBtn(
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
                onClick: () =>
                    state.modal = ModalUpdateAvailable(state.availableUpdate!),
              ),
            ],
            const Spacer(),
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
        ),
      ),
    );
  }
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

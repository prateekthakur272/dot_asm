import 'package:flutter/material.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/dot_pattern.dart';
import 'package:dot_asm/components/drag_devices.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/features/dialogs/modals.dart';
import 'package:dot_asm/features/shell/palette.dart';
import 'package:dot_asm/features/shell/status_bar.dart';
import 'package:dot_asm/features/shell/top_bar.dart';
import 'package:dot_asm/features/shell/window_chrome.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';
import 'package:dot_asm/utils/app_config.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.state, required this.chrome});

  final AppState state;
  final WindowChrome chrome;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final p = context.pal;
        final ui = state.uiState;

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Custom desktop title bar
                chrome.dragArea(
                  GestureDetector(
                    onDoubleTap: chrome.onDoubleClick,
                    child: Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: p.panel,
                        border: Border(
                          bottom: BorderSide(color: p.border, width: 1),
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Row(
                              children: [
                                if (chrome.leftInset > 0)
                                  SizedBox(width: chrome.leftInset),
                                if (chrome.menuBar != null) chrome.menuBar!,
                                const Spacer(),
                                if (chrome.controls != null) chrome.controls!,
                              ],
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Center(
                                child: T(
                                  AppConfig.NAME,
                                  size: 11.5,
                                  color: p.muted,
                                  weight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Merged Unified Header (Branding + Search + Controls)
                AppTopBar(state: state),
                // Workspace body: collapsible left sidebar + main content
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (ui.sidebarVisible) ...[
                        SizedBox(
                          width: ui.sidebarWidth.clamp(200.0, 380.0),
                          child: Container(
                            color: p.sidebar,
                            alignment: Alignment.topLeft,
                            padding: const EdgeInsets.all(14),
                            child: T(
                              'Sidebar',
                              size: 12,
                              color: p.muted,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _PaneDivider(
                          color: p.border,
                          onDrag: (delta) {
                            state.updateUiState(
                              (s) => s.copyWith(
                                sidebarWidth: (s.sidebarWidth + delta).clamp(
                                  200.0,
                                  380.0,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                      const Expanded(child: _HomeView()),
                    ],
                  ),
                ),
                // Bottom desktop status bar
                StatusBar(state: state),
              ],
            ),
            // Command Palette Overlay
            if (state.paletteOpen)
              Positioned.fill(child: CommandPalette(state: state)),
            // Modal Overlay
            if (state.modal != null)
              Positioned.fill(child: buildActiveModal(context, state)),
            // Toast Notification
            if (state.toast != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: p.dark
                            ? const Color(0xFF3A3F47)
                            : const Color(0xFF1F2328),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: T(
                        state.toast!,
                        color: const Color(0xFFFFFFFF),
                        size: 12,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PaneDivider extends StatelessWidget {
  const _PaneDivider({required this.color, required this.onDrag});
  final Color color;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        supportedDevices: kDragDevices,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        child: Container(
          width: 5,
          color: Colors.transparent,
          child: Center(child: Container(width: 1, color: color)),
        ),
      ),
    );
  }
}

/// Placeholder main view; replaced by the real feature screens.
class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Stack(
      children: [
        const Positioned.fill(child: DotPatternBackground()),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.code, size: 28, color: p.muted),
              const SizedBox(height: 10),
              const T(AppConfig.NAME, size: 16, weight: FontWeight.w700),
              const SizedBox(height: 4),
              T(AppConfig.TAGLINE, size: 12, color: p.muted),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/drag_devices.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/features/dialogs/modals.dart';
import 'package:dot_asm/features/processor_builder/builder_view.dart';
import 'package:dot_asm/features/projects/gallery_view.dart';
import 'package:dot_asm/features/projects/home_view.dart';
import 'package:dot_asm/features/projects/sidebar.dart';
import 'package:dot_asm/features/workspace/workspace_view.dart';
import 'package:dot_asm/features/shell/palette.dart';
import 'package:dot_asm/features/shell/status_bar.dart';
import 'package:dot_asm/features/shell/window_chrome.dart';
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
                                  state.activeProject == null
                                      ? AppConfig.NAME
                                      : '${state.activeProject!.name} — ${AppConfig.NAME}',
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
                // Workspace body: collapsible left sidebar + main content
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (ui.sidebarVisible) ...[
                        SizedBox(
                          width: ui.sidebarWidth.clamp(200.0, 380.0),
                          child: ProjectsSidebar(state: state),
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
                      Expanded(
                        child: ColoredBox(
                          color: p.bg,
                          child: switch (ui.activeView) {
                            'builder' => BuilderView(state: state),
                            'gallery' => GalleryView(state: state),
                            'workspace' when state.activeProject != null =>
                              WorkspaceView(state: state),
                            _ => HomeView(state: state),
                          },
                        ),
                      ),
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
                            ? const Color(0xFF2A2A2A)
                            : const Color(0xFF1F1F1F),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/context_menu.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';
import 'package:dot_asm/utils/app_config.dart';
import 'package:dot_asm/utils/app_metadata.dart';
import 'package:dot_asm/utils/issue_report.dart';
import 'package:dot_asm/utils/paths.dart';
import 'package:dot_asm/utils/update_checker.dart';

/// Triggers a manual update check.
/// Shows a toast or opens the update modal so the user gets instant feedback.
void checkForUpdates(AppState state) {
  unawaited(_doCheckForUpdates(state));
}

Future<void> _doCheckForUpdates(AppState state) async {
  await UpdateChecker.clearDismissed();
  final result = await UpdateChecker.check(AppMetadata.version);
  if (result.failed) {
    state.showToast("Couldn't check for updates: ${result.error}");
  } else if (result.hasUpdate) {
    state.availableUpdate = result.version;
    state.modal = ModalUpdateAvailable(result.version!);
  } else {
    state.availableUpdate = null;
    state.showToast('${AppConfig.NAME} is up to date (${AppMetadata.version})');
  }
}

/// Native macOS menu bar (PlatformMenuBar).
List<PlatformMenuItem> buildMacMenus(AppState state, VoidCallback onQuit) {
  return [
    PlatformMenu(
      label: AppConfig.NAME,
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'About ${AppConfig.NAME}',
              onSelected: () => state.modal = const ModalAbout(),
            ),
            PlatformMenuItem(
              label: 'Developer…',
              onSelected: () => state.modal = const ModalDeveloper(),
            ),
            PlatformMenuItem(
              label: 'Check for Updates…',
              onSelected: () => checkForUpdates(state),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Preferences…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.comma,
                meta: true,
              ),
              onSelected: () => state.modal = const ModalSettings(),
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.servicesSubmenu,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hideOtherApplications,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.showAllApplications,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Quit ${AppConfig.NAME}',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyQ,
                meta: true,
              ),
              onSelected: onQuit,
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'File',
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Show Data Folder',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyD,
                meta: true,
                alt: true,
              ),
              onSelected: () => Platform.reveal(AppStore.dir),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Close Window',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyW,
                meta: true,
              ),
              onSelected: onQuit,
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'Edit',
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Undo',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
              ),
              onSelected: () {},
            ),
            PlatformMenuItem(
              label: 'Redo',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ),
              onSelected: () {},
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Cut',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyX,
                meta: true,
              ),
              onSelected: () {},
            ),
            PlatformMenuItem(
              label: 'Copy',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyC,
                meta: true,
              ),
              onSelected: () {},
            ),
            PlatformMenuItem(
              label: 'Paste',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyV,
                meta: true,
              ),
              onSelected: () {},
            ),
            PlatformMenuItem(
              label: 'Select All',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyA,
                meta: true,
              ),
              onSelected: () {},
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'View',
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Command Palette…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyK,
                meta: true,
              ),
              onSelected: () => state.paletteOpen = true,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Toggle Sidebar',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyB,
                meta: true,
              ),
              onSelected: state.toggleSidebar,
            ),
            PlatformMenuItem(
              label: 'Toggle Dark / Light Theme',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyT,
                meta: true,
              ),
              onSelected: state.toggleTheme,
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'Window',
      menus: [
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: 'Help',
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Check for Updates…',
              onSelected: () => checkForUpdates(state),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Show Data Folder',
              onSelected: () => Platform.reveal(AppStore.dir),
            ),
            PlatformMenuItem(
              label: 'Show Log File',
              onSelected: () => Platform.reveal(Paths.logFile(AppStore.dir)),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Developer & GitHub…',
              onSelected: () => state.modal = const ModalDeveloper(),
            ),
            PlatformMenuItem(
              label: 'Report an Issue…',
              onSelected: () => Platform.openUrl(IssueReport.url().toString()),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'About ${AppConfig.NAME}',
              onSelected: () => state.modal = const ModalAbout(),
            ),
          ],
        ),
      ],
    ),
  ];
}

/// Menu items for the in-window menu bar on Windows and Linux.
Map<String, List<ContextMenuItem>> buildWindowsLinuxMenuItems({
  required AppState state,
  required VoidCallback onQuit,
  VoidCallback? onMinimize,
  VoidCallback? onToggleMaximize,
}) {
  return {
    'File': [
      ContextMenuItem(
        label: 'Settings…',
        icon: AppIcons.settings,
        shortcut: 'Ctrl+,',
        action: () => state.modal = const ModalSettings(),
      ),
      ContextMenuItem(
        label: 'Open Data Directory',
        icon: Icons.folder_special_outlined,
        action: () => Platform.reveal(AppStore.dir),
      ),
      const ContextMenuItem(label: ''),
      ContextMenuItem(
        label: 'Exit',
        icon: Icons.exit_to_app_rounded,
        shortcut: 'Alt+F4',
        danger: true,
        action: onQuit,
      ),
    ],
    'View': [
      ContextMenuItem(
        label: 'Command Palette…',
        icon: AppIcons.search,
        shortcut: 'Ctrl+K',
        action: () => state.paletteOpen = true,
      ),
      const ContextMenuItem(label: ''),
      ContextMenuItem(
        label: 'Toggle Sidebar',
        icon: Icons.view_sidebar_outlined,
        shortcut: 'Ctrl+B',
        action: state.toggleSidebar,
      ),
      ContextMenuItem(
        label: 'Toggle Dark / Light Theme',
        icon: Icons.brightness_medium_outlined,
        shortcut: 'Ctrl+T',
        action: state.toggleTheme,
      ),
    ],
    'Window': [
      ContextMenuItem(
        label: 'Minimize',
        icon: AppIcons.windowMinimize,
        action: onMinimize,
      ),
      ContextMenuItem(
        label: 'Maximize / Restore',
        icon: AppIcons.windowMaximize,
        action: onToggleMaximize,
      ),
      const ContextMenuItem(label: ''),
      ContextMenuItem(
        label: 'Close Window',
        icon: AppIcons.windowClose,
        shortcut: 'Alt+F4',
        danger: true,
        action: onQuit,
      ),
    ],
    'Help': [
      ContextMenuItem(
        label: 'Check for Updates…',
        icon: Icons.system_update_rounded,
        action: () => checkForUpdates(state),
      ),
      const ContextMenuItem(label: ''),
      ContextMenuItem(
        label: 'Show Data Directory',
        icon: Icons.folder_outlined,
        action: () => Platform.reveal(AppStore.dir),
      ),
      ContextMenuItem(
        label: 'Show Log File',
        icon: Icons.description_outlined,
        action: () => Platform.reveal(Paths.logFile(AppStore.dir)),
      ),
      const ContextMenuItem(label: ''),
      ContextMenuItem(
        label: 'Developer & GitHub…',
        icon: AppIcons.github,
        action: () => state.modal = const ModalDeveloper(),
      ),
      ContextMenuItem(
        label: 'Report an Issue…',
        icon: AppIcons.bug,
        action: () => Platform.openUrl(IssueReport.url().toString()),
      ),
      const ContextMenuItem(label: ''),
      ContextMenuItem(
        label: 'About ${AppConfig.NAME}',
        icon: Icons.info_outline_rounded,
        action: () => state.modal = const ModalAbout(),
      ),
    ],
  };
}

/// In-window menu bar for Windows and Linux custom window chrome.
class WindowMenuBar extends StatefulWidget {
  const WindowMenuBar({
    super.key,
    required this.state,
    required this.onQuit,
    this.onMinimize,
    this.onToggleMaximize,
  });

  final AppState state;
  final VoidCallback onQuit;
  final VoidCallback? onMinimize;
  final VoidCallback? onToggleMaximize;

  @override
  State<WindowMenuBar> createState() => _WindowMenuBarState();
}

class _WindowMenuBarState extends State<WindowMenuBar> {
  String? _activeMenu;

  void _openMenu(
    BuildContext btnContext,
    String name,
    List<ContextMenuItem> items,
  ) {
    setState(() => _activeMenu = name);
    final box = btnContext.findRenderObject() as RenderBox?;
    if (box != null) {
      final pos = box.localToGlobal(Offset(0, box.size.height + 2));
      ContextMenu.show(context, pos, items).then((_) {
        if (mounted) setState(() => _activeMenu = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final menuItemsMap = buildWindowsLinuxMenuItems(
      state: widget.state,
      onQuit: widget.onQuit,
      onMinimize: widget.onMinimize,
      onToggleMaximize: widget.onToggleMaximize,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 6),
          child: Image.asset(
            'assets/icons/header_logo.png',
            width: 14,
            height: 14,
            filterQuality: FilterQuality.medium,
          ),
        ),
        for (final entry in menuItemsMap.entries)
          Builder(
            builder: (btnCtx) {
              final isOpen = _activeMenu == entry.key;
              return HoverBuilder(
                cursor: SystemMouseCursors.click,
                onTap: () => _openMenu(btnCtx, entry.key, entry.value),
                builder: (context, hovered) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isOpen || hovered ? p.hover : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: T(
                      entry.key,
                      size: 11.5,
                      weight: FontWeight.w500,
                      color: isOpen || hovered ? p.text : p.muted,
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }
}

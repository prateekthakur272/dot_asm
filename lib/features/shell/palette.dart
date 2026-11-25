import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/selectable_row.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/features/shell/menus.dart' show checkForUpdates;
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';
import 'package:dot_asm/utils/app_config.dart';
import 'package:dot_asm/utils/app_metadata.dart';

int _fuzzy(String q, String t) {
  if (q.isEmpty) return 0;
  final ql = q.toLowerCase();
  final tl = t.toLowerCase();
  var qi = 0, score = 0, last = -2;
  for (var i = 0; i < tl.length; i++) {
    if (qi < ql.length && tl[i] == ql[qi]) {
      score += i == last + 1 ? 6 : 1;
      if (i == 0 || ' /-_.:'.contains(tl[i - 1])) score += 4;
      last = i;
      qi++;
    }
  }
  return qi == ql.length ? score - tl.length ~/ 25 : -1;
}

class _PaletteItem {
  const _PaletteItem({
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.action,
  });

  final String title;
  final String subtitle;
  final String category;
  final IconData icon;
  final VoidCallback action;
}

class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key, required this.state});
  final AppState state;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<_PaletteItem> _buildItems() {
    final state = widget.state;

    // Closes the palette first, then runs [action].
    VoidCallback run(VoidCallback action) => () {
      state.paletteOpen = false;
      action();
    };

    final project = state.activeProject;
    return [
      _PaletteItem(
        title: 'New Project',
        subtitle: 'Pick an architecture and processor',
        category: 'Actions',
        icon: AppIcons.add,
        action: run(() => state.modal = const ModalNewProject()),
      ),
      _PaletteItem(
        title: 'Open Project…',
        subtitle: 'Choose a project folder (contains project.dotasm)',
        category: 'Actions',
        icon: AppIcons.folder,
        action: run(() => state.openProjectFromPicker()),
      ),
      _PaletteItem(
        title: 'Processor Gallery',
        subtitle: 'Browse famous processors by family and era',
        category: 'Actions',
        icon: Icons.collections_bookmark_outlined,
        action: run(state.openGallery),
      ),
      if (project != null) ...[
        _PaletteItem(
          title: 'Processor Builder',
          subtitle: 'Edit the processors of this project',
          category: 'Actions',
          icon: Icons.memory_rounded,
          action: run(state.openBuilder),
        ),
        _PaletteItem(
          title: 'New Processor',
          subtitle: 'Design a processor in this project',
          category: 'Actions',
          icon: AppIcons.add,
          action: run(state.newProcessor),
        ),
        _PaletteItem(
          title: 'Assemble',
          subtitle: 'Assemble the source and restart the processor',
          category: 'Run',
          icon: Icons.build_circle_outlined,
          action: run(state.assembleNow),
        ),
        _PaletteItem(
          title: state.sim.running ? 'Pause' : 'Run',
          subtitle: 'Run the program until it stops or hits a breakpoint',
          category: 'Run',
          icon: state.sim.running
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          action: run(
            () => state.sim.running
                ? state.sim.pause()
                : unawaited(state.sim.run()),
          ),
        ),
        _PaletteItem(
          title: 'Step',
          subtitle: 'Execute one instruction',
          category: 'Run',
          icon: Icons.skip_next_rounded,
          action: run(state.sim.stepOnce),
        ),
        _PaletteItem(
          title: 'Step Back',
          subtitle: 'Undo the last instruction',
          category: 'Run',
          icon: Icons.undo_rounded,
          action: run(state.sim.stepBack),
        ),
        _PaletteItem(
          title: 'Reset Processor',
          subtitle: 'Registers, flags and memory back to the start',
          category: 'Run',
          icon: Icons.restart_alt_rounded,
          action: run(state.sim.reset),
        ),
        _PaletteItem(
          title: 'Close Project',
          subtitle: project.name,
          category: 'Actions',
          icon: AppIcons.close,
          action: run(state.closeProject),
        ),
      ],
      for (final pr in state.projects)
        _PaletteItem(
          title: 'Open ${pr.name}',
          subtitle: state.processorFor(pr)?.name ?? '${pr.processor}',
          category: 'Projects',
          icon: Icons.memory_rounded,
          action: run(() => state.openProject(pr.id)),
        ),
      _PaletteItem(
        title: 'Open Preferences',
        subtitle: 'Theme, editor, simulator and startup options',
        category: 'Actions',
        icon: AppIcons.settings,
        action: run(() => state.modal = const ModalSettings()),
      ),
      _PaletteItem(
        title: 'Toggle Dark / Light Theme',
        subtitle: 'Switch the interface palette',
        category: 'Actions',
        icon: Icons.brightness_medium_outlined,
        action: run(state.toggleTheme),
      ),
      _PaletteItem(
        title: 'Toggle Sidebar',
        subtitle: 'Show or hide the left sidebar',
        category: 'Actions',
        icon: AppIcons.sidebar,
        action: run(state.toggleSidebar),
      ),
      _PaletteItem(
        title: 'Check for Updates',
        subtitle: 'Look for a newer release on GitHub',
        category: 'Actions',
        icon: Icons.system_update_rounded,
        action: run(() => checkForUpdates(state)),
      ),
      _PaletteItem(
        title: 'Show Data Folder',
        subtitle: AppStore.dir,
        category: 'Actions',
        icon: AppIcons.folder,
        action: run(() => Platform.reveal(AppStore.dir)),
      ),
      _PaletteItem(
        title: 'Welcome Tour',
        subtitle: 'A short walkthrough of what dot ASM does',
        category: 'Help',
        icon: Icons.waving_hand_outlined,
        action: run(() => state.modal = const ModalOnboarding()),
      ),
      _PaletteItem(
        title: 'Developer & GitHub',
        subtitle: 'Source code, releases and issue reporting',
        category: 'Help',
        icon: AppIcons.code,
        action: run(() => state.modal = const ModalDeveloper()),
      ),
      _PaletteItem(
        title: 'About ${AppConfig.NAME}',
        subtitle: 'Version ${AppMetadata.version}',
        category: 'Help',
        icon: AppIcons.info,
        action: run(() => state.modal = const ModalAbout()),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final query = _controller.text.trim();
    final allItems = _buildItems();

    final filtered = query.isEmpty
        ? allItems
        : (allItems
                  .map((item) {
                    final score = _fuzzy(
                      query,
                      '${item.title} ${item.subtitle}',
                    );
                    return (item: item, score: score);
                  })
                  .where((it) => it.score >= 0)
                  .toList()
                ..sort((a, b) => b.score.compareTo(a.score)))
              .map((it) => it.item)
              .toList();

    final safeIndex = filtered.isEmpty
        ? 0
        : _selectedIndex.clamp(0, filtered.length - 1);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            setState(() {
              if (filtered.isNotEmpty) {
                _selectedIndex = (_selectedIndex + 1) % filtered.length;
              }
            });
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            setState(() {
              if (filtered.isNotEmpty) {
                _selectedIndex =
                    (_selectedIndex - 1 + filtered.length) % filtered.length;
              }
            });
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.enter) {
            if (filtered.isNotEmpty) {
              filtered[safeIndex].action();
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            widget.state.paletteOpen = false;
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: ClickableNoRipple(
        onClick: () => widget.state.paletteOpen = false,
        child: Container(
          color: Colors.black.withOpacity(0.55),
          child: Align(
            alignment: const Alignment(0, -0.6),
            child: ClickableNoRipple(
              onClick: () {}, // Prevent click propagation
              child: Container(
                width: 620,
                constraints: const BoxConstraints(maxHeight: 460),
                decoration: BoxDecoration(
                  color: p.panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.border, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 32,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Search bar
                    DrawBottomBorder(
                      color: p.border,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(AppIcons.search, size: 16, color: p.muted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Center(
                                child: Transform.translate(
                                  offset: const Offset(0, -1.5),
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _focusNode,
                                    onChanged: (_) =>
                                        setState(() => _selectedIndex = 0),
                                    maxLines: 1,
                                    cursorHeight: 16,
                                    textAlignVertical: TextAlignVertical.center,
                                    style: TextStyle(
                                      color: p.text,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    decoration: InputDecoration.collapsed(
                                      hintText: 'Type a command…',
                                      hintStyle: TextStyle(
                                        color: p.muted,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: p.field,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: p.border, width: 0.5),
                              ),
                              child: T(
                                'ESC',
                                size: 10,
                                color: p.muted,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Item list
                    Flexible(
                      child: filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(
                                child: T(
                                  'No matching commands',
                                  color: p.muted,
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemBuilder: (context, idx) {
                                final item = filtered[idx];
                                final isSelected = idx == safeIndex;

                                return HoverBuilder(
                                  cursor: SystemMouseCursors.click,
                                  onTap: item.action,
                                  builder: (context, hovered) {
                                    return SelectableRow(
                                      selected: isSelected,
                                      hovered: hovered,
                                      radius: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 11,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            item.icon,
                                            size: 16,
                                            color: isSelected
                                                ? p.accent
                                                : p.muted,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                T(
                                                  item.title,
                                                  size: 13,
                                                  weight: isSelected
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                                  color: isSelected
                                                      ? p.accent
                                                      : p.text,
                                                ),
                                                T(
                                                  item.subtitle,
                                                  size: 11.5,
                                                  color: p.muted,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          T(
                                            item.category,
                                            size: 11,
                                            color: p.muted.withOpacity(0.7),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

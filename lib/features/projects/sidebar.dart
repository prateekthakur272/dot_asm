import 'package:flutter/material.dart';
import 'package:dot_asm/components/empty_state.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/components/context_menu.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/selectable_row.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/core/model/project.dart';
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';
import 'package:dot_asm/utils/app_config.dart';

/// Left sidebar: the list of projects.
class ProjectsSidebar extends StatelessWidget {
  const ProjectsSidebar({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final projects = state.projects;
    final active = state.activeProject?.id;
    return Container(
      color: p.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeader(state: state),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                T(
                  'PROJECTS',
                  size: 10.5,
                  weight: FontWeight.w700,
                  color: p.muted,
                ),
                const Spacer(),
                IconBtn(
                  icon: AppIcons.folder,
                  tooltip: 'Open a project folder…',
                  size: 24,
                  iconSize: 14,
                  onClick: () => state.openProjectFromPicker(),
                ),
                IconBtn(
                  icon: AppIcons.add,
                  tooltip: 'New project',
                  size: 24,
                  iconSize: 14,
                  onClick: () => state.modal = const ModalNewProject(),
                ),
              ],
            ),
          ),
          Expanded(
            child: projects.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: EmptyState(
                          art: EmptyArt.projects,
                          title: 'No projects yet',
                          subtitle: 'Create one, or open a folder that has a project.dotasm.',
                          action: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Btn(
                                label: 'New project',
                                icon: AppIcons.add,
                                primary: true,
                                height: 30,
                                onClick: () =>
                                    state.modal = const ModalNewProject(),
                              ),
                              const SizedBox(height: 6),
                              Btn(
                                label: 'Open project…',
                                icon: AppIcons.folder,
                                height: 30,
                                onClick: () => state.openProjectFromPicker(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    physics: const ClampingScrollPhysics(),
                    itemCount:
                        projects.length + state.missingProjectPaths.length,
                    itemBuilder: (context, i) => i < projects.length
                        ? _ProjectRow(
                            state: state,
                            project: projects[i],
                            selected: projects[i].id == active,
                          )
                        : _MissingRow(
                            state: state,
                            path:
                                state.missingProjectPaths[i - projects.length],
                          ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Btn(
                  label: 'Processor gallery',
                  icon: Icons.collections_bookmark_outlined,
                  height: 30,
                  fontSize: 12,
                  outlined: true,
                  onClick: state.openGallery,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.state,
    required this.project,
    required this.selected,
  });
  final AppState state;
  final Project project;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final proc = state.processorFor(project);
    return Builder(
      builder: (rowCtx) => HoverBuilder(
        cursor: SystemMouseCursors.click,
        onTap: () => state.openProject(project.id),
        onSecondaryTap: () {
          final box = rowCtx.findRenderObject() as RenderBox?;
          if (box == null) return;
          ContextMenu.show(
            rowCtx,
            box.localToGlobal(Offset(24, box.size.height - 4)),
            [
              ContextMenuItem(
                label: Platform.revealLabel,
                icon: AppIcons.folder,
                action: () => Platform.reveal(project.path),
              ),
              ContextMenuItem(
                label: 'Copy folder path',
                icon: AppIcons.copy,
                action: () {
                  Platform.copy(project.path);
                  state.showToast('Copied the project path');
                },
              ),
              const ContextMenuItem(label: ''),
              ContextMenuItem(
                label: 'Rename…',
                icon: AppIcons.edit,
                action: () => state.modal = ModalRenameProject(project),
              ),
              ContextMenuItem(
                label: 'Remove…',
                icon: AppIcons.delete,
                danger: true,
                action: () => state.modal = ModalConfirmDeleteProject(project),
              ),
            ],
          );
        },
        builder: (context, hovered) => SelectableRow(
          selected: selected,
          hovered: hovered,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.memory_rounded,
                size: 15,
                color: selected ? p.accent : p.muted,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    T(
                      project.name,
                      size: 12.5,
                      weight: selected ? FontWeight.w700 : FontWeight.w500,
                      maxLines: 1,
                    ),
                    T(
                      proc?.name ?? 'Missing processor',
                      size: 10.5,
                      color: proc == null ? p.err : p.muted,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A registered project whose folder cannot be read any more.
class _MissingRow extends StatelessWidget {
  const _MissingRow({required this.state, required this.path});
  final AppState state;
  final String path;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: path,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        child: Row(
          children: [
            Icon(Icons.folder_off_outlined, size: 15, color: p.err),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  T(
                    path
                            .split(RegExp(r'[\\/]'))
                            .where((e) => e.isNotEmpty)
                            .lastOrNull ??
                        path,
                    size: 12.5,
                    color: p.muted,
                    maxLines: 1,
                  ),
                  T('Folder not found', size: 10.5, color: p.err, maxLines: 1),
                ],
              ),
            ),
            IconBtn(
              icon: AppIcons.close,
              tooltip: 'Forget this project',
              size: 22,
              iconSize: 12,
              onClick: () => state.forgetMissing(path),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's header, at the top of the sidebar: the app name with search, preferences and the sidebar toggle.
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mod = Platform.isMac ? '⌘K' : 'Ctrl+K';
    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border.withOpacity(0.7))),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/icons/header_logo.png',
            width: 24,
            height: 24,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: T(AppConfig.NAME, size: 15, weight: FontWeight.w700),
          ),
          IconBtn(
            icon: Icons.search_rounded,
            tooltip: 'Command palette ($mod)',
            size: 28,
            iconSize: 16,
            onClick: () => state.paletteOpen = true,
          ),
          IconBtn(
            icon: AppIcons.settings,
            tooltip: 'Preferences (${Platform.isMac ? "⌘," : "Ctrl+,"})',
            size: 28,
            iconSize: 15,
            onClick: () => state.modal = const ModalSettings(),
          ),
        ],
      ),
    );
  }
}

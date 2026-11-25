import 'package:flutter/material.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/components/dot_pattern.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';
import 'package:dot_asm/utils/app_config.dart';

/// Shown when no project is open: the app's name, one primary action, a row of secondary ones, and recent projects.
class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final recent = state.recentProjects();
    return Stack(
      children: [
        const Positioned.fill(child: DotPatternBackground()),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/icons/app_icon.png',
                    width: 56,
                    height: 56,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(height: 14),
                  const T(AppConfig.NAME, size: 22, weight: FontWeight.w700),
                  const SizedBox(height: 6),
                  T(
                    'Write assembly and watch a processor run it.',
                    size: 12.5,
                    color: p.muted,
                    align: TextAlign.center,
                    overflow: TextOverflow.visible,
                  ),
                  const SizedBox(height: 22),
                  Btn(
                    label: 'New project',
                    icon: AppIcons.add,
                    primary: true,
                    height: 38,
                    fontSize: 13,
                    onClick: () => state.modal = const ModalNewProject(),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      Btn(
                        label: 'Open project…',
                        icon: AppIcons.folder,
                        height: 30,
                        fontSize: 12,
                        outlined: true,
                        onClick: () => state.openProjectFromPicker(),
                      ),
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
                  if (recent.isNotEmpty) ...[
                    const SizedBox(height: 34),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: T(
                        'RECENT PROJECTS',
                        size: 10.5,
                        weight: FontWeight.w700,
                        color: p.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final pr in recent)
                      HoverBuilder(
                        cursor: SystemMouseCursors.click,
                        onTap: () => state.openProject(pr.path),
                        builder: (context, hovered) => Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: hovered ? p.hover : p.panel,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: p.border),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.memory_rounded,
                                size: 15,
                                color: p.muted,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    T(
                                      pr.name,
                                      size: 12.5,
                                      weight: FontWeight.w600,
                                      maxLines: 1,
                                    ),
                                    T(
                                      state.processorFor(pr)?.name ??
                                          'Processor not found',
                                      size: 10.5,
                                      color: p.muted,
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: p.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

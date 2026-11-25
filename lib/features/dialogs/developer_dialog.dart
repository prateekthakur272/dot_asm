import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/components/layout.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';
import 'package:dot_asm/utils/app_config.dart';
import 'package:dot_asm/utils/app_metadata.dart';
import 'package:dot_asm/utils/issue_report.dart';

/// Developer and GitHub modal dialog, featuring interactive quick actions, repository links, and author identity.
class DeveloperDialog extends StatelessWidget {
  const DeveloperDialog({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;

    return ModalScaffold(
      title: 'Developer',
      width: 620,
      maxHeight: 640,
      onClose: () => state.modal = null,
      actions: [
        Btn(
          label: 'Close',
          primary: true,
          height: 32,
          onClick: () => state.modal = null,
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Author & Project Hero Banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: p.field,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p.border, width: 1),
                ),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: p.panel,
                            border: Border.all(color: p.border, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(
                                  p.dark ? 0.35 : 0.08,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: GitHubIcon(size: 34, color: p.text),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: p.ok,
                              shape: BoxShape.circle,
                              border: Border.all(color: p.panel, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              T(
                                AppConfig.VENDOR,
                                size: 18,
                                weight: FontWeight.w700,
                              ),
                              const SizedBox(width: 8),
                              HoverBuilder(
                                cursor: SystemMouseCursors.click,
                                onTap: () =>
                                    Platform.openUrl(AppConfig.DEVELOPER_URL),
                                builder: (context, hovered) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: hovered
                                          ? p.accent.withOpacity(0.2)
                                          : p.accent.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: hovered
                                            ? p.accent
                                            : p.accent.withOpacity(0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GitHubIcon(size: 11, color: p.accent),
                                        const SizedBox(width: 4),
                                        T(
                                          '@prateekthakur272',
                                          size: 10.5,
                                          color: p.accent,
                                          weight: FontWeight.w600,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          T(
                            'Developer of ${AppConfig.NAME}',
                            size: 12,
                            color: p.muted,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _PillBadge(
                                label: 'Public Repo',
                                color: p.ok,
                                dot: true,
                              ),
                              _PillBadge(
                                label: 'v${AppMetadata.version}',
                                color: p.accent,
                              ),
                              _PillBadge(
                                label: 'Flutter Desktop',
                                color: const Color(0xFF54C5F8),
                              ),
                              _PillBadge(label: 'Open Source', color: p.muted),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 2. Interactive Quick Actions Grid
              Row(
                children: [
                  Expanded(
                    child: _ActionTile(
                      icon: AppIcons.code,
                      iconColor: p.accent,
                      title: 'Source Code',
                      subtitle: 'Browse repository & code',
                      onClick: () => Platform.openUrl(AppConfig.REPOSITORY),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionTile(
                      icon: Icons.star_rounded,
                      iconColor: const Color(0xFFE3B341),
                      title: 'Star on GitHub',
                      subtitle: 'Bookmark & show support',
                      onClick: () => Platform.openUrl(AppConfig.REPOSITORY),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ActionTile(
                      icon: AppIcons.download,
                      iconColor: p.ok,
                      title: 'Releases & Notes',
                      subtitle: 'Latest binaries & changelog',
                      onClick: () => Platform.openUrl(AppConfig.RELEASES_URL),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionTile(
                      icon: AppIcons.bug,
                      iconColor: p.warn,
                      title: 'Report an Issue',
                      subtitle: 'Bugs, ideas & suggestions',
                      onClick: () =>
                          Platform.openUrl(IssueReport.url().toString()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 3. Interactive Link Cards
              if (AppConfig.MORE_APPS_URL.trim().isNotEmpty) ...[
                _InteractiveLinkCard(
                  label: 'EXPLORE MORE APPS',
                  icon: Icons.apps_rounded,
                  url: AppConfig.MORE_APPS_URL,
                ),
                const SizedBox(height: 12),
              ],

              // 4. Open-Source Community Banner
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: p.panel,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: p.border, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.favorite_rounded,
                      size: 14,
                      color: const Color(0xFFF778BA),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: T(
                        '${AppConfig.NAME} is built in the open. Bug reports, ideas and pull requests are welcome on GitHub.',
                        color: p.muted,
                        size: 11.5,
                      ),
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

/// Small pill badge for metadata chips.
class _PillBadge extends StatelessWidget {
  const _PillBadge({
    required this.label,
    required this.color,
    this.dot = false,
  });
  final String label;
  final Color color;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          T(label, size: 10, weight: FontWeight.w600, color: color),
        ],
      ),
    );
  }
}

/// Interactive quick action tile with icon, title, subtitle, and hover effects.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onClick,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;

    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      onTap: onClick,
      builder: (context, hovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: hovered ? p.hover : p.field,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hovered ? iconColor.withOpacity(0.6) : p.border,
              width: 1,
            ),
            boxShadow: hovered
                ? [
                    BoxShadow(
                      color: iconColor.withOpacity(p.dark ? 0.2 : 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(hovered ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        T(
                          title,
                          size: 12.5,
                          weight: FontWeight.w600,
                          color: hovered ? p.text : p.text.withOpacity(0.9),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_outward_rounded,
                          size: 11,
                          color: hovered ? iconColor : p.muted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    T(subtitle, size: 10.5, color: p.muted, maxLines: 1),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Rich interactive link card with label, icon, monospaced URL, and interactive copy/open controls.
class _InteractiveLinkCard extends StatefulWidget {
  const _InteractiveLinkCard({
    required this.label,
    required this.icon,
    required this.url,
  });

  final String label;
  final IconData icon;
  final String url;

  @override
  State<_InteractiveLinkCard> createState() => _InteractiveLinkCardState();
}

class _InteractiveLinkCardState extends State<_InteractiveLinkCard> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _handleCopy() {
    Platform.copy(widget.url);
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;

    return HoverBuilder(
      builder: (context, cardHovered) {
        return Container(
          decoration: BoxDecoration(
            color: p.field,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: cardHovered ? p.accent.withOpacity(0.4) : p.border,
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(widget.icon, size: 12, color: p.muted),
                  const SizedBox(width: 5),
                  T(
                    widget.label,
                    color: p.muted,
                    size: 10.5,
                    weight: FontWeight.w600,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.only(
                  left: 10,
                  top: 4,
                  bottom: 4,
                  right: 4,
                ),
                decoration: BoxDecoration(
                  color: p.panel,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: p.border, width: 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: MonoText(
                        widget.url,
                        size: 11.5,
                        color: p.text.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Copy action button with animated visual confirmation
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _copied
                          ? Container(
                              key: const ValueKey('copied'),
                              height: 28,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: p.ok.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: p.ok.withOpacity(0.4),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(AppIcons.check, size: 12, color: p.ok),
                                  const SizedBox(width: 4),
                                  T(
                                    'Copied',
                                    size: 11,
                                    color: p.ok,
                                    weight: FontWeight.w600,
                                  ),
                                ],
                              ),
                            )
                          : Btn(
                              key: const ValueKey('copy'),
                              label: 'Copy',
                              icon: AppIcons.copy,
                              height: 28,
                              fontSize: 11,
                              onClick: _handleCopy,
                            ),
                    ),
                    const SizedBox(width: 6),
                    Btn(
                      label: 'Open',
                      height: 28,
                      fontSize: 11,
                      primary: true,
                      icon: AppIcons.external,
                      onClick: () => Platform.openUrl(widget.url),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

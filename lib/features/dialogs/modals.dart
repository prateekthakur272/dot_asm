import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/components/layout.dart';
import 'package:dot_asm/components/selectable_row.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/core/model/models.dart';
import 'package:dot_asm/core/storage/storage.dart';
import 'package:dot_asm/features/dialogs/developer_dialog.dart';
import 'package:dot_asm/features/dialogs/onboarding_dialog.dart';
import 'package:dot_asm/features/dialogs/processor_dialogs.dart';
import 'package:dot_asm/features/dialogs/settings_widgets.dart';
import 'package:dot_asm/features/dialogs/project_dialogs.dart';
import 'package:dot_asm/features/shell/menus.dart' show checkForUpdates;
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';
import 'package:dot_asm/utils/app_config.dart';
import 'package:dot_asm/utils/app_metadata.dart';
import 'package:dot_asm/utils/paths.dart';
import 'package:dot_asm/utils/update_checker.dart';

/// Resolves the active [AppModal] into its dialog, over a dimmed, click-to-dismiss backdrop.
Widget buildActiveModal(BuildContext context, AppState state) {
  final modal = state.modal;
  if (modal == null) return const SizedBox.shrink();

  return ClickableNoRipple(
    onClick: () => state.modal = null,
    child: Container(
      color: Colors.black.withOpacity(0.5),
      child: switch (modal) {
        ModalSettings() => _SettingsDialog(state: state),
        ModalAbout() => _AboutDialog(state: state),
        ModalDeveloper() => DeveloperDialog(state: state),
        ModalOnboarding() => OnboardingDialog(state: state),
        ModalUpdateAvailable(:final version) => _UpdateAvailableDialog(
          state: state,
          version: version,
        ),
        ModalNewProject(:final templateId, :final openInBuilder) =>
          NewProjectDialog(
            state: state,
            templateId: templateId,
            openInBuilder: openInBuilder,
          ),
        ModalRenameProject(:final project) => RenameProjectDialog(
          state: state,
          project: project,
        ),
        ModalImportProcessor() => ImportProcessorDialog(state: state),
        ModalConfirmDeleteProcessor(:final processor) =>
          ConfirmDeleteProcessorDialog(state: state, processor: processor),
        ModalConfirmDeleteProject(:final project) => ConfirmDeleteProjectDialog(
          state: state,
          project: project,
        ),
      },
    ),
  );
}

enum _SettingsCategory {
  general('General', Icons.tune_rounded),
  editor('Editor', Icons.code_rounded),
  simulator('Simulator', Icons.developer_board_rounded),
  storage('Storage & Data', AppIcons.folder);

  const _SettingsCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.state});
  final AppState state;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  _SettingsCategory _category = _SettingsCategory.general;

  void _updateSettings(AppSettings Function(AppSettings current) updater) {
    widget.state.updateSettings(updater(widget.state.settings));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final settings = widget.state.settings;

    return ModalScaffold(
      title: 'Preferences',
      width: 780,
      onClose: () => widget.state.modal = null,
      actions: [
        Btn(
          label: 'Reset to defaults',
          height: 32,
          outlined: true,
          onClick: () => _updateSettings((_) => const AppSettings()),
        ),
        Btn(
          label: 'Done',
          primary: true,
          height: 32,
          onClick: () => widget.state.modal = null,
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 460),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The categories, down the left side
            SizedBox(
              width: 168,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final cat in _SettingsCategory.values)
                    HoverBuilder(
                      cursor: SystemMouseCursors.click,
                      onTap: () => setState(() => _category = cat),
                      builder: (context, hovered) => SelectableRow(
                        selected: _category == cat,
                        hovered: hovered,
                        height: 34,
                        margin: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          children: [
                            Icon(
                              cat.icon,
                              size: 15,
                              color: _category == cat ? p.accent : p.muted,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: T(
                                cat.label,
                                size: 12,
                                weight: _category == cat
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _category == cat ? p.text : p.muted,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: p.border.withOpacity(0.7),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: switch (_category) {
                  _SettingsCategory.general => _buildGeneralTab(
                    context,
                    p,
                    settings,
                  ),
                  _SettingsCategory.editor => _buildEditorTab(settings),
                  _SettingsCategory.simulator => _buildSimulatorTab(settings),
                  _SettingsCategory.storage => _buildStorageTab(context, p),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- TAB 1: GENERAL & THEME ---
  Widget _buildGeneralTab(BuildContext context, Pal p, AppSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const T('Appearance & Theme', size: 12.5, weight: FontWeight.w700),
        const SizedBox(height: 4),
        T(
          'Choose your preferred desktop interface theme mode.',
          size: 11.5,
          color: p.muted,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildThemeCard(
              p: p,
              title: 'System',
              subtitle: 'Match OS look',
              icon: Icons.brightness_auto_rounded,
              mode: ThemeMode.system,
              selected: settings.themeMode == ThemeMode.system,
            ),
            const SizedBox(width: 10),
            _buildThemeCard(
              p: p,
              title: 'Dark',
              subtitle: 'Charcoal palette',
              icon: Icons.dark_mode_rounded,
              mode: ThemeMode.dark,
              selected: settings.themeMode == ThemeMode.dark,
            ),
            const SizedBox(width: 10),
            _buildThemeCard(
              p: p,
              title: 'Light',
              subtitle: 'Daylight palette',
              icon: Icons.light_mode_rounded,
              mode: ThemeMode.light,
              selected: settings.themeMode == ThemeMode.light,
            ),
          ],
        ),
        const SizedBox(height: 22),

        SettingsGroup(
          title: 'Startup',
          subtitle: 'What the app does when it starts.',
          children: [
            SettingToggle(
              title: 'Reopen the last project',
              description: 'Start where you left off. When off, the app opens on the start screen.',
              value: settings.reopenLastProject,
              onChanged: (v) =>
                  _updateSettings((s) => s.copyWith(reopenLastProject: v)),
            ),
            SettingToggle(
              title: 'Check for updates on startup',
              description: 'Look for a newer release on GitHub when the app starts. Nothing else is ever sent.',
              value: settings.checkUpdates,
              onChanged: (v) =>
                  _updateSettings((s) => s.copyWith(checkUpdates: v)),
            ),
            SettingRow(
              title: 'Welcome tour',
              description:
                  'A short walkthrough of what ${AppConfig.NAME} does.',
              trailing: Btn(
                label: 'Show tour',
                height: 28,
                fontSize: 11.5,
                onClick: () => widget.state.modal = const ModalOnboarding(),
              ),
            ),
          ],
        ),

        // App info & version banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.field,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.border, width: 1),
          ),
          child: Row(
            children: [
              Image.asset(
                'assets/icons/header_logo.png',
                width: 28,
                height: 28,
                filterQuality: FilterQuality.medium,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        const T(
                          AppConfig.NAME,
                          size: 13,
                          weight: FontWeight.w700,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: p.accent.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: T(
                            'v${AppMetadata.version}',
                            size: 10,
                            weight: FontWeight.w700,
                            color: p.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    T(AppConfig.TAGLINE, size: 11, color: p.muted),
                  ],
                ),
              ),
              Btn(
                label: 'Check for Updates…',
                icon: Icons.update_rounded,
                height: 30,
                fontSize: 11.5,
                onClick: () => checkForUpdates(widget.state),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- TAB: EDITOR ---
  Widget _buildEditorTab(AppSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Assembly editor',
          subtitle: 'How the code editor behaves while you type.',
          children: [
            SettingChoice<int>(
              title: 'Font size',
              description: 'The size of the code in the assembly editor, the processor source and the starter program.',
              value: settings.editorFontSize,
              options: {
                for (final n in const [11, 12, 13, 14, 15, 16, 18]) n: '$n',
              },
              onChanged: (v) =>
                  _updateSettings((s) => s.copyWith(editorFontSize: v)),
            ),
            SettingChoice<int>(
              title: 'Indentation',
              description: 'Spaces per indent level (Tab key, auto-indent and indent guides).',
              value: settings.editorTabSize,
              options: const {2: '2', 4: '4', 8: '8'},
              onChanged: (v) =>
                  _updateSettings((s) => s.copyWith(editorTabSize: v)),
            ),
            SettingToggle(
              title: 'Close brackets and quotes',
              description: 'Typing ( [ or " adds the closing one, and typing it again moves past it.',
              value: settings.autoClosePairs,
              onChanged: (v) =>
                  _updateSettings((s) => s.copyWith(autoClosePairs: v)),
            ),
            SettingToggle(
              title: 'Suggest while typing',
              description: 'Show instructions, registers and labels as you type. Ctrl+Space always opens them.',
              value: settings.autoSuggest,
              onChanged: (v) =>
                  _updateSettings((s) => s.copyWith(autoSuggest: v)),
            ),
            SettingToggle(
              title: 'Indent guides',
              description: 'Faint vertical lines at every indent step.',
              value: settings.indentGuides,
              onChanged: (v) =>
                  _updateSettings((s) => s.copyWith(indentGuides: v)),
            ),
          ],
        ),
      ],
    );
  }

  // --- TAB: SIMULATOR ---
  Widget _buildSimulatorTab(AppSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Running programs',
          subtitle: 'Defaults for projects and the processor view.',
          children: [
            SettingChoice<String>(
              title: 'Run speed for new projects',
              description: 'How quickly Run executes. Each project remembers its own speed afterwards.',
              value: settings.defaultSpeed,
              options: const {
                'slow': 'Slow',
                'medium': 'Medium',
                'fast': 'Fast',
              },
              onChanged: (v) =>
                  _updateSettings((s) => s.copyWith(defaultSpeed: v)),
            ),
            SettingChoice<String>(
              title: 'Show values as',
              description: 'How registers and memory are shown when the app starts. Changing it in the processor view updates this.',
              value: settings.valueFormat,
              options: const {
                'hex': 'Hex',
                'dec': 'Signed',
                'udec': 'Unsigned',
                'bin': 'Binary',
              },
              onChanged: (v) =>
                  _updateSettings((s) => s.copyWith(valueFormat: v)),
            ),
            SettingChoice<int>(
              title: 'Undo history',
              description: 'Executed instructions kept for Step back and the trace. More uses more memory.',
              value: settings.historyLimit,
              options: const {
                1000: '1,000',
                5000: '5,000',
                20000: '20,000',
                50000: '50,000',
              },
              onChanged: (v) =>
                  _updateSettings((s) => s.copyWith(historyLimit: v)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildThemeCard({
    required Pal p,
    required String title,
    required String subtitle,
    required IconData icon,
    required ThemeMode mode,
    required bool selected,
  }) {
    return Expanded(
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        onTap: () => _updateSettings((s) => s.copyWith(themeMode: mode)),
        builder: (context, hovered) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected
                  ? p.accent.withOpacity(0.12)
                  : hovered
                  ? p.hover
                  : p.field,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? p.accent
                    : hovered
                    ? p.accent.withOpacity(0.4)
                    : p.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: selected ? p.accent : p.muted),
                    const Spacer(),
                    if (selected)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: p.accent,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                T(
                  title,
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: selected ? p.accent : p.text,
                ),
                const SizedBox(height: 2),
                T(subtitle, size: 10.5, color: p.muted),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- TAB 2: STORAGE & DATA ---
  Widget _buildStorageTab(BuildContext context, Pal p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const T('File Storage & Data', size: 12.5, weight: FontWeight.w700),
        const SizedBox(height: 4),
        T(
          '${AppConfig.NAME} keeps preferences and session state in plain files on this computer.',
          size: 11.5,
          color: p.muted,
        ),
        const SizedBox(height: 12),
        _buildStorageCard(
          p: p,
          title: 'Rotating Diagnostic Log',
          subtitle: 'Rotating log file capped at 1 MB (.old backup preserved)',
          path: Paths.logFile(AppStore.dir),
          icon: Icons.description_outlined,
          isFile: true,
        ),
        const SizedBox(height: 8),
        _buildStorageCard(
          p: p,
          title: 'Master ${AppConfig.NAME} Storage Folder',
          subtitle:
              'Contains settings.json, state.json, prefs.json and the log',
          path: AppStore.dir,
          icon: AppIcons.folder,
        ),
      ],
    );
  }

  Widget _buildStorageCard({
    required Pal p,
    required String title,
    required String subtitle,
    required String path,
    required IconData icon,
    bool isFile = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: p.accent),
              const SizedBox(width: 8),
              T(title, size: 12.5, weight: FontWeight.w600),
              const Spacer(),
              IconBtn(
                icon: AppIcons.copy,
                tooltip: 'Copy path',
                size: 24,
                iconSize: 12,
                onClick: () {
                  Platform.copy(path);
                  widget.state.showToast('Copied path to clipboard');
                },
              ),
              const SizedBox(width: 4),
              Btn(
                label: Platform.revealLabel,
                icon: AppIcons.folder,
                height: 26,
                fontSize: 11,
                onClick: () => Platform.reveal(path),
              ),
            ],
          ),
          const SizedBox(height: 4),
          T(subtitle, size: 11, color: p.muted),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: p.panel,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: p.border.withOpacity(0.5), width: 0.5),
            ),
            child: MonoText(path, size: 10.5, color: p.muted),
          ),
        ],
      ),
    );
  }
}

class _AboutDialog extends StatelessWidget {
  const _AboutDialog({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ModalScaffold(
      title: 'About ${AppConfig.NAME}',
      width: 440,
      onClose: () => state.modal = null,
      actions: [
        Btn(
          label: 'Check for Updates…',
          onClick: () {
            state.modal = null;
            checkForUpdates(state);
          },
        ),
        Btn(label: 'Close', primary: true, onClick: () => state.modal = null),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/icons/app_icon.png',
            width: 64,
            height: 64,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(height: 12),
          T(AppConfig.NAME, size: 18, weight: FontWeight.w700),
          const SizedBox(height: 4),
          T(
            'Version ${AppMetadata.version} (${AppMetadata.buildNumber})',
            size: 12,
            color: p.muted,
          ),
          const SizedBox(height: 12),
          T(
            AppConfig.DESCRIPTION,
            size: 12.5,
            color: p.text,
            overflow: TextOverflow.visible,
          ),
          const SizedBox(height: 16),
          T(AppConfig.COPYRIGHT, size: 11, color: p.muted),
        ],
      ),
    );
  }
}

class _UpdateAvailableDialog extends StatelessWidget {
  const _UpdateAvailableDialog({required this.state, required this.version});

  final AppState state;
  final String version;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ModalScaffold(
      title: 'Update Available',
      width: 440,
      onClose: _dismiss,
      actions: [
        Btn(label: 'Later', onClick: _dismiss),
        Btn(
          label: 'Download $version',
          primary: true,
          onClick: () {
            state.modal = null;
            state.availableUpdate = null;
            unawaited(Platform.openUrl(AppConfig.RELEASES_URL));
          },
        ),
      ],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: p.accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(AppIcons.download, size: 24, color: p.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                T(
                  'Version $version is now available',
                  size: 14,
                  weight: FontWeight.w600,
                ),
                const SizedBox(height: 6),
                T(
                  'You are running ${AppMetadata.version}. '
                  'Visit the GitHub releases page to download the latest build.',
                  color: p.muted,
                  size: 12,
                  overflow: TextOverflow.visible,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _dismiss() {
    state.modal = null;
    unawaited(UpdateChecker.dismissVersion(version));
  }
}

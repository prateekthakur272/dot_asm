import 'package:flutter/material.dart';
import 'package:dot_asm/app/app_state.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/platform/platform.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';
import 'package:dot_asm/utils/app_config.dart';

/// Unified header: branding on the left, global actions on the right.
class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: p.panel,
        border: Border(bottom: BorderSide(color: p.border, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/icons/header_logo.png',
            width: 22,
            height: 22,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 8),
          const T(AppConfig.NAME, size: 14, weight: FontWeight.w700),
          const Spacer(),
          IconBtn(
            icon: AppIcons.settings,
            tooltip: 'Preferences (${Platform.isMac ? "⌘," : "Ctrl+,"})',
            size: 34,
            iconSize: 15,
            onClick: () => state.modal = const ModalSettings(),
          ),
          const SizedBox(width: 8),
          Btn(
            label: Platform.isMac ? '⌘K' : 'Ctrl+K',
            height: 34,
            onClick: () => state.paletteOpen = true,
          ),
        ],
      ),
    );
  }
}

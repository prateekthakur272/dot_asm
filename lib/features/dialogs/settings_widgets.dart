import 'package:flutter/material.dart';
import 'package:dot_asm/components/inputs.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/theme/theme.dart';

/// A heading with a one-line explanation, above a group of settings.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          T(title, size: 12.5, weight: FontWeight.w700),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            T(
              subtitle!,
              size: 11.5,
              color: p.muted,
              overflow: TextOverflow.visible,
            ),
          ],
          const SizedBox(height: 10),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One setting: a title, what it does, and its control on the right.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    required this.description,
    required this.trailing,
    this.onTap,
  });
  final String title;
  final String description;
  final Widget trailing;

  /// Makes the whole row clickable (used by toggles).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return HoverBuilder(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onTap: onTap,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: onTap != null && hovered ? p.hover : p.field,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  T(title, size: 12.5, weight: FontWeight.w600),
                  const SizedBox(height: 2),
                  T(
                    description,
                    size: 11,
                    color: p.muted,
                    overflow: TextOverflow.visible,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// A setting that is on or off.
class SettingToggle extends StatelessWidget {
  const SettingToggle({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SettingRow(
    title: title,
    description: description,
    onTap: () => onChanged(!value),
    trailing: IgnorePointer(
      child: AppCheckbox(value: value, onChanged: (_) {}),
    ),
  );
}

/// A setting with a few choices, shown as a segmented control.
class SettingChoice<V> extends StatelessWidget {
  const SettingChoice({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String title;
  final String description;
  final V value;

  /// The choices and their labels, in display order.
  final Map<V, String> options;
  final ValueChanged<V> onChanged;

  @override
  Widget build(BuildContext context) => SettingRow(
    title: title,
    description: description,
    trailing: Segmented<V>(
      value: value,
      options: options,
      onChanged: onChanged,
    ),
  );
}

/// A row of connected choices where one is selected.
class Segmented<V> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final V value;
  final Map<V, String> options;
  final ValueChanged<V> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in options.entries)
            HoverBuilder(
              cursor: SystemMouseCursors.click,
              onTap: () => onChanged(e.key),
              builder: (context, hovered) => AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: 26,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 11),
                decoration: BoxDecoration(
                  color: e.key == value
                      ? p.accent.withOpacity(0.16)
                      : (hovered ? p.hover : Colors.transparent),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: T(
                  e.value,
                  size: 11.5,
                  weight: e.key == value ? FontWeight.w700 : FontWeight.w500,
                  color: e.key == value ? p.accent : p.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

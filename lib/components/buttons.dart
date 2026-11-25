import 'package:flutter/material.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';

const double kControlHeight = 34.0;

class Btn extends StatelessWidget {
  const Btn({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.onClick,
    this.primary = false,
    this.outlined = false,
    this.danger = false,
    this.height = kControlHeight,
    this.fontSize,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onClick;
  final bool primary;
  final bool outlined;
  final bool danger;
  final double height;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final enabled = onClick != null;

    return HoverBuilder(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onTap: onClick,
      builder: (context, hovered) {
        Color bg;
        Color fg;
        Border? border;

        if (primary) {
          bg = danger
              ? (hovered ? p.err.withOpacity(0.85) : p.err)
              : (hovered ? p.accent.withOpacity(0.85) : p.accent);
          fg = Colors.white;
        } else if (outlined) {
          bg = hovered
              ? (danger ? p.err.withOpacity(0.12) : p.hover)
              : Colors.transparent;
          fg = danger ? p.err : p.text;
          border = Border.all(
            color: hovered
                ? (danger ? p.err : p.accent.withOpacity(0.55))
                : p.border,
            width: 1,
          );
        } else {
          bg = hovered ? p.hover : p.field;
          fg = danger ? p.err : p.text;
          border = Border.all(color: p.border, width: 1);
        }

        if (!enabled) {
          bg = bg.withOpacity(0.5);
          fg = fg.withOpacity(0.5);
        }

        final effectiveFontSize =
            fontSize ?? (height <= 24 ? 11.5 : (height <= 28 ? 12.0 : 12.5));

        return Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: border,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 6),
              ] else if (icon != null) ...[
                Icon(icon, size: height <= 24 ? 13 : 14, color: fg),
                const SizedBox(width: 6),
              ],
              T(
                label,
                size: effectiveFontSize,
                weight: FontWeight.w500,
                color: fg,
              ),
            ],
          ),
        );
      },
    );
  }
}

class IconBtn extends StatelessWidget {
  const IconBtn({
    super.key,
    this.icon,
    this.child,
    this.onClick,
    this.tooltip,
    this.size = 28.0,
    this.iconSize = 15.0,
    this.color,
    this.active = false,
  }) : assert(
         icon != null || child != null,
         'Either icon or child must be provided',
       );

  final IconData? icon;
  final Widget? child;
  final VoidCallback? onClick;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final enabled = onClick != null;

    Widget btn = HoverBuilder(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onTap: onClick,
      builder: (context, hovered) {
        final c = color ?? (active ? p.accent : (hovered ? p.text : p.muted));
        final bg = active
            ? p.accent.withOpacity(0.12)
            : (hovered
                  ? (p.dark ? const Color(0xFF353942) : const Color(0xFFD6D9DE))
                  : Colors.transparent);

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child:
                child ??
                (icon == AppIcons.github
                    ? GitHubIcon(size: iconSize, color: c)
                    : Icon(icon, size: iconSize, color: c)),
          ),
        );
      },
    );

    if (tooltip != null) {
      btn = Tooltip(message: tooltip!, child: btn);
    }

    return btn;
  }
}

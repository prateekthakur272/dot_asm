import 'package:flutter/material.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/theme/theme.dart';

/// A titled card that groups related settings.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    // A flat panel: square, filled with the panel colour (white in the light theme), with hairlines top and bottom.
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: BoxDecoration(
        color: p.panel,
        border: Border(bottom: BorderSide(color: p.border.withOpacity(0.7))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(icon, size: 17, color: p.muted),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    T(title, size: 14, weight: FontWeight.w700),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      T(
                        subtitle!,
                        size: 11,
                        color: p.muted,
                        overflow: TextOverflow.visible,
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// A small caption above a form control.
class Labeled extends StatelessWidget {
  const Labeled(this.label, this.child, {super.key, this.hint});
  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        T(label, size: 11, weight: FontWeight.w600, color: p.muted),
        const SizedBox(height: 5),
        child,
        if (hint != null) ...[
          const SizedBox(height: 4),
          T(
            hint!,
            size: 10.5,
            color: p.muted.withOpacity(0.85),
            overflow: TextOverflow.visible,
          ),
        ],
      ],
    );
  }
}

/// Lays out [children] in equal-width columns that wrap onto more rows when the space is narrow.
class FormGrid extends StatelessWidget {
  const FormGrid({
    super.key,
    required this.children,
    this.minColumnWidth = 220,
  });
  final List<Widget> children;
  final double minColumnWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / minColumnWidth).floor().clamp(1, 4);
        final w = (c.maxWidth - (cols - 1) * 12) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        );
      },
    );
  }
}

/// Compact text-style button used in dense rows.
class MiniAction extends StatelessWidget {
  const MiniAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              icon,
              size: 15,
              color: onTap == null
                  ? p.muted.withOpacity(0.4)
                  : (danger ? p.err : p.muted),
            ),
          ),
        ),
      ),
    );
  }
}

/// Parses `a=1, b=0x2` into a map; returns null when the text is malformed.
Map<String, int>? parseAssignments(String text) {
  final out = <String, int>{};
  for (final part in text.split(',')) {
    final t = part.trim();
    if (t.isEmpty) continue;
    final kv = t.split('=');
    if (kv.length != 2) return null;
    final v = kv[1].trim();
    final n = v.startsWith('0x') || v.startsWith('0X')
        ? int.tryParse(v.substring(2), radix: 16)
        : int.tryParse(v);
    if (n == null || kv[0].trim().isEmpty) return null;
    out[kv[0].trim()] = n;
  }
  return out;
}

/// Stores a typed number as an int when it is one, otherwise keeps the text so validation can report it.
Object numberOrText(String t) {
  final s = t.trim();
  return int.tryParse(s) ?? s;
}

String formatAssignments(Object? v, {bool hex = false}) {
  if (v is! Map) return '';
  return v.entries
      .map((e) {
        final val = e.value;
        return '${e.key}=${val is int && hex ? '0x${val.toRadixString(16)}' : val}';
      })
      .join(', ');
}

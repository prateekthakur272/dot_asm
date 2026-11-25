import 'package:flutter/material.dart';
import 'package:dot_asm/theme/theme.dart';

/// The one look of a selected list row: a soft tinted background with an accent bar on the left edge. Hovering a row
/// that is not selected tints it lighter. Use it for navigation lists, project lists, pickers and menus.
class SelectableRow extends StatelessWidget {
  const SelectableRow({
    super.key,
    required this.selected,
    required this.child,
    this.hovered = false,
    this.height,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
    this.margin = EdgeInsets.zero,
    this.radius = 8,
  });

  final bool selected;
  final bool hovered;
  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      height: height,
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: selected
            ? p.accent.withOpacity(0.1)
            : (hovered ? p.hover : Colors.transparent),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Padding(
              padding: padding,
              child: height == null
                  ? child
                  : Align(alignment: Alignment.centerLeft, child: child),
            ),
          ),
          Positioned(
            left: 0,
            top: 8,
            bottom: 8,
            width: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? p.accent : Colors.transparent,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

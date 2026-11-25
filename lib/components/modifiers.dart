import 'package:flutter/material.dart';

class ClickableNoRipple extends StatelessWidget {
  const ClickableNoRipple({super.key, this.onClick, required this.child});

  final VoidCallback? onClick;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onClick ?? () {},
    child: child,
  );
}

class HoverBuilder extends StatefulWidget {
  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.basic,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.opaque = true,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onSecondaryTap;
  final bool opaque;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    Widget w = MouseRegion(
      cursor: widget.cursor,
      opaque: widget.opaque,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );

    if (widget.onTap != null ||
        widget.onDoubleTap != null ||
        widget.onSecondaryTap != null) {
      w = GestureDetector(
        behavior: widget.opaque
            ? HitTestBehavior.opaque
            : HitTestBehavior.translucent,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTap: widget.onSecondaryTap,
        child: w,
      );
    }
    return w;
  }
}

class DrawBottomBorder extends StatelessWidget {
  const DrawBottomBorder({
    super.key,
    required this.color,
    required this.child,
    this.width = 1.0,
  });

  final Color color;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: color, width: width),
        ),
      ),
      child: child,
    );
  }
}

class DrawRightBorder extends StatelessWidget {
  const DrawRightBorder({
    super.key,
    required this.color,
    required this.child,
    this.width = 1.0,
  });

  final Color color;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: color, width: width),
        ),
      ),
      child: child,
    );
  }
}

class DrawTopBorder extends StatelessWidget {
  const DrawTopBorder({
    super.key,
    required this.color,
    required this.child,
    this.width = 1.0,
  });

  final Color color;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: color, width: width),
        ),
      ),
      child: child,
    );
  }
}

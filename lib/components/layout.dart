import 'package:flutter/material.dart';
import 'package:dot_asm/components/buttons.dart';
import 'package:dot_asm/components/drag_devices.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';

/// Two-pane horizontal layout with a draggable divider.
class SplitPane extends StatelessWidget {
  const SplitPane({
    super.key,
    required this.fraction,
    required this.onFraction,
    required this.first,
    required this.second,
    this.minFraction = 0.15,
    this.maxFraction = 0.40,
    this.minWidth = 220.0,
    this.dividerWidth = 4.0,
  });

  final double fraction;
  final ValueChanged<double> onFraction;
  final Widget first;
  final Widget second;
  final double minFraction;
  final double maxFraction;
  final double minWidth;
  final double dividerWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth.clamp(1.0, double.infinity);
        final rawWidth = totalWidth * fraction;
        final maxW = (totalWidth * maxFraction).clamp(minWidth, totalWidth);
        final firstWidth = rawWidth.clamp(minWidth, maxW);

        void onDrag(double delta) {
          final next = (firstWidth + delta) / totalWidth;
          onFraction(next.clamp(minFraction, maxFraction));
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: firstWidth, child: first),
            DragBar(width: dividerWidth, onDrag: onDrag),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

/// A vertical bar between two panes that is dragged sideways to resize them. A thin line at rest; on hover and while
/// dragging it thickens and takes the accent colour, so it is clear that it can be grabbed.
class DragBar extends StatefulWidget {
  const DragBar({super.key, required this.onDrag, this.width = 5});

  /// Called with the horizontal movement of every drag update.
  final ValueChanged<double> onDrag;
  final double width;

  @override
  State<DragBar> createState() => _DragBarState();
}

class _DragBarState extends State<DragBar> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final active = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Critical desktop rule: exclude trackpad so two-finger scroll does not resize dividers
        supportedDevices: kDragDevices,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        child: SizedBox(
          width: widget.width,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: active ? 3 : 1,
              decoration: BoxDecoration(
                color: active
                    ? p.accent.withOpacity(_dragging ? 0.9 : 0.6)
                    : p.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal dialog frame. Shrink-wraps its content; the body scrolls when it would exceed the window.
class ModalScaffold extends StatelessWidget {
  const ModalScaffold({
    super.key,
    required this.title,
    required this.child,
    required this.onClose,
    this.actions = const [],
    this.width = 540,
    this.maxHeight,
  });

  final String title;
  final Widget child;
  final VoidCallback onClose;
  final List<Widget> actions;
  final double width;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxScreenHeight = constraints.maxHeight;
        // Total chrome: margins (24 * 2 = 48) + header (~48) + padding (16 * 2 = 32) + footer if present (~56) + borders (2)
        final chromeHeight = 48 + 48 + 32 + (actions.isNotEmpty ? 56 : 0) + 2;
        final maxBodyHeight = (maxScreenHeight - chromeHeight).clamp(
          80.0,
          maxHeight != null
              ? (maxHeight! - chromeHeight + 48)
              : double.infinity,
        );

        return Center(
          child: ClickableNoRipple(
            onClick: () {},
            child: Container(
              width: width,
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: p.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.border, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DrawBottomBorder(
                    color: p.border,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: T(title, size: 14, weight: FontWeight.w600),
                          ),
                          IconBtn(
                            icon: AppIcons.close,
                            onClick: onClose,
                            size: 24,
                            iconSize: 13,
                          ),
                        ],
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxBodyHeight),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: child,
                    ),
                  ),
                  if (actions.isNotEmpty)
                    DrawTopBorder(
                      color: p.border,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          spacing: 8,
                          children: actions,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

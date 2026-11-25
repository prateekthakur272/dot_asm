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
    final p = context.pal;
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
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Critical desktop rule: exclude trackpad so two-finger scroll does not resize dividers
                supportedDevices: kDragDevices,
                onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
                child: Container(
                  width: dividerWidth,
                  color: Colors.transparent,
                  child: Center(child: Container(width: 1, color: p.border)),
                ),
              ),
            ),
            Expanded(child: second),
          ],
        );
      },
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

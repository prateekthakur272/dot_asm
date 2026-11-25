import 'package:flutter/material.dart';
import 'package:dot_asm/components/modifiers.dart';
import 'package:dot_asm/theme/icons.dart';
import 'package:dot_asm/theme/theme.dart';

class WindowChrome {
  const WindowChrome({
    this.leftInset = 0,
    this.controls,
    this.menuBar,
    this.dragArea = _identity,
    this.onDoubleClick,
  });

  final double leftInset;
  final Widget? controls;
  final Widget? menuBar;
  final Widget Function(Widget content) dragArea;
  final VoidCallback? onDoubleClick;

  static Widget _identity(Widget w) => w;

  factory WindowChrome.desktop({
    required bool isMac,
    required bool maximized,
    required VoidCallback onMinimize,
    required VoidCallback onToggleMaximize,
    required VoidCallback onClose,
    required VoidCallback onDragStart,
    Widget? menuBar,
    VoidCallback? onContextMenu,
  }) => WindowChrome(
    leftInset: isMac ? 76 : 8,
    controls: isMac
        ? null
        : WindowControls(
            maximized: maximized,
            onMinimize: onMinimize,
            onToggleMaximize: onToggleMaximize,
            onClose: onClose,
          ),
    menuBar: isMac ? null : menuBar,
    dragArea: (content) => TitleBarDrag(
      onDragStart: onDragStart,
      onContextMenu: onContextMenu,
      child: content,
    ),
    onDoubleClick: onToggleMaximize,
  );
}

class TitleBarDrag extends StatelessWidget {
  const TitleBarDrag({
    super.key,
    required this.onDragStart,
    this.onContextMenu,
    required this.child,
  });

  final VoidCallback onDragStart;
  final VoidCallback? onContextMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => onDragStart(),
      onSecondaryTap: onContextMenu,
      child: child,
    );
  }
}

class WindowControls extends StatelessWidget {
  const WindowControls({
    super.key,
    required this.maximized,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
  });

  final bool maximized;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          icon: AppIcons.windowMinimize,
          danger: false,
          onClick: onMinimize,
        ),
        _CaptionButton(
          icon: maximized ? AppIcons.windowRestore : AppIcons.windowMaximize,
          danger: false,
          onClick: onToggleMaximize,
        ),
        _CaptionButton(
          icon: AppIcons.windowClose,
          danger: true,
          onClick: onClose,
        ),
      ],
    );
  }
}

class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.icon,
    required this.danger,
    required this.onClick,
  });

  final IconData icon;
  final bool danger;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return HoverBuilder(
      cursor: SystemMouseCursors.basic,
      onTap: onClick,
      builder: (context, hovered) {
        Color bg;
        Color fg;

        if (danger) {
          bg = hovered ? p.err : Colors.transparent;
          fg = hovered ? Colors.white : p.muted;
        } else {
          bg = hovered ? p.hover : Colors.transparent;
          fg = hovered ? p.text : p.muted;
        }

        return Container(
          width: 44,
          height: 28,
          color: bg,
          child: Center(child: Icon(icon, size: 13, color: fg)),
        );
      },
    );
  }
}

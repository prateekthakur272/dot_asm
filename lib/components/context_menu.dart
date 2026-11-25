import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/theme/theme.dart';

class ContextMenuItem {
  const ContextMenuItem({
    required this.label,
    this.icon,
    this.leading,
    this.shortcut,
    this.danger = false,
    this.action,
    this.submenu,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final String? shortcut;
  final bool danger;
  final VoidCallback? action;
  final List<ContextMenuItem>? submenu;

  bool get isDivider => label.isEmpty;
  bool get hasSubmenu => submenu != null && submenu!.isNotEmpty;
}

class ContextMenu extends StatelessWidget {
  const ContextMenu({super.key, required this.items, required this.onDismiss});

  final List<ContextMenuItem> items;
  final VoidCallback onDismiss;

  static Future<void> show(
    BuildContext context,
    Offset position,
    List<ContextMenuItem> items,
  ) async {
    final nav = Navigator.of(context, rootNavigator: true);
    final action = await nav.push<VoidCallback>(
      _ContextMenuRoute(
        position: position,
        items: items,
        pal: context.pal,
        themes: InheritedTheme.capture(from: context, to: nav.context),
      ),
    );

    action?.call();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _ContextMenuLayout extends SingleChildLayoutDelegate {
  _ContextMenuLayout(this.position);
  final Offset position;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: 170,
        maxWidth: 280,
        maxHeight: constraints.maxHeight - 24,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = position.dx;
    if (x + childSize.width > size.width - 10) {
      x = (size.width - childSize.width - 10).clamp(10.0, double.infinity);
    }
    if (x < 10) x = 10;

    var y = position.dy;
    if (y + childSize.height > size.height - 10) {
      final above = position.dy - childSize.height;
      y = above >= 10
          ? above
          : (size.height - childSize.height - 10).clamp(10.0, double.infinity);
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_ContextMenuLayout old) => old.position != position;
}

class _ContextMenuRoute extends PopupRoute<VoidCallback> {
  _ContextMenuRoute({
    required this.position,
    required this.items,
    required this.pal,
    required this.themes,
  });

  final Offset position;
  final List<ContextMenuItem> items;
  final Pal pal;
  final CapturedThemes themes;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 90);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return themes.wrap(
      PalScope(
        pal: pal,
        child: FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: _ContextMenuOverlay(
            position: position,
            items: items,
            pal: pal,
          ),
        ),
      ),
    );
  }
}

class _ContextMenuOverlay extends StatefulWidget {
  const _ContextMenuOverlay({
    required this.position,
    required this.items,
    required this.pal,
  });

  final Offset position;
  final List<ContextMenuItem> items;
  final Pal pal;

  @override
  State<_ContextMenuOverlay> createState() => _ContextMenuOverlayState();
}

class _ContextMenuOverlayState extends State<_ContextMenuOverlay> {
  List<ContextMenuItem>? _activeSubmenu;
  Rect? _submenuAnchor;
  Timer? _closeTimer;

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  void _onSubmenuHover(List<ContextMenuItem> submenu, Rect anchor) {
    _closeTimer?.cancel();
    setState(() {
      _activeSubmenu = submenu;
      _submenuAnchor = anchor;
    });
  }

  void _onHoverNonSubmenu() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 140), () {
      if (mounted) {
        setState(() {
          _activeSubmenu = null;
          _submenuAnchor = null;
        });
      }
    });
  }

  void _onSubmenuPanelEnter() {
    _closeTimer?.cancel();
  }

  Widget _buildMenuPanel({
    required BuildContext context,
    required List<ContextMenuItem> items,
    required Pal pal,
    required bool isSubmenu,
    void Function(List<ContextMenuItem> submenu, Rect rect)? onSubmenuHover,
    VoidCallback? onHoverNonSubmenu,
  }) {
    final p = pal;
    final anyHasIcon = items.any((i) => i.icon != null || i.leading != null);

    return Container(
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border.withOpacity(0.9), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.38),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              if (item.isDivider)
                Container(
                  margin: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 4,
                  ),
                  height: 1,
                  color: p.border.withOpacity(0.6),
                )
              else
                _ContextRow(
                  item: item,
                  showIconGutter: anyHasIcon,
                  onClick: () {
                    if (!item.hasSubmenu) {
                      Navigator.of(context).pop(item.action);
                    }
                  },
                  onSubmenuHover: onSubmenuHover != null && item.hasSubmenu
                      ? (rect) => onSubmenuHover(item.submenu!, rect)
                      : null,
                  onHoverNonSubmenu: onHoverNonSubmenu,
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    Widget? submenuWidget;
    if (_activeSubmenu != null && _submenuAnchor != null) {
      final anchor = _submenuAnchor!;
      const submenuMinWidth = 160.0;

      double left = anchor.right - 4;
      if (left + submenuMinWidth > screenSize.width - 10) {
        left = (anchor.left - submenuMinWidth + 4).clamp(10.0, double.infinity);
      }

      double top = anchor.top - 4;
      final approxHeight = _activeSubmenu!.length * 30.0 + 12.0;
      if (top + approxHeight > screenSize.height - 10) {
        top = (screenSize.height - approxHeight - 10).clamp(
          10.0,
          double.infinity,
        );
      }
      if (top < 10) top = 10;

      submenuWidget = Positioned(
        left: left,
        top: top,
        child: MouseRegion(
          onEnter: (_) => _onSubmenuPanelEnter(),
          child: _buildMenuPanel(
            context: context,
            items: _activeSubmenu!,
            pal: widget.pal,
            isSubmenu: true,
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomSingleChildLayout(
          delegate: _ContextMenuLayout(widget.position),
          child: _buildMenuPanel(
            context: context,
            items: widget.items,
            pal: widget.pal,
            isSubmenu: false,
            onSubmenuHover: _onSubmenuHover,
            onHoverNonSubmenu: _onHoverNonSubmenu,
          ),
        ),
        ?submenuWidget,
      ],
    );
  }
}

class _ContextRow extends StatefulWidget {
  const _ContextRow({
    required this.item,
    required this.showIconGutter,
    required this.onClick,
    this.onSubmenuHover,
    this.onHoverNonSubmenu,
  });

  final ContextMenuItem item;
  final bool showIconGutter;
  final VoidCallback onClick;
  final void Function(Rect rect)? onSubmenuHover;
  final VoidCallback? onHoverNonSubmenu;

  @override
  State<_ContextRow> createState() => _ContextRowState();
}

class _ContextRowState extends State<_ContextRow> {
  bool _hovered = false;

  void _reportRect() {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final pos = box.localToGlobal(Offset.zero);
      widget.onSubmenuHover?.call(
        Rect.fromLTWH(pos.dx, pos.dy, box.size.width, box.size.height),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final p = context.pal;
    final isDanger = item.danger;

    final bg = _hovered
        ? (isDanger ? p.err.withOpacity(0.15) : p.hover)
        : Colors.transparent;
    final textColor = isDanger
        ? p.err
        : (item.hasSubmenu && _hovered ? p.text : p.text);
    final iconColor = isDanger ? p.err : (_hovered ? p.accent : p.muted);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
        if (item.hasSubmenu) {
          _reportRect();
        } else {
          widget.onHoverNonSubmenu?.call();
        }
      },
      onExit: (_) {
        setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (item.hasSubmenu) {
            _reportRect();
          }
          widget.onClick();
        },
        child: Container(
          height: 28,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showIconGutter) ...[
                SizedBox(
                  width: 18,
                  child:
                      item.leading ??
                      (item.icon != null
                          ? Icon(item.icon, size: 13.5, color: iconColor)
                          : null),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: T(
                  item.label,
                  size: 12.5,
                  weight: FontWeight.w400,
                  color: textColor,
                ),
              ),
              if (item.shortcut != null) ...[
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: p.field,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: MonoText(item.shortcut!, size: 10, color: p.muted),
                ),
              ],
              if (item.hasSubmenu) ...[
                const SizedBox(width: 10),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: _hovered ? p.text : p.muted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

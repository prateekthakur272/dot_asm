import 'package:flutter/material.dart';

/// Semantic colour palette for DotAsm desktop themes.
class Pal {
  const Pal({
    required this.dark,
    required this.bg,
    required this.panel,
    required this.sidebar,
    required this.field,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.ok,
    required this.err,
    required this.warn,
    required this.hover,
    required this.selected,
  });

  final bool dark;
  final Color bg;
  final Color panel;
  final Color sidebar;
  final Color field;
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;
  final Color ok;
  final Color err;
  final Color warn;
  final Color hover;
  final Color selected;

  static Pal of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<PalScope>();
    return s?.pal ?? DarkPal;
  }
}

extension PalContext on BuildContext {
  Pal get pal => Pal.of(this);
}

const DarkPal = Pal(
  dark: true,
  bg: Color(0xFF131417),
  panel: Color(0xFF1C1E22),
  sidebar: Color(0xFF1C1E22),
  field: Color(0xFF16181B),
  border: Color(0xFF2C2F36),
  text: Color(0xFFE6E8EB),
  muted: Color(0xFF8F96A3),
  accent: Color(0xFF6C5CE7),
  ok: Color(0xFF00B894),
  err: Color(0xFFFF7675),
  warn: Color(0xFFFDCB6E),
  hover: Color(0xFF262930),
  selected: Color(0xFF2D313A),
);

const LightPal = Pal(
  dark: false,
  bg: Color(0xFFF4F6F9),
  panel: Color(0xFFFFFFFF),
  sidebar: Color(0xFFFFFFFF),
  field: Color(0xFFFFFFFF),
  border: Color(0xFFE2E5EB),
  text: Color(0xFF1E2125),
  muted: Color(0xFF6E7683),
  accent: Color(0xFF5A4BD8),
  ok: Color(0xFF00A381),
  err: Color(0xFFE05655),
  warn: Color(0xFFE5A638),
  hover: Color(0xFFEEF1F6),
  selected: Color(0xFFE4E8F0),
);

/// InheritedTheme so popups, tooltips, dialogs inherit the active palette.
class PalScope extends InheritedTheme {
  const PalScope({super.key, required this.pal, required super.child});
  final Pal pal;

  @override
  bool updateShouldNotify(PalScope oldWidget) => pal != oldWidget.pal;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      PalScope(pal: pal, child: child);
}

class DotAsmTheme {
  DotAsmTheme._();

  static Pal palFor(bool dark) => dark ? DarkPal : LightPal;

  static ThemeData makeTheme(bool dark) {
    final p = palFor(dark);
    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: p.bg,
      colorScheme: dark
          ? ColorScheme.dark(
              primary: p.accent,
              surface: p.panel,
              outline: p.border,
            )
          : ColorScheme.light(
              primary: p.accent,
              surface: p.panel,
              outline: p.border,
            ),
      fontFamily:
          '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2A2D35) : const Color(0xFF2A2D35),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: p.border, width: 0.5),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

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
    required this.onAccent,
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

  /// Text and icon colour on top of [accent] (primary buttons).
  final Color onAccent;
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

/// Black and grey: near-black surfaces, neutral greys, a light-grey accent. Status colours stay muted but readable.
const DarkPal = Pal(
  dark: true,
  bg: Color(0xFF0A0A0A),
  panel: Color(0xFF121212),
  sidebar: Color(0xFF0F0F0F),
  field: Color(0xFF0D0D0D),
  border: Color(0xFF262626),
  text: Color(0xFFE8E8E8),
  muted: Color(0xFF8A8A8A),
  accent: Color(0xFFD4D4D4),
  onAccent: Color(0xFF0A0A0A),
  ok: Color(0xFF8FBF9F),
  err: Color(0xFFE07070),
  warn: Color(0xFFD4B26A),
  hover: Color(0xFF1C1C1C),
  selected: Color(0xFF242424),
);

const LightPal = Pal(
  dark: false,
  bg: Color(0xFFF2F2F2),
  panel: Color(0xFFFFFFFF),
  sidebar: Color(0xFFF8F8F8),
  field: Color(0xFFFFFFFF),
  border: Color(0xFFDCDCDC),
  text: Color(0xFF111111),
  muted: Color(0xFF6B6B6B),
  accent: Color(0xFF1F1F1F),
  onAccent: Color(0xFFFFFFFF),
  ok: Color(0xFF2E7D4F),
  err: Color(0xFFC0392B),
  warn: Color(0xFFA97C1F),
  hover: Color(0xFFEBEBEB),
  selected: Color(0xFFE0E0E0),
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
          color: dark ? const Color(0xFF262626) : const Color(0xFF1F1F1F),
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

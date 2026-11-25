import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:dot_asm/components/text.dart';
import 'package:dot_asm/theme/theme.dart';

/// Flat, abstract 2D illustrations for empty states. Drawn in code with the palette, so they follow the theme.
enum EmptyArt {
  /// Stacked cards with a plus: no projects yet.
  projects,

  /// A chip with pins: processors.
  processor,

  /// A magnifier over scattered dots: nothing matches.
  search,

  /// A terminal window: program output.
  terminal,

  /// A timeline of steps: nothing has run yet.
  steps,

  /// Concentric rings with a check: all good.
  ok,

  /// Lines of code with one highlighted: nothing assembled.
  code,
}

/// An illustration with a title, an optional line of explanation and an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.art,
    required this.title,
    this.subtitle,
    this.action,
    this.artSize = 112,
  });
  final EmptyArt art;
  final String title;
  final String? subtitle;
  final Widget? action;
  final double artSize;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        EmptyArtView(art: art, size: artSize),
        const SizedBox(height: 12),
        T(
          title,
          size: 12.5,
          weight: FontWeight.w600,
          color: p.text,
          align: TextAlign.center,
          overflow: TextOverflow.visible,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          T(
            subtitle!,
            size: 11,
            color: p.muted,
            align: TextAlign.center,
            overflow: TextOverflow.visible,
          ),
        ],
        if (action != null) ...[const SizedBox(height: 14), action!],
      ],
    );
  }
}

class EmptyArtView extends StatelessWidget {
  const EmptyArtView({super.key, required this.art, this.size = 112});
  final EmptyArt art;

  /// Width in logical pixels; the height is 3/4 of it.
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      width: size,
      height: size * 0.75,
      child: CustomPaint(painter: _ArtPainter(art, p)),
    );
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.art, this.p);
  final EmptyArt art;
  final Pal p;

  // Everything is drawn in a 120 x 90 box and scaled to fit.
  static const _w = 120.0;
  static const _h = 90.0;

  Color get _line => p.muted.withOpacity(p.dark ? 0.55 : 0.6);
  Color get _faint => p.muted.withOpacity(0.28);
  Color get _fill => p.panel;
  Color get _tint => p.accent.withOpacity(p.dark ? 0.16 : 0.10);

  Paint _stroke(Color c, [double w = 1.6]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = c
    ..isAntiAlias = true;

  Paint _paint(Color c) => Paint()
    ..style = PaintingStyle.fill
    ..color = c
    ..isAntiAlias = true;

  RRect _r(double l, double t, double w, double h, [double r = 6]) =>
      RRect.fromRectAndRadius(Rect.fromLTWH(l, t, w, h), Radius.circular(r));

  void _bar(
    Canvas c,
    double x,
    double y,
    double w,
    Color color, [
    double h = 3.2,
  ]) => c.drawRRect(_r(x, y, w, h, h / 2), _paint(color));

  void _dot(Canvas c, double x, double y, double r, Color color) =>
      c.drawCircle(Offset(x, y), r, _paint(color));

  /// A soft backdrop: a faint dotted grid that fades toward the edges.
  void _backdrop(Canvas c) {
    for (var gy = 0; gy < 6; gy++) {
      for (var gx = 0; gx < 8; gx++) {
        final x = 8.0 + gx * 15;
        final y = 8.0 + gy * 15;
        final d =
            math.sqrt(math.pow(x - _w / 2, 2) + math.pow(y - _h / 2, 2)) / 70;
        _dot(
          c,
          x,
          y,
          1.1,
          p.muted.withOpacity((0.30 * (1 - d.clamp(0, 1))).clamp(0.0, 0.3)),
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final s = math.min(size.width / _w, size.height / _h);
    canvas.translate((size.width - _w * s) / 2, (size.height - _h * s) / 2);
    canvas.scale(s);
    _backdrop(canvas);
    switch (art) {
      case EmptyArt.projects:
        _projects(canvas);
      case EmptyArt.processor:
        _processor(canvas);
      case EmptyArt.search:
        _search(canvas);
      case EmptyArt.terminal:
        _terminal(canvas);
      case EmptyArt.steps:
        _steps(canvas);
      case EmptyArt.ok:
        _ok(canvas);
      case EmptyArt.code:
        _code(canvas);
    }
    canvas.restore();
  }

  void _projects(Canvas c) {
    // Three cards fanned back to front.
    c.drawRRect(_r(26, 14, 64, 48), _stroke(_faint));
    c.drawRRect(_r(32, 20, 64, 48), _stroke(_line.withOpacity(0.5)));
    final front = _r(38, 26, 64, 48);
    c.drawRRect(front, _paint(_fill));
    c.drawRRect(front, _stroke(_line));
    c.drawRRect(_r(38, 26, 64, 12, 6), _paint(_tint));
    _dot(c, 46, 32, 2, _line);
    _dot(c, 53, 32, 2, _faint);
    _bar(c, 46, 47, 40, _faint);
    _bar(c, 46, 55, 28, _faint);
    _bar(c, 46, 63, 34, _faint);
    // Plus badge.
    _dot(c, 98, 70, 11, _paint(p.accent).color);
    final plus = _stroke(p.onAccent, 2);
    c.drawLine(const Offset(98, 65), const Offset(98, 75), plus);
    c.drawLine(const Offset(93, 70), const Offset(103, 70), plus);
  }

  void _processor(Canvas c) {
    const cx = 60.0, cy = 45.0;
    // Traces.
    final trace = _stroke(_faint, 1.3);
    for (final t in [
      [const Offset(30, 28), const Offset(18, 28), const Offset(18, 16)],
      [const Offset(90, 28), const Offset(102, 28), const Offset(102, 16)],
      [const Offset(30, 62), const Offset(18, 62), const Offset(18, 74)],
      [const Offset(90, 62), const Offset(102, 62), const Offset(102, 74)],
    ]) {
      final path = Path()..moveTo(t[0].dx, t[0].dy);
      for (final o in t.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      c.drawPath(path, trace);
      _dot(c, t.last.dx, t.last.dy, 2.4, _faint);
    }
    // Pins.
    final pin = _paint(_line);
    for (var i = 0; i < 4; i++) {
      final o = -15.0 + i * 10;
      c.drawRRect(_r(cx + o - 1.6, cy - 36, 3.2, 9, 1.6), pin);
      c.drawRRect(_r(cx + o - 1.6, cy + 27, 3.2, 9, 1.6), pin);
      c.drawRRect(_r(cx - 36, cy + o - 1.6, 9, 3.2, 1.6), pin);
      c.drawRRect(_r(cx + 27, cy + o - 1.6, 9, 3.2, 1.6), pin);
    }
    final body = _r(cx - 28, cy - 28, 56, 56, 9);
    c.drawRRect(body, _paint(_fill));
    c.drawRRect(body, _stroke(_line));
    c.drawRRect(_r(cx - 17, cy - 17, 34, 34, 6), _paint(_tint));
    c.drawRRect(
      _r(cx - 17, cy - 17, 34, 34, 6),
      _stroke(p.accent.withOpacity(0.7), 1.4),
    );
    _dot(c, cx, cy, 4, p.accent);
    _dot(c, cx - 22, cy - 22, 1.6, _line);
  }

  void _search(Canvas c) {
    for (final o in const [
      Offset(22, 62),
      Offset(96, 22),
      Offset(100, 66),
      Offset(24, 26),
    ]) {
      _dot(c, o.dx, o.dy, 2.4, _faint);
    }
    const lens = Offset(55, 42);
    c.drawCircle(lens, 21, _paint(_fill));
    c.drawCircle(lens, 21, _stroke(p.accent.withOpacity(0.85), 2.4));
    c.drawCircle(lens, 14, _stroke(_faint, 1.2));
    // Handle.
    c.drawLine(
      const Offset(71, 58),
      const Offset(88, 75),
      _stroke(p.accent.withOpacity(0.85), 4.5),
    );
    // A small "nothing" mark inside: dashed line.
    for (var i = 0; i < 3; i++) {
      _bar(c, 46 + i * 7.0, 42, 4, _line, 2.6);
    }
  }

  void _terminal(Canvas c) {
    final win = _r(16, 16, 88, 58, 8);
    c.drawRRect(win, _paint(_fill));
    c.drawRRect(win, _stroke(_line));
    c.drawRRect(_r(16, 16, 88, 14, 8), _paint(_tint));
    for (var i = 0; i < 3; i++) {
      _dot(c, 25 + i * 7.0, 23, 2, i == 0 ? p.accent.withOpacity(0.8) : _faint);
    }
    // Prompt.
    final chevron = Path()
      ..moveTo(27, 40)
      ..lineTo(35, 46)
      ..lineTo(27, 52);
    c.drawPath(chevron, _stroke(p.accent, 2.2));
    _bar(c, 41, 44.5, 22, _faint, 3.4);
    _bar(c, 27, 59, 46, _faint.withOpacity(0.18));
    // Cursor.
    c.drawRRect(_r(67, 42, 6, 8, 1.5), _paint(p.accent.withOpacity(0.8)));
  }

  void _steps(Canvas c) {
    const y = 34.0;
    const xs = [22.0, 46.0, 70.0, 94.0];
    c.drawLine(const Offset(22, y), const Offset(94, y), _stroke(_faint, 2));
    c.drawLine(
      const Offset(22, y),
      const Offset(46, y),
      _stroke(p.accent.withOpacity(0.8), 2),
    );
    for (var i = 0; i < xs.length; i++) {
      c.drawCircle(Offset(xs[i], y), i == 0 ? 8 : 6, _paint(_fill));
      c.drawCircle(
        Offset(xs[i], y),
        i == 0 ? 8 : 6,
        _stroke(i == 0 ? p.accent : _line, 1.8),
      );
    }
    // "Play" triangle on the current step.
    final tri = Path()
      ..moveTo(20, y - 3.6)
      ..lineTo(26, y)
      ..lineTo(20, y + 3.6)
      ..close();
    c.drawPath(tri, _paint(p.accent));
    // Register-like rows below.
    for (var i = 0; i < 3; i++) {
      final yy = 52.0 + i * 9;
      c.drawRRect(
        _r(22, yy, 72, 6, 3),
        _paint(p.accent.withOpacity(i == 0 ? 0.18 : 0.08)),
      );
      _bar(c, 26, yy + 1.4, 14.0 + (i * 11) % 22, _faint, 3.2);
    }
  }

  void _ok(Canvas c) {
    const cx = 60.0, cy = 45.0;
    c.drawCircle(
      const Offset(cx, cy),
      34,
      _stroke(_faint.withOpacity(0.2), 1.2),
    );
    c.drawCircle(const Offset(cx, cy), 27, _stroke(_faint, 1.4));
    c.drawCircle(const Offset(cx, cy), 20, _paint(_tint));
    c.drawCircle(
      const Offset(cx, cy),
      20,
      _stroke(p.accent.withOpacity(0.75), 2),
    );
    final check = Path()
      ..moveTo(50, 46)
      ..lineTo(57, 53)
      ..lineTo(71, 37);
    c.drawPath(check, _stroke(p.accent, 3.4));
    for (final a in [0.4, 1.7, 3.0, 4.4, 5.5]) {
      _dot(c, cx + 34 * math.cos(a), cy + 34 * math.sin(a), 1.8, _line);
    }
  }

  void _code(Canvas c) {
    final panel = _r(20, 14, 80, 62, 8);
    c.drawRRect(panel, _paint(_fill));
    c.drawRRect(panel, _stroke(_line));
    const lines = [30.0, 46.0, 24.0, 38.0, 18.0];
    for (var i = 0; i < lines.length; i++) {
      final y = 24.0 + i * 10;
      if (i == 2) {
        c.drawRRect(_r(24, y - 4, 72, 9, 3), _paint(_tint));
        _dot(c, 29, y + 0.5, 2.2, p.accent);
      }
      _bar(
        c,
        36,
        y - 1.2,
        lines[i] + 6,
        i == 2 ? p.accent.withOpacity(0.8) : _faint,
        3.2,
      );
      _bar(c, 24, y - 1.2, 6, _faint.withOpacity(0.18), 3.2);
    }
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.art != art || old.p != p;
}

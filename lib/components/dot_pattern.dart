import 'package:flutter/material.dart';
import 'package:dot_asm/theme/theme.dart';

class DotPatternBackground extends StatelessWidget {
  const DotPatternBackground({
    super.key,
    this.spacing = 18.0,
    this.dotRadius = 1.0,
    this.dotColor,
    this.opacityMultiplier = 1.0,
  });

  final double spacing;
  final double dotRadius;
  final Color? dotColor;
  final double opacityMultiplier;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final baseColor =
        dotColor ??
        (p.dark ? const Color(0xFFE2E8F0) : const Color(0xFF64748B));

    return ClipRect(
      child: CustomPaint(
        painter: _UniformDotGridPainter(
          dotColor: baseColor,
          spacing: spacing,
          dotRadius: dotRadius,
          isDark: p.dark,
          opacityMultiplier: opacityMultiplier,
        ),
      ),
    );
  }
}

class _UniformDotGridPainter extends CustomPainter {
  const _UniformDotGridPainter({
    required this.dotColor,
    required this.spacing,
    required this.dotRadius,
    required this.isDark,
    required this.opacityMultiplier,
  });

  final Color dotColor;
  final double spacing;
  final double dotRadius;
  final bool isDark;
  final double opacityMultiplier;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Strictly clip to bounds so dots never bleed into header, side panes or status bar
    canvas.clipRect(Offset.zero & size);

    // Completely uniform opacity across the entire canvas (no fading / gradient)
    final baseAlpha = isDark ? 0.08 : 0.12;
    final effectiveAlpha = (baseAlpha * opacityMultiplier).clamp(0.0, 1.0);

    final paint = Paint()
      ..isAntiAlias = true
      ..color = dotColor.withOpacity(effectiveAlpha);

    for (double y = spacing / 2; y <= size.height; y += spacing) {
      for (double x = spacing / 2; x <= size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _UniformDotGridPainter oldDelegate) {
    return oldDelegate.dotColor != dotColor ||
        oldDelegate.spacing != spacing ||
        oldDelegate.dotRadius != dotRadius ||
        oldDelegate.isDark != isDark ||
        oldDelegate.opacityMultiplier != opacityMultiplier;
  }
}

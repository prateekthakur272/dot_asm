import 'package:flutter/material.dart';
import 'package:dot_asm/theme/theme.dart';

/// Desktop typography helper.
class T extends StatelessWidget {
  const T(
    this.text, {
    super.key,
    this.size = 13,
    this.weight,
    this.color,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
    this.italic = false,
    this.align,
    this.softWrap,
  });

  final String text;
  final double size;
  final FontWeight? weight;
  final Color? color;
  final int? maxLines;
  final TextOverflow overflow;
  final bool italic;
  final TextAlign? align;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: align,
      softWrap: softWrap ?? (maxLines == 1 ? false : null),
      style: TextStyle(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w400,
        color: color ?? p.text,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        decoration: TextDecoration.none,
      ),
    );
  }
}

/// The monospaced font. A font list must be given as fallbacks: a comma separated string is read as one family name.
const String kMonoFamily = 'Menlo';
const List<String> kMonoFallback = [
  'SFMono-Regular',
  'Monaco',
  'Consolas',
  'Liberation Mono',
  'DejaVu Sans Mono',
  'Courier New',
  'monospace',
];

/// Monospaced text helper for paths, hashes, commands.
class MonoText extends StatelessWidget {
  const MonoText(
    this.text, {
    super.key,
    this.size = 12,
    this.color,
    this.weight,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.softWrap = false,
  });

  final String text;
  final double size;
  final Color? color;
  final FontWeight? weight;
  final int? maxLines;
  final TextOverflow overflow;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
      style: TextStyle(
        fontFamily: kMonoFamily,
        fontFamilyFallback: kMonoFallback,
        fontSize: size,
        fontWeight: weight ?? FontWeight.w400,
        color: color ?? p.text,
        decoration: TextDecoration.none,
      ),
    );
  }
}

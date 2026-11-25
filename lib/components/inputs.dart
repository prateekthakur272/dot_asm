import 'package:flutter/material.dart';
import 'package:dot_asm/components/text.dart' show kMonoFamily, kMonoFallback;
import 'package:dot_asm/theme/theme.dart';

/// Single-line framed text field used in dialogs and toolbars.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.height = 34,
    this.mono = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final double height;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final family = mono ? kMonoFamily : null;
    final fallback = mono ? kMonoFallback : null;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.border, width: 1),
      ),
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -2.0),
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            maxLines: 1,
            cursorHeight: 15,
            textAlignVertical: TextAlignVertical.center,
            style: TextStyle(
              color: p.text,
              fontSize: 12.5,
              fontFamily: family,
              fontFamilyFallback: fallback,
            ),
            decoration: InputDecoration.collapsed(
              hintText: hint,
              hintStyle: TextStyle(
                color: p.muted,
                fontSize: 12.5,
                fontFamily: family,
                fontFamilyFallback: fallback,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Framed dropdown with the same look as [AppTextField].
class AppDropdown<V> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.height = 34,
  });

  final V value;
  final List<DropdownMenuItem<V>> items;
  final ValueChanged<V?> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.border, width: 1),
      ),
      alignment: Alignment.centerLeft,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<V>(
          value: value,
          isDense: true,
          isExpanded: true,
          dropdownColor: p.panel,
          style: TextStyle(color: p.text, fontSize: 12.5),
          iconSize: 18,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// A text field bound to a value that lives elsewhere (a JSON draft). It keeps its own controller so typing is not
/// interrupted, and re-reads [value] when the field is not focused or when [revision] changes.
class BoundTextField extends StatefulWidget {
  const BoundTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint = '',
    this.mono = false,
    this.revision = 0,
    this.lines = 1,
    this.height = 34,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String hint;
  final bool mono;
  final int revision;
  final int lines;
  final double height;

  @override
  State<BoundTextField> createState() => _BoundTextFieldState();
}

class _BoundTextFieldState extends State<BoundTextField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(BoundTextField old) {
    super.didUpdateWidget(old);
    if ((old.revision != widget.revision || !_focus.hasFocus) &&
        _c.text != widget.value) {
      _c.text = widget.value;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final multi = widget.lines > 1;
    return Container(
      height: multi ? null : widget.height,
      constraints: multi
          ? BoxConstraints(minHeight: widget.lines * 18.0 + 16)
          : null,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: multi ? 8 : 0),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.border, width: 1),
      ),
      child: multi
          ? TextField(
              controller: _c,
              focusNode: _focus,
              onChanged: widget.onChanged,
              minLines: widget.lines,
              maxLines: null,
              style: TextStyle(
                color: p.text,
                fontSize: 12,
                height: 1.5,
                fontFamily: widget.mono ? kMonoFamily : null,
                fontFamilyFallback: widget.mono ? kMonoFallback : null,
              ),
              decoration: InputDecoration.collapsed(
                hintText: widget.hint,
                hintStyle: TextStyle(color: p.muted, fontSize: 12),
              ),
            )
          : Center(
              child: Transform.translate(
                offset: const Offset(0, -2.0),
                child: TextField(
                  controller: _c,
                  focusNode: _focus,
                  onChanged: widget.onChanged,
                  maxLines: 1,
                  cursorHeight: 15,
                  textAlignVertical: TextAlignVertical.center,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 12.5,
                    fontFamily: widget.mono ? kMonoFamily : null,
                    fontFamilyFallback: widget.mono ? kMonoFallback : null,
                  ),
                  decoration: InputDecoration.collapsed(
                    hintText: widget.hint,
                    hintStyle: TextStyle(
                      color: p.muted,
                      fontSize: 12.5,
                      fontFamily: widget.mono ? kMonoFamily : null,
                      fontFamilyFallback: widget.mono ? kMonoFallback : null,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// The app's checkbox: a small rounded box that fills with the accent colour when checked.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Checkbox(
      value: value,
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
      activeColor: p.accent,
      checkColor: p.onAccent,
      side: BorderSide(color: p.muted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

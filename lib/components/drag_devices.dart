import 'package:flutter/gestures.dart' show PointerDeviceKind;

/// Pointers whose drags may move or resize things (dividers, splitters, tiles).
///
/// Excludes [PointerDeviceKind.trackpad]: on desktop, trackpad two-finger swipes
/// reach Flutter as pan/drag gestures. Excluding trackpads from drag handles prevents
/// natural trackpad scrolling from triggering accidental layout resize or dragging.
const Set<PointerDeviceKind> kDragDevices = {
  PointerDeviceKind.mouse,
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};

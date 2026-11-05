// Which way an icon actually points on screen. Icons with matchTextDirection are
// mirrored by Flutter in RTL, so the icon's name alone does not say: an RTL
// ternary on top of that mirror flips it twice and paints it backwards.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

enum Pointing { left, right }

/// The direction the single [Icon] behind [icon] is painted in: its glyph's own
/// direction, reversed by each negative x-scale between it and its glyph.
Pointing paintedPointing(WidgetTester tester, Finder icon) {
  final data = tester.widget<Icon>(icon).icon;
  final Pointing glyph;
  if (data == Icons.chevron_right_rounded || data == Icons.arrow_forward_ios_rounded) {
    glyph = Pointing.right;
  } else if (data == Icons.chevron_left_rounded || data == Icons.arrow_back_ios_rounded) {
    glyph = Pointing.left;
  } else {
    throw ArgumentError('Not a directional icon: $data');
  }
  final mirrors = tester
      .widgetList<Transform>(find.descendant(of: icon, matching: find.byType(Transform)))
      .where((t) => t.transform.storage[0] < 0)
      .length;
  if (mirrors.isEven) return glyph;
  return glyph == Pointing.right ? Pointing.left : Pointing.right;
}

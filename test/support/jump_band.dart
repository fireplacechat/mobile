import 'dart:ui' as ui;

import 'package:fireplace/src/view/chat/widgets/message_flash.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The row a timeline wraps in a MessageFlash for message [id].
Finder flashedRow(String id) =>
    find.byWidgetPredicate((w) => w is MessageFlash && w.messageId == id);

/// The highlight band behind message [id]: the first AnimatedContainer
/// under its MessageFlash, painted before the row.
Finder jumpBand(String id) => find
    .descendant(of: flashedRow(id), matching: find.byType(AnimatedContainer))
    .first;

/// The band's colour as configured, faded in or not.
Color jumpBandTarget(WidgetTester t, String id) =>
    (t.widget<AnimatedContainer>(jumpBand(id)).decoration! as BoxDecoration)
        .color!;

/// How opaque the band is painted now, part way through its fade or not.
double jumpBandShown(WidgetTester t, String id) =>
    ((t.renderObject(jumpBand(id)) as RenderDecoratedBox).decoration
            as BoxDecoration)
        .color!
        .a;

/// The colour painted at [at] inside the RepaintBoundary under [boundary],
/// in its logical pixels. Use a view with a device pixel ratio of 1.
Future<Color> paintedPixel(
  WidgetTester t,
  GlobalKey boundary,
  Offset at,
) async {
  final box =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await t.runAsync(() async {
    final image = await box.toImage();
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    } finally {
      image.dispose();
    }
  });
  final index = at.dy.floor() * box.size.width.round() + at.dx.floor();
  final rgba = bytes!.getUint32(index * 4);
  return Color.fromARGB(
    rgba & 0xff,
    rgba >> 24,
    (rgba >> 16) & 0xff,
    (rgba >> 8) & 0xff,
  );
}
